import Foundation
import AVFoundation

enum SpeechEngineError: LocalizedError {
    case missingBinary
    case missingModel(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary: return "找不到语音引擎（speech.cpp）。请使用完整打包的 App，或设置 IELTSMOCK_SPEECH_BIN。"
        case .missingModel(let m): return "尚未下载语音模型：\(m)。请在设置 › 口语中下载。"
        case .failed(let m): return "语音识别失败：\(m)"
        }
    }
}

/// speech.cpp (github.com/nyosegawa/speech.cpp, MIT), the runtime Arion uses for Qwen3-ASR.
enum SpeechEngine {
    /// The executable shipped in the app at Contents/Resources/speech/speech.
    static var binary: URL? {
        if let env = ProcessInfo.processInfo.environment["IELTSMOCK_SPEECH_BIN"], FileManager.default.isExecutableFile(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        if let u = Bundle.main.resourceURL?.appendingPathComponent("speech/speech"), FileManager.default.isExecutableFile(atPath: u.path) {
            return u
        }
        return nil
    }

    /// Regions of speech in each file, from Silero VAD (`speech vad --format json`).
    static func detectSpeech(in files: [URL], model: URL) async throws -> [URL: [SpeechRegion]] {
        guard let bin = binary else { throw SpeechEngineError.missingBinary }
        guard !files.isEmpty else { return [:] }
        return try await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = bin
            p.arguments = ["vad", model.path] + files.map(\.path) + ["--format", "json", "--threads", "2"]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw SpeechEngineError.failed(String(data: errData, encoding: .utf8)?.split(separator: "\n").last.map(String.init) ?? "vad exited \(p.terminationStatus)")
            }
            var result: [URL: [SpeechRegion]] = [:]
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let file = obj["file"] as? String else { continue }
                let regions = (obj["regions"] as? [[String: Any]] ?? []).compactMap { r -> SpeechRegion? in
                    guard let s = (r["start"] as? NSNumber)?.doubleValue, let e = (r["end"] as? NSNumber)?.doubleValue else { return nil }
                    return SpeechRegion(start: s, end: e)
                }
                result[URL(fileURLWithPath: file)] = regions
            }
            for f in files where result[f] == nil { result[f] = [] }
            return result
        }.value
    }

    /// 16-bit mono samples of a recording, at the file's own rate.
    static func pcm16(of url: URL) throws -> (data: Data, sampleRate: Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let format = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SpeechEngineError.failed("无法读取录音")
        }
        try file.read(into: buf)
        guard let ch = buf.int16ChannelData else { throw SpeechEngineError.failed("录音格式不支持") }
        let channels = Int(format.channelCount)
        let frames = Int(buf.frameLength)
        if channels == 1 {
            return (Data(bytes: ch[0], count: frames * 2), format.sampleRate)
        }
        // Interleaved stereo: average the channels.
        var mono = [Int16](repeating: 0, count: frames)
        let p = ch[0]
        for i in 0..<frames {
            var s = 0
            for c in 0..<channels { s += Int(p[i * channels + c]) }
            mono[i] = Int16(s / channels)
        }
        return (mono.withUnsafeBufferPointer { Data(buffer: $0) }, format.sampleRate)
    }
}

/// A `speech worker` process that keeps Qwen3-ASR loaded and transcribes one recording at a time
/// (worker protocol 3: JSON Lines on stdin and stdout).
final class SpeechWorker: @unchecked Sendable {
    struct Transcript {
        var text: String
        var languages: [String]
    }

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var ready: CheckedContinuation<Void, Error>?
    private var errorTail = ""
    private var nextID = 0
    private var exited = false

    private init() {}

    /// Starts the worker and waits until the model is loaded and warmed up (about 5 s on Apple silicon).
    static func start(model: URL, language: String = "en") async throws -> SpeechWorker {
        guard let bin = SpeechEngine.binary else { throw SpeechEngineError.missingBinary }
        let w = SpeechWorker()
        w.process.executableURL = bin
        w.process.arguments = ["worker", model.path, "--device", "auto", "--language", language]
        w.process.standardInput = w.stdin
        w.process.standardOutput = w.stdout
        w.process.standardError = w.stderr
        w.stdout.fileHandleForReading.readabilityHandler = { [weak w] h in w?.consume(h.availableData) }
        w.stderr.fileHandleForReading.readabilityHandler = { [weak w] h in
            guard let w, let s = String(data: h.availableData, encoding: .utf8) else { return }
            w.lock.lock()
            w.errorTail = String((w.errorTail + s).suffix(600))
            w.lock.unlock()
        }
        w.process.terminationHandler = { [weak w] _ in w?.terminated() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            w.lock.lock()
            w.ready = c
            w.lock.unlock()
            do { try w.process.run() } catch {
                w.lock.lock()
                w.ready = nil
                w.lock.unlock()
                c.resume(throwing: error)
            }
        }
        return w
    }

    func transcribe(_ wav: URL) async throws -> Transcript {
        let (pcm, rate) = try SpeechEngine.pcm16(of: wav)
        let id: String = {
            lock.lock(); defer { lock.unlock() }
            nextID += 1
            return "t\(nextID)"
        }()
        let reply = try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
            lock.lock()
            if exited {
                lock.unlock()
                c.resume(throwing: SpeechEngineError.failed("语音引擎已退出：\(errorTail)"))
                return
            }
            pending[id] = c
            lock.unlock()
            // Ten seconds of audio per chunk line.
            let step = Int(rate) * 2 * 10
            var seq = 0
            var offset = 0
            repeat {
                let end = min(pcm.count, offset + step)
                send(["type": "chunk", "id": id, "seq": seq, "pcm": pcm.subdata(in: offset..<end).base64EncodedString()])
                seq += 1
                offset = end
            } while offset < pcm.count
            send(["type": "transcribe", "id": id, "sample_rate": Int(rate)])
        }
        if reply["type"] as? String == "end" {
            return Transcript(text: (reply["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              languages: reply["languages"] as? [String] ?? [])
        }
        let err = (reply["error"] as? [String: Any])?["message"] as? String ?? "\(reply["type"] ?? "error")"
        throw SpeechEngineError.failed(err)
    }

    func stop() {
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [process] in
            if process.isRunning { process.terminate() }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard var d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        d.append(UInt8(ascii: "\n"))
        try? stdin.fileHandleForWriting.write(contentsOf: d)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines {
            guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = msg["type"] as? String else { continue }
            lock.lock()
            switch type {
            case "ready":
                let c = ready
                ready = nil
                lock.unlock()
                c?.resume()
            case "fatal":
                let c = ready
                ready = nil
                lock.unlock()
                let m = (msg["error"] as? [String: Any])?["message"] as? String ?? "worker failed"
                c?.resume(throwing: SpeechEngineError.failed(m))
            case "end", "error", "cancelled":
                let id = msg["id"] as? String ?? ""
                let c = pending.removeValue(forKey: id)
                lock.unlock()
                c?.resume(returning: msg)
            default:
                lock.unlock()
            }
        }
    }

    private func terminated() {
        lock.lock()
        exited = true
        let tail = errorTail
        let waiting = pending
        pending = [:]
        let r = ready
        ready = nil
        lock.unlock()
        let err = SpeechEngineError.failed(tail.isEmpty ? "语音引擎意外退出" : tail)
        r?.resume(throwing: err)
        for c in waiting.values { c.resume(throwing: err) }
    }
}
