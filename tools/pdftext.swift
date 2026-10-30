import Foundation
import PDFKit
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
for p in CommandLine.arguments.dropFirst(2).compactMap({ Int($0) }) {
    print("===== page \(p)")
    print(doc.page(at: p-1)?.string ?? "")
}
