import MapKit
import SwiftUI

extension Units {
    /// "1,092 km" or "679 mi".
    static func distanceText(_ meters: CLLocationDistance) -> String {
        let f = MKDistanceFormatter()
        f.units = imperial ? .imperial : .metric
        f.unitStyle = .abbreviated
        return f.string(fromDistance: meters)
    }
}

/// The weather where your partner is: now, the next hours and the next days, with their
/// local time — from the status their phone shares. `compact` is a one-row version.
struct WeatherCard: View {
    @EnvironmentObject var model: AppModel
    let partner: Partner
    var compact = false

    var body: some View {
        if !Feature.weather.isOn {
            EmptyView()
        } else if let w = model.weather(for: partner) {
            if compact { compactView(w) } else { fullView(w) }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 24))
                Text("\(partner.displayName)'s weather shows up here when they share their location (Map tab) or their weather.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: Theme.cardCorner)
        }
    }

    private func localTime(_ w: WeatherInfo) -> String? {
        guard let id = w.timeZone, let tz = TimeZone(identifier: id), tz.secondsFromGMT() != TimeZone.current.secondsFromGMT() else { return nil }
        let f = DateFormatter()
        f.timeZone = tz
        f.timeStyle = .short
        return f.string(from: Date())
    }

    private func compactView(_ w: WeatherInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(WeatherInfo.degrees(w.temp)) · \(w.summary)").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                Text([w.place, localTime(w).map { "\($0) there" }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let hi = w.high, let lo = w.low {
                Text("\(WeatherInfo.degrees(hi)) / \(WeatherInfo.degrees(lo))").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(12)
        .glass(cornerRadius: Theme.cardCorner)
    }

    private func fullView(_ w: WeatherInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weather \(w.place.map { "in \($0)" } ?? "with \(partner.displayName)")")
                    .font(Theme.font(15, .heavy)).foregroundStyle(Theme.mutedHeadline).lineLimit(1)
                Spacer()
                if let t = localTime(w) { Text("\(t) there").font(Theme.font(12, .semibold)).foregroundStyle(Theme.subtitle) }
            }
            HStack(spacing: 12) {
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 0) {
                    Text(WeatherInfo.degrees(w.temp)).font(Theme.font(34, .heavy)).foregroundStyle(Theme.title)
                    Text(w.summary).font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(w.days.dropFirst().prefix(3), id: \.date) { d in
                        HStack(spacing: 6) {
                            Text(d.date.formatted(.dateTime.weekday(.abbreviated))).font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
                                .frame(width: 30, alignment: .leading)
                            Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 13))
                            Text("\(WeatherInfo.degrees(d.high)) \(WeatherInfo.degrees(d.low))").font(Theme.font(11, .semibold))
                                .foregroundStyle(Theme.title).monospacedDigit()
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(w.hours.prefix(7), id: \.at) { h in
                    VStack(spacing: 4) {
                        Text(hourLabel(h.at, w)).font(Theme.font(10, .bold)).foregroundStyle(Theme.subtitle)
                        Image(systemName: h.symbol).symbolRenderingMode(.multicolor).font(.system(size: 15))
                        Text(WeatherInfo.degrees(h.temp)).font(Theme.font(12, .heavy)).foregroundStyle(Theme.title)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Weather: Open-Meteo").font(Theme.font(10)).foregroundStyle(Theme.subtitle)
            if let mine = model.myWeather {
                Text("You: \(WeatherInfo.degrees(mine.temp)) \(mine.summary.lowercased())\(mine.place.map { " in \($0)" } ?? "")")
                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(14)
        .glass(cornerRadius: Theme.cardCorner)
    }

    private func hourLabel(_ d: Date, _ w: WeatherInfo) -> String {
        let f = DateFormatter()
        f.timeZone = w.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: d)
    }
}

/// Their weather in one row; tap for the full forecast.
struct WeatherButton: View {
    let partner: Partner
    @State private var open = false

    var body: some View {
        Button { open = true } label: { WeatherCard(partner: partner, compact: true) }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) {
                ScrollView { WeatherCard(partner: partner).padding(16) }
                    .screenBackground()
                    .presentationDetents([.medium])
            }
            .accessibilityHint("Shows the forecast")
    }
}

/// The Classic home's cards, in the order you've arranged them; any can be hidden and added
/// back (Home → the cards button).
enum HomeCard: String, CaseIterable, Identifiable {
    case pair, send, meanings, weather, together, feed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pair: return "Map & greeting"
        case .send: return "Send a touch"
        case .meanings: return "Meanings"
        case .weather: return "Their weather"
        case .together: return "Together & dates"
        case .feed: return "Recent touches"
        }
    }
    var icon: String {
        switch self {
        case .pair: return "map.fill"
        case .send: return "hand.tap.fill"
        case .meanings: return "text.bubble.fill"
        case .weather: return "cloud.sun.fill"
        case .together: return "heart.fill"
        case .feed: return "clock.arrow.circlepath"
        }
    }

    static let key = "classicCards"
    static let defaultOrder: [HomeCard] = [.pair, .weather, .send, .meanings, .feed]

    static func decode(_ raw: String) -> [HomeCard] {
        raw.isEmpty ? defaultOrder : raw.split(separator: ",").compactMap { HomeCard(rawValue: String($0)) }
    }
    static func encode(_ cards: [HomeCard]) -> String { cards.map(\.rawValue).joined(separator: ",") }
}

/// Arrange the Classic home: drag to reorder, remove, and add cards back.
struct HomeCardsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeCard.key) private var raw = ""

    var body: some View {
        let shown = HomeCard.decode(raw)
        NavigationStack {
            List {
                Section("On Home — drag to reorder") {
                    ForEach(shown) { c in
                        HStack(spacing: 12) {
                            Image(systemName: c.icon).foregroundStyle(Theme.accent).frame(width: 26)
                            Text(c.title).foregroundStyle(Theme.title)
                            Spacer()
                            Button { raw = HomeCard.encode(shown.filter { $0 != c }) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger)
                            }
                            .buttonStyle(.plain).accessibilityLabel("Remove \(c.title)")
                        }
                        .listRowBackground(Theme.ink.opacity(0.06))
                    }
                    .onMove { from, to in
                        var list = shown
                        list.move(fromOffsets: from, toOffset: to)
                        raw = HomeCard.encode(list)
                    }
                }
                let hidden = HomeCard.allCases.filter { !shown.contains($0) }
                if !hidden.isEmpty {
                    Section("Add") {
                        ForEach(hidden) { c in
                            Button { raw = HomeCard.encode(shown + [c]) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: c.icon).foregroundStyle(Theme.subtitle).frame(width: 26)
                                    Text(c.title).foregroundStyle(Theme.title)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.lime)
                                }
                            }
                            .listRowBackground(Theme.ink.opacity(0.06))
                        }
                    }
                }
                Section {
                    Button("Reset to default") { raw = "" }.foregroundStyle(Theme.accent)
                        .listRowBackground(Theme.ink.opacity(0.06))
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Home cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
