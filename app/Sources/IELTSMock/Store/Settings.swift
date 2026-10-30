import Foundation
import SwiftUI
import AppKit
import Security

enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case claude, openai
    var id: String { rawValue }
    var label: String { self == .claude ? "Claude (Anthropic)" : "OpenAI" }
}

/// App settings backed by UserDefaults. API keys live in the Keychain, never in defaults.
@MainActor
final class SettingsStore: ObservableObject {
    private let d = UserDefaults.standard

    @Published var provider: AIProviderKind { didSet { d.set(provider.rawValue, forKey: "ai.provider") } }
    @Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "ai.claude.model") } }
    @Published var claudeBaseURL: String { didSet { d.set(claudeBaseURL, forKey: "ai.claude.base") } }
    @Published var claudeFallbacks: Bool { didSet { d.set(claudeFallbacks, forKey: "ai.claude.fallbacks") } }
    @Published var openaiModel: String { didSet { d.set(openaiModel, forKey: "ai.openai.model") } }
    @Published var openaiBaseURL: String { didSet { d.set(openaiBaseURL, forKey: "ai.openai.base") } }
    @Published var aiLanguage: String { didSet { d.set(aiLanguage, forKey: "ai.lang") } }
    @Published var explainEffort: String { didSet { d.set(explainEffort, forKey: "ai.effort.explain") } }
    @Published var writingEffort: String { didSet { d.set(writingEffort, forKey: "ai.effort.writing") } }

    @Published var readingMinutes: Int { didSet { d.set(readingMinutes, forKey: "time.reading") } }
    @Published var writingMinutes: Int { didSet { d.set(writingMinutes, forKey: "time.writing") } }
    @Published var listeningReviewMinutes: Int { didSet { d.set(listeningReviewMinutes, forKey: "time.listeningReview") } }
    @Published var reminderMinutes: [Int] { didSet { d.set(reminderMinutes, forKey: "time.reminders") } }
    @Published var reminderSound: Bool { didSet { d.set(reminderSound, forKey: "time.sound") } }
    @Published var reminderNotification: Bool { didSet { d.set(reminderNotification, forKey: "time.notify") } }
    @Published var autoSubmit: Bool { didSet { d.set(autoSubmit, forKey: "time.autoSubmit") } }
    @Published var writingTaskNudge: Bool { didSet { d.set(writingTaskNudge, forKey: "time.writingNudge") } }
    @Published var readingPassageNudge: Bool { didSet { d.set(readingPassageNudge, forKey: "time.readingNudge") } }
    @Published var fontScale: Double { didSet { d.set(fontScale, forKey: "ui.fontScale") } }
    @Published var candidateName: String { didSet { d.set(candidateName, forKey: "ui.candidate") } }
    /// Colour scheme of the exam screen, as offered by computer-delivered IELTS ("Contrast" in the options menu).
    @Published var examContrast: ExamContrast { didSet { d.set(examContrast.rawValue, forKey: "ui.examContrast") } }
    @Published var autoAdvanceListening: Bool { didSet { d.set(autoAdvanceListening, forKey: "ui.autoAdvance") } }

    static let claudeModels = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1"]
    static let openaiModels = ["gpt-6-astra", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-5.5"]

    init() {
        provider = AIProviderKind(rawValue: d.string(forKey: "ai.provider") ?? "") ?? .claude
        claudeModel = d.string(forKey: "ai.claude.model") ?? "claude-opus-5-5"
        claudeBaseURL = d.string(forKey: "ai.claude.base") ?? "https://api.anthropic.com"
        claudeFallbacks = d.object(forKey: "ai.claude.fallbacks") as? Bool ?? true
        openaiModel = d.string(forKey: "ai.openai.model") ?? "gpt-6-astra"
        openaiBaseURL = d.string(forKey: "ai.openai.base") ?? "https://api.openai.com/v1"
        aiLanguage = d.string(forKey: "ai.lang") ?? "zh"
        explainEffort = d.string(forKey: "ai.effort.explain") ?? "medium"
        writingEffort = d.string(forKey: "ai.effort.writing") ?? "high"
        readingMinutes = d.object(forKey: "time.reading") as? Int ?? 60
        writingMinutes = d.object(forKey: "time.writing") as? Int ?? 60
        listeningReviewMinutes = d.object(forKey: "time.listeningReview") as? Int ?? 2
        reminderMinutes = d.array(forKey: "time.reminders") as? [Int] ?? [10, 5, 1]
        reminderSound = d.object(forKey: "time.sound") as? Bool ?? true
        reminderNotification = d.object(forKey: "time.notify") as? Bool ?? true
        autoSubmit = d.object(forKey: "time.autoSubmit") as? Bool ?? true
        writingTaskNudge = d.object(forKey: "time.writingNudge") as? Bool ?? true
        readingPassageNudge = d.object(forKey: "time.readingNudge") as? Bool ?? true
        fontScale = d.object(forKey: "ui.fontScale") as? Double ?? 1.0
        candidateName = d.string(forKey: "ui.candidate") ?? ""
        examContrast = ExamContrast(rawValue: d.string(forKey: "ui.examContrast") ?? "") ?? .standard
        autoAdvanceListening = d.object(forKey: "ui.autoAdvance") as? Bool ?? true
    }

    var currentModel: String { provider == .claude ? claudeModel : openaiModel }

    /// Keys read from the Keychain this run. Reading is deferred until a key is actually needed, because each new
    /// (ad-hoc signed) build triggers a Keychain access prompt on first read.
    private var keyCache: [AIProviderKind: String] = [:]

    func apiKey(_ p: AIProviderKind) -> String? {
        if let k = keyCache[p] { return k.isEmpty ? nil : k }
        let k = Keychain.get(account: p.rawValue)
        keyCache[p] = k ?? ""
        if hasKey(p) != (k != nil) { d.set(k != nil, forKey: "ai.hasKey.\(p.rawValue)") }
        return k
    }
    func setAPIKey(_ key: String, for p: AIProviderKind) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { Keychain.delete(account: p.rawValue) } else { Keychain.set(k, account: p.rawValue) }
        keyCache[p] = k
        d.set(!k.isEmpty, forKey: "ai.hasKey.\(p.rawValue)")
        objectWillChange.send()
    }
    /// Whether a key has been saved, without touching the Keychain.
    func hasKey(_ p: AIProviderKind) -> Bool { d.bool(forKey: "ai.hasKey.\(p.rawValue)") }
    var hasKeyForCurrentProvider: Bool { hasKey(provider) }
}

enum ExamContrast: String, CaseIterable, Identifiable {
    case standard, whiteOnBlack, yellowOnBlack
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Black on white"
        case .whiteOnBlack: return "White on black"
        case .yellowOnBlack: return "Yellow on black"
        }
    }
    var isDark: Bool { self != .standard }
    var ink: Color { self == .yellowOnBlack ? Color(red: 1, green: 0.92, blue: 0.2) : (isDark ? .white : .black) }
    var nsInk: NSColor { self == .yellowOnBlack ? NSColor(red: 1, green: 0.92, blue: 0.2, alpha: 1) : (isDark ? .white : .black) }
    var background: Color { isDark ? .black : .white }
    var nsBackground: NSColor { isDark ? .black : .white }
}

/// Text size presets of the computer-delivered test ("Text size" in the options menu); ⌘+/⌘- still fine-tune.
enum ExamTextSize: Double, CaseIterable, Identifiable {
    case standard = 1.0, large = 1.25, extraLarge = 1.5
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }
}

enum Keychain {
    static let service = "IELTSMock.APIKeys"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
