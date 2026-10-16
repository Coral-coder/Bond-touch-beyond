import SwiftUI

/// Renders a touch rhythm as a row of glowing neon strokes and dots — the app's signature
/// visualization of a "touch". Short gaps become dots, longer gaps become strokes; the
/// stroke length scales with the gap. Original rendering (not copied artwork).
struct TouchViz: View {
    let pattern: [Int]      // inter-tap gaps in ms
    let colorRGB: Int
    var height: CGFloat = 26

    private var color: Color { Color(rgbInt: colorRGB) }

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
                markView(items[index])
            }
        }
        .frame(height: height)
    }

    @ViewBuilder private func markView(_ mark: Mark) -> some View {
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

    private enum Mark { case dot; case stroke(Int) }
}
