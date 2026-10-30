import SwiftUI
import AppKit

enum Theme {
    static let brand = Color(red: 0.72, green: 0.07, blue: 0.13)
    static let correct = Color(red: 0.13, green: 0.6, blue: 0.33)
    static let wrong = Color(red: 0.85, green: 0.2, blue: 0.2)
    static let near = Color.orange
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let examBackground = Color(nsColor: .textBackgroundColor)
    static let highlight = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.45, alpha: 0.85)
    static let evidence = NSColor(calibratedRed: 0.55, green: 0.85, blue: 1.0, alpha: 0.55)

    static func moduleColor(_ m: Module) -> Color {
        switch m {
        case .listening: return Color(red: 0.2, green: 0.45, blue: 0.85)
        case .reading: return Color(red: 0.15, green: 0.6, blue: 0.45)
        case .writing: return Color(red: 0.8, green: 0.45, blue: 0.1)
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07)))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct BandBadge: View {
    var band: Double?
    var label: String? = nil
    var size: CGFloat = 34

    var body: some View {
        VStack(spacing: 2) {
            Text(Grader.bandString(band))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(band == nil ? Color.secondary : Theme.brand)
            if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct Pill: View {
    var text: String
    var color: Color = .accentColor
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

/// Wrapping layout: places children left-to-right and wraps lines; children of a line are vertically centred.
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 6

    struct Cache { var lines: [[Int]] = []; var sizes: [CGSize] = [] }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func compute(_ width: CGFloat, _ subviews: Subviews) -> (lines: [[Int]], sizes: [CGSize], heights: [CGFloat]) {
        var lines: [[Int]] = [[]]
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        for (i, sv) in subviews.enumerated() {
            let s = sv.sizeThatFits(.unspecified)
            sizes.append(s)
            let isBreak = sv[LineBreakKey.self]
            if isBreak {
                lines.append([])
                x = 0
                continue
            }
            if x > 0, x + s.width > width {
                lines.append([])
                x = 0
            }
            lines[lines.count - 1].append(i)
            x += s.width + spacing
        }
        let heights = lines.map { l in l.map { sizes[$0].height }.max() ?? 0 }
        return (lines, sizes, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 600
        let (lines, sizes, heights) = compute(width, subviews)
        let maxW = lines.map { l in l.reduce(0) { $0 + sizes[$1].width + spacing } }.max() ?? 0
        let h = heights.reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: min(width, maxW), height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let (lines, sizes, heights) = compute(bounds.width, subviews)
        var y = bounds.minY
        for (li, l) in lines.enumerated() {
            var x = bounds.minX
            for i in l {
                let s = sizes[i]
                subviews[i].place(at: CGPoint(x: x, y: y + (heights[li] - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += heights[li] + lineSpacing
        }
        for (i, sv) in subviews.enumerated() where sv[LineBreakKey.self] {
            _ = i
            sv.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: .zero)
        }
    }
}

struct LineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

/// Image from the bank, with click-to-enlarge.
struct BankImage: View {
    var url: URL?
    var maxHeight: CGFloat? = nil
    @State private var zoom = false

    var body: some View {
        if let url, let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: min(img.size.width, 900), maxHeight: maxHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.1)))
                .onTapGesture { zoom = true }
                .help("点击放大")
                .sheet(isPresented: $zoom) {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button("关闭") { zoom = false }.keyboardShortcut(.cancelAction)
                        }
                        .padding(8)
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                                .frame(width: min(img.size.width * 1.2, 1400))
                                .background(Color.white)
                        }
                    }
                    .frame(minWidth: 700, minHeight: 600)
                }
        } else {
            Label("图片缺失", systemImage: "photo").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
    }
}

/// Text with the bank's inline markup.
struct MarkupText: View {
    var text: String
    var font: Font = .body
    init(_ text: String, font: Font = .body) {
        self.text = text
        self.font = font
    }
    var body: some View {
        Text(InlineMarkup.attributed(text, baseFont: font))
    }
}

/// Markdown text from AI output.
struct MarkdownText: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        if let a = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(a)
        } else {
            Text(text)
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var systemImage: String
    var message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

func formatDuration(_ s: Double) -> String {
    let m = Int(s) / 60
    if m >= 60 { return "\(m / 60) 小时 \(m % 60) 分" }
    return "\(m) 分 \(Int(s) % 60) 秒"
}

extension Date {
    var shortString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: self)
    }
}
