import SwiftUI

/// Renders a touch as a glowing timeline: the pattern is the on/off millisecond list the
/// bracelet and server use (even indices = finger down, odd = finger up). Each "on" becomes
/// a neon stroke whose length is its duration (short presses read as dots), and the gaps
/// keep their proportions. The whole touch is scaled to the available width, so any
/// pattern length fits — it never pushes the layout wider. The colour runs as the touch's
/// start → end gradient.
struct TouchViz: View {
    let pattern: [Int]
    let startColorRGB: Int
    let endColorRGB: Int
    var height: CGFloat = 26

    init(pattern: [Int], colorRGB: Int, endColorRGB: Int? = nil, height: CGFloat = 26) {
        self.pattern = pattern
        self.startColorRGB = colorRGB
        self.endColorRGB = endColorRGB ?? colorRGB
        self.height = height
    }

    /// (start, duration) of each press, in ms from the beginning of the touch.
    private var presses: [(start: Double, length: Double)] {
        let values = pattern.isEmpty ? [200] : pattern.map { Double(max($0, 1)) }
        var out: [(start: Double, length: Double)] = []
        var t = 0.0
        for (i, v) in values.enumerated() {
            if i % 2 == 0 { out.append((start: t, length: v)) }
            t += v
        }
        return out
    }

    var body: some View {
        let items = presses
        let total = max(items.last.map { $0.start + $0.length } ?? 1, 1)
        Canvas { ctx, size in
            let dot = height * 0.42
            let pad = dot / 2 + 4
            let usable = max(size.width - pad * 2, 1)
            let mid = size.height / 2
            for (i, p) in items.enumerated() {
                let t = items.count > 1 ? Double(i) / Double(items.count - 1) : 0
                let tint = color(at: t)
                let x0 = pad + usable * p.start / total
                let w = max(usable * p.length / total, dot)
                let rect = CGRect(x: x0 - dot / 2, y: mid - dot / 2, width: w, height: dot)
                var layer = ctx
                layer.addFilter(.shadow(color: tint.opacity(0.85), radius: 7))
                layer.fill(Path(roundedRect: rect, cornerRadius: dot / 2), with: .color(tint))
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .accessibilityLabel("Touch with \(items.count) press\(items.count == 1 ? "" : "es")")
    }

    /// Interpolated colour at fraction `t` (0…1) between the start and end colours.
    private func color(at t: Double) -> Color {
        func comp(_ rgb: Int, _ shift: Int) -> Double { Double((rgb >> shift) & 0xFF) }
        let r = comp(startColorRGB, 16) + (comp(endColorRGB, 16) - comp(startColorRGB, 16)) * t
        let g = comp(startColorRGB, 8)  + (comp(endColorRGB, 8)  - comp(startColorRGB, 8))  * t
        let b = comp(startColorRGB, 0)  + (comp(endColorRGB, 0)  - comp(startColorRGB, 0))  * t
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
