import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var attempts: [Attempt] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() { load() }

    func load() {
        let dir = AppPaths.attempts
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var list: [Attempt] = []
        for f in files where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let a = try? decoder.decode(Attempt.self, from: d) { list.append(a) }
        }
        attempts = list.sorted { $0.startedAt > $1.startedAt }
        // A Speaking test cannot be resumed; one left unfinished by a crash or forced quit is removed.
        for a in attempts where a.status == .inProgress && a.modules.contains(.speaking) { delete(a) }
    }

    func save(_ a: Attempt) {
        if let i = attempts.firstIndex(where: { $0.id == a.id }) { attempts[i] = a } else { attempts.insert(a, at: 0) }
        attempts.sort { $0.startedAt > $1.startedAt }
        let url = AppPaths.attempts.appendingPathComponent("\(a.id.uuidString).json")
        if let data = try? encoder.encode(a) { try? data.write(to: url, options: .atomic) }
    }

    func delete(_ a: Attempt) {
        attempts.removeAll { $0.id == a.id }
        try? FileManager.default.removeItem(at: AppPaths.attempts.appendingPathComponent("\(a.id.uuidString).json"))
        if a.speaking != nil { try? FileManager.default.removeItem(at: AppPaths.recordings(a.id)) }
    }

    func attempt(_ id: UUID) -> Attempt? { attempts.first { $0.id == id } }

    var submitted: [Attempt] { attempts.filter { $0.status == .submitted } }

    /// An unfinished attempt that can be resumed.
    var resumable: Attempt? { attempts.first { $0.status == .inProgress && !$0.modules.contains(.speaking) } }

    func attempts(exam id: String) -> [Attempt] { submitted.filter { $0.examId == id } }

    /// Every wrong answer across submitted attempts, newest first.
    var mistakes: [(attempt: Attempt, result: QuestionResult)] {
        submitted.flatMap { a in a.wrongResults.map { (a, $0) } }
    }

    func exportAll(to url: URL) throws {
        let data = try encoder.encode(attempts)
        try data.write(to: url)
    }

    func importAll(from url: URL) throws -> Int {
        let list = try decoder.decode([Attempt].self, from: Data(contentsOf: url))
        for a in list { save(a) }
        return list.count
    }
}
