import Foundation
import AVFoundation

/// The examiner's voice: system speech synthesis, one line at a time.
@MainActor
final class Examiner: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var line = ""

    /// Development: speak at volume 0 (timing stays realistic).
    static var muted = false

    private let synth = AVSpeechSynthesizer()
    private var finish: CheckedContinuation<Void, Never>?
    var voiceIdentifier: String?
    var rate: Float = 0.47

    override init() {
        super.init()
        synth.delegate = self
    }

    /// The examiner's name, from the voice ("Daniel", "Serena").
    var name: String {
        let v = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.defaultVoice
        return v?.name.components(separatedBy: " ").first ?? "Daniel"
    }

    func say(_ text: String) async {
        stop()
        line = text
        isSpeaking = true
        let u = AVSpeechUtterance(string: text)
        u.voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.defaultVoice
        u.rate = rate
        u.postUtteranceDelay = 0.15
        if Self.muted { u.volume = 0 }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finish = c
            synth.speak(u)
        }
        isSpeaking = false
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        resume()
    }

    private func resume() {
        let c = finish
        finish = nil
        c?.resume()
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    /// English voices, British first, then by quality.
    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                let ga = a.language == "en-GB", gb = b.language == "en-GB"
                if ga != gb { return ga }
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    /// The best British voice installed (Daniel ships with every Mac).
    static var defaultVoice: AVSpeechSynthesisVoice? {
        englishVoices.first { $0.language == "en-GB" } ?? AVSpeechSynthesisVoice(language: "en-GB")
    }
}
