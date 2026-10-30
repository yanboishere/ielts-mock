import Foundation
import AppKit

// usage: montage <out.png> <cols> <cellWidth> files...
let a = CommandLine.arguments
let out = a[1]; let cols = Int(a[2])!; let cw = CGFloat(Double(a[3])!)
let files = Array(a.dropFirst(4))
let imgs = files.compactMap { NSImage(contentsOfFile: $0) }
guard !imgs.isEmpty else { exit(1) }
let ratio = imgs[0].size.height / imgs[0].size.width
let ch = cw * ratio + 18
let rows = (imgs.count + cols - 1) / cols
let W = Int(CGFloat(cols) * cw), H = Int(CGFloat(rows) * ch)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.lightGray.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, img) in imgs.enumerated() {
    let r = i / cols, c = i % cols
    let x = CGFloat(c) * cw, y = CGFloat(H) - CGFloat(r + 1) * ch
    let ih = cw * (img.size.height / img.size.width)
    img.draw(in: NSRect(x: x + 2, y: y + 2, width: cw - 4, height: min(ih, ch - 20) - 2))
    let label = ((files[i] as NSString).lastPathComponent as NSString).deletingPathExtension
    (label as NSString).draw(at: NSPoint(x: x + 4, y: y + ch - 16), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.red])
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("\(W)x\(H)")
