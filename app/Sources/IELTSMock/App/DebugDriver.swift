import Foundation
import AppKit

/// Development-only remote control, active when launched with IELTSMOCK_DEBUG=1.
/// Commands arrive as distributed notifications named "local.ieltsmock.debug" whose object is a command line, e.g.
///   snap /tmp/a.png | route library | open C15-T1 | full C15-T1 | module C15-T1 reading
///   practice C15-T1 reading 1 | begin | go 14 | answer 3 Smith | section 2 | submit | end | font 1.2 | review <attemptId>
/// Send with scripts/debugctl.swift.
@MainActor
final class DebugDriver {
    static var shared: DebugDriver?
    static let reviewRequest = Notification.Name("IELTSMockDebugReview")
    private weak var app: AppState?
    private var observer: NSObjectProtocol?

    static func installIfRequested(_ app: AppState) {
        guard ProcessInfo.processInfo.environment["IELTSMOCK_DEBUG"] == "1", shared == nil else { return }
        let d = DebugDriver()
        d.app = app
        d.observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.ieltsmock.debug"), object: nil, queue: .main
        ) { note in
            let cmd = note.object as? String ?? ""
            Task { @MainActor in d.run(cmd) }
        }
        shared = d
    }

    private func reply(_ text: String) {
        let url = URL(fileURLWithPath: "/tmp/ieltsmock-debug.log")
        let line = "\(Date().timeIntervalSince1970) \(text)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func run(_ line: String) {
        guard let app else { return }
        let p = line.split(separator: " ", maxSplits: 3).map(String.init)
        guard let c = p.first else { return }
        func arg(_ i: Int) -> String { i < p.count ? p[i] : "" }
        switch c {
        case "snap": snap(to: arg(1))
        case "route":
            let r: [String: Route] = ["home": .home, "library": .library, "history": .history,
                                      "mistakes": .mistakes, "writing": .writingLog, "custom": .custom]
            if let route = r[arg(1)] { app.navigate(route) }
        case "open": app.open(.test(arg(1)))
        case "book": app.open(.book(Int(arg(1)) ?? 15))
        case "attempt":
            if let a = app.history.attempts.first { app.navigate(.history, open: .attempt(a.id)) }
        case "full": if let r = app.bank.ref(arg(1)) { app.startFullMock(r) }
        case "module":
            if let r = app.bank.ref(arg(1)), let m = Module(rawValue: arg(2)) { app.startModule(r, m) }
        case "practice":
            if let r = app.bank.ref(arg(1)), let m = Module(rawValue: arg(2)) {
                app.startPractice(r, m, section: Int(arg(3)) ?? 1)
            }
        case "review":
            NotificationCenter.default.post(name: DebugDriver.reviewRequest, object: Module(rawValue: arg(1)) ?? .listening)
        case "ai":   // ai <claude|openai> <baseURL> <key> [model]
            if let k = AIProviderKind(rawValue: arg(1)) {
                app.settings.provider = k
                let rest = p.count > 3 ? p[3].split(separator: " ").map(String.init) : []
                if k == .claude { app.settings.claudeBaseURL = arg(2) } else { app.settings.openaiBaseURL = arg(2) }
                app.settings.setAPIKey(rest.first ?? "", for: k)
                if rest.count > 1 { if k == .claude { app.settings.claudeModel = rest[1] } else { app.settings.openaiModel = rest[1] } }
            }
        case "aireset":
            for k in [AIProviderKind.claude, .openai] { app.settings.setAPIKey("", for: k) }
            app.settings.claudeBaseURL = "https://api.anthropic.com"
            app.settings.openaiBaseURL = "https://api.openai.com/v1"
            app.settings.provider = .claude
        case "aitest":
            Task { do { reply("aitest: " + (try await app.ai.testConnection())) } catch { reply("aitest error: \(error)") } }
        case "explain":   // explain <module> <section>
            if let a = app.history.attempts.first, let r = app.bank.ref(a.examId), let m = Module(rawValue: arg(1)) {
                Task {
                    await AIActions.explain(ai: app.ai, history: app.history, attemptId: a.id, ref: r, module: m, section: Int(arg(2)) ?? 0, onlyMissing: false)
                    reply("explain done; errors: \(app.ai.errors)")
                }
            }
        case "assess":    // assess <task>
            if let a = app.history.attempts.first, let r = app.bank.ref(a.examId),
               let t = r.exam.writing?.tasks.first(where: { $0.task == Int(arg(1)) }) {
                Task {
                    await AIActions.assess(ai: app.ai, history: app.history, attemptId: a.id, ref: r, task: t)
                    reply("assess done; errors: \(app.ai.errors)")
                }
            }
        case "begin": app.session?.startTimer()
        case "go": if let n = Int(arg(1)) { app.session?.go(to: n) }
        case "section": if let n = Int(arg(1)) { app.session?.currentSection = n }
        case "answer":
            if let n = Int(arg(1)) { app.session?.setAnswer(n, p.count > 2 ? p[2...].joined(separator: " ") : "") }
        case "essay":
            if let n = Int(arg(1)) { app.session?.setEssay(n, p.count > 2 ? p[2...].joined(separator: " ") : "") }
        case "submit": app.session?.submitStage()
        case "end": app.endSession(discard: arg(1) == "discard")
        case "font": app.settings.fontScale = Double(arg(1)) ?? 1
        case "quit": NSApp.terminate(nil)
        default: reply("unknown command: \(line)")
        }
        reply("ok: \(c == "ai" ? "ai \(arg(1)) <redacted>" : line)")
    }

    /// Renders the main window's content (including sheets attached to it) without needing screen-recording permission.
    private func snap(to path: String) {
        guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }),
              let view = win.contentView?.superview ?? win.contentView else {
            reply("snap: no window"); return
        }
        var images: [(NSBitmapImageRep, NSRect)] = []
        for w in [win] + (win.attachedSheet.map { [$0] } ?? []) {
            guard let v = w.contentView?.superview ?? w.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            images.append((rep, w.frame))
        }
        guard let base = images.first else { return }
        let scale = CGFloat(base.0.pixelsWide) / base.1.width
        let out = NSImage(size: NSSize(width: base.0.pixelsWide, height: base.0.pixelsHigh))
        out.lockFocus()
        for (rep, frame) in images {
            let r = NSRect(x: (frame.minX - base.1.minX) * scale, y: (frame.minY - base.1.minY) * scale,
                           width: frame.width * scale, height: frame.height * scale)
            rep.draw(in: r)
        }
        out.unlockFocus()
        _ = view
        guard let tiff = out.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        reply("snap: \(path)")
    }
}
