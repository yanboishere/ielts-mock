import Foundation
import PDFKit
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let n = Int(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "3")!
for i in 0..<doc.pageCount {
    let s = (doc.page(at: i)?.string ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    print("p\(i+1): " + s.prefix(n).joined(separator: " | ").prefix(160))
}
