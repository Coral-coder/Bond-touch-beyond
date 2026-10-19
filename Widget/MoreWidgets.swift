import SwiftUI
import WidgetKit

// MARK: - Shared timeline: just the snapshot

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let s = WidgetShared.loadSnapshot()
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview && s?.partner == nil ? .sample : s))
    }

    /// The app reloads the widgets when anything changes; one entry a day after midnight
    /// keeps "days together" and "in N days" right on their own.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(5)
        let s = WidgetShared.loadSnapshot()
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: s), SnapshotEntry(date: midnight, snapshot: s)],
                            policy: .after(midnight)))
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        var s = WidgetSnapshot(partner: .init(id: "sample", name: "Alex", colorRGB: 0xEC5A89, photo: nil), meanings: [])
        s.lastTouch = .init(from: "Alex", pattern: [120, 120, 120, 120, 400], generation: 2, colorRGB: 0xEC5A89,
                            endColorRGB: 0xB173DF, label: "Love you", emoji: "❤️", bpm: nil, at: Date().addingTimeInterval(-300))
        s.together = .init(since: Calendar.current.date(byAdding: .day, value: -412, to: Date()),
                           nextTitle: "Our anniversary", nextDate: Calendar.current.date(byAdding: .day, value: 12, to: Date()))
        return s
    }
}

private func daysUntil(_ d: Date, from now: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
}

private func daysSince(_ d: Date, to now: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0
}

/// The touch, drawn: its trace or taps, or a heartbeat's EKG.
private struct LastTouchDrawing: View {
    let t: WidgetSnapshot.LastTouch
    var height: CGFloat
    var body: some View {
        if let bpm = t.bpm {
            EKGView(bpm: bpm, colorRGB: t.colorRGB, lineWidth: 2).frame(height: height)
        } else {
            TouchViz(pattern: t.pattern, generation: t.generation, colorRGB: t.colorRGB, endColorRGB: t.endColorRGB, height: height)
        }
    }
}

// MARK: - Last touch

/// The last touch your partner sent: who, its meaning, when, and the touch drawn. Home screen
/// and Lock Screen. Tapping opens the app.
struct LastTouchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.lastTouchKind, provider: SnapshotProvider()) { entry in
            LastTouchView(entry: entry)
        }
        .configurationDisplayName("Last touch")
        .description("The last touch your partner sent you.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct LastTouchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let t = entry.snapshot?.lastTouch
        switch family {
        case .accessoryInline:
            if let t { Text("\(t.emoji ?? "💞") \(t.from) · \(t.label ?? (t.bpm != nil ? "♥ \(t.bpm!)" : "touch")) · \(t.at, style: .relative)") }
            else { Text("💞 No touches yet") }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(t?.emoji ?? (t?.bpm != nil ? "♥" : "💞")).font(.system(size: 18))
                    if let t { Text(t.at, style: .offset).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5) }
                }
            }
            .accessoryBackground()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let t {
                    HStack(spacing: 4) {
                        Text(t.from).font(.headline).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(t.at, style: .relative).font(.caption2).lineLimit(1).multilineTextAlignment(.trailing)
                    }
                    Text(t.bpm.map { "♥ \($0) BPM" } ?? "\(t.emoji ?? "") \(t.label ?? "touched you")")
                        .font(.caption).lineLimit(1)
                    LastTouchDrawing(t: t, height: 18).widgetAccentable()
                } else {
                    Text("Last touch").font(.headline)
                    Text("Nothing yet").font(.caption)
                }
            }
            .accessoryBackground()
        default:
            VStack(alignment: .leading, spacing: 6) {
                if let t {
                    HStack {
                        Text(t.from).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(t.at, style: .relative).font(Theme.font(11, .semibold)).foregroundStyle(Theme.subtitle)
                            .lineLimit(1).multilineTextAlignment(.trailing)
                    }
                    Text(t.bpm.map { "♥ \($0) BPM" } ?? "\(t.emoji ?? "") \(t.label ?? "touched you")")
                        .font(Theme.font(14, .bold)).foregroundStyle(Theme.title).lineLimit(1)
                    Spacer(minLength: 0)
                    LastTouchDrawing(t: t, height: family == .systemSmall ? 46 : 60)
                    Spacer(minLength: 0)
                } else {
                    Image(systemName: "hand.tap.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                    Text("No touches yet").font(Theme.font(14, .heavy)).foregroundStyle(Theme.title)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBackground(WidgetSky())
        }
    }
}

// MARK: - Together

/// Days together and the next anniversary or birthday. Home screen and Lock Screen; with the
/// Last touch widget beside it, the two fill the Lock Screen's widget row.
struct TogetherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.togetherKind, provider: SnapshotProvider()) { entry in
            TogetherWidgetView(entry: entry)
        }
        .configurationDisplayName("Together")
        .description("How long you've been together, and your next special day.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TogetherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let g = entry.snapshot?.together
        let name = entry.snapshot?.partner?.name ?? "Us"
        let days = g?.since.map { daysSince($0, to: entry.date) }
        let next = g?.nextDate.map { daysUntil($0, from: entry.date) }
        switch family {
        case .accessoryInline:
            if let days { Text("♥ \(days) days with \(name)") } else { Text("♥ \(name)") }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Image(systemName: "heart.fill").font(.system(size: 10))
                    Text(days.map(String.init) ?? "—").font(.system(size: 17, weight: .heavy)).minimumScaleFactor(0.5)
                    Text("days").font(.system(size: 8, weight: .bold))
                }
            }
            .accessoryBackground()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").widgetAccentable()
                    Text(days.map { "\($0) days" } ?? "Together").font(.headline).lineLimit(1)
                }
                Text("with \(name)").font(.caption).lineLimit(1)
                if let title = g?.nextTitle, let next {
                    Text("\(g?.nextIsBirthday == true ? "🎂" : "💞") \(title) \(next == 0 ? "today" : "in \(next)d")")
                        .font(.caption2).lineLimit(1)
                }
            }
            .accessoryBackground()
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(Theme.pink)
                Spacer(minLength: 0)
                Text(days.map { "\($0)" } ?? "—").font(Theme.font(34, .heavy)).foregroundStyle(Theme.title)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("days with \(name)").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle).lineLimit(1)
                if let title = g?.nextTitle, let next {
                    Text("\(title) \(next == 0 ? "today 🎉" : "in \(next) days")")
                        .font(Theme.font(11, .semibold)).foregroundStyle(Theme.accent).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBackground(WidgetSky())
        }
    }
}

extension View {
    /// Lock Screen widgets: no background of their own (iOS 17 still wants one declared).
    @ViewBuilder func accessoryBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}

// MARK: - Weather

/// The weather where your partner is: now and the next hours (medium adds the days).
struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BondTouchBeyondWeather", provider: SnapshotProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Their weather")
        .description("The weather where your partner is.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let name = entry.snapshot?.partner?.name ?? "Them"
        if let w = entry.snapshot?.weather {
            switch family {
            case .accessoryInline:
                Text("\(Image(systemName: WeatherInfo.symbol(w.code, isDay: w.isDay))) \(WeatherInfo.degrees(w.temp)) \(w.place ?? name)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: WeatherInfo.symbol(w.code, isDay: w.isDay))
                        Text(WeatherInfo.degrees(w.temp)).font(.headline)
                    }
                    Text(w.place ?? name).font(.caption).lineLimit(1)
                    Text(WeatherInfo.text(w.code)).font(.caption2).lineLimit(1)
                }
                .accessoryBackground()
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(w.place ?? name).font(Theme.font(13, .heavy)).foregroundStyle(Theme.title).lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: WeatherInfo.symbol(w.code, isDay: w.isDay)).symbolRenderingMode(.multicolor)
                    }
                    Text(WeatherInfo.degrees(w.temp)).font(Theme.font(34, .heavy)).foregroundStyle(Theme.title)
                    Text(WeatherInfo.text(w.code) + (w.high.map { " · H \(WeatherInfo.degrees($0))" } ?? ""))
                        .font(Theme.font(11, .semibold)).foregroundStyle(Theme.subtitle).lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        ForEach(w.hours.prefix(family == .systemSmall ? 4 : 7), id: \.at) { h in
                            VStack(spacing: 2) {
                                Image(systemName: WeatherInfo.symbol(h.code, isDay: h.isDay)).symbolRenderingMode(.multicolor)
                                    .font(.system(size: 12))
                                Text(WeatherInfo.degrees(h.temp)).font(Theme.font(10, .bold)).foregroundStyle(Theme.title)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetBackground(WidgetSky())
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.title2)
                Spacer(minLength: 0)
                Text("\(name)'s weather").font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
                Text("Shows once their app shares it.").font(Theme.font(10)).foregroundStyle(Theme.subtitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBackground(WidgetSky())
        }
    }
}
