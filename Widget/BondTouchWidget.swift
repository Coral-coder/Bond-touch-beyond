import AppIntents
import SwiftUI
import WidgetKit

/// The home-screen widget, as in the original: your partner (name + photo) and up to 10 of
/// your meanings with their touch drawn; tap one to send it. On iOS 17 the tap sends in the
/// background (`SendMeaningIntent`) and the meaning shows Sent / Failed for a few seconds; on
/// iOS 16 it opens the app, which sends it. Everything shown comes from the snapshot the app
/// keeps in the App Group (`WidgetShared`).
@main
struct BondWidgets: WidgetBundle {
    var body: some Widget {
        BondTouchWidget()
        LastTouchWidget()
        TogetherWidget()
    }
}

struct BondTouchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind, provider: BondProvider()) { entry in
            BondWidgetView(entry: entry)
        }
        .configurationDisplayName("Bond Touch")
        .description("Your partner and your meanings. Tap one to send it to their bracelet.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct BondEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Send state per meaning id, for the meanings showing one at `date`.
    let states: [String: WidgetSendState]
}

struct BondProvider: TimelineProvider {
    func placeholder(in context: Context) -> BondEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (BondEntry) -> Void) {
        let snapshot = WidgetShared.loadSnapshot()
        if context.isPreview, snapshot?.partner == nil { completion(.sample); return }
        completion(BondEntry(date: Date(), snapshot: snapshot, states: [:]))
    }

    /// One entry now, then one each time a Sent / Failed runs out. The app reloads the
    /// widget whenever its data changes, so nothing is refreshed on a schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BondEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetShared.loadSnapshot()
        let statuses = WidgetShared.statuses(now: now)
        func entry(at date: Date) -> BondEntry {
            BondEntry(date: date, snapshot: snapshot,
                      states: statuses.filter { $0.value.visibleUntil > date }.mapValues(\.state))
        }
        let changes = Set(statuses.values.map(\.visibleUntil)).sorted()
        completion(Timeline(entries: [entry(at: now)] + changes.map(entry(at:)), policy: .never))
    }
}

extension BondEntry {
    /// Shown in the widget gallery before the app has written anything.
    static var sample: BondEntry {
        let meanings: [WidgetSnapshot.Meaning] = [
            .init(id: "s1", label: "Love you", emoji: "❤️", colorRGB: 0xEC5A89, endColorRGB: 0xB173DF,
                  pattern: [120, 120, 120, 120, 400], generation: 2, serverID: nil, favourite: true, imageFile: nil),
            .init(id: "s2", label: "Thinking of you", emoji: "💭", colorRGB: 0x57C3BB, endColorRGB: 0x57C3BB,
                  pattern: [300, 200, 300], generation: 2, serverID: nil, favourite: false, imageFile: nil),
            .init(id: "s3", label: "Goodnight", emoji: "🌙", colorRGB: 0xB173DF, endColorRGB: 0x57C3BB,
                  pattern: [600, 300, 600], generation: 2, serverID: nil, favourite: false, imageFile: nil),
            .init(id: "s4", label: "Miss you", emoji: "🥺", colorRGB: 0xECA94B, endColorRGB: 0xEC5A89,
                  pattern: [100, 100, 100, 100, 100, 100, 100], generation: 2, serverID: nil, favourite: false, imageFile: nil),
        ]
        return BondEntry(date: Date(),
                         snapshot: WidgetSnapshot(partner: .init(id: "sample", name: "Alex", colorRGB: 0xEC5A89, photo: nil),
                                                  meanings: meanings),
                         states: ["s1": .sent])
    }
}

// MARK: - Views

struct BondWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BondEntry

    /// Small: 2 meanings (1 on iOS 16, where a small widget has a single tap target);
    /// medium: 4; large: up to 10.
    private var slots: Int {
        switch family {
        case .systemSmall:
            if #available(iOS 17.0, *) { return 2 }
            return 1
        case .systemMedium: return 4
        default: return WidgetShared.maxMeanings
        }
    }

    private var columns: Int { family == .systemSmall ? 1 : 2 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBackground(WidgetSky())
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot, let partner = snapshot.partner {
            let meanings = Array(snapshot.meanings.prefix(slots))
            VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 8) {
                PartnerHeader(partner: partner, compact: family == .systemSmall)
                if meanings.isEmpty {
                    Spacer(minLength: 0)
                    Text("Add meanings in the app to send them from here.")
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.subtitle)
                    Spacer(minLength: 0)
                } else {
                    grid(meanings, bondID: partner.id)
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(singleTapURL(meanings, bondID: partner.id))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
                Text("Bond Touch")
                    .font(Theme.font(15, .heavy))
                    .foregroundStyle(Theme.title)
                Text("Pair with your partner in the app to send touches from here.")
                    .font(Theme.font(11, .semibold))
                    .foregroundStyle(Theme.subtitle)
            }
        }
    }

    /// iOS 16's small widget can only open one link: the meaning it shows.
    private func singleTapURL(_ meanings: [WidgetSnapshot.Meaning], bondID: String) -> URL? {
        if #available(iOS 17.0, *) { return nil }
        guard family == .systemSmall, let m = meanings.first else { return nil }
        return WidgetShared.sendURL(meaningID: m.id, bondID: bondID)
    }

    private func grid(_ meanings: [WidgetSnapshot.Meaning], bondID: String) -> some View {
        let rows = stride(from: 0, to: meanings.count, by: columns).map {
            Array(meanings[$0..<min($0 + columns, meanings.count)])
        }
        return VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(rows[i]) { m in
                        MeaningButton(meaning: m, bondID: bondID, state: entry.states[m.id],
                                      linkable: family != .systemSmall)
                    }
                    if rows[i].count < columns { Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }
}

/// The partner's photo (or initial) in a ring of their colour, and their name.
struct PartnerHeader: View {
    let partner: WidgetSnapshot.Partner
    let compact: Bool

    var body: some View {
        let ring = Color(rgbInt: partner.colorRGB)
        let size: CGFloat = compact ? 26 : 32
        HStack(spacing: 8) {
            ZStack {
                if let photo = WidgetShared.image(partner.photo) {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Circle().fill(LinearGradient(colors: [ring.opacity(0.85), ring.opacity(0.45)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(partner.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(Theme.font(size * 0.45, .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
            .overlay(Circle().stroke(ring, lineWidth: 2).padding(-3))
            .shadow(color: ring.opacity(0.6), radius: 4)
            .padding(3)

            VStack(alignment: .leading, spacing: 0) {
                Text(partner.name)
                    .font(Theme.font(compact ? 14 : 16, .heavy))
                    .foregroundStyle(Theme.title)
                    .lineLimit(1)
                if !compact {
                    Text("Tap a meaning to send it")
                        .font(Theme.font(10, .semibold))
                        .foregroundStyle(Theme.subtitle)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "hand.tap.fill")
                .font(.system(size: compact ? 12 : 14, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// One meaning slot: a button that sends it (iOS 17), or a link into the app (iOS 16).
struct MeaningButton: View {
    let meaning: WidgetSnapshot.Meaning
    let bondID: String
    let state: WidgetSendState?
    /// iOS 16 links work in medium and large widgets only (small uses `widgetURL`).
    let linkable: Bool

    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: SendMeaningIntent(meaningID: meaning.id, bondID: bondID)) { tile }
                .buttonStyle(.plain)
        } else {
            link
        }
    }

    @ViewBuilder private var link: some View {
        if linkable {
            Link(destination: WidgetShared.sendURL(meaningID: meaning.id, bondID: bondID)) { tile }
        } else {
            tile
        }
    }

    private var tile: some View {
        let tint = Color(rgbInt: meaning.colorRGB)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(spacing: 6) {
            if !meaning.emoji.isEmpty {
                Text(meaning.emoji).font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(meaning.label)
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.title)
                    .lineLimit(1)
                touch
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: 56, alignment: .leading)
        .background(
            // Widget glass: no live blur on the home screen, so a light-to-clear fill, a tint
            // of the meaning's colour and the bright top edge.
            shape.fill(LinearGradient(colors: [Theme.glassTop, Theme.glassBottom], startPoint: .top, endPoint: .bottom))
                .overlay(shape.fill(LinearGradient(colors: [tint.opacity(0.22), .clear],
                                                   startPoint: .leading, endPoint: .trailing)))
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
        )
        .overlay { if let state { StatusBadge(state: state, shape: shape) } }
    }

    /// The touch as the app draws it.
    private var touch: some View {
        TouchViz(pattern: meaning.pattern, generation: meaning.generation,
                 colorRGB: meaning.colorRGB, endColorRGB: meaning.endColorRGB, height: 14)
    }
}

/// Sending… / Queued / Sent / Failed over a meaning.
struct StatusBadge: View {
    let state: WidgetSendState
    let shape: RoundedRectangle

    private var style: (text: String, icon: String, color: Color) {
        switch state {
        case .sending: return ("Sending…", "paperplane.fill", Theme.accent)
        case .queued: return ("Queued", "clock.fill", Theme.amber)
        case .sent: return ("Sent", "checkmark.circle.fill", Theme.lime)
        case .failed: return ("Failed", "exclamationmark.triangle.fill", Theme.danger)
        }
    }

    var body: some View {
        ZStack {
            shape.fill(Theme.bgBottom.opacity(0.82))
            shape.stroke(style.color.opacity(0.8), lineWidth: 1)
            Label(style.text, systemImage: style.icon)
                .font(Theme.font(12, .heavy))
                .foregroundStyle(style.color)
                .lineLimit(1)
        }
    }
}

/// The app's aero sky, held still: navy gradient, soft teal / violet / pink blooms and the
/// faint HUD grid.
struct WidgetSky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    bloom(Theme.accent, 0.32, w * 1.1).position(x: w * 0.1, y: 0)
                    bloom(Theme.magenta, 0.24, w * 0.9).position(x: w * 0.95, y: h * 0.45)
                    bloom(Theme.pink, 0.2, w * 0.8).position(x: w * 0.1, y: h)
                }
                HUDGrid(spacing: 23).stroke(Theme.grid, lineWidth: 0.5)
            }
        }
    }

    private func bloom(_ color: Color, _ opacity: Double, _ size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), .clear], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

extension View {
    /// iOS 17 wants the background as the widget's container background (so it can be
    /// removed in StandBy and on the Lock Screen); iOS 16 just draws it behind, with the
    /// content margins iOS 17 adds itself.
    @ViewBuilder func widgetBackground<B: View>(_ background: B) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { background }
        } else {
            padding(14).background(background)
        }
    }
}
