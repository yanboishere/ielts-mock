import SwiftUI

struct ExamView: View {
    @ObservedObject var session: ExamSession
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsStore
    @State private var confirmExit = false

    var body: some View {
        VStack(spacing: 0) {
            ExamTopBar(confirmExit: $confirmExit)
            Divider()
            if session.finished {
                FinishedView()
            } else if session.awaitingStart {
                StageIntroView()
            } else {
                InstructionBar()
                Group {
                    switch session.module {
                    case .listening: ListeningPane()
                    case .reading: ReadingPane()
                    case .writing: WritingPane()
                    case .speaking: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if session.module != .writing { PrevNextButtons().padding(12) }
                }
                Divider()
                QuestionNavigator()
            }
        }
        .background(settings.examContrast.background)
        .foregroundStyle(settings.examContrast.ink)
        .environment(\.colorScheme, settings.examContrast.isDark ? .dark : .light)
        .tint(settings.examContrast == .yellowOnBlack ? settings.examContrast.ink : .accentColor)
        .overlay(alignment: .top) {
            if let b = session.banner {
                ReminderBannerView(banner: b) { session.banner = nil }
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: session.banner)
        .confirmationDialog(submitTitle, isPresented: $session.confirmSubmit, titleVisibility: .visible) {
            Button(session.isLastStage ? "确认交卷" : "交卷并进入\(nextModuleTitle)") { session.submitStage() }
            Button("继续作答", role: .cancel) {}
        } message: {
            Text(submitMessage)
        }
        .confirmationDialog("退出考试？", isPresented: $confirmExit, titleVisibility: .visible) {
            if session.finished {
                Button("查看结果") { app.endSession() }
            } else {
                Button("保存进度并退出") { app.endSession() }
                Button("放弃本次考试", role: .destructive) { app.endSession(discard: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(session.finished ? "" : "进度会自动保存，可以稍后在首页继续（计时从退出时的剩余时间继续；听力会从当前 Part 重新开始）。")
        }
    }

    var nextModuleTitle: String {
        session.stages.indices.contains(session.stageIndex + 1) ? session.stages[session.stageIndex + 1].module.title : ""
    }

    var submitTitle: String { session.isLastStage ? "确定交卷？" : "确定提交\(session.module.title)部分？" }

    var submitMessage: String {
        switch session.module {
        case .writing:
            let tasks = session.sections.compactMap { session.exam.writing?.tasks[safe: $0] }
            return tasks.map { t in
                let w = WordCounter.count(session.essay(t.task))
                return "Task \(t.task)：\(w) 词" + (w < t.minWords ? "（少于 \(t.minWords) 词会被扣分）" : "")
            }.joined(separator: "\n") + "\n提交后不能再修改。"
        default:
            let un = session.questionNumbers.count - session.answeredCount
            return (un > 0 ? "还有 \(un) 题未作答。" : "所有题目都已作答。") + "提交后不能再修改。"
        }
    }
}

// MARK: - top bar (modelled on the computer-delivered IELTS header)

struct ExamTopBar: View {
    @Binding var confirmExit: Bool
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 14) {
            Text("IELTS").font(.system(size: 22, weight: .heavy)).foregroundStyle(settings.examContrast.isDark ? settings.examContrast.ink : Theme.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidateLine).font(.system(size: 13, weight: .semibold))
                Text("\(session.exam.shortTitle) · \(session.mode.label)\(session.isReview ? " · 复盘" : "")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !session.isReview && !session.finished {
                TimerDisplay()
            }
            HStack(spacing: 12) {
                if session.module == .listening && !session.finished {
                    VolumeSlider(audio: session.audio)
                }
                if !session.isReview && !session.finished && session.allotted > 0 {
                    Button(session.hideTimer ? "Show" : "Hide") { session.hideTimer.toggle() }
                        .help("隐藏/显示计时（时间提醒仍会弹出）")
                }
                Button("Help") { showHelp = true }
                    .popover(isPresented: $showHelp, arrowEdge: .bottom) { ExamHelpView() }
                optionsMenu
            }
            .buttonStyle(CBTBarButtonStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(settings.examContrast.background)
    }

    var candidateLine: String {
        let name = settings.candidateName.isEmpty ? "Candidate" : settings.candidateName
        return "\(name) - \(session.exam.id)"
    }

    var optionsMenu: some View {
        Menu {
            Section("Contrast") {
                ForEach(ExamContrast.allCases) { c in
                    Button { settings.examContrast = c } label: {
                        if settings.examContrast == c { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                    }
                }
            }
            Section("Text size") {
                ForEach(ExamTextSize.allCases) { t in
                    Button { settings.fontScale = t.rawValue } label: {
                        if abs(settings.fontScale - t.rawValue) < 0.01 { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                    }
                }
            }
            Divider()
            if !session.finished && !session.awaitingStart && !session.isReview {
                Button(session.isLastStage ? "交卷" : "提交本部分") { session.confirmSubmit = true }
            }
            Button(session.finished ? "完成" : "退出考试…") { confirmExit = true }
        } label: {
            Image(systemName: "line.3.horizontal").font(.system(size: 17, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options：对比度、字号、退出")
    }
}

/// Flat, rectangular header buttons like the test software's.
struct CBTBarButtonStyle: ButtonStyle {
    @EnvironmentObject var settings: SettingsStore
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(settings.examContrast.ink.opacity(configuration.isPressed ? 0.2 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(settings.examContrast.ink.opacity(0.35)))
            .contentShape(Rectangle())
    }
}

struct ExamHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Help").font(.headline)
            Group {
                Text("• 底部题号可直接跳转；下划线 = 已作答，圆角框 = 标记了 Review。")
                Text("• 右下角箭头或 ⌘← / ⌘→ 切换上一题 / 下一题；填空按回车跳到下一题。")
                Text("• 阅读文章中选中文字后右键可高亮 / 清除高亮。")
                Text("• 右上角 ☰ 可调整对比度和字号（也可用 ⌘+ / ⌘-）。")
                Text("• Hide 隐藏计时；剩余 10 / 5 / 1 分钟仍会提醒。")
                Text("• 右下角 ✓ 交卷；交卷后不能再修改。")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
    }
}

struct VolumeSlider: View {
    @ObservedObject var audio: AudioController
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: audio.volume < 0.01 ? "speaker.slash" : "speaker.wave.2")
            Slider(value: Binding(get: { Double(audio.volume) }, set: { audio.volume = Float($0) }), in: 0...1)
                .frame(width: 90)
        }
        .help("音量")
    }
}

/// "35 minutes left" in the middle of the header, as in the real test; seconds are shown in the last two minutes.
struct TimerDisplay: View {
    @EnvironmentObject var session: ExamSession
    @State private var blink = false
    @State private var exact = false

    var color: Color {
        switch session.timeState {
        case .idle, .normal, .caution: return .primary
        case .warning, .critical: return Theme.wrong
        }
    }

    var text: String {
        let s = Int(session.remaining.rounded(.up))
        if exact { return session.timeText + " left" }
        if s <= 120 { return "\(s) seconds left" }
        let m = Int((Double(s) / 60).rounded(.up))
        return "\(m) minute\(m == 1 ? "" : "s") left"
    }

    var body: some View {
        HStack(spacing: 6) {
            if session.hideTimer {
                EmptyView()
            } else if session.module == .listening, case .ready = session.listeningPhase {
                Image(systemName: "clock")
                Text("Waiting to start")
            } else if session.allotted == 0 {
                Image(systemName: "headphones")
                Text(session.listeningStatus)
            } else {
                Image(systemName: "clock")
                Text(text)
                    .monospacedDigit()
                    .opacity(session.timeState == .critical && blink ? 0.35 : 1)
                    .onTapGesture { exact.toggle() }
                    .help("点击切换精确到秒")
                if session.paused { Text("(paused)").foregroundStyle(.secondary) }
                if !session.isStrict {
                    Button { session.togglePause() } label: { Image(systemName: session.paused ? "play.fill" : "pause.fill") }
                        .buttonStyle(.borderless)
                        .help(session.paused ? "继续计时" : "暂停计时（练习模式）")
                }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(color)
        .fixedSize()
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in blink.toggle() }
    }
}

struct ReminderBannerView: View {
    var banner: ReminderBanner
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.urgent ? "exclamationmark.triangle.fill" : "bell.fill")
                .font(.title2)
                .foregroundStyle(banner.urgent ? Theme.wrong : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.headline)
                Text(banner.message).font(.callout).foregroundStyle(.secondary)
            }
            Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(banner.urgent ? Theme.wrong.opacity(0.6) : Color.primary.opacity(0.1)))
        .shadow(radius: 12, y: 4)
    }
}

// MARK: - instruction bar

/// The grey box under the header: "Part 1  Read the text and answer questions 1–13."
struct InstructionBar: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 15 * min(settings.fontScale, 1.3), weight: .bold))
            Text(detail).font(.system(size: 14 * min(settings.fontScale, 1.3)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 3).fill(settings.examContrast.isDark ? Color.white.opacity(0.1) : Color(white: 0.94)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.15)))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    var label: String {
        let e = session.exam, i = session.currentSection
        switch session.module {
        case .listening: return "Part \(e.listening?.parts[safe: i]?.part ?? i + 1)"
        case .reading: return "Part \(e.reading?.passages[safe: i]?.passage ?? i + 1)"
        case .writing: return "Part \(e.writing?.tasks[safe: i]?.task ?? i + 1)"
        case .speaking: return ""
        }
    }

    var detail: String {
        let e = session.exam
        switch session.module {
        case .listening:
            guard let p = e.listening?.parts[safe: session.currentSection] else { return "" }
            return "Listen and answer questions \(p.first)–\(p.last)."
        case .reading:
            guard let p = e.reading?.passages[safe: session.currentSection] else { return "" }
            return "Read the text and answer questions \(p.first)–\(p.last)."
        case .writing:
            guard let t = e.writing?.tasks[safe: session.currentSection] else { return "" }
            return "You should spend about \(t.minutes) minutes on this task. Write at least \(t.minWords) words."
        case .speaking:
            return ""
        }
    }
}

// MARK: - navigator (bottom bar of the real test)

struct QuestionNavigator: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            if session.module != .writing, !session.isReview, let f = session.focusedQuestion {
                Toggle(isOn: Binding(get: { session.isFlagged(f) }, set: { _ in session.toggleFlag(f) })) {
                    Text("Review").font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.checkbox)
                .help("标记 Q\(f)，稍后复查（题号会显示为圆角框）")
                .padding(.horizontal, 12)
                Divider().frame(height: 30)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(session.sections, id: \.self) { i in
                        sectionItem(i)
                        Divider().frame(height: 30)
                    }
                }
            }
            Spacer(minLength: 8)
            if !session.finished && !session.awaitingStart && !session.isReview {
                Button { session.confirmSubmit = true } label: {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                        .frame(width: 46, height: 40)
                }
                .buttonStyle(CBTDarkButtonStyle())
                .help(session.isLastStage ? "交卷" : "提交本部分")
                .padding(.trailing, 10)
            }
        }
        .frame(height: 56)
        .background(settings.examContrast.isDark ? Color.white.opacity(0.08) : Color(white: 0.95))
    }

    func numbers(_ i: Int) -> [Int] {
        switch session.module {
        case .listening: return session.exam.listening.map { p in Array(p.parts[i].first...p.parts[i].last) } ?? []
        case .reading: return session.exam.reading.map { p in Array(p.passages[i].first...p.passages[i].last) } ?? []
        case .writing, .speaking: return []
        }
    }

    func title(_ i: Int) -> String {
        switch session.module {
        case .listening: return "Part \(session.exam.listening?.parts[safe: i]?.part ?? i + 1)"
        case .reading: return "Part \(session.exam.reading?.passages[safe: i]?.passage ?? i + 1)"
        case .writing: return "Part \(session.exam.writing?.tasks[safe: i]?.task ?? i + 1)"
        case .speaking: return ""
        }
    }

    func select(_ i: Int) {
        if session.module == .listening && !session.isStrict && !session.isReview { session.selectPracticePart(i) } else { session.currentSection = i }
        session.focusedQuestion = numbers(i).first
    }

    @ViewBuilder func sectionItem(_ i: Int) -> some View {
        let nums = numbers(i)
        let current = i == session.currentSection
        HStack(spacing: 10) {
            Text(title(i)).font(.system(size: 14, weight: .bold))
            if session.module == .writing {
                if let t = session.exam.writing?.tasks[safe: i] {
                    let w = WordCounter.count(session.essay(t.task))
                    Text("\(w) words").font(.system(size: 13)).foregroundStyle(w < t.minWords ? Theme.near : .secondary)
                }
            } else if current {
                HStack(spacing: 2) { ForEach(nums, id: \.self) { n in numberButton(n) } }
            } else if session.isReview {
                Text("\(nums.filter { session.result($0)?.isCorrect ?? false }.count) of \(nums.count) correct")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text("\(nums.filter { session.isAnswered($0) }.count) of \(nums.count)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(current ? (settings.examContrast.isDark ? Color.white.opacity(0.12) : Color.white) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if !current || session.module == .writing { select(i) } }
    }

    func numberButton(_ n: Int) -> some View {
        let answered = session.isAnswered(n)
        let focused = session.focusedQuestion == n
        let flagged = session.isFlagged(n) && !session.isReview
        var fill: Color = .clear
        if session.isReview, let r = session.result(n) { fill = (r.isCorrect ? Theme.correct : Theme.wrong).opacity(0.3) }
        return Button { session.go(to: n) } label: {
            Text("\(n)")
                .font(.system(size: 13, weight: focused ? .bold : .regular).monospacedDigit())
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: flagged ? 13 : 2).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: flagged ? 13 : 2)
                    .stroke(focused ? Color.accentColor : (flagged ? Color.primary.opacity(0.7) : .clear), lineWidth: focused ? 2 : 1.2))
                .overlay(alignment: .bottom) {
                    if answered && !session.isReview { Rectangle().fill(Color.primary).frame(width: 16, height: 2).offset(y: -1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(flagged ? "Q\(n)（已标记 Review）" : "Q\(n)")
    }
}

/// Dark square buttons of the real test (previous / next / submit).
struct CBTDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: configuration.isPressed ? 0.15 : 0.25)))
            .contentShape(Rectangle())
    }
}

/// The two arrow buttons that float above the bottom-right corner of the question area.
struct PrevNextButtons: View {
    @EnvironmentObject var session: ExamSession

    var body: some View {
        HStack(spacing: 4) {
            Button { session.previous() } label: {
                Image(systemName: "arrow.left").font(.system(size: 18, weight: .bold)).frame(width: 46, height: 42)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("上一题（⌘←）")
            Button { session.next() } label: {
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold)).frame(width: 46, height: 42)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .help("下一题（⌘→）")
        }
        .buttonStyle(CBTDarkButtonStyle())
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}


// MARK: - stage intro

struct StageIntroView: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: session.module.symbol).font(.system(size: 46)).foregroundStyle(Theme.moduleColor(session.module))
                Text("IELTS \(session.module.englishTitle)").font(.system(size: 30, weight: .bold))
                Text(timeLine).font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("INSTRUCTIONS TO CANDIDATES").font(.headline)
                    ForEach(instructions, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .card()
                if session.module == .listening, !session.ref.missingAudioParts.filter({ session.sections.contains($0) }).isEmpty {
                    Label("缺少 Part \(session.ref.missingAudioParts.filter { session.sections.contains($0) }.map { String($0 + 1) }.joined(separator: ", ")) 的音频，这部分将无法播放（可在题目详情页导入音频）。",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 640)
                }
                if !reminderLine.isEmpty {
                    Label(reminderLine, systemImage: "bell").foregroundStyle(.secondary)
                }
                Button {
                    session.startTimer()
                } label: {
                    if session.module == .listening && !session.listeningPrepared {
                        Text("正在准备录音…").frame(minWidth: 160)
                    } else {
                        Text(session.stageIndex > 0 && session.mode == .fullMock ? "开始\(session.module.title)" : "开始").frame(minWidth: 160)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.brand)
                .keyboardShortcut(.defaultAction)
                .disabled(session.module == .listening && (!session.listeningPrepared || (session.allotted == 0 && session.isStrict && session.ref.missingAudioParts.count == 4)))
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    var timeLine: String {
        switch session.module {
        case .listening:
            if !session.isStrict { return "练习模式：可暂停、拖动进度、调节语速" }
            return session.allotted > 0 ? "约 \(Int(session.allotted / 60)) 分钟（录音 + \(settings.listeningReviewMinutes) 分钟检查时间）" : "正在读取音频…"
        case .reading, .writing:
            return "\(Int(session.allotted / 60)) 分钟" + (session.remaining < session.allotted ? "（剩余 \(session.timeText)）" : "")
        case .speaking:
            return ""
        }
    }

    var reminderLine: String {
        guard session.isStrict || session.allotted > 0 else { return "" }
        let mins = settings.reminderMinutes.sorted(by: >).map { "\($0)" }.joined(separator: " / ")
        return "剩余 \(mins) 分钟时会提醒" + (settings.reminderNotification ? "（App 在后台时也会发系统通知）" : "")
    }

    var instructions: [String] {
        switch session.module {
        case .listening:
            var a = ["There are four parts to the test. You will hear each part once only.",
                     "Answer all the questions. Write your answers on the question paper as you listen.",
                     "There are 40 questions in total. Each question carries one mark."]
            if session.isStrict {
                a.append("录音开始后不能暂停或回放；录音结束后有 \(settings.listeningReviewMinutes) 分钟检查答案。")
                a.append("填空题注意字数限制与拼写；大小写不影响判分。")
            }
            return a
        case .reading:
            return ["There are 40 questions in this test. Each question carries one mark.",
                    "There are three parts to the test. Spend about 20 minutes on each passage.",
                    "右键选中文字可以高亮（或选中后按 H）；在题号上右键可标记题目。"]
        case .writing:
            return ["Answer both parts. Task 2 contributes twice as much as Task 1 to the Writing score.",
                    "Write at least 150 words for Task 1 and at least 250 words for Task 2.",
                    "编辑器不提供拼写检查和自动更正，与机考一致。"]
        case .speaking:
            return []
        }
    }
}

// MARK: - finished

struct FinishedView: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.correct)
            Text("已交卷").font(.largeTitle.bold())
            HStack(spacing: 30) {
                ForEach(session.attempt.modules, id: \.self) { m in
                    VStack(spacing: 6) {
                        Label(m.title, systemImage: m.symbol).foregroundStyle(Theme.moduleColor(m))
                        if let s = session.attempt.scores[m] {
                            Text("\(s.correct) / \(s.total)").font(.title.bold().monospacedDigit())
                            if let b = s.band { Text("Band \(Grader.bandString(b))").foregroundStyle(Theme.brand) }
                        } else if m == .writing {
                            let words = session.attempt.essays.sorted { $0.key < $1.key }.map { "T\($0.key) \(WordCounter.count($0.value)) 词" }
                            Text(words.isEmpty ? "未作答" : words.joined(separator: "  ")).font(.title3)
                            Text("可在结果页使用 AI 评分").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 160)
                    .card()
                }
            }
            HStack {
                Button("返回") { app.endSession(showResult: false) }
                Button("查看结果与解析") { app.endSession(showResult: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
