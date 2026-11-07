import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let r = history.resumable { resumeCard(r) }
                statsRow
                if !trend.isEmpty { trendChart }
                HStack(alignment: .top, spacing: 18) {
                    quickStart
                    weakTypes
                }
                if !settings.hasKeyForCurrentProvider {
                    HStack(spacing: 12) {
                        Image(systemName: "key").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("配置 AI 解析（可选）").font(.headline)
                            Text("在设置中填入你自己的 Claude 或 OpenAI API Key，即可在交卷后获得错题解析与写作评分。Key 只保存在本机钥匙串。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsLink { Text("打开设置") }
                    }
                    .card()
                }
                if let e = bank.lastError {
                    Text("部分题目文件读取失败：\n\(e)").font(.caption).foregroundStyle(.red).card()
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle("首页")
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("雅思模考").font(.largeTitle.bold())
            Text(bank.refs.isEmpty ? "题库为空：请在设置 → 题库中导入题库文件夹。" :
                    "剑桥雅思 \(bank.books.first.map(String.init) ?? "")–\(bank.books.last.map(String.init) ?? "") 共 \(bank.refs.filter { !$0.isCustom }.count) 套真题 · 听力 / 阅读 / 写作 / 口语全真模考")
                .foregroundStyle(.secondary)
        }
    }

    func resumeCard(_ a: Attempt) -> some View {
        HStack {
            Image(systemName: "pause.circle.fill").font(.largeTitle).foregroundStyle(Theme.brand)
            VStack(alignment: .leading) {
                Text("有未完成的考试").font(.headline)
                Text("\(a.title) · 开始于 \(a.startedAt.shortString)").foregroundStyle(.secondary)
            }
            Spacer()
            Button("放弃") { history.delete(a) }
            Button("继续作答") { app.resume(a) }.buttonStyle(.borderedProminent)
        }
        .card()
    }

    var submitted: [Attempt] { history.submitted }

    var statsRow: some View {
        let lBands = submitted.compactMap { $0.scores[.listening]?.band }
        let rBands = submitted.compactMap { $0.scores[.reading]?.band }
        let wBands = submitted.compactMap(\.writingBand)
        let sBands = submitted.compactMap(\.speakingBand)
        let totalTime = submitted.flatMap { $0.timing.values.map(\.used) }.reduce(0, +)
        func avg(_ a: [Double]) -> Double? { a.isEmpty ? nil : roundHalf(a.reduce(0, +) / Double(a.count)) }
        return HStack(spacing: 14) {
            stat("已完成", "\(submitted.count)", "次练习/模考")
            statBand("听力平均", avg(Array(lBands.prefix(5))), "最近 5 次")
            statBand("阅读平均", avg(Array(rBands.prefix(5))), "最近 5 次")
            statBand("写作平均", avg(Array(wBands.prefix(5))), "AI 评分")
            statBand("口语平均", avg(Array(sBands.prefix(5))), "AI 评分")
            stat("累计用时", formatDuration(totalTime), "")
        }
    }

    func stat(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
            Text(sub).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    func statBand(_ title: String, _ b: Double?, _ sub: String) -> some View {
        stat(title, Grader.bandString(b), sub)
    }

    struct TrendPoint: Identifiable {
        var id = UUID()
        var date: Date
        var module: String
        var band: Double
    }

    var trend: [TrendPoint] {
        submitted.reversed().flatMap { a -> [TrendPoint] in
            var pts: [TrendPoint] = []
            if let b = a.scores[.listening]?.band { pts.append(TrendPoint(date: a.finishedAt ?? a.startedAt, module: "听力", band: b)) }
            if let b = a.scores[.reading]?.band { pts.append(TrendPoint(date: a.finishedAt ?? a.startedAt, module: "阅读", band: b)) }
            if let b = a.writingBand { pts.append(TrendPoint(date: a.finishedAt ?? a.startedAt, module: "写作", band: b)) }
            if let b = a.speakingBand { pts.append(TrendPoint(date: a.finishedAt ?? a.startedAt, module: "口语", band: b)) }
            return pts
        }
    }

    var trendChart: some View {
        VStack(alignment: .leading) {
            Text("分数趋势").font(.headline)
            Chart(trend) { p in
                LineMark(x: .value("日期", p.date), y: .value("Band", p.band))
                    .foregroundStyle(by: .value("科目", p.module))
                    .symbol(by: .value("科目", p.module))
            }
            .chartYScale(domain: max(0, (trend.map(\.band).min() ?? 4) - 1).rounded(.down)...9)
            .frame(height: 180)
        }
        .card()
    }

    var nextTest: ExamRef? {
        let done = Set(submitted.map(\.examId))
        return bank.refs.first { !$0.isCustom && !done.contains($0.id) }
    }

    var quickStart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快速开始").font(.headline)
            if let n = nextTest {
                Text("下一套未做的题：\(n.exam.shortTitle)").foregroundStyle(.secondary)
                HStack {
                    Button("全真模考") { app.startFullMock(n) }.buttonStyle(.borderedProminent)
                    Button("查看") { app.navigate(.library, open: .test(n.id)) }
                }
            }
            if let r = bank.refs.filter({ !$0.isCustom && !($0.exam.reading?.passages.isEmpty ?? true) }).randomElement() {
                if nextTest != nil { Divider() }
                Text("随机一篇阅读：\(r.exam.shortTitle)").foregroundStyle(.secondary)
                HStack {
                    let p = Int.random(in: 0..<max(1, r.exam.reading?.passages.count ?? 1))
                    Button("练习 Passage \(p + 1)（20 分钟）") { app.startPractice(r, .reading, section: p) }
                }
            }
            if nextTest == nil && !bank.refs.contains(where: { !$0.isCustom && !($0.exam.reading?.passages.isEmpty ?? true) }) {
                Text("题库里的题都做过了，可以去「题库」重做任意一套。").foregroundStyle(.secondary)
                Button("打开题库") { app.navigate(.library) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    struct TypeStat: Identifiable {
        var name: String
        var correct: Int
        var total: Int
        var id: String { name }
        var rate: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    }

    var typeStats: [TypeStat] {
        let all: [QuestionResult] = submitted.flatMap(\.results)
        var dict: [String: TypeStat] = [:]
        for r in all {
            let k = "\(r.module.title)·\(r.type.label)"
            var s = dict[k] ?? TypeStat(name: k, correct: 0, total: 0)
            s.total += 1
            if r.isCorrect { s.correct += 1 }
            dict[k] = s
        }
        let list = dict.values.filter { $0.total >= 3 }.sorted { $0.rate < $1.rate }
        return Array(list.prefix(6))
    }

    var weakTypes: some View {
        let rows = typeStats
        return VStack(alignment: .leading, spacing: 8) {
            Text("薄弱题型").font(.headline)
            if rows.isEmpty {
                Text("完成几次练习后，这里会显示正确率最低的题型。").foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                HStack {
                    Text(r.name)
                    Spacer()
                    Text("\(r.correct)/\(r.total)").monospacedDigit().foregroundStyle(.secondary)
                    ProgressView(value: Double(r.correct), total: Double(max(1, r.total))).frame(width: 90)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var history: HistoryStore

    let columns = [GridItem(.adaptive(minimum: 230), spacing: 16)]

    var body: some View {
        ScrollView {
            if bank.refs.isEmpty && !bank.loading {
                EmptyStateView(title: "题库为空", systemImage: "books.vertical",
                               message: "请到 设置 → 题库 中选择题库文件夹（包含 exams/ 子目录），或使用安装脚本导入剑桥雅思 4–18。")
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(bank.books, id: \.self) { b in
                    Button { app.open(.book(b)) } label: { bookCard(b) }
                        .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .navigationTitle("题库")
    }

    func bookCard(_ b: Int) -> some View {
        let refs = bank.refs(book: b)
        let done = refs.filter { !history.attempts(exam: $0.id).isEmpty }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("剑桥雅思").font(.headline)
                Text("\(b)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Theme.brand)
                Spacer()
                Text("Academic").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(refs) { r in
                    let n = history.attempts(exam: r.id).count
                    Text("T\(r.exam.source.test)")
                        .font(.caption.bold())
                        .frame(width: 34, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(n > 0 ? Theme.correct.opacity(0.2) : Color.secondary.opacity(0.12)))
                }
            }
            Text("已练习 \(done)/\(refs.count) 套").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }
}

struct BookView: View {
    var book: Int
    @EnvironmentObject var app: AppState
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(bank.refs(book: book)) { r in
                    TestSummaryCard(ref: r)
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("剑桥雅思 \(book)")
    }
}

struct TestSummaryCard: View {
    var ref: ExamRef
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        let exam = ref.exam
        let atts = history.attempts(exam: ref.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Test \(exam.source.test)").font(.title2.bold())
                if !atts.isEmpty { Pill(text: "已练习 \(atts.count) 次", color: Theme.correct) }
                if !ref.missingAudioParts.isEmpty { Pill(text: "缺少听力音频 Part \(ref.missingAudioParts.map { String($0 + 1) }.joined(separator: ","))", color: .orange) }
                Spacer()
                Button("详情") { app.open(.test(ref.id)) }
                Button("全真模考") { app.startFullMock(ref) }.buttonStyle(.borderedProminent)
            }
            if let ps = exam.reading?.passages {
                ForEach(ps) { p in
                    HStack(spacing: 6) {
                        Text("P\(p.passage)").font(.caption.bold()).foregroundStyle(Theme.moduleColor(.reading))
                        Text(InlineMarkup.strip(p.title)).lineLimit(1)
                    }
                }
            }
            if let t = exam.writing?.tasks.last {
                HStack(alignment: .top, spacing: 6) {
                    Text("W2").font(.caption.bold()).foregroundStyle(Theme.moduleColor(.writing))
                    Text(t.prompt.dropFirst().first.map { InlineMarkup.strip($0) } ?? t.promptText).lineLimit(2).foregroundStyle(.secondary)
                }
            }
            if let c = exam.speaking?.part2 {
                HStack(alignment: .top, spacing: 6) {
                    Text("S2").font(.caption.bold()).foregroundStyle(Theme.moduleColor(.speaking))
                    Text(InlineMarkup.strip(c.topic)).lineLimit(1).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}

struct TestDetailView: View {
    var examId: String
    @EnvironmentObject var app: AppState
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var history: HistoryStore
    @State private var importPart: Int?

    var body: some View {
        if let ref = bank.ref(examId) {
            content(ref)
                .navigationTitle(ref.exam.shortTitle)
                .fileImporter(isPresented: Binding(get: { importPart != nil }, set: { if !$0 { importPart = nil } }),
                              allowedContentTypes: [.audio]) { result in
                    if case .success(let url) = result, let p = importPart {
                        let ok = url.startAccessingSecurityScopedResource()
                        defer { if ok { url.stopAccessingSecurityScopedResource() } }
                        do { try bank.setAudioOverride(ref: ref, part: p, file: url) } catch { app.alert = error.localizedDescription }
                    }
                    importPart = nil
                }
        } else {
            EmptyStateView(title: "找不到题目", systemImage: "questionmark.folder", message: examId)
        }
    }

    func content(_ ref: ExamRef) -> some View {
        let exam = ref.exam
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exam.title).font(.title.bold())
                        Text("全真模考顺序：听力（约 30 分钟 + \(app.settings.listeningReviewMinutes) 分钟检查）→ 阅读 \(app.settings.readingMinutes) 分钟 → 写作 \(app.settings.writingMinutes) 分钟")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { app.startFullMock(ref) } label: { Label("开始全真模考", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .card()

                if let L = exam.listening { listeningCard(ref, L) }
                if let R = exam.reading { readingCard(ref, R) }
                if let W = exam.writing { writingCard(ref, W) }
                if let S = exam.speaking { speakingCard(ref, S) }

                let atts = history.attempts(exam: ref.id)
                if !atts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本套题的练习记录").font(.headline)
                        ForEach(atts) { a in AttemptRow(attempt: a) }
                    }
                    .card()
                }
                if let issues = exam.issues, !issues.isEmpty {
                    DisclosureGroup("题目录入备注（\(issues.count)）") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(issues, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .card()
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    func moduleHeader(_ m: Module, _ ref: ExamRef, _ detail: String) -> some View {
        HStack {
            Label(m.title, systemImage: m.symbol).font(.title3.bold()).foregroundStyle(Theme.moduleColor(m))
            Text(detail).foregroundStyle(.secondary)
            Spacer()
            Button("\(m.title)模考") { app.startModule(ref, m) }
        }
    }

    func types(_ groups: [QuestionGroup]) -> String {
        var seen: [String] = []
        for g in groups where !seen.contains(g.type.label) { seen.append(g.type.label) }
        return seen.joined(separator: " · ")
    }

    func listeningCard(_ ref: ExamRef, _ L: ListeningModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            moduleHeader(.listening, ref, "4 个 Part · 40 题")
            ForEach(Array(L.parts.enumerated()), id: \.offset) { i, p in
                HStack {
                    Text("Part \(p.part)").bold().frame(width: 60, alignment: .leading)
                    Text("Q\(p.first)–\(p.last)").monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Text(types(p.groups)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if ref.audioURL(part: i) == nil {
                        Button("导入音频…") { importPart = i }.foregroundStyle(.orange)
                    }
                    Button("练习") { app.startPractice(ref, .listening, section: i) }
                        .disabled(ref.audioURL(part: i) == nil)
                }
            }
        }
        .card()
    }

    func readingCard(_ ref: ExamRef, _ R: ReadingModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            moduleHeader(.reading, ref, "3 篇文章 · 40 题")
            ForEach(Array(R.passages.enumerated()), id: \.offset) { i, p in
                HStack {
                    Text("Passage \(p.passage)").bold().frame(width: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(InlineMarkup.strip(p.title))
                        Text("Q\(p.first)–\(p.last) · " + types(p.groups)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("练习（20 分钟）") { app.startPractice(ref, .reading, section: i) }
                }
            }
        }
        .card()
    }

    func speakingCard(_ ref: ExamRef, _ S: SpeakingModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("口语", systemImage: Module.speaking.symbol).font(.title3.bold()).foregroundStyle(Theme.moduleColor(.speaking))
                Text("考官语音提问 · 本地转写 · 官方标准评分").foregroundStyle(.secondary)
                Spacer()
                Button("口语模考（约 11–14 分钟）") { app.startSpeaking(ref) }
            }
            if let p1 = S.part1 {
                HStack(alignment: .top) {
                    Text("Part 1").bold().frame(width: 60, alignment: .leading)
                    Text(p1.topics.map(\.title).joined(separator: " · ") + " · \(p1.topics.map(\.questions.count).reduce(0, +)) 题")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("练习") { app.startSpeaking(ref, part: 1) }
                }
            }
            if let c = S.part2 {
                HStack(alignment: .top) {
                    Text("Part 2").bold().frame(width: 60, alignment: .leading)
                    Text(InlineMarkup.strip(c.topic)).foregroundStyle(.secondary)
                    Spacer()
                    Button("练习") { app.startSpeaking(ref, part: 2) }
                }
            }
            if let p3 = S.part3 {
                HStack(alignment: .top) {
                    Text("Part 3").bold().frame(width: 60, alignment: .leading)
                    Text(p3.topics.map(\.title).joined(separator: " · ")).foregroundStyle(.secondary)
                    Spacer()
                    Button("练习") { app.startSpeaking(ref, part: 3) }
                }
            }
        }
        .card()
    }

    func writingCard(_ ref: ExamRef, _ W: WritingModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            moduleHeader(.writing, ref, "Task 1 + Task 2")
            ForEach(Array(W.tasks.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top) {
                    Text("Task \(t.task)").bold().frame(width: 60, alignment: .leading)
                    Text(t.prompt.map { InlineMarkup.strip($0) }.joined(separator: " ")).lineLimit(3).foregroundStyle(.secondary)
                    Spacer()
                    Button("练习（\(t.minutes) 分钟）") { app.startPractice(ref, .writing, section: i) }
                }
            }
        }
        .card()
    }
}
