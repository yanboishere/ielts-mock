import Foundation
import PDFKit

for path in CommandLine.arguments.dropFirst() {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { print("FAIL \(path)"); continue }
    let n = doc.pageCount
    var textPages = 0
    var totalChars = 0
    for i in 0..<n {
        let s = doc.page(at: i)?.string ?? ""
        let c = s.trimmingCharacters(in: .whitespacesAndNewlines).count
        if c > 50 { textPages += 1 }
        totalChars += c
    }
    let p0 = doc.page(at: min(10, n-1))!
    let b = p0.bounds(for: .mediaBox)
    print("\((path as NSString).lastPathComponent)\tpages=\(n)\ttextPages=\(textPages)\tchars=\(totalChars)\tsize=\(Int(b.width))x\(Int(b.height))")
}
