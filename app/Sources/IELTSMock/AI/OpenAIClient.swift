import Foundation

/// OpenAI Chat Completions over raw HTTP, streaming. Also works with OpenAI-compatible endpoints via a custom base URL.
struct OpenAIClient: LLMClient {
    var apiKey: String
    var model: String
    var baseURL: String

    var modelName: String { model }

    private var isOfficial: Bool { (URL(string: baseURL)?.host ?? "") == "api.openai.com" }
    private var isReasoningModel: Bool {
        let m = model.lowercased()
        return m.hasPrefix("gpt-5") || m.hasPrefix("gpt-6") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4")
    }

    struct Options { var schema = true; var reasoning = true; var completionTokens = true }

    func complete(_ req: LLMRequest, progress: @escaping @Sendable (Int) -> Void) async throws -> LLMResponse {
        var o = Options(schema: true, reasoning: isOfficial && isReasoningModel, completionTokens: isOfficial)
        for _ in 0..<4 {
            do {
                return try await HTTP.retrying { try await send(req, o, progress) }
            } catch AIError.http(400, let msg) {
                let m = msg.lowercased()
                if o.reasoning, m.contains("reasoning") { o.reasoning = false; continue }
                if o.schema, m.contains("response_format") || m.contains("json_schema") || m.contains("schema") { o.schema = false; continue }
                if m.contains("max_completion_tokens") || m.contains("max_tokens") { o.completionTokens.toggle(); continue }
                throw AIError.http(400, msg)
            }
        }
        return try await send(req, o, progress)
    }

    private func send(_ req: LLMRequest, _ o: Options, _ progress: @escaping @Sendable (Int) -> Void) async throws -> LLMResponse {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/chat/completions") else { throw AIError.badResponse("Base URL 无效") }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var parts: [[String: Any]] = []
        for c in req.content {
            switch c {
            case .image(let data, let mime):
                parts.append(["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]])
            case .text(let t):
                parts.append(["type": "text", "text": t])
            }
        }
        var system = req.system
        if !o.schema {
            system += "\n\nReply with a single JSON object that matches this JSON schema, and nothing else:\n" + schemaText(req.schema)
        }
        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [["role": "system", "content": system], ["role": "user", "content": parts]],
        ]
        body[o.completionTokens ? "max_completion_tokens" : "max_tokens"] = req.maxTokens
        if o.schema {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": req.schemaName, "strict": true, "schema": req.schema]]
        } else {
            body["response_format"] = ["type": "json_object"]
        }
        if o.reasoning { body["reasoning_effort"] = req.effort }
        if isOfficial { body["stream_options"] = ["include_usage": true] }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await HTTP.session.bytes(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AIError.http(status, HTTP.errorMessage(await HTTP.readAll(bytes))) }

        var text = ""
        var finish: String?
        var servedBy = model
        var inTok: Int?
        var outTok: Int?
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8), let ev = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let e = ev["error"] as? [String: Any] { throw AIError.http(500, e["message"] as? String ?? payload) }
            servedBy = ev["model"] as? String ?? servedBy
            if let choices = ev["choices"] as? [[String: Any]], let c = choices.first {
                if let delta = c["delta"] as? [String: Any] {
                    if let t = delta["content"] as? String {
                        text += t
                        progress(text.count)
                    }
                    if let refusal = delta["refusal"] as? String, !refusal.isEmpty { throw AIError.refusal(refusal) }
                }
                if let f = c["finish_reason"] as? String { finish = f }
            }
            if let u = ev["usage"] as? [String: Any] {
                inTok = u["prompt_tokens"] as? Int
                outTok = u["completion_tokens"] as? Int
            }
        }
        if finish == "length" { throw AIError.truncated }
        if finish == "content_filter" { throw AIError.refusal("content_filter") }
        return LLMResponse(text: text, model: servedBy, inputTokens: inTok, outputTokens: outTok)
    }
}
