import Foundation
import PDFKit
import AppKit
import Vision

// usage: pdfocr <pdf> <outdir> <targetWidthPx> <pages|all> [--text-layer]
// writes outdir/pNNNN.jpg (rendered page) and outdir/pNNNN.json (OCR lines with boxes, top-left origin, normalized)
let a = CommandLine.arguments
let doc = PDFDocument(url: URL(fileURLWithPath: a[1]))!
let out = URL(fileURLWithPath: a[2])
let targetW = CGFloat(Double(a[3]) ?? 1400)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var pages: [Int] = []
if a[4] == "all" { pages = Array(1...doc.pageCount) } else {
    for part in a[4].split(separator: ",") {
        let r = part.split(separator: "-").compactMap { Int($0) }
        if r.count == 2 { pages += Array(r[0]...r[1]) } else if r.count == 1 { pages.append(r[0]) }
    }
}
struct Line: Codable { let t: String; let x: Double; let y: Double; let w: Double; let h: Double; let c: Double }
struct PageOut: Codable { let page: Int; let width: Int; let height: Int; let lines: [Line] }

func render(_ cg: CGPDFPage) -> CGImage? {
    let box = cg.getBoxRect(.mediaBox)
    let rot = ((Int(cg.rotationAngle) % 360) + 360) % 360
    let (bw, bh) = (rot == 90 || rot == 270) ? (box.height, box.width) : (box.width, box.height)
    let scale = targetW / bw
    let w = Int(bw * scale), h = Int(bh * scale)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(w) / bw, y: CGFloat(h) / bh)
    ctx.concatenate(cg.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: bw, height: bh), rotate: 0, preserveAspectRatio: true))
    ctx.drawPDFPage(cg)
    return ctx.makeImage()
}

let enc = JSONEncoder()
for p in pages where p >= 1 && p <= doc.pageCount {
    autoreleasepool {
        let jsonURL = out.appendingPathComponent(String(format: "p%04d.json", p))
        if FileManager.default.fileExists(atPath: jsonURL.path) { return }
        guard let cg = doc.page(at: p - 1)?.pageRef, let img = render(cg) else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: out.appendingPathComponent(String(format: "p%04d.jpg", p)))
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["en-US"]
        req.usesLanguageCorrection = true
        req.revision = VNRecognizeTextRequestRevision3
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        do { try handler.perform([req]) } catch { print("ocr fail p\(p): \(error)"); return }
        var lines: [Line] = []
        for obs in req.results ?? [] {
            guard let cand = obs.topCandidates(1).first else { continue }
            let b = obs.boundingBox
            lines.append(Line(t: cand.string, x: Double(b.minX), y: Double(1 - b.maxY), w: Double(b.width), h: Double(b.height), c: Double(cand.confidence)))
        }
        let po = PageOut(page: p, width: img.width, height: img.height, lines: lines)
        try? enc.encode(po).write(to: jsonURL)
    }
}
print("done \(pages.count)")
