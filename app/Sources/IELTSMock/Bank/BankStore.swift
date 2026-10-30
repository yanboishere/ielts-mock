import Foundation
import SwiftUI

/// Where app data lives: ~/Library/Application Support/IELTSMock
enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("IELTSMock", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    /// The bank shipped inside the app bundle (Contents/Resources/Bank) when present, else the one in Application Support.
    static var defaultBank: URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Bank", isDirectory: true),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("exams").path) {
            return r
        }
        return support.appendingPathComponent("Bank", isDirectory: true)
    }
    static var customBank: URL {
        let u = support.appendingPathComponent("CustomBank", isDirectory: true)
        try? FileManager.default.createDirectory(at: u.appendingPathComponent("exams"), withIntermediateDirectories: true)
        return u
    }
    static var attempts: URL {
        let u = support.appendingPathComponent("Attempts", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var audioOverrides: URL {
        let u = support.appendingPathComponent("AudioOverrides", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

/// An exam plus the bank root its relative paths resolve against.
struct ExamRef: Identifiable, Hashable {
    var exam: Exam
    var root: URL
    var isCustom: Bool
    var id: String { exam.id }

    func url(_ relative: String?) -> URL? {
        guard let r = relative, !r.isEmpty else { return nil }
        if r.hasPrefix("/") { return URL(fileURLWithPath: r) }
        return root.appendingPathComponent(r)
    }

    /// Audio for a listening part: user override first, then the bank file.
    func audioURL(part: Int) -> URL? {
        let override = AppPaths.audioOverrides.appendingPathComponent("\(exam.id)-P\(part + 1)")
        for ext in ["mp3", "m4a", "wav", "aac"] {
            let u = override.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        guard let parts = exam.listening?.parts, part < parts.count, let u = url(parts[part].audio) else { return nil }
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func pageURL(_ page: Int) -> URL? {
        let u = root.appendingPathComponent("pages/C\(exam.source.book)/p\(String(format: "%04d", page)).jpg")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    var missingAudioParts: [Int] {
        guard let parts = exam.listening?.parts else { return [] }
        return parts.indices.filter { audioURL(part: $0) == nil }
    }
}

@MainActor
final class BankStore: ObservableObject {
    @Published private(set) var refs: [ExamRef] = []
    @Published private(set) var loading = false
    @Published var lastError: String?

    @AppStorage("bankPath") var bankPath: String = ""

    var bankRoot: URL { bankPath.isEmpty ? AppPaths.defaultBank : URL(fileURLWithPath: bankPath) }

    var books: [Int] { Array(Set(refs.filter { !$0.isCustom }.map(\.exam.source.book))).sorted() }

    func refs(book: Int) -> [ExamRef] {
        refs.filter { $0.exam.source.book == book && !$0.isCustom }.sorted { $0.exam.source.test < $1.exam.source.test }
    }

    var customRefs: [ExamRef] { refs.filter(\.isCustom) }

    func ref(_ id: String) -> ExamRef? { refs.first { $0.id == id } }

    func reload() {
        loading = true
        let roots: [(URL, Bool)] = [(bankRoot, false), (AppPaths.customBank, true)]
        Task.detached(priority: .userInitiated) {
            var out: [ExamRef] = []
            var errors: [String] = []
            let dec = JSONDecoder()
            for (root, custom) in roots {
                let dir = root.appendingPathComponent("exams")
                guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for f in files where f.pathExtension == "json" {
                    do {
                        let data = try Data(contentsOf: f)
                        let exam = try dec.decode(Exam.self, from: data)
                        out.append(ExamRef(exam: exam, root: root, isCustom: custom))
                    } catch {
                        errors.append("\(f.lastPathComponent): \(error)")
                    }
                }
            }
            out.sort { ($0.exam.source.book, $0.exam.source.test, $0.exam.id) < ($1.exam.source.book, $1.exam.source.test, $1.exam.id) }
            let loaded = out
            let problems = errors
            await MainActor.run {
                self.refs = loaded
                self.loading = false
                self.lastError = problems.isEmpty ? nil : problems.joined(separator: "\n")
            }
        }
    }

    /// Imports a single exam JSON (same schema) into the custom bank. Images referenced relative to the JSON's
    /// folder are copied along when present.
    func importExam(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let exam = try JSONDecoder().decode(Exam.self, from: data)
        let dest = AppPaths.customBank.appendingPathComponent("exams/\(exam.id).json")
        try? FileManager.default.removeItem(at: dest)
        try data.write(to: dest)
        // copy referenced images / audio if they sit next to the file
        let srcRoot = url.deletingLastPathComponent()
        var rels: [String] = []
        for p in exam.listening?.parts ?? [] {
            if let a = p.audio { rels.append(a) }
            rels += p.groups.compactMap(\.image)
            rels += p.groups.flatMap { $0.content ?? [] }.compactMap(\.src)
        }
        for p in exam.reading?.passages ?? [] {
            rels += p.groups.compactMap(\.image)
            rels += p.groups.flatMap { $0.content ?? [] }.compactMap(\.src)
            rels += p.paragraphs.compactMap(\.src)
        }
        rels += exam.writing?.tasks.compactMap(\.image) ?? []
        for r in rels {
            for base in [srcRoot, srcRoot.deletingLastPathComponent()] {
                let s = base.appendingPathComponent(r)
                if FileManager.default.fileExists(atPath: s.path) {
                    let d = AppPaths.customBank.appendingPathComponent(r)
                    try? FileManager.default.createDirectory(at: d.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: d)
                    try? FileManager.default.copyItem(at: s, to: d)
                    break
                }
            }
        }
        reload()
    }

    func deleteCustom(_ ref: ExamRef) {
        guard ref.isCustom else { return }
        try? FileManager.default.removeItem(at: AppPaths.customBank.appendingPathComponent("exams/\(ref.exam.id).json"))
        reload()
    }

    /// Lets the user attach a local audio file to a listening part (e.g. when the bank has none).
    func setAudioOverride(ref: ExamRef, part: Int, file: URL) throws {
        let base = AppPaths.audioOverrides.appendingPathComponent("\(ref.exam.id)-P\(part + 1)")
        for ext in ["mp3", "m4a", "wav", "aac"] { try? FileManager.default.removeItem(at: base.appendingPathExtension(ext)) }
        let dest = base.appendingPathExtension(file.pathExtension.lowercased())
        try FileManager.default.copyItem(at: file, to: dest)
        objectWillChange.send()
    }
}
