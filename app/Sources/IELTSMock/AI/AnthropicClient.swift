import Foundation

/// Claude Messages API over raw HTTP (Swift has no official Anthropic SDK). Streams SSE and accumulates text.
struct AnthropicClient: LLMClient {
    var apiKey: String
    var model: String
    var baseURL: String
    /// Server-side refusal fallbacks (`fallbacks: "default"`), Claude API only.
    var useFallbacks: Bool

    var modelName: String { model }

    private var isFirstParty: Bool {
        (URL(string: baseURL)?.host ?? "").hasSuffix("anthropic.com")
    }

    /// Models that accept `fallbacks: "default"` (Claude Haiku 5.5 has no server-side fallback).
    private var supportsFallbacks: Bool {
        ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
    }

    func complete(_ req: LLMRequest, progress: @escaping @Sendable (Int) -> Void) async throws -> LLMResponse {
        var opts = Options(effort: true, format: true, fallbacks: useFallbacks && isFirstParty && supportsFallbacks)
        // Retry once without an optional feature if the endpoint/model rejects it (custom base URLs, older models).
        for _ in 0..<4 {
            do {
                return try await HTTP.retrying { try await send(req, opts, progress) }
            } catch AIError.http(400, let msg) {
                let m = msg.lowercased()
                if opts.fallbacks, m.contains("fallback") { opts.fallbacks = false; continue }
                if opts.effort, m.contains("effort") { opts.effort = false; continue }
                if opts.format, m.contains("output_config") || m.contains("format") || m.contains("schema") { opts.format = false; continue }
                throw AIError.http(400, msg)
            }
        }
        return try await send(req, opts, progress)
    }

    struct Options { var effort: Bool; var format: Bool; var fallbacks: Bool }

    private func send(_ req: LLMRequest, _ opts: Options, _ progress: @escaping @Sendable (Int) -> Void) async throws -> LLMResponse {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base.hasSuffix("/v1") ? base + "/messages" : base + "/v1/messages") else {
            throw AIError.badResponse("Base URL 无效")
        }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("text/event-stream", forHTTPHeaderField: "accept")

        var blocks: [[String: Any]] = []
        for c in req.content {
            switch c {
            case .image(let data, let mime):
                blocks.append(["type": "image", "source": ["type": "base64", "media_type": mime, "data": data.base64EncodedString()]])
            case .text(let t):
                blocks.append(["type": "text", "text": t])
            }
        }
        var outputConfig: [String: Any] = [:]
        if opts.effort { outputConfig["effort"] = req.effort }
        var system = req.system
        if opts.format {
            outputConfig["format"] = ["type": "json_schema", "schema": req.schema]
        } else {
            system += "\n\nReply with a single JSON object that matches this JSON schema, and nothing else:\n" + schemaText(req.schema)
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": req.maxTokens,
            "stream": true,
            "system": system,
            "messages": [["role": "user", "content": blocks]],
        ]
        if !outputConfig.isEmpty { body["output_config"] = outputConfig }
        if opts.fallbacks {
            r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await HTTP.session.bytes(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AIError.http(status, HTTP.errorMessage(await HTTP.readAll(bytes)))
        }

        var text = ""
        var servedBy = model
        var stopReason: String?
        var stopCategory: String?
        var inTok: Int?
        var outTok: Int?
        var received = 0
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let d = payload.data(using: .utf8), let ev = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            switch ev["type"] as? String {
            case "message_start":
                if let m = ev["message"] as? [String: Any] {
                    servedBy = m["model"] as? String ?? servedBy
                    inTok = (m["usage"] as? [String: Any])?["input_tokens"] as? Int
                }
            case "content_block_delta":
                if let delta = ev["delta"] as? [String: Any] {
                    if delta["type"] as? String == "text_delta", let t = delta["text"] as? String {
                        text += t   // text blocks before/after a fallback boundary form one continuous reply
                        received += t.count
                        progress(received)
                    } else if delta["type"] as? String == "thinking_delta" {
                        received += 1
                        progress(received)
                    }
                }
            case "message_delta":
                if let delta = ev["delta"] as? [String: Any] {
                    stopReason = delta["stop_reason"] as? String ?? stopReason
                    if let sd = delta["stop_details"] as? [String: Any] { stopCategory = sd["category"] as? String }
                }
                if let u = ev["usage"] as? [String: Any] { outTok = u["output_tokens"] as? Int ?? outTok }
            case "error":
                let e = ev["error"] as? [String: Any]
                let type = e?["type"] as? String ?? ""
                let msg = e?["message"] as? String ?? payload
                throw AIError.http(type == "overloaded_error" ? 529 : 500, msg)
            default:
                break
            }
        }
        if stopReason == "refusal" { throw AIError.refusal(stopCategory) }
        if stopReason == "max_tokens" { throw AIError.truncated }
        return LLMResponse(text: text, model: servedBy, inputTokens: inTok, outputTokens: outTok)
    }
}

func schemaText(_ schema: [String: Any]) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
    return String(data: d, encoding: .utf8) ?? "{}"
}
