import Foundation
import SwiftUI

/// Minimal inline markup used in the bank: **bold**, *italic*, and {{n}} gaps.
enum InlineMarkup {
    struct Run: Hashable {
        var text: String
        var bold = false
        var italic = false
    }

    enum Token: Hashable {
        case text(Run)
        case gap(Int)
        case lineBreak
    }

    /// Splits a string into styled runs and gap tokens.
    static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var bold = false
        var italic = false
        var buf = ""
        let chars = Array(s)
        var i = 0
        func flush() {
            if !buf.isEmpty {
                tokens.append(.text(Run(text: buf, bold: bold, italic: italic)))
                buf = ""
            }
        }
        while i < chars.count {
            let c = chars[i]
            if c == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                var j = i + 2
                var digits = ""
                while j < chars.count, chars[j].isNumber { digits.append(chars[j]); j += 1 }
                if !digits.isEmpty, j + 1 < chars.count, chars[j] == "}", chars[j + 1] == "}", let n = Int(digits) {
                    flush()
                    tokens.append(.gap(n))
                    i = j + 2
                    continue
                }
            }
            if c == "*" {
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    flush(); bold.toggle(); i += 2; continue
                }
                // Treat a lone asterisk as italic toggle only if it plausibly opens/closes a span.
                let prev: Character? = i > 0 ? chars[i - 1] : nil
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let opens = !italic && next != nil && next != " "
                let closes = italic && prev != nil && prev != " "
                if opens || closes {
                    flush(); italic.toggle(); i += 1; continue
                }
            }
            if c == "\n" {
                flush()
                tokens.append(.lineBreak)
                i += 1
                continue
            }
            buf.append(c)
            i += 1
        }
        flush()
        return tokens
    }

    static func strip(_ s: String) -> String {
        var out = ""
        for t in tokenize(s) {
            switch t {
            case .text(let r): out += r.text
            case .gap(let n): out += "(\(n))"
            case .lineBreak: out += "\n"
            }
        }
        return out
    }

    static func attributed(_ s: String, baseFont: Font = .body) -> AttributedString {
        var out = AttributedString()
        for t in tokenize(s) {
            switch t {
            case .text(let r):
                var a = AttributedString(r.text)
                var f = baseFont
                if r.bold { f = f.bold() }
                if r.italic { f = f.italic() }
                a.font = f
                out += a
            case .gap(let n):
                var a = AttributedString(" (\(n)) ")
                a.font = baseFont.bold()
                out += a
            case .lineBreak:
                out += AttributedString("\n")
            }
        }
        return out
    }

    static func nsAttributed(_ s: String, size: CGFloat, color: NSColor = .textColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base = NSFont.systemFont(ofSize: size)
        for t in tokenize(s) {
            switch t {
            case .text(let r):
                var font = base
                var traits: NSFontDescriptor.SymbolicTraits = []
                if r.bold { traits.insert(.bold) }
                if r.italic { traits.insert(.italic) }
                if !traits.isEmpty {
                    font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
                }
                out.append(NSAttributedString(string: r.text, attributes: [.font: font, .foregroundColor: color]))
            case .gap(let n):
                out.append(NSAttributedString(string: "(\(n))", attributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: color]))
            case .lineBreak:
                out.append(NSAttributedString(string: "\n", attributes: [.font: base]))
            }
        }
        return out
    }
}
