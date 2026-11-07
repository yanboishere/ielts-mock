import SwiftUI
import AVFoundation

// MARK: - pre-flight

/// Checks before a Speaking test: microphone, speech models and engine, AI key.
struct SpeakingPreflightView: View {
    let launch: SpeakingLaunch
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var models: SpeechModelStore
    @Environment(\.dismiss) private var dismiss
    @State private var micStatus = SpeakingRecorder.permission
    @StateObject private var probe = SpeakingRecorder()

    var micReady: Bool { micStatus == .authorized || !SpeakingRecorder.debugFeed.isEmpty }
    var engineReady: Bool { SpeechEngine.binary != nil }
    var canStart: Bool { micReady && models.allReady && engineReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "mic.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.moduleColor(.speaking))
                VStack(alignment: .leading, spacing: 2) {
                    Text("口语考试准备 · \(launch.ref.exam.shortTitle)").font(.title2.bold())
                    Text(launch.part.map { "Part \($0) 专项练习" } ?? "全真口语模考 · Part 1 → Part 2 → Part 3，约 11–14 分钟")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            checkRow(ok: micReady, title: "麦克风") {
                switch micStatus {
                case .authorized:
                    VStack(alignment: .leading, spacing: 4) {
                        LevelMeter(level: probe.level).frame(height: 8)
                        Text("说几句话，音量条应随声音明显跳动。建议在安静的环境中使用耳机麦克风。").font(.caption).foregroundStyle(.secondary)
                    }
                case .notDetermined:
                    Button("允许使用麦克风") { Task { _ = await SpeakingRecorder.requestPermission(); micStatus = SpeakingRecorder.permission; startProbe() } }
                default:
                    HStack {
                        Text("麦克风权限被拒绝。").foregroundStyle(.red)
                        Button("打开系统设置") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }
                }
            }
            ForEach(SpeechCatalog.all) { spec in
                checkRow(ok: models.state(spec) == .ready, title: spec.title) { ModelStatusView(spec: spec) }
            }
            checkRow(ok: engineReady, title: "语音引擎 speech.cpp") {
                Text(engineReady ? "已内置" : "未找到：请使用完整打包的 App").font(.callout).foregroundStyle(engineReady ? Color.secondary : .red)
            }
            checkRow(ok: settings.hasKeyForCurrentProvider, title: "AI 评分", optional: true) {
                Text(settings.hasKeyForCurrentProvider
                     ? "考完由 \(settings.provider.label)（\(settings.currentModel)）按官方标准评分"
                     : "未配置 API Key：考完仍会显示转写和流利度指标，配置 Key 后可在结果页补评分。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("显示考官问题的文字（真实考试中没有）", isOn: $settings.speakingShowText)
            HStack {
                Toggle("说完后静音自动进入下一题", isOn: Binding(get: { settings.speakingAutoEnd > 0 }, set: { settings.speakingAutoEnd = $0 ? 4 : 0 }))
                if settings.speakingAutoEnd > 0 {
                    Stepper("\(Int(settings.speakingAutoEnd)) 秒", value: $settings.speakingAutoEnd, in: 2...10, step: 1).fixedSize()
                }
            }
            Text("录音只保存在本机，用于本地转写与回放；AI 评分时只发送转写文字和停顿统计，不上传录音。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { probe.cancel(); app.speakingLaunch = nil }
                    .keyboardShortcut(.cancelAction)
                Button("开始口语考试") { probe.cancel(); app.beginSpeaking(launch) }
                    .buttonStyle(.borderedProminent).tint(Theme.brand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear { startProbe() }
        .onDisappear { probe.cancel() }
    }

    func startProbe() {
        guard micStatus == .authorized, !probe.isRecording, SpeakingRecorder.debugFeed.isEmpty else { return }
        try? probe.start(to: FileManager.default.temporaryDirectory.appendingPathComponent("ielts-mic-check.wav"))
    }

    func checkRow<C: View>(ok: Bool, title: String, optional: Bool = false, @ViewBuilder detail: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : (optional ? "minus.circle" : "exclamationmark.circle.fill"))
                .foregroundStyle(ok ? Theme.correct : (optional ? Color.secondary : Color.orange))
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                detail()
            }
            Spacer(minLength: 0)
        }
    }
}

/// Download / verify / import status of one speech model.
struct ModelStatusView: View {
    let spec: SpeechModelSpec
    @EnvironmentObject var models: SpeechModelStore
    @EnvironmentObject var settings: SettingsStore
    @State private var importing = false

    var body: some View {
        let size = ByteCountFormatter.string(fromByteCount: spec.size, countStyle: .file)
        VStack(alignment: .leading, spacing: 4) {
            switch models.state(spec) {
            case .ready:
                Text("已下载并校验（\(size)）").font(.callout).foregroundStyle(.secondary)
            case .verifying:
                HStack { ProgressView().controlSize(.small); Text("正在校验 SHA-256…").font(.callout) }
            case .downloading(let got, let total, let rate):
                ProgressView(value: Double(got), total: Double(total))
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: got, countStyle: .file)) / \(size)")
                    if rate > 0 { Text("· \(ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file))/s") }
                    Spacer()
                    Button("暂停") { models.cancel(spec) }
                }
                .font(.caption).foregroundStyle(.secondary)
            case .missing, .failed:
                if case .failed(let m) = models.state(spec) { Text(m).font(.caption).foregroundStyle(.red) }
                HStack {
                    let partial = models.partialBytes(spec)
                    Button(partial > 0 ? "继续下载（\(size)）" : "下载（\(size)）") { models.download(spec, mirror: settings.modelMirror) }
                    Toggle("国内镜像", isOn: $settings.modelMirror).toggleStyle(.checkbox)
                    Button("导入文件…") { importing = true }
                }
                Text("来源：\(settings.modelMirror ? "hf-mirror.com" : "huggingface.co") · \(spec.repository) @ \(spec.revision.prefix(8))，下载后校验 SHA-256")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { r in
            if case .success(let url) = r {
                Task {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    await models.importFile(url, for: spec)
                }
            }
        }
    }
}

struct LevelMeter: View {
    var level: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(level > 0.85 ? Color.orange : Theme.correct)
                    .frame(width: max(4, g.size.width * level))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
    }
}

// MARK: - the test

struct SpeakingExamView: View {
    @ObservedObject var session: SpeakingSession
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsStore
    @State private var confirmExit = false

    var body: some View {
        VStack(spacing: 0) {
            SpeakingTopBar(session: session, confirmExit: $confirmExit)
            Divider()
            Group {
                switch session.phase {
                case .ready: SpeakingIntroView(session: session)
                case .processing(let step): processing(step)
                case .finished: SpeakingFinishedView(session: session)
                default: SpeakingStageView(session: session, recorder: session.recorder, examiner: session.examiner)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(settings.examContrast.background)
        .foregroundStyle(settings.examContrast.ink)
        .environment(\.colorScheme, settings.examContrast.isDark ? .dark : .light)
        .confirmationDialog("结束口语考试？", isPresented: $confirmExit, titleVisibility: .visible) {
            if session.phase == .ready {
                Button("返回") { app.endSpeaking() }
            } else if case .processing = session.phase {
                Button("放弃本次结果", role: .destructive) { app.endSpeaking() }
            } else if session.phase == .finished {
                Button("查看结果") { app.endSpeaking() }
            } else {
                Button("结束并评分已完成的部分") { session.endEarly() }
                Button("放弃本次考试", role: .destructive) { app.endSpeaking() }
            }
            Button("继续", role: .cancel) {}
        } message: {
            Text(session.phase == .ready ? "" : "放弃会删除本次录音。")
        }
    }

    func processing(_ step: String) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(step).font(.title3)
            if step.hasPrefix("正在转写") {
                ProgressView(value: session.processingProgress).frame(width: 320)
                Text("本地识别（\(SpeechCatalog.asr.title)），录音不会上传").font(.caption).foregroundStyle(.secondary)
            }
            if let e = session.errorMessage { Text(e).font(.caption).foregroundStyle(.red).frame(maxWidth: 520) }
        }
    }
}

struct SpeakingTopBar: View {
    @ObservedObject var session: SpeakingSession
    @Binding var confirmExit: Bool
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 14) {
            Text("IELTS").font(.system(size: 22, weight: .heavy)).foregroundStyle(settings.examContrast.isDark ? settings.examContrast.ink : Theme.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(settings.candidateName.isEmpty ? "Candidate" : settings.candidateName) - \(session.ref.exam.id)").font(.system(size: 13, weight: .semibold))
                Text("\(session.ref.exam.shortTitle) · \(session.mode == .practice ? "口语专项练习" : "口语模考")").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if session.part > 0 {
                HStack(spacing: 6) {
                    ForEach(session.speaking?.parts ?? [], id: \.self) { p in
                        Text("Part \(p)")
                            .font(.system(size: 13, weight: p == session.part ? .bold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(p == session.part ? Theme.moduleColor(.speaking).opacity(0.18) : Color.clear))
                            .opacity(session.practicePart == nil || session.practicePart == p ? 1 : 0.35)
                    }
                }
            }
            HStack(spacing: 12) {
                if let s = session.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Label(formatClock(ctx.date.timeIntervalSince(s)), systemImage: "clock").monospacedDigit()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                Button(session.phase == .finished ? "完成" : "退出") { confirmExit = true }
                    .buttonStyle(CBTBarButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(settings.examContrast.background)
    }
}

func formatClock(_ s: Double) -> String {
    let t = Int(max(0, s))
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct SpeakingIntroView: View {
    @ObservedObject var session: SpeakingSession

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "person.wave.2").font(.system(size: 46)).foregroundStyle(Theme.moduleColor(.speaking))
                Text("IELTS Speaking").font(.system(size: 30, weight: .bold))
                Text(session.practicePart.map { "Part \($0) 专项练习" } ?? "约 11–14 分钟 · 三个部分").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("INSTRUCTIONS TO CANDIDATES").font(.headline)
                    ForEach(lines, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: 660, alignment: .leading)
                .card()
                HStack(spacing: 8) {
                    if !session.engineReady { ProgressView().controlSize(.small) }
                    Image(systemName: session.engineReady ? "checkmark.circle.fill" : "waveform").foregroundStyle(session.engineReady ? Theme.correct : .secondary)
                    Text(session.engineStatus).foregroundStyle(.secondary)
                }
                Button { session.begin() } label: { Text("开始").frame(minWidth: 160) }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.brand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.engineReady)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    var lines: [String] {
        var a = [
            "Part 1 (4–5 minutes): the examiner asks general questions about yourself and familiar topics.",
            "Part 2 (3–4 minutes): you get a task card, one minute to prepare (you can make notes) and then talk for one to two minutes.",
            "Part 3 (4–5 minutes): a discussion of more abstract questions linked to the Part 2 topic.",
            "考官用语音提问，问完立刻开始录音；说完点「回答完毕」（⌘↩），或停顿几秒后自动进入下一题。",
            "Part 2 讲满 2 分钟考官会打断；不足 1 分钟考官会请你再多说一些。",
            "考后在本地转写与分析停顿、语速、语调，再按官方四项标准评分（发音为估算）。",
        ]
        if let p = session.practicePart { a = [a[p - 1]] + Array(a.suffix(3)) }
        return a
    }
}

struct SpeakingStageView: View {
    @ObservedObject var session: SpeakingSession
    @ObservedObject var recorder: SpeakingRecorder
    @ObservedObject var examiner: Examiner
    @EnvironmentObject var settings: SettingsStore

    var answering: Bool { if case .answering = session.phase { return true }; return false }
    var limit: Double { if case .answering(let l) = session.phase { return l }; return 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                examinerPanel
                if session.showCueCard, let c = session.cueCard {
                    CueCardView(card: c)
                }
            }
            .frame(maxWidth: 520)
            VStack(spacing: 16) {
                if session.phase == .preparing {
                    preparation
                } else {
                    candidatePanel
                }
                if session.showCueCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        TextEditor(text: $session.notes)
                            .font(.system(size: 15))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.25)))
                            .frame(minHeight: 160)
                    }
                }
            }
            .frame(maxWidth: 520)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var examinerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.moduleColor(.speaking).opacity(0.14)).frame(width: 56, height: 56)
                    Image(systemName: examiner.isSpeaking ? "waveform" : "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.moduleColor(.speaking))
                        .symbolEffect(.variableColor.iterative, isActive: examiner.isSpeaking)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Examiner · \(examiner.name)").font(.headline)
                    Text(examiner.isSpeaking ? "正在提问…" : (answering ? "请回答" : (session.phase == .preparing ? "准备时间" : " ")))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if answering, !session.question.isEmpty {
                    Button { session.repeatQuestion() } label: { Label("再说一遍", systemImage: "arrow.counterclockwise") }
                        .help("Could you repeat the question, please?")
                }
            }
            let text = examiner.isSpeaking ? examiner.line : session.question
            if settings.speakingShowText || session.revealQuestion {
                Text(InlineMarkup.strip(text)).font(.system(size: 18 * settings.fontScale)).fixedSize(horizontal: false, vertical: true)
            } else if !text.isEmpty {
                Button { session.revealQuestion = true } label: { Label("显示题目文字", systemImage: "eye") }
                    .buttonStyle(.link)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    var candidatePanel: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 10).frame(width: 150, height: 150)
                Circle()
                    .trim(from: 0, to: answering && limit > 0 ? min(1, recorder.elapsed / limit) : 0)
                    .stroke(Theme.moduleColor(.speaking), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 150)
                Circle().fill((answering ? Theme.brand : Color.secondary).opacity(0.12 + 0.5 * recorder.level))
                    .frame(width: 70 + 50 * recorder.level, height: 70 + 50 * recorder.level)
                    .animation(.linear(duration: 0.08), value: recorder.level)
                Image(systemName: answering ? "mic.fill" : "mic.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(answering ? Theme.brand : .secondary)
            }
            if answering {
                Text("\(formatClock(recorder.elapsed)) / \(formatClock(limit))").font(.title3.monospacedDigit())
                if session.part == 2, limit >= 100 {
                    Text(recorder.elapsed < 60 ? "至少讲满 1 分钟" : "讲到 2 分钟考官会打断").font(.caption).foregroundStyle(.secondary)
                } else if settings.speakingAutoEnd > 0 && recorder.hasSpoken && recorder.silence > 1 {
                    Text("停顿 \(Int(settings.speakingAutoEnd)) 秒后自动进入下一题").font(.caption).foregroundStyle(.secondary)
                }
                Button { session.answerFinished() } label: { Text("回答完毕").frame(minWidth: 140) }
                    .buttonStyle(.borderedProminent).tint(Theme.brand).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Text(examiner.isSpeaking ? "请听考官提问" : " ").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    var preparation: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 10).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: session.prepRemaining / 60)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                    .animation(.linear(duration: 0.1), value: session.prepRemaining)
                Text("\(Int(session.prepRemaining.rounded(.up)))").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text("准备时间：可以在下方记笔记").foregroundStyle(.secondary)
            Button("准备好了，现在开始") { session.startTalkingNow() }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

/// The Part 2 task card as the book prints it.
struct CueCardView: View {
    let card: CueCard
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let fs = 16 * settings.fontScale
        VStack(alignment: .leading, spacing: 8) {
            MarkupText(card.topic, font: .system(size: fs + 2, weight: .bold))
            if let p = card.prompt { Text(p).font(.system(size: fs)) }
            ForEach(card.points, id: \.self) { pt in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    MarkupText(pt, font: .system(size: fs))
                }
                .padding(.leading, 12)
            }
            if let c = card.closing { MarkupText(c, font: .system(size: fs)) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.6), lineWidth: 1.5))
    }
}

struct SpeakingFinishedView: View {
    @ObservedObject var session: SpeakingSession
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.correct)
            Text("口语考试结束").font(.largeTitle.bold())
            if let a = session.attempt.speaking?.assessment {
                BandBadge(band: a.overallBand, label: "口语总分", size: 44)
                HStack(spacing: 20) {
                    ForEach(a.criteria) { c in
                        VStack(spacing: 2) {
                            Text(c.key).font(.caption).foregroundStyle(.secondary)
                            Text(Grader.bandString(c.band)).font(.title2.bold())
                            if c.estimated { Pill(text: "估算", color: .orange) }
                        }
                    }
                }
            } else if let m = session.attempt.speaking?.metrics {
                Text(String(format: "共说了 %d 个词，语速 %.0f 词/分钟", m.words, m.speechRate)).foregroundStyle(.secondary)
                if let e = session.ai.errors.first(where: { $0.key.hasPrefix("speaking-") })?.value {
                    Text("AI 评分失败：\(e)").foregroundStyle(.red).frame(maxWidth: 520)
                }
            }
            Button("查看结果与解析") { app.endSpeaking() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}
