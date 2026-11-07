import Foundation

enum AttemptMode: String, Codable, Hashable {
    case fullMock      // L → R → W, strict timing
    case moduleMock    // one module, strict timing
    case practice      // one part / passage / task, relaxed timing

    var label: String {
        switch self {
        case .fullMock: return "全真模考"
        case .moduleMock: return "单科模考"
        case .practice: return "专项练习"
        }
    }
}

enum AttemptStatus: String, Codable, Hashable {
    case inProgress, submitted, abandoned
}

/// What the attempt covers inside one module.
struct AttemptScope: Codable, Hashable {
    var module: Module
    /// nil = whole module; otherwise part / passage / task index (0-based)
    var section: Int?
}

struct Highlight: Codable, Hashable, Identifiable {
    var id = UUID()
    var passage: Int        // passage index
    var paragraph: Int      // paragraph index
    var location: Int
    var length: Int
    var color: String = "yellow"
}

struct WritingAssessment: Codable, Hashable {
    struct Criterion: Codable, Hashable, Identifiable {
        var name: String
        var band: Double
        var comment: String
        var id: String { name }
    }
    struct Correction: Codable, Hashable, Identifiable {
        var original: String
        var suggestion: String
        var explanation: String
        var id: String { original + suggestion }
    }
    var overallBand: Double
    var criteria: [Criterion]
    var summary: String
    var strengths: [String]
    var weaknesses: [String]
    var corrections: [Correction]
    var improvedVersion: String
    var nextSteps: [String]
    var model: String
    var createdAt: Date
}

struct QuestionExplanation: Codable, Hashable {
    var number: Int
    var module: Module
    var explanation: String       // markdown
    var evidence: String?         // quote from passage / transcript
    var paraphrases: [String]?    // synonym / paraphrase pairs
    var tip: String?
    var model: String
    var createdAt: Date
}

struct ModuleTiming: Codable, Hashable {
    var allotted: Double     // seconds
    var used: Double         // seconds
}

struct Attempt: Codable, Identifiable, Hashable {
    var id = UUID()
    var examId: String
    var examTitle: String
    var mode: AttemptMode
    var scopes: [AttemptScope]
    var startedAt = Date()
    var finishedAt: Date?
    var status: AttemptStatus = .inProgress

    /// "L12" / "R5" -> answer
    var answers: [String: String] = [:]
    var flagged: Set<String> = []
    var highlights: [Highlight] = []
    /// task number -> essay
    var essays: [Int: String] = [:]
    var timing: [Module: ModuleTiming] = [:]

    // results
    var results: [QuestionResult] = []
    var scores: [Module: ModuleScore] = [:]
    var explanations: [String: QuestionExplanation] = [:]
    var assessments: [Int: WritingAssessment] = [:]
    var speaking: SpeakingRecord?

    // live session bookkeeping (for resuming)
    var currentStage: Int = 0
    var remaining: [Module: Double] = [:]

    var modules: [Module] { scopes.map(\.module) }

    var title: String {
        if mode == .practice, let s = scopes.first {
            switch s.module {
            case .listening: return "\(examTitle) · 听力" + (s.section.map { " Part \($0 + 1)" } ?? "")
            case .reading: return "\(examTitle) · 阅读" + (s.section.map { " Passage \($0 + 1)" } ?? "")
            case .writing: return "\(examTitle) · 写作" + (s.section.map { " Task \($0 + 1)" } ?? "")
            case .speaking: return "\(examTitle) · 口语" + (s.section.map { " Part \($0 + 1)" } ?? "")
            }
        }
        if mode == .moduleMock, let m = scopes.first?.module { return "\(examTitle) · \(m.title)模考" }
        return "\(examTitle) · 全真模考"
    }

    var overallBand: Double? {
        var bands = scores.values.compactMap(\.band)
        let w = assessments.values.map(\.overallBand)
        if !w.isEmpty, modules.contains(.writing) {
            // Task 2 counts double in IELTS writing
            let t1 = assessments[1]?.overallBand
            let t2 = assessments[2]?.overallBand
            if let t1, let t2 { bands.append(roundHalf((t1 + 2 * t2) / 3)) } else { bands.append(roundHalf(w.reduce(0, +) / Double(w.count))) }
        }
        if let s = speakingBand { bands.append(s) }
        guard scopes.allSatisfy({ $0.section == nil }) else { return nil }
        return Grader.overall(bands)
    }

    var speakingBand: Double? { speaking?.assessment?.overallBand }

    var writingBand: Double? {
        let t1 = assessments[1]?.overallBand
        let t2 = assessments[2]?.overallBand
        if let t1, let t2 { return roundHalf((t1 + 2 * t2) / 3) }
        return t1 ?? t2
    }

    var wrongResults: [QuestionResult] { results.filter { !$0.isCorrect } }
}

func roundHalf(_ x: Double) -> Double { (x * 2).rounded() / 2 }
