import SwiftUI
import AppKit

/// Read-only, selectable rich text that supports user highlights (right-click → 高亮) and evidence marks.
struct HighlightableText: NSViewRepresentable {
    var text: NSAttributedString
    var highlights: [NSRange]
    var evidence: [NSRange] = []
    var onHighlight: (NSRange) -> Void = { _ in }
    var onClear: (NSRange?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PassageTextView {
        let tv = PassageTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = true
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.coordinator = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateNSView(_ tv: PassageTextView, context: Context) {
        context.coordinator.parent = self
        let s = NSMutableAttributedString(attributedString: text)
        for r in evidence where NSMaxRange(r) <= s.length { s.addAttributes([.backgroundColor: Theme.evidence, .foregroundColor: NSColor.black], range: r) }
        for r in highlights where NSMaxRange(r) <= s.length { s.addAttributes([.backgroundColor: Theme.highlight, .foregroundColor: NSColor.black], range: r) }
        if !(tv.textStorage?.isEqual(to: s) ?? false) {
            let sel = tv.selectedRange()
            tv.textStorage?.setAttributedString(s)
            if NSMaxRange(sel) <= s.length { tv.setSelectedRange(sel) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: PassageTextView, context: Context) -> CGSize? {
        guard let w = proposal.width, w.isFinite, w > 0, let storage = tv.textStorage else { return nil }
        let lm = NSLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: w, height: .greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        let copy = NSTextStorage(attributedString: storage)
        copy.addLayoutManager(lm)
        lm.ensureLayout(for: tc)
        return CGSize(width: w, height: ceil(lm.usedRect(for: tc).height) + 1)
    }

    final class Coordinator {
        var parent: HighlightableText
        init(_ p: HighlightableText) { parent = p }
    }
}

final class PassageTextView: NSTextView {
    weak var coordinator: HighlightableText.Coordinator?

    /// Keep wrapping in step with the width SwiftUI actually gives the view.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let tc = textContainer, abs(tc.containerSize.width - newSize.width) > 0.5 {
            tc.containerSize = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let sel = selectedRange()
        if sel.length > 0 {
            let h = NSMenuItem(title: "高亮 Highlight", action: #selector(doHighlight), keyEquivalent: "")
            h.target = self
            m.addItem(h)
        }
        let c = NSMenuItem(title: sel.length > 0 ? "清除所选高亮" : "清除本段高亮", action: #selector(doClear), keyEquivalent: "")
        c.target = self
        m.addItem(c)
        if sel.length > 0 {
            m.addItem(.separator())
            let cp = NSMenuItem(title: "拷贝", action: #selector(copy(_:)), keyEquivalent: "")
            cp.target = self
            m.addItem(cp)
        }
        return m
    }

    override func keyDown(with event: NSEvent) {
        // H: highlight the selection, like the computer-delivered test
        if event.charactersIgnoringModifiers?.lowercased() == "h", event.modifierFlags.intersection([.command, .option, .control]).isEmpty, selectedRange().length > 0 {
            doHighlight()
            return
        }
        super.keyDown(with: event)
    }

    @objc func doHighlight() {
        let r = selectedRange()
        guard r.length > 0 else { return }
        coordinator?.parent.onHighlight(r)
        setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
    }

    @objc func doClear() {
        let r = selectedRange()
        coordinator?.parent.onClear(r.length > 0 ? r : nil)
    }
}

/// Plain-text essay editor: no spell check, autocorrect or smart substitutions — like the real test.
struct EssayEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var editable: Bool = true
    var ink: NSColor = .textColor
    var background: NSColor = .textBackgroundColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.string = text
        tv.isEditable = editable
        tv.backgroundColor = background
        tv.textColor = ink
        tv.insertionPointColor = ink
        tv.drawsBackground = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        if tv.font?.pointSize != fontSize { tv.font = NSFont.systemFont(ofSize: fontSize) }
        tv.isEditable = editable
        if tv.backgroundColor != background { tv.backgroundColor = background }
        if tv.textColor != ink { tv.textColor = ink; tv.insertionPointColor = ink }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EssayEditor
        init(_ p: EssayEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// Finds `quote` inside `text` (case-insensitive, tolerant of whitespace / quote-style differences).
func findEvidence(_ quote: String, in text: String) -> NSRange? {
    let q = quote.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’…. ")))
    guard q.count >= 8 else { return nil }
    let ns = text as NSString
    let r = ns.range(of: q, options: [.caseInsensitive, .diacriticInsensitive])
    if r.location != NSNotFound { return r }
    // tolerant regex: words separated by any whitespace / punctuation run
    let words = q.split { !$0.isLetter && !$0.isNumber }.map { NSRegularExpression.escapedPattern(for: String($0)) }
    guard words.count >= 3 else { return nil }
    for take in [words.count, min(words.count, 12), min(words.count, 7)] {
        let pattern = words.prefix(take).joined(separator: #"[^A-Za-z0-9]+"#)
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            return m.range
        }
    }
    return nil
}
