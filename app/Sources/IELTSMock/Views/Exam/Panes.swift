import SwiftUI

// MARK: - listening

struct ListeningPane: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var part: ListeningPart? { session.exam.listening?.parts[safe: session.currentSection] }

    var body: some View {
        VStack(spacing: 0) {
            AudioBar(audio: session.audio)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let p = part {
                            Text("PART \(p.part)").font(.system(size: 18 * settings.fontScale, weight: .heavy))
                            if let c = p.context { MarkupText(c, font: .system(size: 15 * settings.fontScale)).italic() }
                            ForEach(p.groups) { g in QuestionGroupView(group: g) }
                            if session.isReview, let t = p.transcript {
                                TranscriptView(transcript: t)
                            }
                        }
                    }
                    .padding(28)
                    .padding(.bottom, 56)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: session.focusedQuestion) { _, n in
                    if let n { withAnimation { proxy.scrollTo("q\(n)", anchor: .center) } }
                }
            }
        }
        .onAppear { if session.isReview { session.loadReviewAudio(session.currentSection) } }
        .onChange(of: session.currentSection) { _, i in if session.isReview { session.loadReviewAudio(i) } }
    }
}

struct AudioBar: View {
    @ObservedObject var audio: AudioController
    @EnvironmentObject var session: ExamSession

    var controls: Bool { !session.isStrict || session.isReview }

    var body: some View {
        HStack(spacing: 12) {
            if session.ref.audioURL(part: session.currentSection) == nil && session.module == .listening {
                Label("Part \(session.exam.listening?.parts[safe: session.currentSection]?.part ?? session.currentSection + 1) 没有音频", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
            } else if controls {
                Button { audio.toggle() } label: { Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").frame(width: 18) }
                    .keyboardShortcut(.space, modifiers: [])
                Button { audio.skip(-5) } label: { Image(systemName: "gobackward.5") }
                Button { audio.skip(5) } label: { Image(systemName: "goforward.5") }
                Text(timeString(audio.currentTime)).monospacedDigit().font(.caption)
                Slider(value: Binding(get: { audio.currentTime }, set: { audio.seek(to: $0) }), in: 0...max(1, audio.duration))
                Text(timeString(audio.duration)).monospacedDigit().font(.caption)
                Menu("\(String(format: "%.2g", audio.rate))×") {
                    ForEach([0.75, 0.9, 1.0, 1.1, 1.25], id: \.self) { r in Button("\(r)×") { audio.rate = Float(r) } }
                }
                .frame(width: 70)
            } else {
                switch session.listeningPhase {
                case .playing(let p):
                    Image(systemName: "waveform").foregroundStyle(Theme.brand).symbolEffect(.variableColor.iterative, isActive: audio.isPlaying)
                    Text("正在播放 Part \(p + 1)").font(.headline)
                    ProgressView(value: min(audio.currentTime, max(1, audio.duration)), total: max(1, audio.duration))
                    Text("\(timeString(audio.currentTime)) / \(timeString(audio.duration))").monospacedDigit().font(.caption)
                    if p != session.currentSection {
                        Button("回到正在播放的 Part") { session.currentSection = p }
                    }
                case .review:
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.correct)
                    Text("录音已结束 · 检查答案时间").font(.headline)
                    Spacer()
                default:
                    Text("准备中…").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    func timeString(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct TranscriptView: View {
    var transcript: String
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(transcript.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            }
            .textSelection(.enabled)
            .padding(.top, 6)
        } label: {
            Label("听力原文 Audioscript", systemImage: "text.alignleft").font(.headline)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    func lineView(_ line: String) -> some View {
        var a = AttributedString()
        var rest = Substring(line)
        if let r = line.range(of: #"^[A-Z][A-Z .'\-]{1,24}:"#, options: .regularExpression) {
            var sp = AttributedString(String(line[r]))
            sp.font = .system(size: 14 * settings.fontScale, weight: .bold)
            a += sp
            rest = line[r.upperBound...]
        }
        // Q-markers in brand colour; wrong answers' markers emphasised
        let wrong = Set(session.attempt.results.filter { $0.module == .listening && !$0.isCorrect }.map(\.number))
        let parts = String(rest).components(separatedBy: "[Q")
        for (i, piece) in parts.enumerated() {
            if i == 0 {
                var t = AttributedString(piece)
                t.font = .system(size: 14 * settings.fontScale)
                a += t
                continue
            }
            // "[Q7]", or a joint marker such as "[Q21/Q22]" / "[Q21&22]"
            if let close = piece.firstIndex(of: "]"),
               case let nums = piece[..<close].split(whereSeparator: { "/& Q".contains($0) }).compactMap({ Int($0) }),
               !nums.isEmpty, piece[..<close].allSatisfy({ $0.isNumber || "/& Q".contains($0) }) {
                let bad = nums.contains { wrong.contains($0) }
                var m = AttributedString(" Q\(nums.map(String.init).joined(separator: "/")) ")
                m.font = .system(size: 12 * settings.fontScale, weight: .heavy)
                m.foregroundColor = bad ? Theme.wrong : Theme.correct
                m.backgroundColor = (bad ? Theme.wrong : Theme.correct).opacity(0.12)
                a += m
                var t = AttributedString(String(piece[piece.index(after: close)...]))
                t.font = .system(size: 14 * settings.fontScale)
                a += t
            } else {
                var t = AttributedString("[Q" + piece)
                t.font = .system(size: 14 * settings.fontScale)
                a += t
            }
        }
        return Text(a).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - reading

struct ReadingPane: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var passage: Passage? { session.exam.reading?.passages[safe: session.currentSection] }

    var body: some View {
        if let p = passage {
            HSplitView {
                PassageView(passage: p, index: session.currentSection)
                    .frame(minWidth: 380, idealWidth: 620, maxWidth: .infinity)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(p.groups) { g in QuestionGroupView(group: g) }
                        }
                        .padding(24)
                        .padding(.bottom, 56)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: session.focusedQuestion) { _, n in
                        if let n { withAnimation { proxy.scrollTo("q\(n)", anchor: .center) } }
                    }
                }
                .frame(minWidth: 380, idealWidth: 560, maxWidth: .infinity)
            }
            .id(p.passage)
        }
    }
}

struct PassageView: View {
    let passage: Passage
    let index: Int
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var fs: CGFloat { 15.5 * settings.fontScale }

    /// paragraph label -> heading-matching question number
    var headingTargets: [String: (Int, QuestionGroup)] {
        var out: [String: (Int, QuestionGroup)] = [:]
        for g in passage.groups where g.type == .matching {
            let roman = (g.options ?? []).allSatisfy { $0.key.range(of: #"^[ivxlc]+$"#, options: .regularExpression) != nil }
            guard roman else { continue }
            for q in g.questions ?? [] {
                if let r = q.text.range(of: #"^(Paragraph|Section)\s+([A-Z])\b"#, options: [.regularExpression, .caseInsensitive]) {
                    let label = String(q.text[r].split(separator: " ").last ?? "")
                    out[label.uppercased()] = (q.n, g)
                }
            }
        }
        return out
    }

    var evidenceQuotes: [String] {
        guard session.isReview else { return [] }
        return session.attempt.results
            .filter { $0.module == .reading && !$0.isCorrect && $0.section == index }
            .compactMap { session.attempt.explanations[$0.id]?.evidence }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("READING PASSAGE \(passage.passage)").font(.system(size: fs, weight: .heavy))
                if let intro = passage.intro { MarkupText(intro, font: .system(size: fs - 1)).foregroundStyle(.secondary) }
                // a passage whose title is the subject of a question is stored with a "Reading Passage N" placeholder
                if passage.title.range(of: #"^Reading Passage \d+$"#, options: [.regularExpression, .caseInsensitive]) == nil {
                MarkupText(passage.title, font: .system(size: fs + 6, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                }
                if let sub = passage.subtitle, !sub.isEmpty {
                    MarkupText(sub, font: .system(size: fs)).italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                let targets = headingTargets
                let quotes = evidenceQuotes
                ForEach(Array(passage.paragraphs.enumerated()), id: \.offset) { i, para in
                    if let label = para.label?.uppercased(), let (n, g) = targets[label] {
                        HeadingDropZone(n: n, group: g, label: label)
                    }
                    paragraphView(i, para, quotes)
                }
            }
            .padding(26)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(settings.examContrast.background)
    }

    @ViewBuilder func paragraphView(_ i: Int, _ para: Paragraph, _ quotes: [String]) -> some View {
        if para.isImage {
            BankImage(url: session.ref.url(para.src), maxHeight: 420).frame(maxWidth: .infinity)
            if !para.text.isEmpty { MarkupText(para.text, font: .system(size: fs - 2)).foregroundStyle(.secondary) }
        } else if para.isHeading {
            MarkupText(para.text, font: .system(size: fs + 1, weight: .bold)).padding(.top, 4)
        } else {
            let attr = paragraphString(para)
            let hl = session.highlights(passage: index, paragraph: i).map { NSRange(location: $0.location, length: $0.length) }
            let ev = quotes.compactMap { findEvidence($0, in: attr.string) }
            HighlightableText(text: attr, highlights: hl, evidence: ev,
                              onHighlight: { r in session.addHighlight(passage: index, paragraph: i, range: r) },
                              onClear: { r in session.clearHighlights(passage: index, paragraph: i, range: r) })
        }
    }

    func paragraphString(_ para: Paragraph) -> NSAttributedString {
        let size = para.isNote ? fs - 2.5 : fs
        let s = NSMutableAttributedString()
        if let l = para.label {
            s.append(NSAttributedString(string: l + "   ", attributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: settings.examContrast.nsInk]))
        }
        s.append(InlineMarkup.nsAttributed(para.text, size: size, color: para.isNote ? settings.examContrast.nsInk.withAlphaComponent(0.7) : settings.examContrast.nsInk))
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4 * settings.fontScale
        ps.paragraphSpacing = 2
        s.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: s.length))
        return s
    }
}

/// Drop target above a paragraph for "choose the correct heading" questions (also shows the chosen heading).
struct HeadingDropZone: View {
    let n: Int
    let group: QuestionGroup
    let label: String
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore
    @State private var targeted = false

    var body: some View {
        let key = session.answer(n)
        let opt = group.options?.first { $0.key == key }
        HStack(spacing: 8) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.4)))
            if let opt {
                Text("\(opt.key)  \(InlineMarkup.strip(opt.text))").font(.system(size: 14 * settings.fontScale, weight: .semibold))
                if session.isReview, let r = session.result(n) {
                    Image(systemName: r.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r.isCorrect ? Theme.correct : Theme.wrong)
                    if !r.isCorrect { Text("→ \(r.keyDisplay)").foregroundStyle(Theme.correct) }
                } else {
                    Button { session.setAnswer(n, "") } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                }
            } else {
                Text(session.isReview ? "（未作答）→ \(session.result(n)?.keyDisplay ?? "")" : "把标题拖到这里（Paragraph \(label)）")
                    .font(.system(size: 13 * settings.fontScale)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: opt == nil ? [4] : [])).foregroundStyle(session.focusedQuestion == n ? Color.accentColor : Color.primary.opacity(0.3)))
        .onTapGesture { session.focusedQuestion = n }
        .dropDestination(for: String.self) { items, _ in
            guard !session.isReview, let k = items.first, group.options?.contains(where: { $0.key == k }) ?? false else { return false }
            session.setAnswer(n, k)
            session.focusedQuestion = n
            return true
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - writing

struct WritingPane: View {
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var task: WritingTask? { session.exam.writing?.tasks[safe: session.currentSection] }

    var body: some View {
        if let t = task {
            HSplitView {
                ScrollView {
                    WritingPromptView(task: t)
                        .padding(26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 380, idealWidth: 560)
                VStack(spacing: 0) {
                    EssayEditor(text: Binding(get: { session.essay(t.task) }, set: { session.setEssay(t.task, $0) }),
                                fontSize: 15 * settings.fontScale, editable: !session.isReview,
                                ink: settings.examContrast.nsInk, background: settings.examContrast.nsBackground)
                        .id(t.task)
                    Divider()
                    HStack {
                        let w = WordCounter.count(session.essay(t.task))
                        Text("Words: \(w)").font(.headline.monospacedDigit()).foregroundStyle(w < t.minWords ? Theme.near : Theme.correct)
                        Text("（至少 \(t.minWords) 词）").foregroundStyle(.secondary)
                        Spacer()
                        Text("建议用时 \(t.minutes) 分钟").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .frame(minWidth: 420, idealWidth: 640)
            }
        }
    }
}

struct WritingPromptView: View {
    let task: WritingTask
    @EnvironmentObject var session: ExamSession
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let fs = 15 * settings.fontScale
        VStack(alignment: .leading, spacing: 14) {
            Text("WRITING TASK \(task.task)").font(.system(size: fs + 1, weight: .heavy))
            Text("You should spend about \(task.minutes) minutes on this task.").font(.system(size: fs))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(task.prompt.enumerated()), id: \.offset) { _, line in
                    MarkupText(line, font: .system(size: fs, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .overlay(Rectangle().stroke(Color.primary.opacity(0.5)))
            Text("Write at least \(task.minWords) words.").font(.system(size: fs))
            if let img = task.image {
                BankImage(url: session.ref.url(img))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
