import Foundation
import PDFKit
import AppKit
import Vision
// usage: ocrregion <pdf> <page1based> <x> <y> <w> <h> <targetWidthPx> [save.png]
// region is normalized (top-left origin) of the rotated page.
let a = CommandLine.arguments
let doc = PDFDocument(url: URL(fileURLWithPath: a[1]))!
let pno = Int(a[2])!
let rx = CGFloat(Double(a[3])!), ry = CGFloat(Double(a[4])!), rw = CGFloat(Double(a[5])!), rh = CGFloat(Double(a[6])!)
let targetW = CGFloat(Double(a[7])!)
let cg = doc.page(at: pno - 1)!.pageRef!
let box = cg.getBoxRect(.mediaBox)
let rot = ((Int(cg.rotationAngle) % 360) + 360) % 360
let (bw, bh) = (rot == 90 || rot == 270) ? (box.height, box.width) : (box.width, box.height)
let scale = targetW / (bw * rw)
let W = Int(bw * rw * scale), H = Int(bh * rh * scale)
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high
// move region origin to (0,0): region top-left at (rx*bw, ry*bh) in top-left coords; CG is bottom-left
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: -rx * bw, y: -(bh - (ry + rh) * bh))
ctx.concatenate(cg.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: bw, height: bh), rotate: 0, preserveAspectRatio: true))
ctx.drawPDFPage(cg)
let img = ctx.makeImage()!
if a.count > 8 {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[8]))
}
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.recognitionLanguages = ["en-US"]
req.usesLanguageCorrection = false
try! VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
var res: [(Double, Double, String)] = []
for o in req.results ?? [] {
    let b = o.boundingBox
    res.append((Double(1 - b.maxY), Double(b.minX), o.topCandidates(1).first!.string))
}
res.sort { abs($0.0 - $1.0) < 0.004 ? $0.1 < $1.1 : $0.0 < $1.0 }
for (y, x, t) in res { print(String(format: "%.3f %.3f %@", y, x, t)) }
