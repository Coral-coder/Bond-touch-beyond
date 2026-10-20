import SwiftUI
import UIKit

/// The kinds of notification the app shows, each of which can be switched off in
/// Settings → Notifications (all on by default).
///
/// Ones a partner's phone sends (touches, chat, Us updates…) are switched off at the source:
/// the list of what's off travels in your sealed status, and their phone then sends a silent
/// push instead, so everything still syncs, just without a banner or sound. Reminders this
/// phone schedules itself are simply not scheduled.
enum NotificationKind: String, CaseIterable, Identifiable {
    // From partners' phones.
    case touches, heartbeats, arrivals, kisses, chat, care
    // Us updates from a partner, one switch per part of Us.
    case usTodos, usNotes, usWhiteboard, usDates, usLikes, usLanguage, usGames, usLove, usJar,
         usRoulette, usQuestion, usAgreements, usRepair, usMemories, usRadar, usCalendar, usMetamours, usOther
    // Scheduled on this phone.
    case dates, radar, bracelet

    var id: String { rawValue }
    var key: String { "notify.\(rawValue)" }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    enum Section: String, CaseIterable { case partners = "From your partners", us = "Us", reminders = "Reminders" }
    var section: Section {
        switch self {
        case .touches, .heartbeats, .arrivals, .kisses, .chat, .care: return .partners
        case .dates, .radar, .bracelet: return .reminders
        default: return .us
        }
    }

    /// The push group a partner's phone sends this under (nil: scheduled on this phone).
    var pushGroup: String? {
        switch self {
        case .touches: return "t"
        case .heartbeats: return "h"
        case .arrivals: return "a"
        case .kisses: return "k"
        case .chat: return "m"
        case .care: return "c"
        case .dates, .radar, .bracelet: return nil
        default: return "u." + rawValue.dropFirst(2).lowercased()
        }
    }

    var title: String {
        switch self {
        case .touches: return "Touches"
        case .heartbeats: return "Heartbeats"
        case .arrivals: return "Arrivals"
        case .kisses: return "Kisses"
        case .chat: return "Chat messages"
        case .care: return "When a partner needs care"
        case .usTodos: return "To-dos"
        case .usNotes: return "Notes"
        case .usWhiteboard: return "Whiteboard"
        case .usDates: return "Special dates"
        case .usLikes: return "What we like"
        case .usLanguage: return "Touch Language"
        case .usGames: return "Games"
        case .usLove: return "Love languages"
        case .usJar: return "Appreciation jar"
        case .usRoulette: return "Date roulette"
        case .usQuestion: return "Question of the day"
        case .usAgreements: return "Agreements"
        case .usRepair: return "Repair"
        case .usMemories: return "Memory lane"
        case .usRadar: return "R.A.D.A.R."
        case .usCalendar: return "Poly calendar"
        case .usMetamours: return "Metamours & compersion"
        case .usOther: return "Everything else in Us"
        case .dates: return "Anniversaries & birthdays"
        case .radar: return "R.A.D.A.R. reminders"
        case .bracelet: return "Bracelet battery"
        }
    }

    var detail: String? {
        switch self {
        case .touches: return "A partner sends you a touch"
        case .heartbeats: return "A partner sends their heartbeat"
        case .arrivals: return "A partner arrives at a saved place"
        case .kisses: return "The kiss button"
        case .chat: return "New messages (never what they say)"
        case .care: return "A partner is stressed, overwhelmed or running on empty"
        case .usGames: return "Moves and new games, including Story together and Same wavelength"
        case .usRepair: return "Time-outs, feelings and making up"
        case .dates: return "The day before and on the day"
        case .radar: return "Before a check-in"
        case .bracelet: return "When the bracelet runs low"
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .touches: return "hand.tap.fill"
        case .heartbeats: return "waveform.path.ecg"
        case .arrivals: return "mappin.and.ellipse"
        case .kisses: return "heart.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .care: return "hand.raised.fill"
        case .usTodos: return "checklist"
        case .usNotes: return "note.text"
        case .usWhiteboard: return "scribble.variable"
        case .usDates: return "calendar"
        case .usLikes: return "sparkles"
        case .usLanguage: return "hand.wave.fill"
        case .usGames: return "gamecontroller.fill"
        case .usLove: return "heart.text.square.fill"
        case .usJar: return "envelope.open.fill"
        case .usRoulette: return "dice.fill"
        case .usQuestion: return "questionmark.bubble.fill"
        case .usAgreements: return "hand.raised.fingers.spread.fill"
        case .usRepair: return "bandage.fill"
        case .usMemories: return "photo.stack.fill"
        case .usRadar, .radar: return "dot.radiowaves.left.and.right"
        case .usCalendar: return "calendar.badge.clock"
        case .usMetamours: return "person.3.fill"
        case .usOther: return "ellipsis.circle.fill"
        case .dates: return "gift.fill"
        case .bracelet: return "battery.25"
        }
    }

    /// Hidden while the part of the app it's about is switched off.
    var isRelevant: Bool {
        switch self {
        case .usTodos: return Feature.todos.isOn
        case .usNotes: return Feature.notes.isOn
        case .usWhiteboard: return Feature.whiteboard.isOn
        case .usDates, .dates: return Feature.dates.isOn
        case .usLikes: return Feature.likes.isOn
        case .usGames: return Feature.games.isOn
        case .usLove: return Feature.loveLanguages.isOn
        case .usJar: return Feature.appreciation.isOn
        case .usRoulette: return Feature.dateRoulette.isOn
        case .usQuestion: return Feature.question.isOn
        case .usAgreements: return Feature.agreements.isOn
        case .usRepair: return Feature.repair.isOn
        case .usMemories: return Feature.memories.isOn
        case .usRadar, .radar: return Feature.radar.isOn
        case .usCalendar: return Feature.polyCalendar.isOn
        case .usMetamours: return Feature.metamours.isOn
        case .care: return Feature.stress.isOn
        default: return true
        }
    }

    /// Which Us switch a partner's update belongs to, from its wording ("added a to-do").
    static func us(for text: String) -> NotificationKind {
        let t = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("r.a.d.a.r") { return .usRadar }
        if has("calendar") { return .usCalendar }
        if has("metamour", "compersion") { return .usMetamours }
        if has("appreciation") { return .usJar }
        if has("love-language") { return .usLove }
        if has("date idea", "date as done") { return .usRoulette }
        if has("question") { return .usQuestion }
        if has("agreement") { return .usAgreements }
        if has("breather", "ready to talk", "make things right", "how they feel", "resolved") { return .usRepair }
        if has("memory") { return .usMemories }
        if has("to-do") { return .usTodos }
        if has("whiteboard") { return .usWhiteboard }
        if has("a note", "new note") { return .usNotes }
        if has("what we like") { return .usLikes }
        if has("touch language") { return .usLanguage }
        if has("chess", "checkers", "backgammon", "pool", "battleship", "fleet", "shot", "ship", "dice",
               "story", "wavelength", "your turn", "your move", "checkmate", "you win") { return .usGames }
        if has("your dates", "got together", "📅") { return .usDates }
        return .usOther
    }

    /// Push groups switched off here, shared with partners in the status snapshot.
    static var mutedGroups: [String] { allCases.filter { !$0.isOn }.compactMap(\.pushGroup) }
}

/// Settings → Notifications.
struct NotificationSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tick = 0

    var body: some View {
        List {
            ForEach(NotificationKind.Section.allCases, id: \.self) { section in
                Section {
                    ForEach(NotificationKind.allCases.filter { $0.section == section && $0.isRelevant }) { kind in
                        toggle(kind)
                    }
                } header: {
                    Text(section.rawValue)
                } footer: {
                    if section == .partners {
                        Text("Things you switch off still arrive and sync — just without a banner or sound. Your partners' phones learn what you've switched off within a minute.")
                    }
                }
            }
            Section {
                Button("Open iOS notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .listRowBackground(Theme.ink.opacity(0.06))
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Notifications")
    }

    private func toggle(_ kind: NotificationKind) -> some View {
        Toggle(isOn: Binding(get: { _ = tick; return kind.isOn }, set: { on in
            UserDefaults.standard.set(on, forKey: kind.key)
            tick += 1
            apply(kind)
        })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).foregroundStyle(Theme.title)
                    if let detail = kind.detail { Text(detail).font(.caption).foregroundStyle(Theme.subtitle) }
                }
            } icon: {
                Image(systemName: kind.icon).foregroundStyle(Theme.accent)
            }
        }
        .tint(Theme.accent)
        .listRowBackground(Theme.ink.opacity(0.06))
    }

    private func apply(_ kind: NotificationKind) {
        if kind.pushGroup != nil {
            // Tell partners' phones now, so they stop (or start) notifying.
            Task { await model.publishPresence(force: true) }
        } else if kind == .dates || kind == .radar {
            model.scheduleDateReminders()
        }
    }
}
