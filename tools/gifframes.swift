import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: gifframes <gif> <outdir> <step>"); exit(1) }
let url = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let step = Int(args[3]) ?? 10
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { print("bad gif"); exit(1) }
let n = CGImageSourceGetCount(src)
print("frames: \(n)")
var i = 0
while i < n {
    if let img = CGImageSourceCreateImageAtIndex(src, i, nil) {
        let out = outDir.appendingPathComponent(String(format: "f%04d.png", i))
        if let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
    }
    i += step
}
