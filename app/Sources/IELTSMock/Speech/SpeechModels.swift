import Foundation
import CryptoKit

/// A model file pinned by repository revision and SHA-256, as Arion and speech.cpp pin them.
struct SpeechModelSpec: Identifiable, Hashable {
    let id: String
    let title: String
    let repository: String
    let revision: String
    let file: String
    let size: Int64
    let sha256: String

    func url(mirror: Bool) -> URL {
        let host = mirror ? "hf-mirror.com" : "huggingface.co"
        return URL(string: "https://\(host)/\(repository)/resolve/\(revision)/\(file)")!
    }
}

enum SpeechCatalog {
    /// Qwen3-ASR 1.7B in Q8_0, the recognition model Arion adopts (models/catalog.json, artifact qwen3-asr-1.7b-gguf-q8).
    static let asr = SpeechModelSpec(
        id: "qwen3-asr-1.7b-q8_0", title: "Qwen3-ASR 1.7B（Q8_0）",
        repository: "sakasegawa/Qwen3-ASR-1.7B-GGUF", revision: "81e2423d24073cdeeccb5951df16accc89e075a2",
        file: "Qwen3-ASR-1.7B-Q8_0.gguf", size: 2_176_109_216,
        sha256: "5f219b78a1d9c3b9e97da27708b36f8a0bc1bfc1650b541c0a6dbaf87c9a62d0")

    /// Silero VAD v6.2, for the pauses between stretches of speech.
    static let vad = SpeechModelSpec(
        id: "silero-vad-v6.2", title: "Silero VAD v6.2",
        repository: "sakasegawa/silero-vad-GGUF", revision: "7fcb7aa2a70c312f8579fc987b3e1cdecf9321ca",
        file: "silero-vad-309K-v6.2-F32.gguf", size: 1_238_624,
        sha256: "2fc312514e5fc4fa4ffd02b25c76a4853fa4130e8fb9777d01502183b01238cb")

    static let all = [asr, vad]
}

/// Downloads, verifies and keeps the speech models in ~/Library/Application Support/IELTSMock/Models.
@MainActor
final class SpeechModelStore: ObservableObject {
    enum State: Equatable {
        case missing
        case downloading(received: Int64, total: Int64, bytesPerSecond: Double)
        case verifying
        case ready
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    private var downloads: [String: ModelDownload] = [:]

    init() { refresh() }

    func fileURL(_ spec: SpeechModelSpec) -> URL { AppPaths.models.appendingPathComponent(spec.file) }
    private func partURL(_ spec: SpeechModelSpec) -> URL { AppPaths.models.appendingPathComponent(spec.file + ".part") }
    /// Written after a successful SHA-256 check so that the 2 GB file is not hashed on every launch.
    private func markerURL(_ spec: SpeechModelSpec) -> URL { AppPaths.models.appendingPathComponent(spec.file + ".verified") }

    func state(_ spec: SpeechModelSpec) -> State { states[spec.id] ?? .missing }
    var allReady: Bool { SpeechCatalog.all.allSatisfy { state($0) == .ready } }

    func refresh() {
        for spec in SpeechCatalog.all where downloads[spec.id] == nil {
            states[spec.id] = isVerified(spec) ? .ready : .missing
        }
    }

    private func isVerified(_ spec: SpeechModelSpec) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL(spec).path),
              (attrs[.size] as? NSNumber)?.int64Value == spec.size,
              let marker = try? String(contentsOf: markerURL(spec), encoding: .utf8) else { return false }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines) == spec.sha256
    }

    /// Bytes already downloaded of an interrupted download.
    func partialBytes(_ spec: SpeechModelSpec) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: partURL(spec).path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    func downloadAll(mirror: Bool) {
        for spec in SpeechCatalog.all where state(spec) != .ready { download(spec, mirror: mirror) }
    }

    func download(_ spec: SpeechModelSpec, mirror: Bool) {
        guard downloads[spec.id] == nil else { return }
        let d = ModelDownload(spec: spec, url: spec.url(mirror: mirror), part: partURL(spec)) { [weak self] event in
            Task { @MainActor in self?.handle(event, spec) }
        }
        downloads[spec.id] = d
        states[spec.id] = .downloading(received: partialBytes(spec), total: spec.size, bytesPerSecond: 0)
        d.start()
    }

    func cancel(_ spec: SpeechModelSpec) {
        downloads[spec.id]?.cancel()
        downloads[spec.id] = nil
        states[spec.id] = .missing
    }

    func delete(_ spec: SpeechModelSpec) {
        cancel(spec)
        for u in [fileURL(spec), partURL(spec), markerURL(spec)] { try? FileManager.default.removeItem(at: u) }
        states[spec.id] = .missing
    }

    /// Takes a model file the user downloaded elsewhere, after checking its SHA-256.
    func importFile(_ source: URL, for spec: SpeechModelSpec) async {
        states[spec.id] = .verifying
        do {
            let digest = try await Self.sha256(of: source)
            guard digest == spec.sha256 else {
                states[spec.id] = .failed("文件校验不符（SHA-256 \(digest.prefix(12))…），请确认选择的是 \(spec.file)。")
                return
            }
            let dest = fileURL(spec)
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.copyItem(at: source, to: dest) }
            try digest.write(to: markerURL(spec), atomically: true, encoding: .utf8)
            states[spec.id] = .ready
        } catch {
            states[spec.id] = .failed(error.localizedDescription)
        }
    }

    private func handle(_ event: ModelDownload.Event, _ spec: SpeechModelSpec) {
        switch event {
        case .progress(let received, let rate):
            states[spec.id] = .downloading(received: received, total: spec.size, bytesPerSecond: rate)
        case .failed(let message):
            downloads[spec.id] = nil
            states[spec.id] = .failed(message)
        case .finished:
            downloads[spec.id] = nil
            states[spec.id] = .verifying
            Task {
                do {
                    let digest = try await Self.sha256(of: partURL(spec))
                    guard digest == spec.sha256 else {
                        try? FileManager.default.removeItem(at: partURL(spec))
                        states[spec.id] = .failed("下载的文件校验不符，已删除，请重新下载。")
                        return
                    }
                    try? FileManager.default.removeItem(at: fileURL(spec))
                    try FileManager.default.moveItem(at: partURL(spec), to: fileURL(spec))
                    try digest.write(to: markerURL(spec), atomically: true, encoding: .utf8)
                    states[spec.id] = .ready
                } catch {
                    states[spec.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    nonisolated static func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let h = try FileHandle(forReadingFrom: url)
            defer { try? h.close() }
            var hasher = SHA256()
            while let chunk = try h.read(upToCount: 16 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}

/// Streams one file to `<name>.part`, resuming from what is already there with an HTTP range request.
final class ModelDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event {
        case progress(Int64, Double)
        case finished
        case failed(String)
    }

    let spec: SpeechModelSpec
    let url: URL
    let part: URL
    let report: (Event) -> Void
    private var session: URLSession?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var lastReport = Date.distantPast
    private var rateWindow: (Date, Int64) = (Date(), 0)
    private var rate: Double = 0
    private var cancelled = false

    init(spec: SpeechModelSpec, url: URL, part: URL, report: @escaping (Event) -> Void) {
        self.spec = spec
        self.url = url
        self.part = part
        self.report = report
    }

    func start() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: part.path) { fm.createFile(atPath: part.path, contents: nil) }
        received = ((try? fm.attributesOfItem(atPath: part.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if received >= spec.size {
            report(.finished)
            return
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        var req = URLRequest(url: url)
        if received > 0 { req.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
        rateWindow = (Date(), received)
        session?.dataTask(with: req).resume()
    }

    func cancel() {
        cancelled = true
        session?.invalidateAndCancel()
        try? handle?.close()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        if received > 0 { r.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
        completionHandler(r)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            handle = try FileHandle(forWritingTo: part)
            if status == 206 {
                try handle?.seekToEnd()
            } else if status == 200 {
                // The server ignored the range: start over.
                try handle?.truncate(atOffset: 0)
                received = 0
            } else {
                report(.failed("服务器返回 HTTP \(status)。可在设置中换用镜像源再试。"))
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        } catch {
            report(.failed(error.localizedDescription))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
        } catch {
            report(.failed(error.localizedDescription))
            dataTask.cancel()
            return
        }
        received += Int64(data.count)
        let now = Date()
        let dt = now.timeIntervalSince(rateWindow.0)
        if dt >= 1 {
            rate = Double(received - rateWindow.1) / dt
            rateWindow = (now, received)
        }
        if now.timeIntervalSince(lastReport) > 0.25 {
            lastReport = now
            report(.progress(received, rate))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        session.finishTasksAndInvalidate()
        if cancelled { return }
        if let error {
            report(.failed("下载中断：\(error.localizedDescription)。再次点击下载会从断点继续。"))
        } else if received >= spec.size {
            report(.finished)
        } else {
            report(.failed("下载不完整（\(received)/\(spec.size) 字节），再次点击下载会从断点继续。"))
        }
    }
}
