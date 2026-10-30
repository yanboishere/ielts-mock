import Foundation
import SwiftUI

enum Route: Hashable {
    case home
    case library
    case history
    case mistakes
    case writingLog
    case custom
}

enum DetailPage: Hashable {
    case book(Int)
    case test(String)
    case attempt(UUID)
}

@MainActor
final class AppState: ObservableObject {
    let settings: SettingsStore
    let bank: BankStore
    let history: HistoryStore
    let ai: AIService

    @Published var session: ExamSession?
    @Published var route: Route = .home
    @Published var path: [DetailPage] = []
    @Published var alert: String?

    init() {
        let s = SettingsStore()
        settings = s
        bank = BankStore()
        history = HistoryStore()
        ai = AIService(settings: s)
        bank.reload()
    }

    func open(_ page: DetailPage) { path.append(page) }

    func navigate(_ r: Route) {
        route = r
        path = []
    }

    /// Switches the sidebar route and then pushes a page. The push waits a tick: changing the route rebuilds the
    /// detail NavigationStack, which would otherwise drop a path set in the same update.
    func navigate(_ r: Route, open page: DetailPage) {
        let sameRoute = route == r
        navigate(r)
        if sameRoute { path = [page]; return }
        DispatchQueue.main.async { self.path = [page] }
    }

    func start(_ ref: ExamRef, mode: AttemptMode, stages: [Stage]) {
        if let old = history.resumable, old.examId == ref.exam.id { history.delete(old) }
        let s = ExamSession(ref: ref, mode: mode, stages: stages, settings: settings, history: history)
        session = s
        s.begin()
    }

    func startFullMock(_ ref: ExamRef) {
        start(ref, mode: .fullMock, stages: ref.exam.modules.map { Stage(module: $0, section: nil) })
    }

    func startModule(_ ref: ExamRef, _ m: Module) {
        start(ref, mode: .moduleMock, stages: [Stage(module: m, section: nil)])
    }

    func startPractice(_ ref: ExamRef, _ m: Module, section: Int) {
        start(ref, mode: .practice, stages: [Stage(module: m, section: section)])
    }

    func resume(_ a: Attempt) {
        guard let ref = bank.ref(a.examId) else {
            alert = "找不到这套题（\(a.examId)），可能题库已被移除。"
            return
        }
        let stages = a.scopes.map { Stage(module: $0.module, section: $0.section) }
        let s = ExamSession(ref: ref, mode: a.mode, stages: stages, settings: settings, history: history, resume: a)
        session = s
        s.begin()
    }

    /// Called when the exam view closes.
    func endSession(discard: Bool = false, showResult: Bool = true) {
        guard let s = session else { return }
        s.leave(discard: discard)
        let finished = s.finished
        let id = s.attempt.id
        session = nil
        if finished && showResult {
            navigate(.history, open: .attempt(id))
        }
    }
}
