import Foundation
import PDFKit
import AppKit
// usage: figcrop <pdf> <page1based> <x> <y> <w> <h> <out> [targetWidthPx] [jpg]
// Renders a normalized region (top-left origin, of the upright page) at high resolution.
let a = CommandLine.arguments
guard a.count >= 8 else { print("usage: figcrop pdf page x y w h out [targetWidth]"); exit(2) }
guard let doc = PDFDocument(url: URL(fileURLWithPath: a[1])) else { print("cannot open pdf"); exit(1) }
let pno = Int(a[2])!
var rx = CGFloat(Double(a[3])!), ry = CGFloat(Double(a[4])!), rw = CGFloat(Double(a[5])!), rh = CGFloat(Double(a[6])!)
rx = max(0, min(1, rx)); ry = max(0, min(1, ry)); rw = max(0.01, min(1 - rx, rw)); rh = max(0.01, min(1 - ry, rh))
let out = a[7]
guard pno >= 1, pno <= doc.pageCount, let cg = doc.page(at: pno - 1)?.pageRef else { print("bad page"); exit(1) }
let box = cg.getBoxRect(.mediaBox)
let rot = ((Int(cg.rotationAngle) % 360) + 360) % 360
let (bw, bh) = (rot == 90 || rot == 270) ? (box.height, box.width) : (box.width, box.height)
// default: render page at ~2000px full width, then the crop keeps that density (min 900px wide output)
var pageW: CGFloat = 2000
if a.count > 8, let t = Double(a[8]) { pageW = CGFloat(t) / rw }
if pageW * rw < 900 { pageW = 900 / rw }
if pageW * rw > 2600 { pageW = 2600 / rw }
let scale = pageW / bw
let W = Int(bw * rw * scale), H = Int(bh * rh * scale)
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: -rx * bw, y: -(bh - (ry + rh) * bh))
ctx.concatenate(cg.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: bw, height: bh), rotate: 0, preserveAspectRatio: true))
ctx.drawPDFPage(cg)
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
let isJPG = out.lowercased().hasSuffix(".jpg") || (a.count > 9 && a[9] == "jpg")
let data = isJPG ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])! : rep.representation(using: .png, properties: [:])!
try! FileManager.default.createDirectory(at: URL(fileURLWithPath: out).deletingLastPathComponent(), withIntermediateDirectories: true)
try! data.write(to: URL(fileURLWithPath: out))
print("\(out) \(W)x\(H) \(data.count / 1024)KB")
