import Foundation

/// Result for a single question after grading.
struct QuestionResult: Codable, Hashable, Identifiable {
    var module: Module
    var number: Int
    var section: Int          // part / passage index (0-based)
    var groupId: String
    var type: GroupType
    var user: String          // user's answer ("" when blank)
    var accepted: [String]
    var keyDisplay: String
    var isCorrect: Bool
    var nearMiss: Bool        // wrong, but only by hyphen / case / plural / one-letter spelling

    var id: String { "\(module.keyPrefix)\(number)" }
    var isBlank: Bool { user.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct ModuleScore: Codable, Hashable {
    var module: Module
    var correct: Int
    var total: Int
    var band: Double?
}

enum Grader {
    // MARK: normalization

    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        let map: [String: String] = ["’": "'", "‘": "'", "“": "\"", "”": "\"", "–": "-", "—": "-", "‐": "-", "‑": "-", "\u{00A0}": " "]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        // currency / unit symbols the question already prints next to the gap
        for sym in ["£", "$", "€", "¥"] { t = t.replacingOccurrences(of: sym, with: "") }
        // 1,500 -> 1500 ; 9:30 -> 9.30
        t = t.replacingOccurrences(of: #"(?<=\d),(?=\d{3}\b)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\d):(?=\d)"#, with: ".", options: .regularExpression)
        // spaces around hyphens and slashes
        t = t.replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"'()[]").union(.whitespacesAndNewlines))
        return t
    }

    static func loose(_ s: String) -> String {
        var t = normalize(s)
        t = t.replacingOccurrences(of: "-", with: "")
        t = t.replacingOccurrences(of: " ", with: "")
        return t
    }

    static func matches(_ user: String, _ accepted: [String]) -> Bool {
        let u = normalize(user)
        guard !u.isEmpty else { return false }
        return accepted.contains { normalize($0) == u }
    }

    static func nearMiss(_ user: String, _ accepted: [String]) -> Bool {
        let u = loose(user)
        guard u.count >= 3 else { return false }
        for a in accepted {
            let k = loose(a)
            if k == u { return true }
            if k + "s" == u || u + "s" == k || k + "es" == u || u + "es" == k { return true }
            if k.count >= 5, levenshtein(k, u) == 1 { return true }
        }
        return false
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    static func key(_ module: Module, _ n: Int) -> String { "\(module.keyPrefix)\(n)" }

    // MARK: grading

    /// Grades one module of an exam. `answers` is keyed like "L12" / "R5". `limit` restricts grading
    /// to a subset of question numbers (practice of a single part / passage).
    static func grade(exam: Exam, module: Module, answers: [String: String], limit: Set<Int>? = nil) -> [QuestionResult] {
        let keys = exam.answers(for: module)
        var results: [Int: QuestionResult] = [:]
        for (section, g) in exam.groups(for: module) {
            let nums = g.numbers.filter { limit?.contains($0) ?? true }
            guard !nums.isEmpty else { continue }
            if g.type == .multi {
                // letters are marked in either order: each chosen letter that is in the key set scores once
                let correctSet = Set(g.numbers.flatMap { keys[String($0)]?.a ?? [] }.map { $0.uppercased() })
                var used = Set<String>()
                for n in g.numbers.sorted() where nums.contains(n) {
                    let u = (answers[key(module, n)] ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                    let ok = !u.isEmpty && correctSet.contains(u) && !used.contains(u)
                    if ok { used.insert(u) }
                    results[n] = QuestionResult(module: module, number: n, section: section, groupId: g.id, type: g.type,
                                                user: u, accepted: keys[String(n)]?.a ?? [], keyDisplay: keys[String(n)]?.display ?? "?",
                                                isCorrect: ok, nearMiss: false)
                }
                // show the full key set on each line of the group
                let disp = g.numbers.compactMap { keys[String($0)]?.a.first }.joined(separator: ", ") + "（顺序不限）"
                for n in g.numbers where results[n] != nil { results[n]?.keyDisplay = disp }
                continue
            }
            for n in nums {
                let k = keys[String(n)]
                let user = answers[key(module, n)] ?? ""
                let accepted = k?.a ?? []
                var ok: Bool
                switch g.type {
                case .choice, .tfng, .ynng, .matching:
                    ok = accepted.contains { $0.caseInsensitiveCompare(user.trimmingCharacters(in: .whitespaces)) == .orderedSame }
                case .completion:
                    if g.options != nil {
                        ok = accepted.contains { $0.caseInsensitiveCompare(user.trimmingCharacters(in: .whitespaces)) == .orderedSame }
                    } else {
                        ok = matches(user, accepted)
                    }
                case .multi:
                    ok = false
                }
                let near = !ok && g.type == .completion && g.options == nil && nearMiss(user, accepted)
                results[n] = QuestionResult(module: module, number: n, section: section, groupId: g.id, type: g.type, user: user,
                                            accepted: accepted, keyDisplay: k?.display ?? "?", isCorrect: ok, nearMiss: near)
            }
        }
        // "in either order" word gaps
        for pair in exam.eitherOrder(for: module) where pair.allSatisfy({ results[$0] != nil }) {
            let acc = pair.map { keys[String($0)]?.a ?? [] }
            let users = pair.map { answers[key(module, $0)] ?? "" }
            // best assignment of users to keys (pairs are small – try permutations)
            var best = [Bool](repeating: false, count: pair.count)
            var bestScore = -1
            for perm in permutations(Array(0..<pair.count)) {
                var flags = [Bool]()
                for (i, j) in perm.enumerated() { flags.append(matches(users[i], acc[j])) }
                let s = flags.filter { $0 }.count
                if s > bestScore { bestScore = s; best = flags }
            }
            let disp = pair.compactMap { keys[String($0)]?.display }.joined(separator: ", ") + "（顺序不限）"
            for (i, n) in pair.enumerated() {
                results[n]?.isCorrect = best[i]
                results[n]?.keyDisplay = disp
                results[n]?.accepted = acc.flatMap { $0 }
                if best[i] { results[n]?.nearMiss = false }
            }
        }
        return results.keys.sorted().compactMap { results[$0] }
    }

    static func permutations(_ a: [Int]) -> [[Int]] {
        if a.count <= 1 { return [a] }
        var out: [[Int]] = []
        for (i, x) in a.enumerated() {
            var rest = a
            rest.remove(at: i)
            for p in permutations(rest) { out.append([x] + p) }
        }
        return out
    }

    // MARK: bands

    /// Raw score (out of 40) to band. Tables commonly published by IELTS / Cambridge.
    static func band(module: Module, raw: Int) -> Double? {
        let table: [(Int, Double)]
        switch module {
        case .listening:
            table = [(39, 9), (37, 8.5), (35, 8), (32, 7.5), (30, 7), (26, 6.5), (23, 6), (18, 5.5), (16, 5), (13, 4.5), (10, 4), (8, 3.5), (6, 3), (4, 2.5), (2, 2), (1, 1)]
        case .reading:
            table = [(39, 9), (37, 8.5), (35, 8), (33, 7.5), (30, 7), (27, 6.5), (23, 6), (19, 5.5), (15, 5), (13, 4.5), (10, 4), (8, 3.5), (6, 3), (4, 2.5), (2, 2), (1, 1)]
        case .writing:
            return nil
        }
        for (min, b) in table where raw >= min { return b }
        return 0
    }

    /// Overall band: mean rounded to the nearest half band (.25 rounds up to .5, .75 up to the next whole band).
    static func overall(_ bands: [Double]) -> Double? {
        guard !bands.isEmpty else { return nil }
        let mean = bands.reduce(0, +) / Double(bands.count)
        let whole = floor(mean)
        let f = mean - whole
        if f < 0.25 { return whole }
        if f < 0.75 { return whole + 0.5 }
        return whole + 1
    }

    static func bandString(_ b: Double?) -> String {
        guard let b else { return "–" }
        return b == floor(b) ? String(format: "%.1f", b) : String(format: "%.1f", b)
    }
}
