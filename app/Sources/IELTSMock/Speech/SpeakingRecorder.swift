import Foundation
import AVFoundation

/// Records one answer at a time as 16 kHz mono 16-bit WAVE, the format the recogniser takes, and follows the input
/// level to tell when the candidate has started and stopped speaking.
@MainActor
final class SpeakingRecorder: ObservableObject {
    /// Input level 0…1 for the meter.
    @Published private(set) var level: Double = 0
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    /// The candidate has spoken in this answer.
    @Published private(set) var hasSpoken = false
    /// Seconds since the input last held speech (0 while speaking or before any speech).
    @Published private(set) var silence: Double = 0
    /// Seconds from the first to the last moment the input held speech.
    private(set) var spokenSpan: Double = 0
    private var firstSpeech: Double?

    /// Development: answers are taken from these files, one per answer, instead of the microphone.
    static var debugFeed: [URL] = []
    private var feedIndex = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt = Date()
    private var noiseFloor: Float = -50
    private var spokenFrames = 0
    private var feedDuration: Double = 0
    private var target: URL?

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool {
        if !debugFeed.isEmpty { return true }
        switch permission {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(to url: URL) throws {
        stopTimer()
        target = url
        hasSpoken = false
        silence = 0
        spokenSpan = 0
        firstSpeech = nil
        elapsed = 0
        level = 0
        spokenFrames = 0
        startedAt = Date()
        if !Self.debugFeed.isEmpty {
            let src = Self.debugFeed[feedIndex % Self.debugFeed.count]
            feedIndex += 1
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: src, to: url)
            feedDuration = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 3
            isRecording = true
            startTimer()
            return
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else { throw SpeechEngineError.failed("无法开始录音，请检查麦克风权限与输入设备。") }
        recorder = r
        isRecording = true
        startTimer()
    }

    /// Stops and returns the length of the recording in seconds.
    @discardableResult
    func stop() -> Double {
        stopTimer()
        isRecording = false
        level = 0
        if let r = recorder {
            let d = r.currentTime
            r.stop()
            recorder = nil
            return d
        }
        return feedDuration
    }

    func cancel() {
        stop()
        if let t = target { try? FileManager.default.removeItem(at: t) }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        elapsed = Date().timeIntervalSince(startedAt)
        if recorder == nil {
            // Fed file: speech for its length, then silence.
            let speaking = elapsed < feedDuration
            level = speaking ? 0.5 + 0.3 * sin(elapsed * 9) : 0.02
            if speaking { hasSpoken = true; silence = 0 } else { silence = elapsed - feedDuration }
            spokenSpan = min(elapsed, feedDuration)
            return
        }
        guard let r = recorder else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)
        // The quietest level of the last seconds is the room; speech is well above it.
        noiseFloor = min(max(db, -80), noiseFloor + 0.05)
        if db < noiseFloor { noiseFloor = db }
        let threshold = max(noiseFloor + 14, -48)
        level = Double(max(0, min(1, (db + 60) / 60)))
        if db > threshold {
            spokenFrames += 1
            if spokenFrames >= 6 { hasSpoken = true }
            silence = 0
            if firstSpeech == nil { firstSpeech = elapsed }
            spokenSpan = elapsed - (firstSpeech ?? elapsed)
        } else if hasSpoken {
            silence += 0.05
        }
    }
}
