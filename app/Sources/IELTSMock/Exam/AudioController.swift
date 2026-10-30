import Foundation
import AVFoundation

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var part: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float = 1.0 { didSet { if isPlaying { player?.rate = rate } } }
    @Published var volume: Float = 1.0 { didSet { player?.volume = volume } }

    var onFinished: ((Int) -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(_ url: URL, part: Int, autoplay: Bool) {
        stop()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = volume
        player = p
        self.part = part
        currentTime = 0
        duration = 0
        Task {
            if let d = try? await item.asset.load(.duration), d.isNumeric { self.duration = d.seconds }
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.currentTime = t.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.onFinished?(part)
            }
        }
        if autoplay { play() }
    }

    func play() {
        guard let p = player else { return }
        p.playImmediately(atRate: rate)
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to t: Double) {
        player?.seek(to: CMTime(seconds: max(0, min(t, duration > 0 ? duration : t)), preferredTimescale: 600))
        currentTime = t
    }

    func skip(_ delta: Double) { seek(to: currentTime + delta) }

    func stop() {
        player?.pause()
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        timeObserver = nil
        endObserver = nil
        player = nil
        isPlaying = false
        part = nil
    }

    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration), d.isNumeric { return d.seconds }
        return 0
    }
}
