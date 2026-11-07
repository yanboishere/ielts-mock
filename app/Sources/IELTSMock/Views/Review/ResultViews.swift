import SwiftUI

struct AttemptView: View {
    let attemptId: UUID
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var ai: AIService
    @EnvironmentObject var settings: SettingsStore
    @State private var tab: Module = .listening
    @State private var reviewing: Module?

    var body: some View {
        if let a = history.attempt(attemptId), let ref = bank.ref(a.examId) {
            if let m = reviewing {
                ReviewContainer(attempt: a, ref: ref, module: m) { reviewing = nil }
            } else {
                content(a, ref)
                    .navigationTitle(a.title)
                    .onAppear { if !a.modules.contains(tab), let f = a.modules.first { tab = f } }
                    .onReceive(NotificationCenter.default.publisher(for: DebugDriver.reviewRequest)) { n in
                        if let m = n.object as? Module, a.modules.contains(m) { reviewing = m }
                    }
            }
        } else {
            EmptyStateView(title: "记录不存在", systemImage: "doc.questionmark", message: "这条练习记录或对应的题目已被删除。")
        }
    }

    func content(_ a: Attempt, _ ref: ExamRef) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(a)
                if a.modules.count > 1 {
                    Picker("", selection: $tab) {
                        ForEach(a.modules, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
                let m = a.modules.contains(tab) ? tab : (a.modules.first ?? .listening)
                if m == .speaking {
                    SpeakingResultView(attempt: a, ref: ref)
                } else if m == .writing {
                    WritingResultView(attempt: a, ref: ref)
                } else {
                    ObjectiveResultView(attempt: a, ref: ref, module: m) { reviewing = m }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    func header(_ a: Attempt) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(a.title).font(.title2.bold())
                Text("\(a.mode.label) · \((a.finishedAt ?? a.startedAt).shortString) · 用时 \(formatDuration(a.timing.values.map(\.used).reduce(0, +)))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(a.modules, id: \.self) { m in
                VStack(spacing: 2) {
                    Text(m.title).font(.caption).foregroundStyle(.secondary)
                    if m == .writing {
                        BandBadge(band: a.writingBand, size: 26)
                    } else if m == .speaking {
                        BandBadge(band: a.speakingBand, size: 26)
                    } else if let s = a.scores[m] {
                        Text("\(s.correct)/\(s.total)").font(.title3.bold().monospacedDigit())
                        if let b = s.band { Text("Band \(Grader.bandString(b))").font(.caption.bold()).foregroundStyle(Theme.brand) }
                    }
                }
            }
            if a.mode == .fullMock {
                Divider().frame(height: 50)
                BandBadge(band: a.overallBand, label: "总分（不含口语）")
            }
        }
        .card()
    }
}

// MARK: - listening / reading results

struct ObjectiveResultView: View {
    let attempt: Attempt
    let ref: ExamRef
    let module: Module
    var openReview: () -> Void
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var ai: AIService
    @EnvironmentObject var settings: SettingsStore

    var results: [QuestionResult] { attempt.results.filter { $0.module == module } }

    var sections: [Int] { Array(Set(results.map(\.section))).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                let wrong = results.filter { !$0.isCorrect }
                Text("答对 \(results.count - wrong.count) / \(results.count) 题").font(.headline)
                if let b = attempt.scores[module]?.band { Pill(text: "Band \(Grader.bandString(b))", color: Theme.brand) }
                Spacer()
                Button { openReview() } label: { Label("复盘：对照原文查看", systemImage: "rectangle.split.2x1") }
                    .buttonStyle(.borderedProminent)
                AIExplainAllButton(attempt: attempt, ref: ref, module: module)
            }
            typeBreakdown
            ForEach(sections, id: \.self) { s in sectionTable(s) }
        }
    }

    var typeBreakdown: some View {
        let byType = Dictionary(grouping: results, by: \.type)
        return HStack(spacing: 10) {
            ForEach(byType.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { t in
                let rs = byType[t] ?? []
                let ok = rs.filter(\.isCorrect).count
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.label).font(.caption).foregroundStyle(.secondary)
                    Text("\(ok)/\(rs.count)").font(.headline.monospacedDigit())
                        .foregroundStyle(ok == rs.count ? Theme.correct : (Double(ok) / Double(max(1, rs.count)) < 0.6 ? Theme.wrong : .primary))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    func sectionTitle(_ s: Int) -> String {
        switch module {
        case .listening: return "Part \(s + 1)"
        case .reading: return "Passage \(s + 1)" + (ref.exam.reading?.passages[safe: s].map { " · " + InlineMarkup.strip($0.title) } ?? "")
        case .writing, .speaking: return ""
        }
    }

    func sectionTable(_ s: Int) -> some View {
        let rs = results.filter { $0.section == s }
        let wrong = rs.filter { !$0.isCorrect }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sectionTitle(s)).font(.headline)
                Text("\(rs.count - wrong.count)/\(rs.count)").foregroundStyle(.secondary)
                Spacer()
                AIExplainButton(attempt: attempt, ref: ref, module: module, section: s)
            }
            ForEach(rs) { r in
                ResultRow(result: r, ref: ref, explanation: attempt.explanations[r.id])
                if r.id != rs.last?.id { Divider() }
            }
        }
        .card()
    }
}

struct ResultRow: View {
    let result: QuestionResult
    let ref: ExamRef
    let explanation: QuestionExplanation?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isCorrect ? Theme.correct : Theme.wrong)
                Text("Q\(result.number)").bold().monospacedDigit().frame(width: 40, alignment: .leading)
                Text(questionText).lineLimit(expanded ? nil : 1).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text(result.isBlank ? "未作答" : result.user)
                    .foregroundStyle(result.isCorrect ? Theme.correct : Theme.wrong)
                    .frame(width: 150, alignment: .leading)
                    .lineLimit(1)
                Text(result.keyDisplay).bold().frame(width: 170, alignment: .leading).lineLimit(2)
                if explanation != nil {
                    Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "sparkles") }
                        .buttonStyle(.borderless)
                        .help("查看 AI 解析")
                } else {
                    Color.clear.frame(width: 16)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if explanation != nil { expanded.toggle() } }
            if expanded, let e = explanation {
                ExplanationCard(number: result.number, explanation: e).padding(.leading, 30)
            }
        }
    }

    var questionText: String {
        ref.exam.group(containing: result.number, in: result.module)?.group.questionText(result.number) ?? ""
    }
}

struct AIExplainButton: View {
    let attempt: Attempt
    let ref: ExamRef
    let module: Module
    let section: Int
    @EnvironmentObject var ai: AIService
    @EnvironmentObject var history: HistoryStore

    var key: String { "explain-\(ref.exam.id)-\(module.rawValue)-\(section)" }
    var wrong: [QuestionResult] { attempt.results.filter { $0.module == module && $0.section == section && !$0.isCorrect } }
    var missing: [QuestionResult] { wrong.filter { attempt.explanations[$0.id] == nil } }

    var body: some View {
        HStack(spacing: 6) {
            if let n = ai.running[key] {
                ProgressView().controlSize(.small)
                Text(n > 0 ? "生成中… \(n) 字" : "思考中…").font(.caption).foregroundStyle(.secondary)
            } else if let e = ai.errors[key] {
                Text(e).font(.caption).foregroundStyle(Theme.wrong).lineLimit(2).frame(maxWidth: 260)
            }
            if !wrong.isEmpty {
                Button(missing.isEmpty ? "重新解析" : "AI 解析错题（\(missing.count)）") {
                    Task { await AIActions.explain(ai: ai, history: history, attemptId: attempt.id, ref: ref, module: module, section: section, onlyMissing: !missing.isEmpty) }
                }
                .disabled(ai.isRunning(key))
            } else {
                Text("全对 🎉").foregroundStyle(Theme.correct)
            }
        }
    }
}

struct AIExplainAllButton: View {
    let attempt: Attempt
    let ref: ExamRef
    let module: Module
    @EnvironmentObject var ai: AIService
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        let sections = Array(Set(attempt.results.filter { $0.module == module && !$0.isCorrect && attempt.explanations[$0.id] == nil }.map(\.section))).sorted()
        if !sections.isEmpty {
            Button {
                Task {
                    await withTaskGroup(of: Void.self) { g in
                        for s in sections {
                            g.addTask { @MainActor in
                                await AIActions.explain(ai: ai, history: history, attemptId: attempt.id, ref: ref, module: module, section: s, onlyMissing: true)
                            }
                        }
                    }
                }
            } label: { Label("AI 解析全部错题", systemImage: "sparkles") }
        }
    }
}

@MainActor
enum AIActions {
    static func explain(ai: AIService, history: HistoryStore, attemptId: UUID, ref: ExamRef, module: Module, section: Int, onlyMissing: Bool) async {
        guard let a = history.attempt(attemptId) else { return }
        var wrong = a.results.filter { $0.module == module && $0.section == section && !$0.isCorrect }
        if onlyMissing { wrong = wrong.filter { a.explanations[$0.id] == nil } }
        guard !wrong.isEmpty else { return }
        do {
            let items = try await ai.explain(ref: ref, module: module, section: section, wrong: wrong)
            guard var cur = history.attempt(attemptId) else { return }
            for e in items { cur.explanations[Grader.key(module, e.number)] = e }
            history.save(cur)
        } catch {}
    }

    static func assess(ai: AIService, history: HistoryStore, attemptId: UUID, ref: ExamRef, task: WritingTask) async {
        guard let a = history.attempt(attemptId) else { return }
        let essay = a.essays[task.task] ?? ""
        do {
            let r = try await ai.assess(ref: ref, task: task, essay: essay)
            guard var cur = history.attempt(attemptId) else { return }
            cur.assessments[task.task] = r
            history.save(cur)
        } catch {}
    }

    static func assessSpeaking(ai: AIService, history: HistoryStore, attemptId: UUID, ref: ExamRef) async {
        guard let a = history.attempt(attemptId), let record = a.speaking else { return }
        let practice = a.mode == .practice ? a.scopes.first?.section.map { $0 + 1 } : nil
        do {
            let r = try await ai.assessSpeaking(ref: ref, record: record, practicePart: practice)
            guard var cur = history.attempt(attemptId) else { return }
            cur.speaking?.assessment = r
            history.save(cur)
        } catch {}
    }
}

// MARK: - review (passage + questions with answers)

struct ReviewContainer: View {
    let attempt: Attempt
    let ref: ExamRef
    let module: Module
    var close: () -> Void
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @StateObject private var holder = ReviewHolder()

    var body: some View {
        Group {
            if let s = holder.session {
                VStack(spacing: 0) {
                    HStack {
                        Button { close() } label: { Label("返回结果", systemImage: "chevron.left") }
                        Text("复盘 · \(module.title)").font(.headline)
                        Spacer()
                        Text("蓝色底纹 = AI 标出的答案出处；黄色 = 你的高亮").font(.caption).foregroundStyle(.secondary)
                        AIExplainButton(attempt: history.attempt(attempt.id) ?? attempt, ref: ref, module: module, section: s.currentSection)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.bar)
                    Divider()
                    InstructionBar()
                    Divider()
                    Group {
                        if module == .listening { ListeningPane() } else { ReadingPane() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    QuestionNavigator()
                }
                .environmentObject(s)
                .background(Theme.examBackground)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            let s = ExamSession(review: attempt, ref: ref, settings: settings, history: history)
            s.setReviewModule(module)
            holder.session = s
        }
        .onDisappear { holder.session?.audio.stop() }
        .onChange(of: history.attempt(attempt.id)) { _, new in
            if let new { holder.session?.attempt = new }
        }
        .navigationTitle("复盘")
    }
}

@MainActor
final class ReviewHolder: ObservableObject {
    @Published var session: ExamSession?
}

// MARK: - writing results

struct WritingResultView: View {
    let attempt: Attempt
    let ref: ExamRef
    @EnvironmentObject var ai: AIService
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var settings: SettingsStore

    var tasks: [WritingTask] {
        let all = ref.exam.writing?.tasks ?? []
        let scope = attempt.scopes.first { $0.module == .writing }
        if let s = scope?.section { return all.indices.contains(s) ? [all[s]] : [] }
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(tasks) { t in taskCard(t) }
        }
    }

    func taskCard(_ t: WritingTask) -> some View {
        let essay = attempt.essays[t.task] ?? ""
        let words = WordCounter.count(essay)
        let key = "assess-\(ref.exam.id)-\(t.task)"
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Writing Task \(t.task)").font(.title3.bold())
                Pill(text: "\(words) 词", color: words < t.minWords ? Theme.near : Theme.correct)
                Spacer()
                if let n = ai.running[key] {
                    ProgressView().controlSize(.small)
                    Text(n > 0 ? "评分中… \(n) 字" : "考官思考中…").font(.caption).foregroundStyle(.secondary)
                }
                if let e = ai.errors[key] { Text(e).font(.caption).foregroundStyle(Theme.wrong).lineLimit(2).frame(maxWidth: 300) }
                Button(attempt.assessments[t.task] == nil ? "AI 评分与改进建议" : "重新评分") {
                    Task { await AIActions.assess(ai: ai, history: history, attemptId: attempt.id, ref: ref, task: t) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(ai.isRunning(key) || essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            DisclosureGroup("题目") {
                WritingPromptStatic(task: t, ref: ref).padding(.top, 6)
            }
            DisclosureGroup("我的作文") {
                Text(essay.isEmpty ? "（未作答）" : essay)
                    .font(.system(size: 14 * settings.fontScale))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            if let r = attempt.assessments[t.task] {
                AssessmentView(assessment: r, task: t)
            }
            if let s = t.sample {
                DisclosureGroup("书中\(s.kind == "model" ? "范文" : "考生样文")\(s.band.map { "（Band \($0)）" } ?? "")") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.text).textSelection(.enabled)
                        if let c = s.comment {
                            Text("考官评语").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(c).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
            }
        }
        .card()
    }
}

struct WritingPromptStatic: View {
    let task: WritingTask
    let ref: ExamRef
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(task.prompt.enumerated()), id: \.offset) { _, l in MarkupText(l) }
            if let img = task.image { BankImage(url: ref.url(img), maxHeight: 360) }
        }
    }
}

struct AssessmentView: View {
    let assessment: WritingAssessment
    let task: WritingTask
    @State private var showImproved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                BandBadge(band: assessment.overallBand, label: "本篇估分", size: 40)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assessment.criteria) { c in
                        HStack {
                            Text(criterionName(c.name)).frame(width: 150, alignment: .leading)
                            ProgressView(value: c.band, total: 9).frame(width: 160)
                            Text(Grader.bandString(c.band)).bold().monospacedDigit()
                        }
                    }
                }
                Spacer()
                Text(assessment.model).font(.caption2).foregroundStyle(.tertiary)
            }
            if !assessment.summary.isEmpty { MarkdownText(assessment.summary).textSelection(.enabled) }
            ForEach(assessment.criteria) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(criterionName(c.name)) · \(Grader.bandString(c.band))").font(.subheadline.bold())
                    MarkdownText(c.comment).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                listBox("优点", assessment.strengths, "hand.thumbsup", Theme.correct)
                listBox("主要问题", assessment.weaknesses, "exclamationmark.triangle", Theme.wrong)
            }
            if !assessment.corrections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("逐句修改").font(.headline)
                    ForEach(assessment.corrections) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.original).strikethrough(color: Theme.wrong).foregroundStyle(Theme.wrong)
                            Text(c.suggestion).foregroundStyle(Theme.correct).bold()
                            MarkdownText(c.explanation).font(.callout).foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
                    }
                }
            }
            if !assessment.nextSteps.isEmpty { listBox("下一步怎么练", assessment.nextSteps, "arrow.forward.circle", .accentColor) }
            if !assessment.improvedVersion.isEmpty {
                DisclosureGroup("改写后的高分版本（保留你的观点与结构）", isExpanded: $showImproved) {
                    Text(assessment.improvedVersion).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.05)))
    }

    func criterionName(_ n: String) -> String {
        switch n {
        case "Task Achievement": return "任务完成 TA"
        case "Task Response": return "任务回应 TR"
        case "Coherence and Cohesion": return "连贯与衔接 CC"
        case "Lexical Resource": return "词汇丰富度 LR"
        case "Grammatical Range and Accuracy": return "语法多样与准确 GRA"
        default: return n
        }
    }

    func listBox(_ title: String, _ items: [String], _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            ForEach(items, id: \.self) { MarkdownText("• " + $0).textSelection(.enabled) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
