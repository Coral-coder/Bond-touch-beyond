import Charts
import SwiftUI

/// Everyone's heart-rate variability over the last 24 hours on one chart — you and every
/// partner who shares stress & mood — each in their own colour, with their latest reading.
struct EveryoneHRV: View {
    struct Reading: Identifiable { let at: Date; let hrv: Double; var id: Date { at } }
    struct Person: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [Reading]
        var latest: Reading? { points.last }
    }

    let people: [Person]

    private var domain: ClosedRange<Date> {
        let end = Date()
        return end.addingTimeInterval(-24 * 3600)...end
    }

    private var shown: [Person] { people.filter { !$0.points.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everyone's HRV").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Text("Last 24 hours, in ms — higher is more rested").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
            if shown.isEmpty {
                Text("No one has shared heart-rate variability in the last day yet.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(shown) { person in
                        ForEach(person.points.filter { domain.contains($0.at) }) { p in
                            LineMark(x: .value("Time", p.at), y: .value("HRV", p.hrv),
                                     series: .value("Person", person.id))
                                .foregroundStyle(person.color)
                                // Monotone: smooth, but never swings past the readings.
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            PointMark(x: .value("Time", p.at), y: .value("HRV", p.hrv))
                                .foregroundStyle(person.color).symbolSize(14)
                        }
                    }
                }
                .chartXScale(domain: domain)
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
            // Who's who, with each person's latest reading (and how old it is: hours old means
            // their watch isn't on, recent means nothing new to share).
            ForEach(people) { person in
                HStack(spacing: 8) {
                    Circle().fill(person.color).frame(width: 10, height: 10)
                    Text(person.name).font(Theme.font(13, .bold)).foregroundStyle(Theme.title)
                    Spacer()
                    if let last = person.latest {
                        Text("\(Int(last.hrv.rounded())) ms").font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
                        Text(last.at.formatted(.relative(presentation: .named)))
                            .font(Theme.font(11))
                            .foregroundStyle(Date().timeIntervalSince(last.at) > 6 * 3600 ? Theme.amber : Theme.subtitle)
                    } else {
                        Text("Not shared").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                    }
                }
            }
        }
        .padding(16)
        .glass(cornerRadius: Theme.cardCorner)
    }
}

extension EveryoneHRV {
    /// You (from this phone's Health readings) and every partner (from what they share).
    @MainActor
    init(model: AppModel, battery: BatteryService) {
        let me = model.store.profile
        var list = [Person(id: "me", name: me.name.isEmpty ? "Me" : me.name, color: Color(rgbInt: me.colorRGB),
                           points: battery.series.map { Reading(at: $0.at, hrv: $0.hrv) })]
        for p in model.partners {
            let series = p.presence?.mood?.series ?? []
            let points = series.compactMap { $0.count == 3 ? Reading(at: Date(timeIntervalSince1970: $0[0]), hrv: $0[1]) : nil }
            list.append(Person(id: p.id, name: p.displayName, color: Color(rgbInt: p.colorRGB),
                               points: points.sorted { $0.at < $1.at }))
        }
        people = list
    }
}
