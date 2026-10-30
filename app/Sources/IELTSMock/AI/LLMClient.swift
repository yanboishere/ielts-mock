import Foundation

enum LLMContent {
    case text(String)
    case image(Data, mime: String)
}

struct LLMRequest {
    var system: String
    var content: [LLMContent]
    /// JSON schema for the reply (objects must set additionalProperties=false and list every property as required).
    var schema: [String: Any]
    var schemaName: String
    var maxTokens: Int = 32000
    /// "low" | "medium" | "high"
    var effort: String = "medium"
}

struct LLMResponse {
    var text: String
    var model: String
    var inputTokens: Int?
    var outputTokens: Int?
}

enum AIError: LocalizedError {
    case noKey(AIProviderKind)
    case http(Int, String)
    case refusal(String?)
    case truncated
    case badResponse(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noKey(let p): return "尚未设置 \(p.label) 的 API Key（设置 → AI）。"
        case .http(let code, let msg):
            switch code {
            case 401: return "API Key 无效或已失效（401）。\(msg)"
            case 403: return "没有权限使用该模型（403）。\(msg)"
            case 404: return "模型或接口地址不存在（404）。请检查模型名与 Base URL。\(msg)"
            case 429: return "请求过于频繁或额度不足（429），请稍后重试。\(msg)"
            case 529, 503: return "服务繁忙（\(code)），请稍后重试。\(msg)"
            default: return "请求失败（HTTP \(code)）：\(msg)"
            }
        case .refusal(let c): return "模型拒绝了该请求" + (c.map { "（\($0)）" } ?? "") + "。"
        case .truncated: return "输出被截断（达到 max tokens），请重试。"
        case .badResponse(let s): return "无法解析模型输出：\(s)"
        case .cancelled: return "已取消。"
        }
    }

    var isRetryable: Bool {
        if case .http(let c, _) = self { return c == 429 || c == 408 || c >= 500 }
        return false
    }
}

protocol LLMClient: Sendable {
    var modelName: String { get }
    func complete(_ req: LLMRequest, progress: @escaping @Sendable (Int) -> Void) async throws -> LLMResponse
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 1800
        return URLSession(configuration: c)
    }()

    /// Reads a full error body from a streaming response.
    static func readAll(_ bytes: URLSession.AsyncBytes) async -> String {
        var data = Data()
        do {
            for try await b in bytes {
                data.append(b)
                if data.count > 200_000 { break }
            }
        } catch {}
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Extracts a readable message from an error JSON body.
    static func errorMessage(_ body: String) -> String {
        if let d = body.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = j["message"] as? String { return m }
        }
        return String(body.prefix(400))
    }

    static func retrying<T>(_ attempts: Int = 3, _ op: () async throws -> T) async throws -> T {
        var delay: UInt64 = 2_000_000_000
        for i in 0..<attempts {
            do { return try await op() } catch let e as AIError where e.isRetryable && i < attempts - 1 {
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
        return try await op()
    }
}

/// Strips ```json fences or leading prose and returns the JSON object text.
func extractJSONObject(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("```") {
        t = t.replacingOccurrences(of: #"^```[a-zA-Z]*\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"```\s*$"#, with: "", options: .regularExpression)
    }
    if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b { return String(t[a...b]) }
    return t
}
