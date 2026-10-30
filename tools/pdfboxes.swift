import Foundation
import PDFKit
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let pages = CommandLine.arguments.dropFirst(2).compactMap { Int($0) }
for p in pages {
    let page = doc.page(at: p-1)!
    print("p\(p) rot=\(page.rotation) media=\(page.bounds(for: .mediaBox)) crop=\(page.bounds(for: .cropBox)) bleed=\(page.bounds(for: .bleedBox)) art=\(page.bounds(for: .artBox))")
    if let ref = page.pageRef, let dict = ref.dictionary {
        var res: CGPDFDictionaryRef? = nil
        if CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res = res {
            var xo: CGPDFDictionaryRef? = nil
            if CGPDFDictionaryGetDictionary(res, "XObject", &xo), let xo = xo {
                CGPDFDictionaryApplyBlock(xo, { key, obj, _ in
                    var stream: CGPDFStreamRef? = nil
                    if CGPDFObjectGetValue(obj, .stream, &stream), let s = stream, let sd = CGPDFStreamGetDictionary(s) {
                        var w: CGPDFInteger = 0, h: CGPDFInteger = 0
                        CGPDFDictionaryGetInteger(sd, "Width", &w); CGPDFDictionaryGetInteger(sd, "Height", &h)
                        var name: UnsafePointer<CChar>? = nil
                        CGPDFDictionaryGetName(sd, "Subtype", &name)
                        var filt: UnsafePointer<CChar>? = nil
                        CGPDFDictionaryGetName(sd, "Filter", &filt)
                        print("   xobj \(String(cString: key)) \(name.map{String(cString:$0)} ?? "?") \(w)x\(h) filter=\(filt.map{String(cString:$0)} ?? "-")")
                    }
                    return true
                }, nil)
            }
        }
    }
}
