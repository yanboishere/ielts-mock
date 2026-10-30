import Foundation
import AppKit
import Vision
// usage: ocrtest <image> <minTextHeight> <correction 0/1> <strips>
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let mth = Float(a[2])!
let corr = a[3] == "1"
let strips = Int(a[4])!
var all: [(Double, Double, String)] = []
for s in 0..<strips {
    let H = img.height, W = img.width
    let sh = H / strips
    let overlap = strips > 1 ? 60 : 0
    let y0 = max(0, s * sh - overlap), y1 = min(H, (s + 1) * sh + overlap)
    let sub = img.cropping(to: CGRect(x: 0, y: y0, width: W, height: y1 - y0))!
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["en-US"]
    req.usesLanguageCorrection = corr
    if mth > 0 { req.minimumTextHeight = mth }
    try! VNImageRequestHandler(cgImage: sub, options: [:]).perform([req])
    for o in req.results ?? [] {
        let b = o.boundingBox
        let yTop = Double(y0) + Double(1 - b.maxY) * Double(y1 - y0)
        all.append((yTop, Double(b.minX), o.topCandidates(1).first!.string))
    }
}
all.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
var last = -100.0
for (y, x, t) in all { print(String(format: "%5.0f %4.2f  %@", y, x, t)) ; last = y }
