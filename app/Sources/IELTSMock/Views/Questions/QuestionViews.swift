import SwiftUI
import UniformTypeIdentifiers

extension ExamSession {
    func result(_ n: Int) -> QuestionResult? { attempt.results.first { $0.module == module && $0.number == n } }
    func explanation(_ n: Int) -> QuestionExplanation? { attempt.explanations[Grader.key(module, n)] }
}

// MARK: - group

struct QuestionGroupView: View {
    let group: QuestionGroup
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var fs: CGFloat { 15 * settings.fontScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.heading)
                .font(.system(size: fs + 1, weight: .bold))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(group.instructions.enumerated()), id: \.offset) { _, line in
                    MarkupText(line, font: .system(size: fs))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let title = group.title, group.type != .completion {
                MarkupText(title, font: .system(size: fs + 1, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            if let img = group.image {
                BankImage(url: session.ref.url(img), maxHeight: 460)
                    .frame(maxWidth: .infinity)
            }
            switch group.type {
            case .completion: CompletionView(group: group)
            case .choice: ChoiceView(group: group)
            case .multi: MultiView(group: group)
            case .tfng, .ynng: JudgementView(group: group)
            case .matching: MatchingView(group: group)
            }
        }
        .padding(.vertical, 6)
    }
}

struct NumberBadge: View {
    let n: Int
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let focused = session.focusedQuestion == n
        Text("\(n)")
            .font(.system(size: 13 * settings.fontScale, weight: .bold))
            .monospacedDigit()
            .frame(minWidth: 24, minHeight: 22)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(focused ? Color.accentColor.opacity(0.18) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? Color.accentColor : Color.primary.opacity(0.35), lineWidth: focused ? 1.5 : 1))
            .onTapGesture { session.focusedQuestion = n }
            .overlay(alignment: .topTrailing) {
                if session.isFlagged(n) && !session.isReview {
                    Image(systemName: "flag.fill").font(.system(size: 8)).foregroundStyle(.orange).offset(x: 4, y: -4)
                }
            }
            .contextMenu {
                if !session.isReview {
                    Button(session.isFlagged(n) ? "取消标记" : "标记此题（稍后检查）") { session.toggleFlag(n) }
                }
            }
    }
}

/// ✓ / ✗ with the key, shown in review mode.
struct ResultMark: View {
    let n: Int
    @EnvironmentObject var session: ExamSession

    var body: some View {
        if session.isReview, let r = session.result(n) {
            HStack(spacing: 4) {
                Image(systemName: r.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(r.isCorrect ? Theme.correct : Theme.wrong)
                if !r.isCorrect {
                    Text("答案：\(r.keyDisplay)").font(.callout.weight(.semibold)).foregroundStyle(Theme.correct)
                    if r.nearMiss { Text("（拼写/单复数/连字符差异）").font(.caption).foregroundStyle(Theme.near) }
                }
            }
        }
    }
}

// MARK: - completion

struct CompletionView: View {
    let group: QuestionGroup
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var session: ExamSession

    var boxed: Bool {
        let c = group.content ?? []
        return c.contains { $0.t == "h" } || c.count > 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let opts = group.options {
                OptionBox(title: group.optionsTitle, options: opts, group: group)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array((group.content ?? []).enumerated()), id: \.offset) { _, b in
                    BlockView(block: b, group: group)
                }
            }
            .padding(boxed ? 14 : 0)
            .overlay {
                if boxed { RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.45), lineWidth: 1) }
            }
            if session.isReview {
                ExplanationList(numbers: group.numbers)
            }
        }
    }
}

struct BlockView: View {
    let block: Block
    let group: QuestionGroup
    @EnvironmentObject var settings: SettingsStore

    var fs: CGFloat { 15 * settings.fontScale }
    var indent: CGFloat { CGFloat(max(0, (block.level ?? 1) - 1)) * 22 }

    var body: some View {
        switch block.t {
        case "h":
            FlowText(text: block.text ?? "", group: group, size: fs + 2, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .center)
        case "sub":
            FlowText(text: block.text ?? "", group: group, size: fs, weight: .bold)
                .padding(.top, 4)
                .padding(.leading, indent)
        case "li":
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.level ?? 1 > 1 ? "–" : "•").font(.system(size: fs))
                FlowText(text: block.text ?? "", group: group, size: fs)
            }
            .padding(.leading, indent)
        case "note":
            FlowText(text: block.text ?? "", group: group, size: fs - 2, italic: true)
                .foregroundStyle(.secondary)
                .padding(.leading, indent)
        case "table":
            TableBlock(block: block, group: group)
        case "flow":
            FlowChartBlock(block: block, group: group)
        case "img":
            BankImageForBlock(src: block.src)
        default:
            FlowText(text: block.text ?? "", group: group, size: fs)
                .padding(.leading, indent)
        }
    }
}

struct BankImageForBlock: View {
    var src: String?
    @EnvironmentObject var session: ExamSession
    var body: some View { BankImage(url: session.ref.url(src), maxHeight: 420).frame(maxWidth: .infinity) }
}

/// Inline markup text with {{n}} gaps rendered as input fields, wrapped with FlowLayout.
struct FlowText: View {
    let text: String
    let group: QuestionGroup
    var size: CGFloat
    var weight: Font.Weight = .regular
    var italic = false

    enum Piece: Hashable { case word(String, bold: Bool, italic: Bool), space, gap(Int), br }

    var pieces: [Piece] {
        var out: [Piece] = []
        for t in InlineMarkup.tokenize(text) {
            switch t {
            case .gap(let n): out.append(.gap(n))
            case .lineBreak: out.append(.br)
            case .text(let r):
                var s = r.text
                if s.first == " " { out.append(.space); s = String(s.drop { $0 == " " }) }
                let re = try! NSRegularExpression(pattern: #"\S+\s*"#)
                let ns = s as NSString
                for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    out.append(.word(ns.substring(with: m.range), bold: r.bold, italic: r.italic))
                }
            }
        }
        return out
    }

    var body: some View {
        FlowLayout(spacing: 0, lineSpacing: 5) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                switch p {
                case .word(let w, let b, let i):
                    Text(w)
                        .font(.system(size: size, weight: b ? .bold : weight))
                        .italic(i || italic)
                        .fixedSize()
                case .space:
                    Color.clear.frame(width: size * 0.3, height: 1)
                case .gap(let n):
                    GapField(n: n, group: group, size: size)
                        .padding(.trailing, 2)
                case .br:
                    Color.clear.frame(width: 0, height: 0).layoutValue(key: LineBreakKey.self, value: true)
                }
            }
        }
    }
}

struct GapField: View {
    let n: Int
    let group: QuestionGroup
    var size: CGFloat
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if session.isReview {
                Text("\(n)").font(.system(size: size, weight: .bold)).monospacedDigit()
                reviewBody
            } else if let opts = group.options {
                Text("\(n)").font(.system(size: size, weight: .bold)).monospacedDigit()
                OptionPicker(n: n, options: opts, group: group, size: size)
            } else {
                // As in the computer-delivered test: the question number sits inside the empty answer box.
                let value = session.answer(n)
                TextField("", text: Binding(get: { value }, set: { session.setAnswer(n, $0) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: size))
                    .multilineTextAlignment(.center)
                    .frame(width: max(130, size * 9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay {
                        if value.isEmpty && !focused {
                            Text("\(n)").font(.system(size: size, weight: .bold)).monospacedDigit().allowsHitTesting(false)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 2).fill(settings.examContrast.background))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(focused ? Color.accentColor : Color.primary.opacity(0.55), lineWidth: focused ? 2 : 1))
                    .focused($focused)
                    .onChange(of: focused) { _, f in if f { session.focusedQuestion = n } }
                    .onChange(of: session.focusedQuestion) { _, q in if q == n && !focused { focused = true } }
                    .onSubmit { session.next() }
                    .help("Question \(n)")
            }
        }
        .id("q\(n)")
        .contextMenu {
            if !session.isReview { Button(session.isFlagged(n) ? "取消标记" : "标记此题") { session.toggleFlag(n) } }
        }
    }

    @ViewBuilder var reviewBody: some View {
        let r = session.result(n)
        let ok = r?.isCorrect ?? false
        HStack(spacing: 4) {
            Text(r?.isBlank ?? true ? "（未作答）" : (r?.user ?? ""))
                .font(.system(size: size))
                .strikethrough(!ok && !(r?.isBlank ?? true), color: Theme.wrong)
                .foregroundStyle(ok ? Theme.correct : Theme.wrong)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill((ok ? Theme.correct : Theme.wrong).opacity(0.1)))
                .fixedSize()
            if !ok, let r {
                Text("→ \(r.keyDisplay)").font(.system(size: size, weight: .semibold)).foregroundStyle(Theme.correct)
                    .fixedSize()
            }
        }
    }
}

struct OptionPicker: View {
    let n: Int
    let options: [Option]
    let group: QuestionGroup
    var size: CGFloat
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var session: ExamSession
    @State private var targeted = false

    var body: some View {
        let cur = session.answer(n)
        Menu {
            ForEach(options) { o in
                Button(o.text.isEmpty ? o.key : "\(o.key)  \(InlineMarkup.strip(o.text))") {
                    session.setAnswer(n, o.key)
                    session.focusedQuestion = n
                }
            }
            if !cur.isEmpty {
                Divider()
                Button("清除") { session.setAnswer(n, "") }
            }
        } label: {
            Text(cur.isEmpty ? "选择" : label(cur))
                .font(.system(size: size, weight: cur.isEmpty ? .regular : .semibold))
                .foregroundStyle(cur.isEmpty ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(targeted ? Color.accentColor.opacity(0.15) : settings.examContrast.background))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(session.focusedQuestion == n ? Color.accentColor : Color.primary.opacity(0.4)))
        .dropDestination(for: String.self) { items, _ in
            guard let k = items.first, options.contains(where: { $0.key == k }) else { return false }
            session.setAnswer(n, k)
            return true
        } isTargeted: { targeted = $0 }
    }

    func label(_ key: String) -> String {
        guard let o = options.first(where: { $0.key == key }), !o.text.isEmpty else { return key }
        let t = InlineMarkup.strip(o.text)
        return "\(key)  " + (t.count > 38 ? String(t.prefix(36)) + "…" : t)
    }
}

/// Box listing options (headings, word list, features), with draggable chips.
struct OptionBox: View {
    let title: String?
    let options: [Option]
    let group: QuestionGroup
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var used: Set<String> { Set(group.numbers.map { session.answer($0) }) }

    var body: some View {
        if options.allSatisfy({ $0.text.isEmpty }) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if let title { MarkupText(title, font: .system(size: 15 * settings.fontScale, weight: .bold)) }
                ForEach(options) { o in
                    let isUsed = used.contains(o.key) && !group.allowsReuse && !session.isReview
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(o.key).font(.system(size: 15 * settings.fontScale, weight: .bold)).frame(minWidth: 26, alignment: .leading)
                        MarkupText(o.text, font: .system(size: 15 * settings.fontScale))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(isUsed ? 0.02 : 0.05)))
                    .opacity(isUsed ? 0.45 : 1)
                    .draggable(o.key)
                    .help(session.isReview ? "" : "可拖到题目的答题框")
                }
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.45)))
        }
    }
}

struct TableBlock: View {
    let block: Block
    let group: QuestionGroup
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let rows = block.rows ?? []
        let header = block.header ?? 1
        let cols = rows.map(\.count).max() ?? 0
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { ci in
                        let cell = ci < row.count ? row[ci] : ""
                        FlowText(text: cell, group: group, size: 14 * settings.fontScale, weight: ri < header ? .bold : .regular)
                            .padding(7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(ri < header ? Color.primary.opacity(0.06) : Color.clear)
                            .overlay(Rectangle().stroke(Color.primary.opacity(0.35), lineWidth: 0.5))
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
    }
}

struct FlowChartBlock: View {
    let block: Block
    let group: QuestionGroup
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let steps = block.steps ?? []
        VStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                FlowText(text: s, group: group, size: 14 * settings.fontScale)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.5)))
                if i < steps.count - 1 {
                    Image(systemName: "arrow.down").foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - choice

struct ChoiceView: View {
    let group: QuestionGroup
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(group.questions ?? []) { q in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        NumberBadge(n: q.n)
                        MarkupText(q.text, font: .system(size: 15 * settings.fontScale))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        ResultMark(n: q.n)
                    }
                    ForEach(q.options ?? []) { o in
                        OptionRow(n: q.n, option: o, multi: false, selected: session.answer(q.n) == o.key) {
                            session.setAnswer(q.n, session.answer(q.n) == o.key ? "" : o.key)
                            session.focusedQuestion = q.n
                        }
                    }
                    if session.isReview { ExplanationList(numbers: [q.n]) }
                }
                .id("q\(q.n)")
            }
        }
    }
}

struct OptionRow: View {
    let n: Int
    let option: Option
    var multi: Bool
    var selected: Bool
    var correctKeys: Set<String> = []
    var action: () -> Void
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore
    @State private var hover = false

    var reviewColor: Color? {
        guard session.isReview else { return nil }
        let keys = correctKeys.isEmpty ? Set(session.result(n)?.accepted.map { $0.uppercased() } ?? []) : correctKeys
        if keys.contains(option.key.uppercased()) { return Theme.correct }
        if selected { return Theme.wrong }
        return nil
    }

    var body: some View {
        Button(action: { if !session.isReview { action() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: multi ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(option.key).font(.system(size: 15 * settings.fontScale, weight: .bold)).frame(width: 18, alignment: .leading)
                MarkupText(option.text, font: .system(size: 15 * settings.fontScale))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(reviewColor.map { $0.opacity(0.13) } ?? (selected ? Color.accentColor.opacity(0.1) : (hover ? Color.primary.opacity(0.04) : .clear))))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(reviewColor ?? .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.leading, 30)
    }
}

struct MultiView: View {
    let group: QuestionGroup
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let sel = session.multiSelection(group)
        let keys = session.isReview ? Set(group.numbers.flatMap { session.exam.answers(for: session.module)[String($0)]?.a ?? [] }.map { $0.uppercased() }) : []
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(group.numbers, id: \.self) { NumberBadge(n: $0) }
                MarkupText(group.text ?? "", font: .system(size: 15 * settings.fontScale))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !session.isReview {
                    Text("已选 \(sel.count)/\(group.numbers.count)").font(.caption).foregroundStyle(.secondary)
                } else {
                    let right = group.numbers.filter { session.result($0)?.isCorrect ?? false }.count
                    Text("得分 \(right)/\(group.numbers.count) · 答案 \(keys.sorted().joined(separator: ", "))")
                        .font(.callout.weight(.semibold)).foregroundStyle(right == group.numbers.count ? Theme.correct : Theme.wrong)
                }
            }
            ForEach(group.options ?? []) { o in
                OptionRow(n: group.first, option: o, multi: true, selected: sel.contains(o.key), correctKeys: keys) {
                    session.toggleMulti(group, o.key)
                    session.focusedQuestion = group.first
                }
            }
            if session.isReview { ExplanationList(numbers: group.numbers) }
        }
        .id("q\(group.first)")
        .background(Color.clear.id("q\(group.last)"))
    }
}

// MARK: - TFNG / YNNG

struct JudgementView: View {
    let group: QuestionGroup
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(group.questions ?? []) { q in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        NumberBadge(n: q.n)
                        MarkupText(q.text, font: .system(size: 15 * settings.fontScale))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        ForEach(group.judgementOptions, id: \.self) { opt in
                            judgementButton(q.n, opt)
                        }
                        ResultMark(n: q.n)
                    }
                    .padding(.leading, 34)
                    if session.isReview { ExplanationList(numbers: [q.n]) }
                }
                .id("q\(q.n)")
            }
        }
    }

    func judgementButton(_ n: Int, _ opt: String) -> some View {
        let selected = session.answer(n) == opt
        var color: Color = .accentColor
        var filled = selected
        if session.isReview, let r = session.result(n) {
            if r.accepted.contains(opt) { color = Theme.correct; filled = true } else if selected { color = Theme.wrong }
        }
        return Button {
            guard !session.isReview else { return }
            session.setAnswer(n, selected ? "" : opt)
            session.focusedQuestion = n
        } label: {
            Text(opt)
                .font(.system(size: 13 * settings.fontScale, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(filled ? Color.white : Color.primary)
                .background(Capsule().fill(filled ? color : Color.primary.opacity(0.06)))
                .overlay(Capsule().stroke(selected ? color : Color.primary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - matching

struct MatchingView: View {
    let group: QuestionGroup
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionBox(title: group.optionsTitle, options: group.options ?? [], group: group)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.questions ?? []) { q in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 10) {
                            NumberBadge(n: q.n)
                            MarkupText(q.text, font: .system(size: 15 * settings.fontScale))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if session.isReview {
                                let r = session.result(q.n)
                                Text(r?.isBlank ?? true ? "未作答" : (r?.user ?? ""))
                                    .font(.system(size: 15 * settings.fontScale, weight: .semibold))
                                    .foregroundStyle((r?.isCorrect ?? false) ? Theme.correct : Theme.wrong)
                                ResultMark(n: q.n)
                            } else {
                                OptionPicker(n: q.n, options: group.options ?? [], group: group, size: 15 * settings.fontScale)
                            }
                        }
                        if session.isReview { ExplanationList(numbers: [q.n]) }
                    }
                    .id("q\(q.n)")
                }
            }
        }
    }
}

// MARK: - explanations (review)

struct ExplanationList: View {
    let numbers: [Int]
    @EnvironmentObject var session: ExamSession

    var body: some View {
        let items = numbers.compactMap { n -> (Int, QuestionExplanation)? in
            guard let r = session.result(n), !r.isCorrect, let e = session.explanation(n) else { return nil }
            return (n, e)
        }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { n, e in ExplanationCard(number: n, explanation: e) }
            }
            .padding(.leading, 30)
        }
    }
}

struct ExplanationCard: View {
    let number: Int
    let explanation: QuestionExplanation
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Q\(number) 解析", systemImage: "sparkles").font(.callout.bold()).foregroundStyle(Color.accentColor)
                Spacer()
                Text(explanation.model).font(.caption2).foregroundStyle(.tertiary)
            }
            MarkdownText(explanation.explanation)
                .font(.system(size: 14 * settings.fontScale))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let ev = explanation.evidence {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote").foregroundStyle(.secondary)
                    Text(ev).italic().font(.system(size: 13 * settings.fontScale)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let ps = explanation.paraphrases, !ps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同义替换").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(ps, id: \.self) { Text("· " + $0).font(.system(size: 13 * settings.fontScale)).textSelection(.enabled) }
                }
            }
            if let tip = explanation.tip {
                Label(tip, systemImage: "lightbulb").font(.system(size: 13 * settings.fontScale)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.25)))
    }
}
