import Charts
import SwiftUI

/// Stress and HRV over the last 24 hours, with logged moods marked. Pinch to zoom in on a
/// stretch of time, drag to move along it; double-tap to see the whole day again.
struct StressChart: View {
    struct Point: Identifiable { let at: Date; let hrv: Double; let stress: Double; var id: Date { at } }
    struct Mark: Identifiable { let at: Date; let emoji: String; var id: Date { at } }

    let points: [Point]
    var marks: [Mark] = []

    /// Hours shown (1…24) and where the window ends (hours before now).
    @State private var span: Double = 24
    @State private var endOffset: Double = 0
    @State private var pinchBase: Double?
    @State private var dragBase: Double?

    private var domain: ClosedRange<Date> {
        let end = Date().addingTimeInterval(-endOffset * 3600)
        return end.addingTimeInterval(-span * 3600)...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 24 hours").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Text(span >= 23.5 ? "Pinch to zoom" : "\(Int(span.rounded())) h · double-tap for 24 h")
                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            }
            if points.isEmpty {
                Text("No heart-rate variability readings in the last day. Apple Watch records them through the day and while you sleep.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("Stress").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Time", p.at), y: .value("Stress", p.stress))
                            .foregroundStyle(LinearGradient(colors: [Theme.danger.opacity(0.45), Theme.amber.opacity(0.15)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", p.at), y: .value("Stress", p.stress))
                            .foregroundStyle(Theme.danger).interpolationMethod(.catmullRom)
                    }
                    ForEach(marks.filter { domain.contains($0.at) }) { m in
                        PointMark(x: .value("Time", m.at), y: .value("Stress", 92))
                            .opacity(0)
                            .annotation(position: .overlay) { Text(m.emoji).font(.system(size: 16)) }
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel { Text(v.as(Int.self).map { $0 == 0 ? "😌" : $0 == 50 ? "😐" : "😣" } ?? "") }
                } }
                .chartXAxis(.hidden)
                .frame(height: 130)

                Text("HRV (ms) — higher is more rested").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart(points) { p in
                    LineMark(x: .value("Time", p.at), y: .value("HRV", p.hrv))
                        .foregroundStyle(Theme.accent).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Time", p.at), y: .value("HRV", p.hrv))
                        .foregroundStyle(Theme.accent).symbolSize(18)
                }
                .chartXScale(domain: domain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                } }
                .frame(height: 120)
            }
        }
        .padding(16)
        .glass(cornerRadius: Theme.cardCorner)
        .contentShape(Rectangle())
        .gesture(MagnificationGesture()
            .onChanged { scale in
                let base = pinchBase ?? span
                pinchBase = base
                span = min(24, max(1, base / scale))
                endOffset = min(endOffset, 24 - span)
            }
            .onEnded { _ in pinchBase = nil })
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .onChanged { v in
                let base = dragBase ?? endOffset
                dragBase = base
                endOffset = min(24 - span, max(0, base + Double(v.translation.width) / 300 * span))
            }
            .onEnded { _ in dragBase = nil })
        .onTapGesture(count: 2) { withAnimation { span = 24; endOffset = 0 } }
    }
}

extension StressChart {
    /// From this phone's Health readings and mood log.
    init(battery: BatteryService) {
        points = battery.series.map { Point(at: $0.at, hrv: $0.hrv, stress: $0.stress) }
        marks = battery.entries.filter { Date().timeIntervalSince($0.at) < 24 * 3600 }.map { Mark(at: $0.at, emoji: $0.emoji) }
    }

    /// From what a partner shares.
    init(mood: MoodShare) {
        points = (mood.series ?? []).compactMap { $0.count == 3 ? Point(at: Date(timeIntervalSince1970: $0[0]), hrv: $0[1], stress: $0[2]) : nil }
        marks = Date().timeIntervalSince(mood.at) < 24 * 3600 ? [Mark(at: mood.at, emoji: mood.emoji)] : []
    }
}
