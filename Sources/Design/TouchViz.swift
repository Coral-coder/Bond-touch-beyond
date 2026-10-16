import SwiftUI

/// Renders a touch rhythm as a row of glowing neon strokes and dots — the app's signature
/// visualization of a "touch". Short gaps become dots, longer gaps become strokes. The
/// colour runs as a two-stop gradient (start → end) across the sequence, matching the
/// original app's customizable start/end touch colours.
struct TouchViz: View {
    let pattern: [Int]          // inter-tap gaps in ms
    let startColorRGB: Int
    let endColorRGB: Int
    var height: CGFloat = 26

    init(pattern: [Int], colorRGB: Int, endColorRGB: Int? = nil, height: CGFloat = 26) {
        self.pattern = pattern
        self.startColorRGB = colorRGB
        self.endColorRGB = endColorRGB ?? colorRGB
        self.height = height
    }

    private enum Mark { case dot; case stroke(Int) }

    /// One mark per tap (pattern.count + 1 taps). A tap preceded by a long gap renders as a
    /// stroke; a quick tap renders as a dot.
    private var marks: [Mark] {
        var result: [Mark] = [.dot]
        for gap in pattern {
            result.append(gap < 160 ? .dot : .stroke(min(max(gap, 180), 700)))
        }
        return result
    }

    var body: some View {
        let items = marks
        return HStack(alignment: .center, spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                let t = items.count > 1 ? Double(index) / Double(items.count - 1) : 0
                markView(items[index], color: color(at: t))
            }
        }
        .frame(height: height)
    }

    @ViewBuilder private func markView(_ mark: Mark, color: Color) -> some View {
        switch mark {
        case .dot:
            Circle()
                .fill(color)
                .frame(width: height * 0.42, height: height * 0.42)
                .shadow(color: color.opacity(0.9), radius: 8)
        case .stroke(let gap):
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0.85), color],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: CGFloat(gap) / 700 * 64 + 22, height: height * 0.5)
                .shadow(color: color.opacity(0.8), radius: 9)
                .rotationEffect(.degrees(-18))
        }
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
