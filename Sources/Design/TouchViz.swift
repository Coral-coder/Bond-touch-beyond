import SwiftUI

/// Renders a touch, scaled to the available width so any length fits (it never pushes the
/// layout wider), coloured along its start → end gradient.
/// - Generation 3 (touch bar / Bond Touch More): a 2D trace — time to the right, finger
///   position on the bar up and down (position 8 at the top). Taps read as dots, slides as
///   strokes that follow the finger.
/// - Generation 2: a timeline of presses (on/off milliseconds), each press a stroke whose
///   length is its duration.
struct TouchViz: View {
    let pattern: [Int]
    let generation: Int
    let startColorRGB: Int
    let endColorRGB: Int
    var height: CGFloat = 26
    /// The neon's line thickness and glow, adjustable in Settings (1 = as designed).
    @AppStorage("neonWidth") private var neonWidth = 1.0
    @AppStorage("neonGlow") private var neonGlow = 1.0

    init(pattern: [Int], generation: Int = 2, colorRGB: Int, endColorRGB: Int? = nil, height: CGFloat = 26) {
        self.pattern = pattern
        self.generation = generation
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
        if generation == 3 { trace } else { timeline }
    }

    /// Generation 3: the 2D time × position trace.
    private var trace: some View {
        let samples = TouchPattern.trimmed(pattern)
        let n = max(samples.count, 1)
        return Canvas { ctx, size in
            let r = max(min(size.height * 0.11, 5), 2.5) * neonWidth
            // Leave room for the dot and its glow so the top (position 8) and bottom
            // (position 0) of a slide are never clipped at the canvas edge.
            let inset = r + 4
            let usableW = max(size.width - inset * 2, 1), usableH = max(size.height - inset * 2, 1)
            func point(_ i: Int, _ pos: Int) -> CGPoint {
                CGPoint(x: inset + usableW * (n > 1 ? Double(i) / Double(n - 1) : 0.5),
                        y: inset + usableH * (1 - Double(pos) / Double(TouchPattern.positions - 1)))
            }
            var glow = ctx
            glow.addFilter(.shadow(color: color(at: 0.5).opacity(min(1, 0.8 * neonGlow)), radius: 6 * neonGlow))
            var previous: [Int] = []
            for (i, s) in samples.enumerated() {
                let fingers = TouchPattern.fingers(in: s)
                let tint = color(at: Double(i) / Double(n))
                for (k, pos) in fingers.enumerated() {
                    let p = point(i, pos)
                    if k < previous.count {
                        var line = Path()
                        line.move(to: point(i - 1, previous[k]))
                        line.addLine(to: p)
                        glow.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: r * 2, lineCap: .round))
                    } else {
                        glow.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                  with: .color(tint))
                    }
                }
                previous = fingers
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .accessibilityLabel(String(format: "Touch on the bar, %.1f seconds",
                                   Double(samples.count * TouchPattern.sampleMs) / 1000))
    }

    /// Generation 2: the press timeline.
    @ViewBuilder private var timeline: some View {
        let items = presses
        let total = max(items.last.map { $0.start + $0.length } ?? 1, 1)
        Canvas { ctx, size in
            let dot = min(height * 0.42, 22) * neonWidth
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
                layer.addFilter(.shadow(color: tint.opacity(min(1, 0.85 * neonGlow)), radius: 7 * neonGlow))
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
