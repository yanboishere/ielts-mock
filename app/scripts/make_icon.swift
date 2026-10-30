import AppKit

// Draws the app icon: a red rounded square with "IELTS" and a small clock arc.
func draw(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let r = NSRect(x: size * 0.09, y: size * 0.09, width: size * 0.82, height: size * 0.82)
    let path = NSBezierPath(roundedRect: r, xRadius: size * 0.18, yRadius: size * 0.18)
    let grad = NSGradient(colors: [NSColor(calibratedRed: 0.85, green: 0.13, blue: 0.2, alpha: 1), NSColor(calibratedRed: 0.55, green: 0.04, blue: 0.1, alpha: 1)])!
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    grad.draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    // clock ring
    let ring = NSBezierPath()
    let c = NSPoint(x: size * 0.5, y: size * 0.6)
    ring.appendArc(withCenter: c, radius: size * 0.17, startAngle: 0, endAngle: 360)
    ring.lineWidth = size * 0.035
    NSColor.white.withAlphaComponent(0.95).setStroke()
    ring.stroke()
    let hands = NSBezierPath()
    hands.move(to: c); hands.line(to: NSPoint(x: c.x, y: c.y + size * 0.11))
    hands.move(to: c); hands.line(to: NSPoint(x: c.x + size * 0.08, y: c.y - size * 0.03))
    hands.lineWidth = size * 0.03
    hands.lineCapStyle = .round
    hands.stroke()
    let text = "IELTS" as NSString
    let font = NSFont.systemFont(ofSize: size * 0.17, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .kern: size * 0.006]
    let ts = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (size - ts.width) / 2, y: size * 0.17), withAttributes: attrs)
    img.unlockFocus()
    return img
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128),
                   ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let img = draw(size: CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
