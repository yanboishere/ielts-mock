import Foundation
import AppKit

// usage: dewatermark [--check] IMAGE...
// Removes coloured (blue/red) third-party watermark stamps from black-and-white figure crops by turning strongly
// coloured pixels white. --check only reports the share of coloured pixels.
let args = CommandLine.arguments.dropFirst()
let checkOnly = args.contains("--check")
for path in args where path != "--check" {
    guard let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { print("skip \(path)"); continue }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var colored = 0
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 3,
                               hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 3, bitsPerPixel: 24)!
    let dst = out.bitmapData!
    for y in 0..<h {
        for x in 0..<w {
            let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .white
            var r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            let mx = max(r, g, b), mn = min(r, g, b)
            // saturated pixel = stamp ink; greys (chart fills, text) have r≈g≈b
            // also the stamp's anti-aliased fringe: light pixels with a clear blue (or red) cast
            let blueCast = b - r > 0.06 && b - g > 0.02 && mx > 0.45
            let redCast = r - b > 0.10 && r - g > 0.06 && mx > 0.45
            if mx - mn > 0.22 || blueCast || redCast {
                colored += 1
                r = 1; g = 1; b = 1
            }
            let i = (y * w + x) * 3
            dst[i] = UInt8(r * 255); dst[i + 1] = UInt8(g * 255); dst[i + 2] = UInt8(b * 255)
        }
    }
    let share = Double(colored) / Double(w * h) * 100
    if checkOnly { print(String(format: "%6.2f%%  %@", share, path)); continue }
    if colored > 0, let png = out.representation(using: .png, properties: [:]) {
        try! png.write(to: URL(fileURLWithPath: path))
    }
    print(String(format: "cleaned %.2f%%  %@", share, path))
}
