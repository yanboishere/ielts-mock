import Foundation

// Mirrors the `ielts-mock.exam/1` JSON schema produced by the bank builder (see ~/ielts-data/SCHEMA.md).

enum Module: String, Codable, CaseIterable, Identifiable, Hashable {
    case listening, reading, writing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: return "听力"
        case .reading: return "阅读"
        case .writing: return "写作"
        }
    }

    var englishTitle: String {
        switch self {
        case .listening: return "Listening"
        case .reading: return "Reading"
        case .writing: return "Writing"
        }
    }

    var symbol: String {
        switch self {
        case .listening: return "headphones"
        case .reading: return "book"
        case .writing: return "pencil.and.outline"
        }
    }

    /// Prefix used in answer keys ("L12", "R5").
    var keyPrefix: String {
        switch self {
        case .listening: return "L"
        case .reading: return "R"
        case .writing: return "W"
        }
    }
}

struct Exam: Codable, Identifiable, Hashable {
    var schema: String
    var id: String
    var source: ExamSource
    var title: String
    var issues: [String]?
    var listening: ListeningModule?
    var reading: ReadingModule?
    var writing: WritingModule?

    static func == (a: Exam, b: Exam) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var modules: [Module] {
        var m: [Module] = []
        if listening != nil { m.append(.listening) }
        if reading != nil { m.append(.reading) }
        if writing != nil { m.append(.writing) }
        return m
    }

    var shortTitle: String {
        if source.book > 0 { return "剑\(source.book) Test \(source.test)" }
        return title
    }

    func answers(for module: Module) -> [String: AnswerKey] {
        switch module {
        case .listening: return listening?.answers ?? [:]
        case .reading: return reading?.answers ?? [:]
        case .writing: return [:]
        }
    }

    func eitherOrder(for module: Module) -> [[Int]] {
        switch module {
        case .listening: return listening?.eitherOrder ?? []
        case .reading: return reading?.eitherOrder ?? []
        case .writing: return []
        }
    }

    /// All question groups of a module in order, with the index of their part/passage.
    func groups(for module: Module) -> [(section: Int, group: QuestionGroup)] {
        switch module {
        case .listening:
            return (listening?.parts ?? []).enumerated().flatMap { i, p in p.groups.map { (i, $0) } }
        case .reading:
            return (reading?.passages ?? []).enumerated().flatMap { i, p in p.groups.map { (i, $0) } }
        case .writing:
            return []
        }
    }

    func group(containing number: Int, in module: Module) -> (section: Int, group: QuestionGroup)? {
        groups(for: module).first { $0.group.covers(number) }
    }

    /// Section index (part / passage) that contains a question number.
    func section(of number: Int, in module: Module) -> Int {
        switch module {
        case .listening:
            return (listening?.parts ?? []).firstIndex { $0.range.count == 2 && number >= $0.range[0] && number <= $0.range[1] } ?? 0
        case .reading:
            return (reading?.passages ?? []).firstIndex { $0.range.count == 2 && number >= $0.range[0] && number <= $0.range[1] } ?? 0
        case .writing:
            return 0
        }
    }
}

struct ExamSource: Codable, Hashable {
    var book: Int
    var test: Int
}

struct AnswerKey: Codable, Hashable {
    /// Accepted answers (already expanded from the printed key notation).
    var a: [String]
    /// The key as printed in the book (e.g. "grass(es)"), when it differs.
    var k: String?

    var display: String { k ?? a.joined(separator: " / ") }
}

struct ListeningModule: Codable, Hashable {
    var parts: [ListeningPart]
    var answers: [String: AnswerKey]
    var eitherOrder: [[Int]]?
}

struct ListeningPart: Codable, Hashable, Identifiable {
    var part: Int
    var range: [Int]
    var pages: [Int]?
    var context: String?
    var groups: [QuestionGroup]
    var transcript: String?
    /// Relative path of the audio file inside the bank (filled in by the bank builder).
    var audio: String?

    var id: Int { part }
    var first: Int { range.first ?? 1 }
    var last: Int { range.last ?? 10 }
}

struct ReadingModule: Codable, Hashable {
    var passages: [Passage]
    var answers: [String: AnswerKey]
    var eitherOrder: [[Int]]?
}

struct Passage: Codable, Hashable, Identifiable {
    var passage: Int
    var range: [Int]
    var pages: [Int]?
    var intro: String?
    var title: String
    var subtitle: String?
    var paragraphs: [Paragraph]
    var groups: [QuestionGroup]

    var id: Int { passage }
    var first: Int { range.first ?? 1 }
    var last: Int { range.last ?? 13 }

    var plainText: String {
        var lines: [String] = [title]
        if let s = subtitle, !s.isEmpty { lines.append(s) }
        for p in paragraphs where p.kind != "img" {
            if let l = p.label { lines.append("\(l) \(p.text)") } else { lines.append(p.text) }
        }
        return lines.map { InlineMarkup.strip($0) }.joined(separator: "\n\n")
    }
}

struct Paragraph: Codable, Hashable {
    var label: String?
    var kind: String?
    var text: String
    var src: String?

    var isHeading: Bool { kind == "heading" }
    var isNote: Bool { kind == "note" }
    var isImage: Bool { kind == "img" }
}

struct WritingModule: Codable, Hashable {
    var tasks: [WritingTask]
}

struct WritingTask: Codable, Hashable, Identifiable {
    var task: Int
    var minutes: Int
    var minWords: Int
    var pages: [Int]?
    var prompt: [String]
    var image: String?
    var sample: WritingSample?

    var id: Int { task }
    var promptText: String { prompt.map { InlineMarkup.strip($0) }.joined(separator: "\n") }
}

struct WritingSample: Codable, Hashable {
    var kind: String?
    var band: String?
    var text: String
    var comment: String?
}

enum GroupType: String, Codable, Hashable {
    case completion, choice, multi, tfng, ynng, matching

    var label: String {
        switch self {
        case .completion: return "填空"
        case .choice: return "单选"
        case .multi: return "多选"
        case .tfng: return "判断 (T/F/NG)"
        case .ynng: return "判断 (Y/N/NG)"
        case .matching: return "匹配"
        }
    }
}

struct Option: Codable, Hashable, Identifiable {
    var key: String
    var text: String
    var id: String { key }
}

struct Question: Codable, Hashable, Identifiable {
    var n: Int
    var text: String
    var options: [Option]?
    var id: Int { n }
}

struct Block: Codable, Hashable {
    var t: String
    var text: String?
    var level: Int?
    var rows: [[String]]?
    var header: Int?
    var steps: [String]?
    var src: String?
}

struct QuestionGroup: Codable, Hashable, Identifiable {
    var id: String
    var type: GroupType
    var range: [Int]
    var instructions: [String]
    var title: String?
    var image: String?
    var content: [Block]?
    var options: [Option]?
    var optionsTitle: String?
    var reuse: Bool?
    /// Letters may be used more than once: printed "NB" line, or fewer options than questions (classification).
    var allowsReuse: Bool { reuse ?? ((options?.count ?? 0) > 0 && (options?.count ?? 0) < numbers.count) }
    var questions: [Question]?
    var n: [Int]?
    var select: Int?
    var text: String?

    var first: Int { range.first ?? 0 }
    var last: Int { range.last ?? 0 }
    var numbers: [Int] { first <= last ? Array(first...last) : [] }
    func covers(_ number: Int) -> Bool { number >= first && number <= last }

    var heading: String {
        first == last ? "Question \(first)" : (type == .multi && numbers.count == 2 ? "Questions \(first) and \(last)" : "Questions \(first)–\(last)")
    }

    /// For TFNG / YNNG groups the implicit option set.
    var judgementOptions: [String] {
        switch type {
        case .tfng: return ["TRUE", "FALSE", "NOT GIVEN"]
        case .ynng: return ["YES", "NO", "NOT GIVEN"]
        default: return []
        }
    }

    /// Text describing a single question, used for review lists and AI prompts.
    func questionText(_ number: Int) -> String {
        switch type {
        case .choice, .tfng, .ynng, .matching:
            return InlineMarkup.strip(questions?.first { $0.n == number }?.text ?? "")
        case .multi:
            return InlineMarkup.strip(text ?? "")
        case .completion:
            return InlineMarkup.strip(gapContext(number) ?? "")
        }
    }

    /// The line of completion content that contains a gap, with the gap shown as "____".
    func gapContext(_ number: Int) -> String? {
        let marker = "{{\(number)}}"
        for b in content ?? [] {
            if let t = b.text, t.contains(marker) { return Self.blankGaps(t, highlight: number) }
            for row in b.rows ?? [] {
                if let cell = row.first(where: { $0.contains(marker) }) {
                    let rowText = row.filter { !$0.isEmpty }.joined(separator: " | ")
                    return Self.blankGaps(rowText.isEmpty ? cell : rowText, highlight: number)
                }
            }
            if let s = b.steps?.first(where: { $0.contains(marker) }) { return Self.blankGaps(s, highlight: number) }
        }
        return nil
    }

    static func blankGaps(_ s: String, highlight: Int?) -> String {
        let re = try! NSRegularExpression(pattern: #"\{\{(\d+)\}\}"#)
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let n = ns.substring(with: m.range(at: 1))
            out += (Int(n) == highlight) ? "[\(n) ____]" : "(\(n))"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out.replacingOccurrences(of: "\n", with: " ")
    }

    /// Options shown for a question (choice has per-question options).
    func options(for number: Int) -> [Option] {
        if type == .choice { return questions?.first { $0.n == number }?.options ?? [] }
        if type == .tfng || type == .ynng { return judgementOptions.map { Option(key: $0, text: "") } }
        return options ?? []
    }
}

extension Array where Element == Int {
    var rangeLabel: String {
        guard let f = first, let l = last else { return "" }
        return f == l ? "\(f)" : "\(f)–\(l)"
    }
}

extension Module: CodingKeyRepresentable {}
