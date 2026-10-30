import SwiftUI
import UniformTypeIdentifiers

struct AttemptRow: View {
    let attempt: Attempt
    @EnvironmentObject var app: AppState

    var body: some View {
        Button { app.open(.attempt(attempt.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.brand).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attempt.title).font(.body.weight(.medium))
                    Text((attempt.finishedAt ?? attempt.startedAt).shortString).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(attempt.modules, id: \.self) { m in
                    if m == .writing {
                        Text("写 \(Grader.bandString(attempt.writingBand))").monospacedDigit()
                    } else if let s = attempt.scores[m] {
                        Text("\(m == .listening ? "听" : "读") \(s.correct)/\(s.total)" + (s.band.map { " · \(Grader.bandString($0))" } ?? ""))
                            .monospacedDigit()
                    }
                }
                if attempt.mode == .fullMock, let b = attempt.overallBand {
                    Pill(text: "总 \(Grader.bandString(b))", color: Theme.brand)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var icon: String {
        switch attempt.mode {
        case .fullMock: return "rosette"
        case .moduleMock: return attempt.modules.first?.symbol ?? "doc"
        case .practice: return "target"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var app: AppState
    @State private var filter: Module?
    @State private var exporting = false
    @State private var importing = false

    var list: [Attempt] {
        history.submitted.filter { a in filter.map { a.modules.contains($0) } ?? true }
    }

    var body: some View {
        Group {
            if history.submitted.isEmpty {
                EmptyStateView(title: "还没有练习记录", systemImage: "clock", message: "在题库中选择一套题开始模考或专项练习，交卷后成绩会出现在这里。")
            } else {
                List {
                    ForEach(list) { a in
                        AttemptRow(attempt: a)
                            .contextMenu {
                                Button("删除记录", role: .destructive) { history.delete(a) }
                            }
                    }
                }
            }
        }
        .navigationTitle("练习记录")
        .toolbar {
            Picker("科目", selection: $filter) {
                Text("全部").tag(Module?.none)
                ForEach(Module.allCases) { Text($0.title).tag(Module?.some($0)) }
            }
            .pickerStyle(.segmented)
            Menu {
                Button("导出全部记录…") { exporting = true }
                Button("导入记录…") { importing = true }
            } label: { Image(systemName: "square.and.arrow.up.on.square") }
        }
        .fileExporter(isPresented: $exporting, document: JSONDoc(data: (try? JSONEncoder.pretty.encode(history.attempts)) ?? Data()),
                      contentType: .json, defaultFilename: "ielts-mock-history.json") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case .success(let url) = r {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do { let n = try history.importAll(from: url); app.alert = "已导入 \(n) 条记录。" } catch { app.alert = "导入失败：\(error.localizedDescription)" }
            }
        }
    }
}

struct JSONDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

struct MistakesView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var app: AppState
    @State private var module: Module = .reading
    @State private var type: GroupType?

    var items: [(attempt: Attempt, result: QuestionResult)] {
        history.mistakes.filter { $0.result.module == module && (type == nil || $0.result.type == type) }
    }

    var body: some View {
        let types = Array(Set(history.mistakes.filter { $0.result.module == module }.map(\.result.type))).sorted { $0.rawValue < $1.rawValue }
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $module) {
                    Text("听力").tag(Module.listening)
                    Text("阅读").tag(Module.reading)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Picker("题型", selection: $type) {
                    Text("全部题型").tag(GroupType?.none)
                    ForEach(types, id: \.self) { Text($0.label).tag(GroupType?.some($0)) }
                }
                .frame(width: 200)
                Spacer()
                Text("\(items.count) 道错题").foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            if items.isEmpty {
                EmptyStateView(title: "暂无错题", systemImage: "checkmark.seal", message: "交卷后答错的题会自动收录到这里，可以用 AI 生成解析。")
            } else {
                List {
                    ForEach(items, id: \.result.id) { item in
                        // rows from different attempts can share a question id; include the attempt in the identity
                        MistakeRow(attempt: item.attempt, result: item.result)
                            .id("\(item.attempt.id)-\(item.result.id)")
                    }
                }
            }
        }
        .navigationTitle("错题本")
    }
}

struct MistakeRow: View {
    let attempt: Attempt
    let result: QuestionResult
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var app: AppState

    var body: some View {
        if let ref = bank.ref(attempt.examId) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(ref.exam.shortTitle) · \(result.module == .listening ? "Part" : "Passage") \(result.section + 1) · Q\(result.number)").bold()
                    Pill(text: result.type.label, color: .secondary)
                    Spacer()
                    Button("查看") { app.open(.attempt(attempt.id)) }.buttonStyle(.borderless)
                }
                ResultRow(result: result, ref: ref, explanation: attempt.explanations[result.id])
            }
            .padding(.vertical, 4)
        }
    }
}

struct WritingLogView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var app: AppState

    struct EssayItem: Identifiable {
        var attempt: Attempt
        var task: Int
        var text: String
        var id: String { "\(attempt.id.uuidString)-\(task)" }
    }

    var essays: [EssayItem] {
        history.submitted.flatMap { a in a.essays.sorted { $0.key < $1.key }.filter { !$0.value.isEmpty }.map { EssayItem(attempt: a, task: $0.key, text: $0.value) } }
    }

    var body: some View {
        Group {
            if essays.isEmpty {
                EmptyStateView(title: "还没有作文", systemImage: "doc.text", message: "完成写作模考或写作练习后，作文与 AI 评分会出现在这里。")
            } else {
                List {
                    ForEach(essays) { item in
                        let a = item.attempt, task = item.task, text = item.text
                        Button { app.open(.attempt(a.id)) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(a.examTitle) · Task \(task)").bold()
                                    Text(text).lineLimit(2).foregroundStyle(.secondary)
                                    Text("\(WordCounter.count(text)) 词 · \((a.finishedAt ?? a.startedAt).shortString)").font(.caption).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                BandBadge(band: a.assessments[task]?.overallBand, size: 22)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("写作记录")
    }
}

struct CustomBankView: View {
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var app: AppState
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义题目").font(.title2.bold())
                    Text("导入与内置题库相同格式（ielts-mock.exam/1）的 JSON 文件，可以加入自己整理的机经或模拟题。图片/音频放在 JSON 同级的 images/、audio/ 目录中会一并导入。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { importing = true } label: { Label("导入 JSON…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
            }
            if bank.customRefs.isEmpty {
                EmptyStateView(title: "暂无自定义题目", systemImage: "tray", message: "格式说明见题库目录中的 SCHEMA.md。")
            } else {
                List {
                    ForEach(bank.customRefs) { r in
                        HStack {
                            Text(r.exam.title)
                            Spacer()
                            Button("打开") { app.open(.test(r.id)) }
                            Button("删除", role: .destructive) { bank.deleteCustom(r) }
                        }
                    }
                }
            }
        }
        .padding(24)
        .navigationTitle("自定义题目")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r {
                var errs: [String] = []
                for url in urls {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    do { try bank.importExam(from: url) } catch { errs.append("\(url.lastPathComponent)：\(error)") }
                }
                if !errs.isEmpty { app.alert = "部分文件导入失败：\n" + errs.joined(separator: "\n") }
            }
        }
    }
}
