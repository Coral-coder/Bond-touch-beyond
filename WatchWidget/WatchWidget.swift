import SwiftUI
import WidgetKit

/// The watch-face complication: the last touch your partner sent — who, its meaning, how long
/// ago, and the touch drawn. Corner, circular, rectangular and inline. Tapping opens the app.
@main
struct BondWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationTouch.kind, provider: Provider()) { entry in
            WatchLastTouchView(entry: entry)
        }
        .configurationDisplayName("Last touch")
        .description("The last touch your partner sent you.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let touch: ComplicationTouch?
}

struct Provider: TimelineProvider {
    static let sample = ComplicationTouch(from: "Alex", pattern: [120, 120, 120, 120, 400], generation: 2,
                                          startRGB: 0xEC5A89, endRGB: 0xB173DF, label: "Love you", bpm: nil,
                                          at: Date().addingTimeInterval(-300))

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), touch: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), touch: ComplicationTouch.load() ?? (context.isPreview ? Self.sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date(), touch: ComplicationTouch.load())], policy: .never))
    }
}

struct WatchLastTouchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let t = entry.touch
        let what = t.map { $0.bpm.map { "♥ \($0)" } ?? $0.label ?? "touch" } ?? "No touches yet"
        Group {
            switch family {
            case .accessoryInline:
                if let t { Text("💞 \(t.from) · \(what) · \(t.at, style: .relative)") } else { Text("💞 \(what)") }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: t?.bpm != nil ? "heart.fill" : "hand.tap.fill").font(.system(size: 14, weight: .bold))
                            .widgetAccentable()
                        if let t { Text(t.at, style: .offset).font(.system(size: 9, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1) }
                    }
                }
            case .accessoryCorner:
                Image(systemName: t?.bpm != nil ? "heart.fill" : "hand.tap.fill").font(.system(size: 20, weight: .bold))
                    .widgetAccentable()
                    .widgetLabel { Text(t.map { "\($0.from) · \(what)" } ?? what) }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    if let t {
                        HStack(spacing: 4) {
                            Text(t.from).font(.headline).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(t.at, style: .relative).font(.caption2).lineLimit(1).multilineTextAlignment(.trailing)
                        }
                        Text(what).font(.caption).lineLimit(1)
                        ComplicationDrawing(touch: t).frame(height: 16).widgetAccentable()
                    } else {
                        Text("Last touch").font(.headline)
                        Text(what).font(.caption)
                    }
                }
            }
        }
        .complicationBackground()
    }
}

/// The touch drawn small: trace, tap pills, or a heartbeat line.
struct ComplicationDrawing: View {
    let touch: ComplicationTouch

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
    }

    private func color(_ rgb: Int) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let c = color(touch.startRGB)
        if let bpm = touch.bpm {
            let period: Double = 60.0 / Double(min(max(bpm, 30), 220))
            let beat: CGFloat = CGFloat(period / 2.4) * size.width
            let mid: CGFloat = size.height * 0.6
            var path = Path()
            path.move(to: CGPoint(x: 0, y: mid))
            var x: CGFloat = 0
            while x < size.width {
                path.addLine(to: CGPoint(x: x + beat * 0.3, y: mid))
                path.addLine(to: CGPoint(x: x + beat * 0.36, y: mid - size.height * 0.5))
                path.addLine(to: CGPoint(x: x + beat * 0.42, y: mid + size.height * 0.3))
                path.addLine(to: CGPoint(x: x + beat * 0.48, y: mid))
                x += beat
            }
            ctx.stroke(path, with: .color(c), lineWidth: 1.5)
        } else if touch.generation == 3 {
            let samples: [Int] = TouchPattern.trimmed(touch.pattern)
            let n: Int = max(samples.count, 2)
            let top: CGFloat = CGFloat(TouchPattern.positions - 1)
            var path = Path()
            var started = false
            for (i, s) in samples.enumerated() {
                guard let f = TouchPattern.fingers(in: s).first else { started = false; continue }
                let p = CGPoint(x: 2 + (size.width - 4) * CGFloat(i) / CGFloat(n - 1),
                                y: size.height - 2 - (size.height - 4) * CGFloat(f) / top)
                if started { path.addLine(to: p) } else { path.move(to: p); started = true }
            }
            ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        } else {
            var at: Double = 0
            var presses: [(Double, Double)] = []
            for (i, ms) in touch.pattern.enumerated() {
                let d = Double(max(ms, 1))
                if i % 2 == 0 { presses.append((at, d)) }
                at += d
            }
            let total: Double = max(presses.last.map { $0.0 + $0.1 } ?? 1, 1)
            let h: CGFloat = min(8, size.height * 0.6)
            for p in presses {
                let x: CGFloat = (size.width - 4) * CGFloat(p.0 / total) + 2
                let w: CGFloat = max((size.width - 4) * CGFloat(p.1 / total), h)
                ctx.fill(Path(roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: w, height: h), cornerRadius: h / 2),
                         with: .color(c))
            }
        }
    }
}

extension View {
    @ViewBuilder func complicationBackground() -> some View {
        if #available(watchOS 10.0, *) {
            containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}
