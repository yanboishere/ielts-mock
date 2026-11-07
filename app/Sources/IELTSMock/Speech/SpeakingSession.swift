import Foundation
import AppKit

/// One Speaking test (or one part of it as practice): the examiner's script, the recordings, transcription in the
/// background while the test goes on, and the analysis and scoring at the end.
@MainActor
final class SpeakingSession: ObservableObject, Identifiable {
    enum Phase: Equatable {
        /// Instructions before the test; the recogniser loads meanwhile.
        case ready
        case examiner
        case answering(limit: Double)
        case preparing
        case processing(String)
        case finished
    }

    nonisolated let id = UUID()
    let ref: ExamRef
    let mode: AttemptMode
    /// The part practised alone (1–3), nil for the whole test.
    let practicePart: Int?
    let settings: SettingsStore
    let history: HistoryStore
    let ai: AIService
    let models: SpeechModelStore

    @Published var attempt: Attempt
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var part = 0
    /// The question being asked or answered, as printed.
    @Published private(set) var question = ""
    @Published private(set) var showCueCard = false
    @Published var notes = ""
    @Published private(set) var prepRemaining: Double = 60
    @Published private(set) var engineStatus = "正在加载语音识别模型…"
    @Published private(set) var engineReady = false
    @Published private(set) var transcribedCount = 0
    @Published private(set) var processingProgress: Double = 0
    @Published private(set) var errorMessage: String?
    /// The candidate has asked to see the current question as text.
    @Published var revealQuestion = false
    @Published private(set) var startedAt: Date?

    let recorder = SpeakingRecorder()
    let examiner = Examiner()

    private var worker: SpeechWorker?
    private var workerStart: Task<SpeechWorker, Error>?
    private var transcriptions: [String: Task<Void, Never>] = [:]
    private var script: Task<Void, Never>?
    private var answerDone = false
    private var prepDone = false
    private var endRequested = false
    private var abandoned = false
    /// Seconds of the last answer from its first to its last speech.
    private var lastSpokenSpan: Double = 0

    var speaking: SpeakingModule? { ref.exam.speaking }
    var cueCard: CueCard? { speaking?.part2 }
    var turns: [SpeakingTurn] { attempt.speaking?.turns ?? [] }
    var recordingsDir: URL { AppPaths.recordings(attempt.id) }

    init(ref: ExamRef, practicePart: Int?, settings: SettingsStore, history: HistoryStore, ai: AIService, models: SpeechModelStore) {
        self.ref = ref
        self.practicePart = practicePart
        self.mode = practicePart == nil ? .moduleMock : .practice
        self.settings = settings
        self.history = history
        self.ai = ai
        self.models = models
        var a = Attempt(examId: ref.exam.id, examTitle: ref.exam.shortTitle, mode: practicePart == nil ? .moduleMock : .practice,
                        scopes: [AttemptScope(module: .speaking, section: practicePart.map { $0 - 1 })])
        a.speaking = SpeakingRecord()
        attempt = a
        examiner.voiceIdentifier = settings.examinerVoice.isEmpty ? nil : settings.examinerVoice
        examiner.rate = Float(settings.examinerRate)
        loadEngine()
    }

    /// Starts the recogniser now so that it is warm when the first answer arrives.
    private func loadEngine() {
        let model = models.fileURL(SpeechCatalog.asr)
        workerStart = Task {
            try await SpeechWorker.start(model: model)
        }
        Task {
            do {
                worker = try await workerStart?.value
                engineReady = true
                engineStatus = "语音识别模型已就绪"
            } catch {
                engineStatus = "语音识别模型加载失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: control

    func begin() {
        guard phase == .ready else { return }
        startedAt = Date()
        history.save(attempt)
        script = Task { await run() }
    }

    func answerFinished() { answerDone = true }
    func startTalkingNow() { prepDone = true }

    func repeatQuestion() {
        guard case .answering = phase, !question.isEmpty else { return }
        let q = SpeakingQuestion(question).spokenMain
        Task { await examiner.say(q) }
    }

    /// Stops the test where it is and scores what was recorded.
    func endEarly() {
        endRequested = true
        answerDone = true
        prepDone = true
        examiner.stop()
    }

    /// Leaves without keeping anything.
    func abandon() {
        abandoned = true
        endEarly()
        script?.cancel()
        recorder.cancel()
        worker?.stop()
        workerStart?.cancel()
        history.delete(attempt)
    }

    // MARK: script

    private func run() async {
        guard let s = speaking else { return }
        do {
            switch practicePart {
            case nil:
                if let p1 = s.part1 { try await part1(p1, identity: true) }
                if let c = s.part2 { try await part2(c) }
                if let p3 = s.part3 { try await part3(p3, afterCueCard: s.part2 != nil) }
                try await say("Thank you. That is the end of the speaking test.")
            case 1:
                if let p1 = s.part1 { try await part1(p1, identity: false) }
                try await say("Thank you. That is the end of Part 1.")
            case 2:
                if let c = s.part2 { try await part2(c) }
                try await say("Thank you. That is the end of Part 2.")
            default:
                if let p3 = s.part3 { try await part3(p3, afterCueCard: false) }
                try await say("Thank you. That is the end of the speaking test.")
            }
        } catch {}
        guard !abandoned else { return }
        await finish()
    }

    private struct Ended: Error {}

    private func checkEnded() throws {
        if endRequested || Task.isCancelled { throw Ended() }
    }

    private func say(_ text: String) async throws {
        try checkEnded()
        phase = .examiner
        await examiner.say(text)
        try checkEnded()
    }

    private func spokenTitle(_ t: String) -> String {
        let s = SpeakingQuestion.speakable(t)
        guard let first = s.split(separator: " ").first, first.count > 1, first != first.uppercased() else { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }

    private func part1(_ p1: SpeakingTopicSet, identity: Bool) async throws {
        part = 1
        if identity {
            question = "Can you tell me your full name, please?"
            try await say("Good morning. My name is \(examiner.name), and I'll be your examiner today. Can you tell me your full name, please?")
            _ = try await record(id: "id", part: 0, question: question, limit: 20)
            try await say("Thank you. Now, in this first part of the test, I'd like to ask you some questions about yourself.")
        } else {
            try await say("In this first part of the test, I'd like to ask you some questions about yourself.")
        }
        for (ti, topic) in p1.topics.enumerated() where !topic.questions.isEmpty {
            try await say((ti == 0 ? "Let's talk about " : "Now let's talk about ") + spokenTitle(topic.title) + ".")
            for (qi, q) in topic.questions.enumerated() {
                try await ask(id: "p1-\(ti)-\(qi)", part: 1, printed: q, limit: 60)
            }
        }
    }

    private func part2(_ c: CueCard) async throws {
        part = 2
        try await say("Now, I'm going to give you a topic, and I'd like you to talk about it for one to two minutes. Before you talk, you'll have one minute to think about what you're going to say. You can make some notes if you wish. Here is your topic.")
        question = c.topic
        showCueCard = true
        try await say(c.spokenTopic)
        phase = .preparing
        prepDone = false
        prepRemaining = 60
        let prepStart = Date()
        while !prepDone {
            prepRemaining = max(0, 60 - Date().timeIntervalSince(prepStart))
            if prepRemaining <= 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try checkEnded()
        attempt.speaking?.notes = notes
        try await say("All right? Remember, you have one to two minutes for this, so don't worry if I stop you. I'll tell you when the time is up. Can you start speaking now, please?")
        _ = try await record(id: "p2", part: 2, question: c.topic, limit: 120, autoEnd: false)
        var talked = lastSpokenSpan
        if talked < 60, !endRequested {
            let more = "Can you tell me anything more about it?"
            try await say(more)
            _ = try await record(id: "p2-more", part: 2, question: more, limit: max(20, 120 - talked))
            talked += lastSpokenSpan
        }
        attempt.speaking?.notes = notes
        try await say("Thank you.")
        for (i, q) in (c.followUp ?? []).enumerated() {
            try await ask(id: "p2-f\(i)", part: 2, printed: q, limit: 40)
        }
        showCueCard = false
    }

    private func part3(_ p3: SpeakingTopicSet, afterCueCard: Bool) async throws {
        part = 3
        for (ti, topic) in p3.topics.enumerated() where !topic.questions.isEmpty {
            let title = spokenTitle(topic.title)
            if ti == 0 {
                try await say(afterCueCard
                    ? "We've been talking about the topic on your card, and now I'd like to discuss with you one or two more general questions related to this. Let's consider first of all \(title)."
                    : "In this part of the test, I'd like to discuss with you some general questions. Let's consider first of all \(title).")
            } else {
                try await say("Now let's talk about \(title).")
            }
            for (qi, q) in topic.questions.enumerated() {
                try await ask(id: "p3-\(ti)-\(qi)", part: 3, printed: q, limit: 90)
            }
        }
    }

    /// Asks a printed question; when the answer was short and the book prints a prompt such as "[Why?]",
    /// asks that too, as an examiner would.
    private func ask(id: String, part: Int, printed: String, limit: Double) async throws {
        let q = SpeakingQuestion(printed)
        question = printed
        revealQuestion = false
        try await say(q.spokenMain)
        _ = try await record(id: id, part: part, question: printed, limit: limit)
        if let prompt = q.spokenPrompt, lastSpokenSpan < 8, !endRequested {
            try await say(prompt)
            _ = try await record(id: id + "-why", part: part, question: prompt, limit: 45)
        }
    }

    private func record(id: String, part: Int, question: String, limit: Double, autoEnd: Bool = true) async throws -> SpeakingTurn {
        try checkEnded()
        let file = recordingsDir.appendingPathComponent(id + ".wav")
        try recorder.start(to: file)
        phase = .answering(limit: limit)
        answerDone = false
        while true {
            if answerDone || endRequested || Task.isCancelled { break }
            if recorder.elapsed >= limit { break }
            if autoEnd, settings.speakingAutoEnd > 0, recorder.hasSpoken, recorder.silence >= settings.speakingAutoEnd { break }
            // The long turn ends only on the button or at the time limit, unless the candidate has clearly finished.
            if !autoEnd, recorder.hasSpoken, recorder.silence >= max(8, settings.speakingAutoEnd * 2) { break }
            // No answer at all: move on as an examiner would.
            if !recorder.hasSpoken, recorder.elapsed >= 20 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let timeUp = recorder.elapsed >= limit
        lastSpokenSpan = recorder.spokenSpan
        let duration = recorder.stop()
        // Abandoned: the attempt and its recordings are already deleted; keep nothing.
        if abandoned { throw Ended() }
        let turn = SpeakingTurn(id: id, part: part, question: question, audio: file.lastPathComponent, duration: duration)
        attempt.speaking?.turns.append(turn)
        history.save(attempt)
        transcribe(turn)
        if timeUp, part == 2, id == "p2" || id == "p2-more" { examiner.stop() }
        return turn
    }

    // MARK: recognition

    private func transcribe(_ turn: SpeakingTurn) {
        let url = recordingsDir.appendingPathComponent(turn.audio)
        let previous = transcriptions.values.map { $0 }
        transcriptions[turn.id] = Task {
            // One request at a time, in the order of the test.
            for t in previous { await t.value }
            do {
                let w: SpeechWorker
                if let existing = worker { w = existing } else if let pending = workerStart { w = try await pending.value } else { return }
                let r = try await w.transcribe(url)
                if let i = attempt.speaking?.turns.firstIndex(where: { $0.id == turn.id }) {
                    attempt.speaking?.turns[i].transcript = r.text
                }
                transcribedCount += 1
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: finish

    private func finish() async {
        recorder.stop()
        phase = .processing("正在转写录音…")
        let total = Double(max(1, transcriptions.count))
        let progress = Task { @MainActor in
            while !Task.isCancelled {
                processingProgress = Double(transcribedCount) / total
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        for t in Array(transcriptions.values) { await t.value }
        progress.cancel()
        processingProgress = 1
        worker?.stop()

        let tVad = Date()
        phase = .processing("正在分析停顿、语速与语调…")
        let turns = attempt.speaking?.turns ?? []
        let files = turns.map { recordingsDir.appendingPathComponent($0.audio) }
        if let regions = try? await SpeechEngine.detectSpeech(in: files, model: models.fileURL(SpeechCatalog.vad)) {
            for (i, f) in files.enumerated() { attempt.speaking?.turns[i].regions = regions[f] ?? [] }
        }
        let analysed = (attempt.speaking?.turns ?? []).filter(\.assessed).map { (recordingsDir.appendingPathComponent($0.audio), $0.regions ?? []) }
        let tPitch = Date()
        let pitch = await Task.detached(priority: .userInitiated) { SpeakingAnalysis.pitchVariation(files: analysed) }.value
        print(String(format: "[speaking] vad %.2fs, pitch %.2fs", tPitch.timeIntervalSince(tVad), Date().timeIntervalSince(tPitch)))
        attempt.speaking?.metrics = SpeakingAnalysis.metrics(turns: attempt.speaking?.turns ?? [], pitchVariation: pitch)
        attempt.speaking?.asrModel = SpeechCatalog.asr.title
        attempt.status = .submitted
        attempt.finishedAt = Date()
        let used = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        attempt.timing[.speaking] = ModuleTiming(allotted: practicePart == nil ? 14 * 60 : 5 * 60, used: used)
        history.save(attempt)

        if settings.hasKeyForCurrentProvider, !(attempt.speaking?.assessedTurns.isEmpty ?? true) {
            phase = .processing("AI 正在按雅思官方口语评分标准评分…")
            await AIActions.assessSpeaking(ai: ai, history: history, attemptId: attempt.id, ref: ref)
            if let a = history.attempt(attempt.id) { attempt = a }
        }
        phase = .finished
    }
}
