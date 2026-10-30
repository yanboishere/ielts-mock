import Foundation
import PDFKit
import AppKit

// usage: pdfrender <pdf> <outdir> <scale> <pages: e.g. 1-5,10,12 (1-based) or all> [jpg]
let a = CommandLine.arguments
guard a.count >= 5 else { print("usage: pdfrender pdf outdir scale pages [jpg]"); exit(1) }
let doc = PDFDocument(url: URL(fileURLWithPath: a[1]))!
let out = URL(fileURLWithPath: a[2])
let scale = CGFloat(Double(a[3]) ?? 1.5)
let asJPG = a.count > 5 && a[5] == "jpg"
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var pages: [Int] = []
if a[4] == "all" { pages = Array(1...doc.pageCount) } else {
    for part in a[4].split(separator: ",") {
        let r = part.split(separator: "-").compactMap { Int($0) }
        if r.count == 2 { pages += Array(r[0]...r[1]) } else if r.count == 1 { pages.append(r[0]) }
    }
}
for p in pages where p >= 1 && p <= doc.pageCount {
    autoreleasepool {
        let page = doc.page(at: p - 1)!
        guard let cg = page.pageRef else { return }
        let box = cg.getBoxRect(.mediaBox)
        let rot = ((Int(cg.rotationAngle) % 360) + 360) % 360
        let (bw, bh) = (rot == 90 || rot == 270) ? (box.height, box.width) : (box.width, box.height)
        let w = Int(bw * scale), h = Int(bh * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(w) / bw, y: CGFloat(h) / bh)
        ctx.concatenate(cg.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: bw, height: bh), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(cg)
        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        let data = asJPG ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])! : rep.representation(using: .png, properties: [:])!
        try! data.write(to: out.appendingPathComponent(String(format: asJPG ? "p%04d.jpg" : "p%04d.png", p)))
    }
}
print("rendered \(pages.count)")
