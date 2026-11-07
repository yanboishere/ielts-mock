import SwiftUI
import AVFoundation

/// Plays the recordings of a Speaking attempt, one at a time.
@MainActor
final class RecordingPlayer: ObservableObject {
    @Published private(set) var playing: String?
    @Published private(set) var position: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ id: String, url: URL) {
        if playing == id { stop(); return }
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p
        p.play()
        playing = id
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.position = p.currentTime
                if !p.isPlaying { self.stop() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playing = nil
        position = 0
    }
}

struct SpeakingResultView: View {
    let attempt: Attempt
    let ref: ExamRef
    @EnvironmentObject var ai: AIService
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var player = RecordingPlayer()

    var record: SpeakingRecord { attempt.speaking ?? SpeakingRecord() }
    var aiKey: String { "speaking-\(ref.exam.id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            scores
            if let m = record.metrics { SpeakingMetricsView(metrics: m) }
            if let a = record.assessment { feedback(a) }
            ForEach(record.parts, id: \.self) { p in partCard(p) }
            if let model = record.asrModel {
                Text("转写：\(model)（speech.cpp，本地运行）· 停顿检测：\(SpeechCatalog.vad.title)" + (record.assessment.map { " · 评分：\($0.model)" } ?? "")
                     + "\n转写由机器识别：可能漏掉部分语气词，也可能把个别小语法错误自动改正（如 he enjoy → he enjoys），语法评分仅供参考。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: scores

    var scores: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("口语评分").font(.headline)
                Text("按雅思官方公开评分标准：四项各为整数分，总分为四项平均后按 0.5 取整").font(.caption).foregroundStyle(.secondary)
                Spacer()
                aiButton
            }
            if let a = record.assessment {
                HStack(alignment: .top, spacing: 18) {
                    BandBadge(band: a.overallBand, label: "口语总分", size: 46)
                        .frame(width: 110)
                    VStack(spacing: 10) {
                        ForEach(a.criteria) { c in criterionRow(c) }
                    }
                }
            } else {
                Text(settings.hasKeyForCurrentProvider
                     ? "还没有评分。点击「AI 评分」，按官方标准给出流利度、词汇、语法三项分数与逐题点评（发音为本地估算）。"
                     : "还没有评分：请先在设置 › AI 中配置 Claude 或 OpenAI 的 API Key，再点击「AI 评分」。下方的转写与流利度指标已在本地生成。")
                    .foregroundStyle(.secondary)
                if let m = record.metrics {
                    HStack {
                        Text("发音估算：").bold()
                        Text(Grader.bandString(m.pronunciationEstimate))
                        Pill(text: "估算", color: .orange)
                    }
                }
            }
            if let e = ai.errors[aiKey] { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .card()
    }

    @ViewBuilder var aiButton: some View {
        if let n = ai.running[aiKey] {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(n > 0 ? "评分中…（已生成 \(n) 字）" : "评分中…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button {
                Task { await AIActions.assessSpeaking(ai: ai, history: history, attemptId: attempt.id, ref: ref) }
            } label: {
                Label(record.assessment == nil ? "AI 评分" : "重新评分", systemImage: "sparkles")
            }
            .disabled(!settings.hasKeyForCurrentProvider || record.assessedTurns.isEmpty)
        }
    }

    func criterionRow(_ c: SpeakingAssessment.Criterion) -> some View {
        let zh = SpeakingBand.criteria.first { $0.key == c.key }?.chinese ?? c.name
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(Grader.bandString(c.band)).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.brand).frame(width: 46, alignment: .leading)
                Text(zh).font(.headline)
                Text(c.name).font(.caption).foregroundStyle(.secondary)
                if c.estimated { Pill(text: "估算", color: .orange) }
                Spacer()
            }
            MarkdownText(c.comment).font(.callout)
            if !c.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(c.evidence, id: \.self) { Text("“\($0)”").font(.caption).italic().foregroundStyle(.secondary) }
                }
            }
            if let d = SpeakingBand.descriptors[c.key]?[Int(c.band)] {
                DisclosureGroup("官方描述 · Band \(Int(c.band))") {
                    Text(d).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    func feedback(_ a: SpeakingAssessment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !a.summary.isEmpty { MarkdownText(a.summary) }
            HStack(alignment: .top, spacing: 24) {
                if !a.strengths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("优点", systemImage: "hand.thumbsup").font(.headline).foregroundStyle(Theme.correct)
                        ForEach(a.strengths, id: \.self) { MarkdownText("• " + $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !a.improvements.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("提升方向", systemImage: "arrow.up.forward").font(.headline).foregroundStyle(.orange)
                        ForEach(a.improvements, id: \.self) { MarkdownText("• " + $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !a.pronunciationNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("发音提示（根据转写推测）", systemImage: "waveform").font(.headline)
                    MarkdownText(a.pronunciationNotes).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    // MARK: answers

    func partCard(_ p: Int) -> some View {
        let turns = record.assessedTurns.filter { $0.part == p }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Part \(p)").font(.title3.bold()).foregroundStyle(Theme.moduleColor(.speaking))
                Text(p == 1 ? "Introduction and interview" : p == 2 ? "Individual long turn" : "Two-way discussion").foregroundStyle(.secondary)
            }
            if p == 2, let c = ref.exam.speaking?.part2 {
                CueCardView(card: c).frame(maxWidth: 560)
                if !record.notes.isEmpty {
                    Text("你的笔记：\(record.notes)").font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(turns) { t in
                SpeakingTurnRow(turn: t, feedback: record.assessment?.feedback(for: t.id),
                                url: AppPaths.recordings(attempt.id).appendingPathComponent(t.audio), player: player)
                if t.id != turns.last?.id { Divider() }
            }
        }
        .card()
    }
}

struct SpeakingTurnRow: View {
    let turn: SpeakingTurn
    let feedback: SpeakingAssessment.TurnFeedback?
    let url: URL
    @ObservedObject var player: RecordingPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if turn.isFollowUp { Pill(text: "追问", color: .secondary) }
                Text(InlineMarkup.strip(turn.question)).font(.body.weight(.semibold))
                Spacer()
                Text(formatClock(turn.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { player.toggle(turn.id, url: url) } label: {
                    Image(systemName: player.playing == turn.id ? "stop.circle.fill" : "play.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(!FileManager.default.fileExists(atPath: url.path))
                SpeechTimeline(duration: turn.duration, regions: turn.regions ?? [],
                               position: player.playing == turn.id ? player.position : nil)
                    .frame(height: 18)
            }
            Text(highlightedTranscript)
                .font(.system(size: 15))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            let m = SpeakingAnalysis.measure(turn)
            if m.responseTime > 0 {
                Text(String(format: "%d 词 · 有效说话 %.1f 秒 · 停顿 %d 次", m.words, m.speakingTime, m.pauses.count)
                     + (m.pauses.max().map { String(format: "（最长 %.1f 秒）", $0) } ?? "")
                     + (m.latency.map { String(format: " · %.1f 秒后开口", $0) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let f = feedback {
                VStack(alignment: .leading, spacing: 6) {
                    if !f.comment.isEmpty { MarkdownText(f.comment).font(.callout) }
                    ForEach(f.corrections) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.original).strikethrough().foregroundStyle(Theme.wrong)
                            Text(c.suggestion).bold().foregroundStyle(Theme.correct)
                            if !c.explanation.isEmpty { Text(c.explanation).font(.caption).foregroundStyle(.secondary) }
                        }
                        .font(.callout)
                    }
                    if !f.improved.isEmpty {
                        DisclosureGroup("高分示范回答") {
                            Text(f.improved).font(.callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.06)))
            }
        }
    }

    var highlightedTranscript: AttributedString {
        let text = (turn.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            var a = AttributedString(turn.transcript == nil ? "（未转写）" : "（没有识别到语音）")
            a.foregroundColor = .secondary
            return a
        }
        var a = AttributedString(text)
        if let re = try? NSRegularExpression(pattern: SpeakingAnalysis.fillerPattern) {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text), let ar = Range(r, in: a) {
                    a[ar].foregroundColor = .orange
                    a[ar].font = .system(size: 15, weight: .bold)
                }
            }
        }
        return a
    }
}

/// The recording as a bar: where the candidate speaks (filled) and pauses (gaps).
struct SpeechTimeline: View {
    let duration: Double
    let regions: [SpeechRegion]
    var position: Double?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let scale = duration > 0 ? w / duration : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.07))
                ForEach(Array(regions.enumerated()), id: \.offset) { _, r in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.moduleColor(.speaking).opacity(0.75))
                        .frame(width: max(1, r.length * scale), height: g.size.height * 0.7)
                        .offset(x: r.start * scale)
                }
                ForEach(Array(zip(regions, regions.dropFirst()).enumerated()), id: \.offset) { _, pair in
                    let gap = pair.1.start - pair.0.end
                    if gap >= SpeakingAnalysis.longPause {
                        Text(String(format: "%.0fs", gap)).font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                            .offset(x: pair.0.end * scale + 2)
                    }
                }
                if let p = position {
                    Rectangle().fill(Theme.brand).frame(width: 2).offset(x: min(w - 2, p * scale))
                }
            }
        }
        .help("紫色为检测到的说话段，空隙为停顿（≥2 秒标出时长）")
    }
}

struct SpeakingMetricsView: View {
    let metrics: SpeakingMetrics

    struct Item: Identifiable {
        var id: String { title }
        var title: String
        var value: String
        var note: String
        var good: Bool?
    }

    var items: [Item] {
        let m = metrics
        var a: [Item] = [
            Item(title: "有效说话时长", value: formatClock(m.speakingTime), note: "作答共 \(formatClock(m.responseTime)) · \(m.words) 词", good: nil),
            Item(title: "语速", value: String(format: "%.0f 词/分", m.speechRate), note: "含停顿；流利表达约 120–170", good: m.speechRate >= 110),
            Item(title: "发音速度", value: String(format: "%.0f 词/分", m.articulationRate), note: "不含停顿", good: m.articulationRate >= 130),
            Item(title: "停顿频率", value: String(format: "%.1f 次/分", m.pausesPerMinute), note: "≥0.5 秒的停顿；流利表达通常 < 8", good: m.pausesPerMinute < 8),
            Item(title: "长停顿", value: "\(m.longPauses) 次", note: String(format: "≥2 秒 · 平均停顿 %.1f 秒", m.meanPause), good: m.longPauses <= 2),
            Item(title: "平均意群长度", value: String(format: "%.1f 词", m.meanLengthOfRun), note: "两次停顿之间的词数；越长越连贯", good: m.meanLengthOfRun >= 8),
            Item(title: "语气词", value: "\(m.fillers) 个", note: String(format: "每百词 %.1f 个（um/uh/er…，识别会漏掉一部分）", m.fillersPer100Words), good: m.fillersPer100Words < 3),
            Item(title: "重复", value: "\(m.repetitions) 次", note: "紧邻重复的词（I I / the the）", good: m.repetitions <= 3),
            Item(title: "反应时间", value: String(format: "%.1f 秒", m.meanLatency), note: "问题结束到开口的平均时间", good: m.meanLatency < 2),
        ]
        if m.part2Duration > 0 {
            a.append(Item(title: "Part 2 时长", value: formatClock(m.part2Duration), note: "要求 1–2 分钟", good: m.part2Duration >= 90))
        }
        if let p = m.pitchVariation {
            a.append(Item(title: "语调起伏", value: String(format: "%.1f 半音", p), note: "音高标准差；自然口语约 2.5–5.5", good: p >= 2.5))
        }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("流利度与发音指标").font(.headline)
                Text("由本地录音分析得出").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(items) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i.title).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(i.value).font(.title3.bold().monospacedDigit())
                            if let g = i.good {
                                Image(systemName: g ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(g ? Theme.correct : .orange).font(.caption)
                            }
                        }
                        Text(i.note).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                }
            }
            DisclosureGroup("发音估算 \(Grader.bandString(metrics.pronunciationEstimate)) 是怎么得出的") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("从 6.0 起按以下几项增减（范围 2–8.5），评分时再与流利度分数综合取整。真实考试的发音分由考官听音评定，这里只能粗略估计。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(metrics.pronunciationFactors, id: \.self) { Text("• " + $0).font(.caption) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.callout)
        }
        .card()
    }
}
