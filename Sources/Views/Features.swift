import SwiftUI

/// The polyamory features (R.A.D.A.R., the poly calendar, metamours & compersion): off unless
/// you're paired with two or more partners, or they're switched on in the debug menu.
enum Poly {
    enum Mode: String, CaseIterable { case auto, on, off
        var title: String { switch self { case .auto: return "Automatic (2+ partners)"; case .on: return "On"; case .off: return "Off" } }
    }
    static let modeKey = "poly.mode", countKey = "poly.partnerCount"
    static var mode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .auto }
    static var isOn: Bool {
        switch mode {
        case .on: return true
        case .off: return false
        case .auto: return UserDefaults.standard.integer(forKey: countKey) >= 2
        }
    }
    /// Keeps the partner count for Automatic up to date.
    static func notePartnerCount(_ n: Int) {
        if UserDefaults.standard.integer(forKey: countKey) != n { UserDefaults.standard.set(n, forKey: countKey) }
    }
}

/// Parts of the app that can be switched off in Settings → Features (all on by default).
enum Feature: String, CaseIterable, Identifiable {
    case us, dates, likes, todos, notes, whiteboard, games, coop, stress, loveLanguages, appreciation, dateRoulette,
         question, agreements, repair, memories, radar, polyCalendar, metamours, weather
    var id: String { rawValue }
    var key: String { "feature.\(rawValue)" }
    var isPoly: Bool { self == .radar || self == .polyCalendar || self == .metamours }
    var isOn: Bool {
        if isPoly && !Poly.isOn { return false }
        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
    /// The features Settings shows (polyamory ones only when polyamory features are on).
    static var shown: [Feature] { allCases.filter { !$0.isPoly || Poly.isOn } }

    var title: String {
        switch self {
        case .us: return "Us tab"
        case .dates: return "Special dates & reminders"
        case .likes: return "What we like"
        case .todos: return "Shared to-dos"
        case .notes: return "Shared notes"
        case .whiteboard: return "Whiteboard"
        case .games: return "Games"
        case .stress: return "Stress & mood"
        case .radar: return "R.A.D.A.R. check-ins"
        case .weather: return "Their weather"
        case .coop: return "Co-op games"
        case .loveLanguages: return "Love-language check-ins"
        case .appreciation: return "Appreciation jar"
        case .dateRoulette: return "Date roulette"
        case .question: return "Question of the day"
        case .agreements: return "Agreements"
        case .repair: return "Repair tools"
        case .memories: return "Memory lane"
        case .polyCalendar: return "Poly calendar"
        case .metamours: return "Metamours & compersion"
        }
    }

    var icon: String {
        switch self {
        case .us: return "heart.circle.fill"
        case .dates: return "calendar"
        case .likes: return "sparkles"
        case .todos: return "checklist"
        case .notes: return "note.text"
        case .whiteboard: return "scribble.variable"
        case .games: return "gamecontroller.fill"
        case .stress: return "face.smiling"
        case .radar: return "dot.radiowaves.left.and.right"
        case .weather: return "cloud.sun.fill"
        case .coop: return "person.2.fill"
        case .loveLanguages: return "heart.text.square.fill"
        case .appreciation: return "envelope.open.fill"
        case .dateRoulette: return "dice.fill"
        case .question: return "questionmark.bubble.fill"
        case .agreements: return "hand.raised.fingers.spread.fill"
        case .repair: return "bandage.fill"
        case .memories: return "photo.stack.fill"
        case .polyCalendar: return "calendar.badge.clock"
        case .metamours: return "person.3.fill"
        }
    }
}

/// Settings → Features: switch parts of the app on and off, folded away until tapped.
struct FeaturesCard: View {
    @AppStorage("featuresOpen") private var open = false
    @State private var tick = 0

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
                } label: {
                    HStack {
                        Text("Features").foregroundStyle(Theme.title)
                        Spacer()
                        Text("\(Feature.shown.filter(\.isOn).count) of \(Feature.shown.count) on")
                            .font(.subheadline).foregroundStyle(Theme.subtitle)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.subtitle)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(Feature.shown) { f in
                        Toggle(isOn: Binding(get: { _ = tick; return f.isOn },
                                             set: { UserDefaults.standard.set($0, forKey: f.key); tick += 1 })) {
                            Label(f.title, systemImage: f.icon).foregroundStyle(Theme.title)
                        }
                        .tint(Theme.accent)
                    }
                }
            }
        }
    }
}
