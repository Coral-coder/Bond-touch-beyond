import Charts
import SwiftUI

/// Stress, HRV and heart rate over the last 24 hours, with logged moods marked. When the watch
/// hasn't been worn since, it shows the 24 hours up to the last readings (and says when),
/// never an empty box. Pick 24, 12, 6 or 3 hours; zoomed in, the charts slide sideways
/// (iOS 17) to move along the day. No gestures sit on the card itself, so a finger on the
/// charts still scrolls the page up and down.
struct StressChart: View {
    struct Point: Identifiable { let at: Date; let hrv: Double; let stress: Double; var id: Date { at } }
    struct Mark: Identifiable { let at: Date; let emoji: String; var id: Date { at } }
    struct Beat: Identifiable { let at: Date; let bpm: Double; var id: Date { at } }

    let points: [Point]
    var beats: [Beat] = []
    var marks: [Mark] = []
    var emptyText = "No Health readings yet. Apple Watch records them through the day and while you sleep."

    /// Green when calm, amber around your usual, red when stressed.
    static func color(_ stress: Double) -> Color {
        stress < 35 ? Theme.lime : stress < 65 ? Theme.amber : Theme.danger
    }

    /// Hours shown at once.
    @State private var span: Double = 24
    /// Where the zoomed-in charts have slid to (the left edge), shared by both charts.
    @State private var scrollX = Date().addingTimeInterval(-24 * 3600)

    /// The newest reading of any kind.
    private var latest: Date? { [points.last?.at, beats.last?.at].compactMap { $0 }.max() }

    /// Where the day shown ends: now, or the last readings when they're over a day old (the
    /// last report stays on show until a new one replaces it).
    private var end: Date {
        guard let latest, Date().timeIntervalSince(latest) > 24 * 3600 else { return Date() }
        return latest.addingTimeInterval(15 * 60)
    }

    /// The whole day, which the charts slide along `span` hours at a time (iOS 17); on iOS 16,
    /// just the newest `span` hours.
    private var domain: ClosedRange<Date> {
        let end = end
        if #available(iOS 17.0, *) { return end.addingTimeInterval(-24 * 3600)...end }
        return end.addingTimeInterval(-span * 3600)...end
    }

    private var shownBeats: [Beat] {
        if #available(iOS 17.0, *) { return beats }
        return beats.filter { domain.contains($0.at) }
    }

    /// The readings the charts draw: all of them when they slide (iOS 17), else only those in
    /// view — so nothing is drawn past the chart's edges when zoomed in.
    private var shown: [Point] {
        if #available(iOS 17.0, *) { return points }
        return points.filter { domain.contains($0.at) }
    }

    /// Smaller dots when many readings are in view, so a full day doesn't crowd.
    private var pointSize: CGFloat {
        let inView = Double(points.count) * min(span, 24) / 24
        return inView > 120 ? 10 : inView > 60 ? 16 : 26
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Date().timeIntervalSince(end) > 3600 ? "24 hours to " + end.formatted(date: .abbreviated, time: .shortened) : "Last 24 hours")
                    .font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                if latest != nil {
                    Picker("Hours shown", selection: Binding(get: { span }, set: { new in
                        span = new
                        // Zooming in starts at the newest readings.
                        scrollX = end.addingTimeInterval(-new * 3600)
                    })) {
                        ForEach([24.0, 12, 6, 3], id: \.self) { Text("\(Int($0)) h").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            if latest == nil {
                Text(emptyText)
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle).frame(maxWidth: .infinity, minHeight: 120)
            }
            // Recent → nothing new to share; hours old → the watch isn't being worn (Apple
            // Watch records HRV every few hours, more often while asleep).
            if let last = latest {
                Text("Last reading " + last.formatted(.relative(presentation: .named))
                     + (Date().timeIntervalSince(last) > 24 * 3600 ? " · " + last.formatted(date: .abbreviated, time: .shortened) : ""))
                    .font(Theme.font(11)).foregroundStyle(Date().timeIntervalSince(last) > 6 * 3600 ? Theme.amber : Theme.subtitle)
            }
            if !points.isEmpty {
                Text("Stress — every reading").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart {
                    // A soft filled line through every reading, each reading a dot in its
                    // level's colour.
                    ForEach(shown) { p in
                        AreaMark(x: .value("Time", p.at), y: .value("Stress", p.stress))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Theme.ink.opacity(0.16), Theme.ink.opacity(0.01)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Time", p.at), y: .value("Stress", p.stress))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.ink.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("Time", p.at), y: .value("Stress", p.stress))
                            .foregroundStyle(Self.color(p.stress))
                            .symbolSize(pointSize)
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
                .clipped()

                Text("HRV (ms) — higher is more rested").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart(shown) { p in
                    LineMark(x: .value("Time", p.at), y: .value("HRV", p.hrv))
                        .foregroundStyle(Theme.accent).interpolationMethod(.monotone)
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
                .clipped()
            }
            if !beats.isEmpty {
                Text("Heart rate (bpm)").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Chart(shownBeats) { b in
                    AreaMark(x: .value("Time", b.at), y: .value("BPM", b.bpm))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.danger.opacity(0.22), Theme.danger.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", b.at), y: .value("BPM", b.bpm))
                        .foregroundStyle(Theme.danger).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: .automatic(includesZero: false))
                .modifier(SlideAlong(span: span, scrollX: $scrollX))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                } }
                .frame(height: 120)
                .clipped()
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
        beats = battery.heartRate.map { Beat(at: $0.at, bpm: $0.bpm) }
        marks = battery.entries.suffix(50).map { Mark(at: $0.at, emoji: $0.emoji) }
    }

    /// From what a partner shares.
    init(mood: MoodShare?, name: String) {
        self.init(mood: mood ?? MoodShare(emoji: "", label: "", battery: 50, level: "ok", at: .distantPast))
        emptyText = mood == nil
            ? "No Health readings from \(name) yet."
            : "No Apple Watch readings from \(name) yet."
    }

    init(mood: MoodShare) {
        points = (mood.series ?? []).compactMap { $0.count == 3 ? Point(at: Date(timeIntervalSince1970: $0[0]), hrv: $0[1], stress: $0[2]) : nil }
        beats = (mood.heartRate ?? []).compactMap { $0.count == 2 ? Beat(at: Date(timeIntervalSince1970: $0[0]), bpm: $0[1]) : nil }
        marks = mood.emoji.isEmpty ? [] : [Mark(at: mood.at, emoji: mood.emoji)]
    }
}
