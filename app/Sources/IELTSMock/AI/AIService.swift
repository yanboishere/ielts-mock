import Foundation
import AppKit

/// Orchestrates AI explanations and writing assessments, tracks progress for the UI.
@MainActor
final class AIService: ObservableObject {
    @Published var running: [String: Int] = [:]     // job key -> characters received
    @Published var errors: [String: String] = [:]

    let settings: SettingsStore
    init(settings: SettingsStore) { self.settings = settings }

    func client() throws -> LLMClient {
        let p = settings.provider
        guard let key = settings.apiKey(p), !key.isEmpty else { throw AIError.noKey(p) }
        switch p {
        case .claude:
            return AnthropicClient(apiKey: key, model: settings.claudeModel, baseURL: settings.claudeBaseURL, useFallbacks: settings.claudeFallbacks)
        case .openai:
            return OpenAIClient(apiKey: key, model: settings.openaiModel, baseURL: settings.openaiBaseURL)
        }
    }

    func isRunning(_ key: String) -> Bool { running[key] != nil }

    private func run<T>(_ key: String, _ body: @escaping (LLMClient, @escaping @Sendable (Int) -> Void) async throws -> T) async throws -> T {
        errors[key] = nil
        running[key] = 0
        defer { running[key] = nil }
        do {
            let c = try client()
            let progress: @Sendable (Int) -> Void = { [weak self] n in
                Task { @MainActor in if self?.running[key] != nil { self?.running[key] = n } }
            }
            return try await body(c, progress)
        } catch {
            errors[key] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    // MARK: connection test

    func testConnection() async throws -> String {
        try await run("test") { c, p in
            let req = LLMRequest(system: "You are a connectivity check.", content: [.text("Reply with {\"ok\": true, \"model\": \"<your model name>\"}.")],
                                 schema: ["type": "object", "additionalProperties": false, "required": ["ok", "model"],
                                          "properties": ["ok": ["type": "boolean"], "model": ["type": "string"]]],
                                 schemaName: "ping", maxTokens: 2000, effort: "low")
            let r = try await c.complete(req, progress: p)
            return "连接成功：\(r.model)"
        }
    }

    // MARK: explanations

    /// Explains the wrong answers of one part / passage in a single request.
    func explain(ref: ExamRef, module: Module, section: Int, wrong: [QuestionResult]) async throws -> [QuestionExplanation] {
        guard !wrong.isEmpty else { return [] }
        let exam = ref.exam
        var sourceTitle = ""
        var sourceText = ""
        var groups: [QuestionGroup] = []
        switch module {
        case .listening:
            guard let p = exam.listening?.parts[safe: section] else { return [] }
            sourceTitle = "Part \(p.part)"
            sourceText = (p.transcript ?? "(no transcript available)").replacingOccurrences(of: #"\[Q\d+(?:[/&] ?Q?\d+)*\]"#, with: "", options: .regularExpression)
            groups = p.groups
        case .reading:
            guard let p = exam.reading?.passages[safe: section] else { return [] }
            sourceTitle = "Passage \(p.passage): \(p.title)"
            sourceText = p.paragraphs.map { para in
                para.isImage ? "[figure]" : ((para.label.map { "\($0) " } ?? "") + InlineMarkup.strip(para.text))
            }.joined(separator: "\n\n")
            groups = p.groups
        case .writing:
            return []
        }
        let needed = Set(wrong.map(\.groupId))
        groups = groups.filter { needed.contains($0.id) }
        let user = Prompts.explanationUser(sourceTitle: sourceTitle, sourceText: sourceText, groups: groups, wrong: wrong, isListening: module == .listening)
        let key = "explain-\(exam.id)-\(module.rawValue)-\(section)"
        let lang = settings.aiLanguage
        let effort = settings.explainEffort
        return try await run(key) { c, p in
            let req = LLMRequest(system: Prompts.explanationSystem(language: lang), content: [.text(user)],
                                 schema: Prompts.explanationSchema, schemaName: "ielts_explanations", maxTokens: 32000, effort: effort)
            let r = try await c.complete(req, progress: p)
            guard let d = extractJSONObject(r.text).data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let items = j["items"] as? [[String: Any]] else {
                throw AIError.badResponse(String(r.text.prefix(300)))
            }
            let asked = Set(wrong.map(\.number))
            return items.compactMap { it -> QuestionExplanation? in
                guard let n = it["number"] as? Int ?? (it["number"] as? Double).map({ Int($0) }), asked.contains(n) else { return nil }
                return QuestionExplanation(number: n, module: module,
                                           explanation: it["explanation"] as? String ?? "",
                                           evidence: (it["evidence"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                           paraphrases: it["paraphrases"] as? [String],
                                           tip: (it["tip"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                           model: r.model, createdAt: Date())
            }
        }
    }

    // MARK: writing

    func assess(ref: ExamRef, task: WritingTask, essay: String) async throws -> WritingAssessment {
        let words = WordCounter.count(essay)
        var content: [LLMContent] = []
        if let img = ref.url(task.image), let data = try? Data(contentsOf: img) {
            content.append(.image(Self.downscaledPNG(data) ?? data, mime: "image/png"))
        }
        content.append(.text(Prompts.writingUser(task: task, essay: essay, wordCount: words, includeSample: true)))
        let system = Prompts.writingSystem(language: settings.aiLanguage, task: task.task)
        let effort = settings.writingEffort
        let key = "assess-\(ref.exam.id)-\(task.task)"
        return try await run(key) { c, p in
            let req = LLMRequest(system: system, content: content, schema: Prompts.writingSchema, schemaName: "ielts_writing_assessment",
                                 maxTokens: 48000, effort: effort)
            let r = try await c.complete(req, progress: p)
            guard let d = extractJSONObject(r.text).data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                throw AIError.badResponse(String(r.text.prefix(300)))
            }
            func num(_ v: Any?) -> Double { (v as? Double) ?? Double(v as? Int ?? 0) }
            let criteria = (j["criteria"] as? [[String: Any]] ?? []).map {
                WritingAssessment.Criterion(name: $0["name"] as? String ?? "", band: num($0["band"]), comment: $0["comment"] as? String ?? "")
            }
            var overall = num(j["overall_band"])
            if criteria.count == 4 {
                // official rule for a single task: mean of the four criteria, rounded down to the half band
                overall = floor(criteria.map(\.band).reduce(0, +) / 4 * 2) / 2
            }
            let corrections = (j["corrections"] as? [[String: Any]] ?? []).map {
                WritingAssessment.Correction(original: $0["original"] as? String ?? "", suggestion: $0["suggestion"] as? String ?? "",
                                             explanation: $0["explanation"] as? String ?? "")
            }
            return WritingAssessment(overallBand: overall, criteria: criteria, summary: j["summary"] as? String ?? "",
                                     strengths: j["strengths"] as? [String] ?? [], weaknesses: j["weaknesses"] as? [String] ?? [],
                                     corrections: corrections, improvedVersion: j["improved_version"] as? String ?? "",
                                     nextSteps: j["next_steps"] as? [String] ?? [], model: r.model, createdAt: Date())
        }
    }

    /// Keeps images within vision limits (long edge ≤ 1568 px) and re-encodes as PNG.
    static func downscaledPNG(_ data: Data) -> Data? {
        guard let img = NSImage(data: data), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let maxEdge: CGFloat = 1568
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxEdge / max(w, h))
        let W = Int(w * scale), H = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}

enum WordCounter {
    static func count(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.filter { tok in tok.contains { $0.isLetter || $0.isNumber } }.count
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
