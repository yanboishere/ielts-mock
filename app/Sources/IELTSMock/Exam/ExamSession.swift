import Foundation
import AppKit
import UserNotifications

struct Stage: Hashable {
    var module: Module
    var section: Int?     // nil = whole module
}

struct ReminderBanner: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var message: String
    var urgent: Bool
}

enum ListeningPhase: Equatable {
    case ready            // waiting for the candidate to press start
    case playing(Int)     // part index
    case review           // audio finished, checking/transfer time
    case done
}

/// One running exam (full mock, single module or a practice item).
@MainActor
final class ExamSession: ObservableObject, Identifiable {
    let ref: ExamRef
    let mode: AttemptMode
    let stages: [Stage]
    let settings: SettingsStore
    let history: HistoryStore

    @Published var attempt: Attempt
    @Published private(set) var stageIndex: Int
    @Published var currentSection = 0
    @Published var focusedQuestion: Int?
    @Published private(set) var remaining: Double = 0
    @Published private(set) var allotted: Double = 0
    @Published private(set) var paused = false
    @Published var banner: ReminderBanner?
    @Published var listeningPhase: ListeningPhase = .ready
    @Published private(set) var finished = false
    @Published var confirmSubmit = false
    @Published var hideTimer = false
    /// The stage intro screen is shown until the candidate presses Start.
    @Published private(set) var awaitingStart = true
    /// Review mode: which module of a finished attempt is being reviewed.
    @Published var reviewModule: Module?
    let isReview: Bool

    let audio = AudioController()

    private var deadline: Date?
    private var fired: Set<String> = []
    private var ticker: Timer?
    private var stageStarted = Date()
    private var dirty = false
    private var lastSave = Date()
    private var partDurations: [Int: Double] = [:]
    /// Listening: audio durations are measured asynchronously; the clock cannot start before that is done.
    @Published private(set) var listeningPrepared = false
    private var startWhenPrepared = false

    nonisolated let id: UUID
    var exam: Exam { ref.exam }
    var stage: Stage {
        if let m = reviewModule, let st = stages.first(where: { $0.module == m }) { return st }
        return stages[min(stageIndex, stages.count - 1)]
    }
    var module: Module { stage.module }
    var isStrict: Bool { mode != .practice }
    var isLastStage: Bool { stageIndex >= stages.count - 1 }

    init(ref: ExamRef, mode: AttemptMode, stages: [Stage], settings: SettingsStore, history: HistoryStore, resume: Attempt? = nil) {
        self.ref = ref
        self.mode = mode
        self.stages = stages
        self.settings = settings
        self.history = history
        isReview = false
        let a = resume ?? Attempt(examId: ref.exam.id, examTitle: ref.exam.shortTitle, mode: mode,
                                  scopes: stages.map { AttemptScope(module: $0.module, section: $0.section) })
        attempt = a
        stageIndex = resume.map { min($0.currentStage, stages.count - 1) } ?? 0
        id = a.id
        audio.onFinished = { [weak self] part in self?.audioFinished(part) }
    }

    /// Read-only session over a finished attempt, used by the review screens.
    init(review a: Attempt, ref: ExamRef, settings: SettingsStore, history: HistoryStore) {
        self.ref = ref
        self.mode = a.mode
        self.stages = a.scopes.map { Stage(module: $0.module, section: $0.section) }
        self.settings = settings
        self.history = history
        self.isReview = true
        id = UUID()
        attempt = a
        stageIndex = 0
        finished = true
        awaitingStart = false
        reviewModule = a.scopes.first?.module
        currentSection = a.scopes.first?.section ?? 0
        listeningPhase = .done
    }

    func setReviewModule(_ m: Module) {
        reviewModule = m
        currentSection = sections.first ?? 0
        focusedQuestion = questionNumbers.first
        audio.stop()
    }

    /// Review mode: play a part's recording with full controls.
    func loadReviewAudio(_ part: Int) {
        guard isReview, let u = ref.audioURL(part: part) else { return }
        if audio.part != part { audio.load(u, part: part, autoplay: false) }
    }

    // MARK: sections in scope

    /// Indices of parts / passages / tasks shown in the current stage.
    var sections: [Int] {
        if let s = stage.section { return [s] }
        switch module {
        case .listening: return Array((exam.listening?.parts ?? []).indices)
        case .reading: return Array((exam.reading?.passages ?? []).indices)
        case .writing: return Array((exam.writing?.tasks ?? []).indices)
        case .speaking: return []
        }
    }

    /// Question numbers in scope for the current stage.
    var questionNumbers: [Int] {
        switch module {
        case .listening: return sections.flatMap { i in exam.listening.map { p in Array(p.parts[i].first...p.parts[i].last) } ?? [] }
        case .reading: return sections.flatMap { i in exam.reading.map { p in Array(p.passages[i].first...p.passages[i].last) } ?? [] }
        case .writing, .speaking: return []
        }
    }

    // MARK: lifecycle

    func begin() {
        if attempt.status != .inProgress { attempt.status = .inProgress }
        requestNotificationPermission()
        startStage(resuming: attempt.remaining[module] != nil)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func startStage(resuming: Bool) {
        fired = []
        currentSection = sections.first ?? 0
        focusedQuestion = questionNumbers.first
        stageStarted = Date()
        attempt.currentStage = stageIndex
        switch module {
        case .listening:
            listeningPhase = .ready
            allotted = 0
            remaining = 0
            listeningPrepared = false
            startWhenPrepared = false
            Task { await prepareListening(resuming: resuming) }
        case .reading, .writing:
            allotted = stageSeconds()
            remaining = resuming ? (attempt.remaining[module] ?? allotted) : allotted
            deadline = nil
            paused = false
        case .speaking:
            break
        }
        awaitingStart = true
        save(force: true)
    }

    /// Called from the stage intro screen.
    func startTimer() {
        guard awaitingStart, !finished else { return }
        awaitingStart = false
        switch module {
        case .listening:
            if isStrict {
                if listeningPrepared { startListening() } else { startWhenPrepared = true }
            }
        case .reading, .writing:
            deadline = Date().addingTimeInterval(remaining)
        case .speaking:
            break
        }
    }

    private func stageSeconds() -> Double {
        switch module {
        case .reading:
            if stage.section != nil { return 20 * 60 }
            return Double(settings.readingMinutes) * 60
        case .writing:
            if let s = stage.section, let t = exam.writing?.tasks[safe: s] { return Double(t.minutes) * 60 }
            return Double(settings.writingMinutes) * 60
        case .listening, .speaking:
            return 0
        }
    }

    // MARK: listening flow

    private func prepareListening(resuming: Bool) async {
        var total = 0.0
        for i in sections {
            if let u = ref.audioURL(part: i) {
                let d = await AudioController.duration(of: u)
                partDurations[i] = d
                total += d
            }
        }
        let review = isStrict && stage.section == nil ? Double(settings.listeningReviewMinutes) * 60 : (isStrict ? 60 : 0)
        allotted = total + review
        remaining = allotted   // a listening section always restarts from the beginning of the recording
        if !isStrict {
            // practice: load the first part, no running clock until play
            if let first = sections.first, let u = ref.audioURL(part: first) { audio.load(u, part: first, autoplay: false) }
            listeningPhase = .playing(sections.first ?? 0)
            deadline = nil
        }
        listeningPrepared = true
        if startWhenPrepared && !finished { startWhenPrepared = false; startListening() }
    }

    /// Strict mode: the candidate presses "Start" and the recording runs to the end without pausing.
    private func startListening() {
        guard case .ready = listeningPhase, listeningPrepared else { return }
        deadline = Date().addingTimeInterval(remaining)
        let startPart = sections.first { ref.audioURL(part: $0) != nil } ?? sections.first ?? 0
        playPart(startPart)
    }

    private func playPart(_ i: Int) {
        listeningPhase = .playing(i)
        if settings.autoAdvanceListening || isStrict { currentSection = i }
        if let u = ref.audioURL(part: i) {
            audio.load(u, part: i, autoplay: true)
        } else {
            audioFinished(i)
        }
    }

    private func audioFinished(_ part: Int) {
        guard module == .listening else { return }
        if !isStrict {
            return
        }
        if let next = sections.first(where: { $0 > part }) {
            playPart(next)
        } else {
            listeningPhase = .review
            let mins = Int(round(remaining / 60))
            fire(key: "review", title: "录音结束", message: mins > 0 ? "现在有约 \(mins) 分钟检查答案。" : "请检查答案后交卷。", urgent: false)
        }
    }

    /// Practice mode: choose which part's audio is loaded.
    func selectPracticePart(_ i: Int) {
        currentSection = i
        guard !isStrict, module == .listening else { return }
        if audio.part != i, let u = ref.audioURL(part: i) { audio.load(u, part: i, autoplay: false) }
        listeningPhase = .playing(i)
    }

    // MARK: timer

    private func tick() {
        guard !finished else { return }
        if let d = deadline, !paused {
            remaining = max(0, d.timeIntervalSinceNow)
        } else if !isStrict, module == .listening, audio.isPlaying {
            // practice listening: count elapsed audio time against the clock for display only
        }
        checkReminders()
        if deadline != nil, remaining <= 0, !paused {
            timeUp()
        }
        if dirty, Date().timeIntervalSince(lastSave) > 5 { save() }
    }

    func togglePause() {
        guard !isStrict else { return }
        if paused {
            deadline = Date().addingTimeInterval(remaining)
            paused = false
        } else {
            paused = true
            if module == .listening { audio.pause() }
        }
    }

    private func checkReminders() {
        guard deadline != nil, allotted > 0 else { return }
        for m in settings.reminderMinutes.sorted(by: >) {
            let s = Double(m * 60)
            if remaining <= s, allotted > s + 30, !fired.contains("left\(m)") {
                fired.insert("left\(m)")
                fire(key: "left\(m)", title: "\(module.title)剩余 \(m) 分钟", message: m <= 1 ? "请尽快完成并检查答案。" : "注意把握时间。", urgent: m <= 5)
            }
        }
        let elapsed = allotted - remaining
        if module == .reading, stage.section == nil, settings.readingPassageNudge, allotted >= 50 * 60 {
            for (k, at) in [(1, 20.0), (2, 40.0)] where elapsed >= at * 60 && !fired.contains("passage\(k)") {
                fired.insert("passage\(k)")
                if currentSection < k {
                    fire(key: "passage\(k)", title: "已用时 \(Int(at)) 分钟", message: "建议进入 Passage \(k + 1)（每篇约 20 分钟）。", urgent: false)
                }
            }
        }
        if module == .writing, stage.section == nil, settings.writingTaskNudge, allotted >= 50 * 60, elapsed >= 20 * 60, !fired.contains("task2") {
            fired.insert("task2")
            if currentSection == 0 {
                fire(key: "task2", title: "已用时 20 分钟", message: "建议开始写 Task 2（Task 2 分值是 Task 1 的两倍，约需 40 分钟）。", urgent: false)
            }
        }
    }

    private func timeUp() {
        deadline = nil
        remaining = 0
        if module == .listening { audio.stop() }
        fire(key: "timeup", title: "时间到", message: settings.autoSubmit || isStrict ? "本部分已自动交卷。" : "时间已到，可以继续作答或交卷。", urgent: true)
        if settings.autoSubmit || isStrict {
            submitStage()
        }
    }

    func fire(key: String, title: String, message: String, urgent: Bool) {
        let b = ReminderBanner(title: title, message: message, urgent: urgent)
        banner = b
        if settings.reminderSound { NSSound(named: urgent ? "Sosumi" : "Glass")?.play() }
        if settings.reminderNotification, !NSApp.isActive { postNotification(title: title, body: message) }
        Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if self.banner?.id == b.id { self.banner = nil }
        }
    }

    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    private func requestNotificationPermission() {
        guard notificationsAvailable, settings.reminderNotification else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        guard notificationsAvailable else { return }
        let c = UNMutableNotificationContent()
        c.title = "雅思模考 · \(title)"
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: answers

    func key(_ n: Int, _ m: Module? = nil) -> String { Grader.key(m ?? module, n) }

    func answer(_ n: Int, module m: Module? = nil) -> String { attempt.answers[key(n, m)] ?? "" }

    func setAnswer(_ n: Int, _ value: String, module m: Module? = nil) {
        guard !finished else { return }
        let k = key(n, m)
        if value.isEmpty { attempt.answers.removeValue(forKey: k) } else { attempt.answers[k] = value }
        markDirty()
    }

    func isAnswered(_ n: Int) -> Bool { !answer(n).trimmingCharacters(in: .whitespaces).isEmpty }

    func isFlagged(_ n: Int) -> Bool { attempt.flagged.contains(key(n)) }
    func toggleFlag(_ n: Int) {
        let k = key(n)
        if attempt.flagged.contains(k) { attempt.flagged.remove(k) } else { attempt.flagged.insert(k) }
        markDirty()
    }

    /// Letters currently chosen in a multi-select group.
    func multiSelection(_ g: QuestionGroup) -> [String] {
        g.numbers.map { answer($0) }.filter { !$0.isEmpty }
    }

    func toggleMulti(_ g: QuestionGroup, _ letter: String) {
        var sel = multiSelection(g)
        if let i = sel.firstIndex(of: letter) {
            sel.remove(at: i)
        } else {
            if sel.count >= g.numbers.count { sel.removeFirst() }
            sel.append(letter)
        }
        sel.sort()
        for (i, n) in g.numbers.enumerated() { setAnswer(n, i < sel.count ? sel[i] : "") }
    }

    func essay(_ task: Int) -> String { attempt.essays[task] ?? "" }
    func setEssay(_ task: Int, _ text: String) {
        guard !finished else { return }
        attempt.essays[task] = text
        markDirty()
    }

    func highlights(passage: Int, paragraph: Int) -> [Highlight] {
        attempt.highlights.filter { $0.passage == passage && $0.paragraph == paragraph }
    }
    func addHighlight(passage: Int, paragraph: Int, range: NSRange) {
        guard range.length > 0 else { return }
        attempt.highlights.removeAll { $0.passage == passage && $0.paragraph == paragraph && NSIntersectionRange(NSRange(location: $0.location, length: $0.length), range).length > 0 }
        attempt.highlights.append(Highlight(passage: passage, paragraph: paragraph, location: range.location, length: range.length))
        markDirty()
    }
    func clearHighlights(passage: Int, paragraph: Int, range: NSRange?) {
        attempt.highlights.removeAll { h in
            guard h.passage == passage, h.paragraph == paragraph else { return false }
            guard let r = range else { return true }
            return NSIntersectionRange(NSRange(location: h.location, length: h.length), r).length > 0 || r.length == 0 && NSLocationInRange(r.location, NSRange(location: h.location, length: h.length))
        }
        markDirty()
    }

    var answeredCount: Int { questionNumbers.filter { isAnswered($0) }.count }

    private func markDirty() { dirty = true }

    // MARK: navigation

    func go(to n: Int) {
        focusedQuestion = n
        currentSection = exam.section(of: n, in: module)
    }

    func next() {
        let nums = questionNumbers
        guard let f = focusedQuestion, let i = nums.firstIndex(of: f) else { if let first = nums.first { go(to: first) }; return }
        if i + 1 < nums.count { go(to: nums[i + 1]) }
    }

    func previous() {
        let nums = questionNumbers
        guard let f = focusedQuestion, let i = nums.firstIndex(of: f), i > 0 else { return }
        go(to: nums[i - 1])
    }

    // MARK: submit

    func submitStage() {
        guard !finished else { return }
        confirmSubmit = false
        if module == .listening { audio.stop() }
        let used = min(allotted, max(0, allotted - remaining))
        attempt.timing[module] = ModuleTiming(allotted: allotted, used: allotted > 0 ? used : Date().timeIntervalSince(stageStarted))
        if module != .writing {
            let limit = stage.section != nil ? Set(questionNumbers) : nil
            let res = Grader.grade(exam: exam, module: module, answers: attempt.answers, limit: limit)
            attempt.results.removeAll { $0.module == module }
            attempt.results += res
            let correct = res.filter(\.isCorrect).count
            let band = limit == nil ? Grader.band(module: module, raw: correct) : nil
            attempt.scores[module] = ModuleScore(module: module, correct: correct, total: res.count, band: band)
        }
        attempt.remaining[module] = nil
        if isLastStage {
            finish()
        } else {
            stageIndex += 1
            deadline = nil
            startStage(resuming: false)
        }
    }

    private func finish() {
        finished = true
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        audio.stop()
        attempt.status = .submitted
        attempt.finishedAt = Date()
        save(force: true)
    }

    /// Leaves the exam; an unfinished attempt stays resumable unless discarded.
    func leave(discard: Bool) {
        guard !isReview else { audio.stop(); return }
        ticker?.invalidate()
        ticker = nil
        audio.stop()
        if discard {
            history.delete(attempt)
        } else if !finished {
            attempt.remaining[module] = remaining
            save(force: true)
        }
    }

    func save(force: Bool = false) {
        guard !isReview else { return }
        if !finished, module != .listening || deadline != nil { attempt.remaining[module] = remaining }
        history.save(attempt)
        dirty = false
        lastSave = Date()
    }

    // MARK: display helpers

    var timeText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var timeState: TimeState {
        if module == .listening, case .ready = listeningPhase { return .idle }
        if remaining <= 60 { return .critical }
        if remaining <= 300 { return .warning }
        if remaining <= 600 { return .caution }
        return .normal
    }

    enum TimeState { case idle, normal, caution, warning, critical }

    /// Header text while the listening recording plays (the recording itself is the clock).
    var listeningStatus: String {
        switch listeningPhase {
        case .playing(let i): return "Part \(exam.listening?.parts[safe: i]?.part ?? i + 1) · recording playing"
        case .review: return "Check your answers"
        case .ready, .done: return ""
        }
    }
}
