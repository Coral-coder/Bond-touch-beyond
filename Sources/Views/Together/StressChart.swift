import Charts
import SwiftUI

/// Stress and HRV over the last 24 hours, with logged moods marked. Pick 24, 12, 6 or 3 hours;
/// zoomed in, the charts slide sideways (iOS 17) to move along the day. No gestures sit on the
/// card itself, so a finger on the charts still scrolls the page up and down.
struct StressChart: View {
    struct Point: Identifiable { let at: Date; let hrv: Double; let stress: Double; var id: Date { at } }
    struct Mark: Identifiable { let at: Date; let emoji: String; var id: Date { at } }

    let points: [Point]
    var marks: [Mark] = []
    var emptyText = "No heart-rate variability readings in the last day. Apple Watch records them through the day and while you sleep."

    /// Green when calm, amber around your usual, red when stressed.
    static func color(_ stress: Double) -> Color {
        stress < 35 ? Theme.lime : stress < 65 ? Theme.amber : Theme.danger
    }

    /// Hours shown at once.
    @State private var span: Double = 24
    /// Where the zoomed-in charts have slid to (the left edge), shared by both charts.
    @State private var scrollX = Date().addingTimeInterval(-24 * 3600)

    /// The whole day, which the charts slide along `span` hours at a time (iOS 17); on iOS 16,
    /// just the newest `span` hours.
    private var domain: ClosedRange<Date> {
        let end = Date()
        if #available(iOS 17.0, *) { return end.addingTimeInterval(-24 * 3600)...end }
        return end.addingTimeInterval(-span * 3600)...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 24 hours").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                if !points.isEmpty {
                    Picker("Hours shown", selection: Binding(get: { span }, set: { new in
                        span = new
                        // Zooming in starts at the newest readings.
                        scrollX = Date().addingTimeInterval(-new * 3600)
                    })) {
                        ForEach([24.0, 12, 6, 3], id: \.self) { Text("\(Int($0)) h").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            if points.isEmpty {
                Text(emptyText)
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("Stress — every reading").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart {
                    ForEach(points) { p in
                        BarMark(x: .value("Time", p.at), y: .value("Stress", p.stress), width: .fixed(7))
                            .foregroundStyle(Self.color(p.stress))
                            .cornerRadius(3)
                    }
                    ForEach(marks.filter { domain.contains($0.at) }) { m in
                        PointMark(x: .value("Time", m.at), y: .value("Stress", 96))
                            .opacity(0)
                            .annotation(position: .overlay) { Text(m.emoji).font(.system(size: 15)) }
                    }
                }
                .chartXScale(domain: domain)
                .modifier(SlideAlong(span: span, scrollX: $scrollX))
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel { Text(v.as(Int.self).map { $0 == 0 ? "Calm" : $0 == 50 ? "Usual" : "High" } ?? "") }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                } }
                .frame(height: 150)

                Text("HRV (ms) — higher is more rested").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart(points) { p in
                    LineMark(x: .value("Time", p.at), y: .value("HRV", p.hrv))
                        .foregroundStyle(Theme.accent).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Time", p.at), y: .value("HRV", p.hrv))
                        .foregroundStyle(Theme.accent).symbolSize(18)
                }
                .chartXScale(domain: domain)
                .modifier(SlideAlong(span: span, scrollX: $scrollX))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                } }
                .frame(height: 120)
            }
        }
        .padding(16)
        .glass(cornerRadius: Theme.cardCorner)
    }
}

/// Zoomed in: the chart shows `span` hours and slides sideways with the system's own chart
/// scrolling (iOS 17), which hands vertical swipes on to the page.
private struct SlideAlong: ViewModifier {
    let span: Double
    @Binding var scrollX: Date

    func body(content: Content) -> some View {
        if span >= 24 {
            content
        } else if #available(iOS 17.0, *) {
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: span * 3600)
                .chartScrollPosition(x: $scrollX)
        } else {
            content
        }
    }
}

extension StressChart {
    /// From this phone's Health readings and mood log.
    init(battery: BatteryService) {
        points = battery.series.map { Point(at: $0.at, hrv: $0.hrv, stress: $0.stress) }
        marks = battery.entries.filter { Date().timeIntervalSince($0.at) < 24 * 3600 }.map { Mark(at: $0.at, emoji: $0.emoji) }
    }

    /// From what a partner shares.
    init(mood: MoodShare?, name: String) {
        self.init(mood: mood ?? MoodShare(emoji: "", label: "", battery: 50, level: "ok", at: .distantPast))
        emptyText = mood == nil
            ? "\(name) isn't sharing stress and mood. They can switch it on in Stress & mood."
            : "No readings from \(name)'s Apple Watch in the last day."
    }

    init(mood: MoodShare) {
        points = (mood.series ?? []).compactMap { $0.count == 3 ? Point(at: Date(timeIntervalSince1970: $0[0]), hrv: $0[1], stress: $0[2]) : nil }
        marks = Date().timeIntervalSince(mood.at) < 24 * 3600 ? [Mark(at: mood.at, emoji: mood.emoji)] : []
    }
}
