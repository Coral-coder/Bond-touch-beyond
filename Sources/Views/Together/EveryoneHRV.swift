import Charts
import SwiftUI

/// Everyone's heart-rate variability — or heart rate — over a day on one chart: you and every
/// partner who shares stress & mood, each in their own colour, with each person's last
/// reading and when it was taken. A last reading stays on show, however old, until a newer
/// one replaces it; the chart covers the last 24 hours, or the 24 hours up to the newest
/// reading when nobody has one that recent.
struct EveryoneHRV: View {
    struct Reading: Identifiable { let at: Date; let value: Double; var id: Date { at } }
    struct Person: Identifiable {
        let id: String
        let name: String
        let color: Color
        let hrv: [Reading]
        let heartRate: [Reading]
    }

    enum Metric: String, CaseIterable, Identifiable {
        case hrv = "HRV", heartRate = "Heart rate"
        var id: String { rawValue }
        var caption: String {
            self == .hrv ? "In ms — higher is more rested" : "Beats per minute, averaged every 10 minutes"
        }
        var unit: String { self == .hrv ? "ms" : "bpm" }
    }

    let people: [Person]
    @State private var metric = Metric.hrv

    private func readings(_ person: Person) -> [Reading] { metric == .hrv ? person.hrv : person.heartRate }

    private var end: Date {
        let newest = people.compactMap { readings($0).last?.at }.max()
        guard let newest, Date().timeIntervalSince(newest) > 24 * 3600 else { return Date() }
        return newest.addingTimeInterval(15 * 60)
    }

    private var domain: ClosedRange<Date> { end.addingTimeInterval(-24 * 3600)...end }

    var body: some View {
        let window = domain
        let shown = people.filter { readings($0).contains { window.contains($0.at) } }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Everyone").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Picker("Show", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Text(metric.caption).font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
            if shown.isEmpty {
                Text("No \(metric == .hrv ? "heart-rate variability" : "heart rate") readings from anyone yet.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(shown) { person in
                        ForEach(readings(person).filter { window.contains($0.at) }) { r in
                            LineMark(x: .value("Time", r.at), y: .value(metric.rawValue, r.value),
                                     series: .value("Person", person.id))
                                .foregroundStyle(person.color)
                                // Monotone: smooth, but never swings past the readings.
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            if metric == .hrv {
                                PointMark(x: .value("Time", r.at), y: .value(metric.rawValue, r.value))
                                    .foregroundStyle(person.color).symbolSize(14)
                            }
                        }
                    }
                }
                .chartXScale(domain: window)
                .chartYScale(domain: .automatic(includesZero: metric == .hrv))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                } }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel()
                } }
                .frame(height: 160)
                .clipped()
            }
            // Who's who, with each person's last reading and when it was taken (hours old: their
            // watch isn't on; recent: nothing new to share).
            ForEach(people) { person in
                HStack(spacing: 8) {
                    Circle().fill(person.color).frame(width: 10, height: 10)
                    Text(person.name).font(Theme.font(13, .bold)).foregroundStyle(Theme.title)
                    Spacer()
                    if let last = readings(person).last {
                        Text("\(Int(last.value.rounded())) \(metric.unit)").font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
                        Text(last.at.formatted(.relative(presentation: .named)))
                            .font(Theme.font(11))
                            .foregroundStyle(Date().timeIntervalSince(last.at) > 6 * 3600 ? Theme.amber : Theme.subtitle)
                    } else {
                        Text("No readings yet").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                    }
                }
            }
        }
        .padding(16)
        .glass(cornerRadius: Theme.cardCorner)
    }
}

extension EveryoneHRV {
    /// You (from this phone's Health readings) and every partner (their last report).
    @MainActor
    init(model: AppModel, battery: BatteryService) {
        let me = model.store.profile
        var list = [Person(id: "me", name: me.name.isEmpty ? "Me" : me.name, color: Color(rgbInt: me.colorRGB),
                           hrv: battery.series.map { Reading(at: $0.at, value: $0.hrv) },
                           heartRate: battery.heartRate.map { Reading(at: $0.at, value: $0.bpm) })]
        for p in model.partners {
            let mood = p.presence?.mood
            let hrv = (mood?.series ?? []).compactMap { $0.count == 3 ? Reading(at: Date(timeIntervalSince1970: $0[0]), value: $0[1]) : nil }
            let hr = (mood?.heartRate ?? []).compactMap { $0.count == 2 ? Reading(at: Date(timeIntervalSince1970: $0[0]), value: $0[1]) : nil }
            list.append(Person(id: p.id, name: p.displayName, color: Color(rgbInt: p.colorRGB),
                               hrv: hrv.sorted { $0.at < $1.at }, heartRate: hr.sorted { $0.at < $1.at }))
        }
        people = list
    }
}
