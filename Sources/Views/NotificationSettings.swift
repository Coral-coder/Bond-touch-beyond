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
    case touches, heartbeats, arrivals, kisses, chat, us, care, dates, radar, bracelet
    var id: String { rawValue }
    var key: String { "notify.\(rawValue)" }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// The push group a partner's phone sends this under (nil: scheduled on this phone).
    var pushGroup: String? {
        switch self {
        case .touches: return "t"
        case .heartbeats: return "h"
        case .arrivals: return "a"
        case .kisses: return "k"
        case .chat: return "m"
        case .us: return "u"
        case .care: return "c"
        case .dates, .radar, .bracelet: return nil
        }
    }

    var title: String {
        switch self {
        case .touches: return "Touches"
        case .heartbeats: return "Heartbeats"
        case .arrivals: return "Arrivals"
        case .kisses: return "Kisses"
        case .chat: return "Chat messages"
        case .us: return "Us updates"
        case .care: return "When a partner needs care"
        case .dates: return "Anniversaries & birthdays"
        case .radar: return "R.A.D.A.R. reminders"
        case .bracelet: return "Bracelet battery"
        }
    }

    var detail: String {
        switch self {
        case .touches: return "A partner sends you a touch"
        case .heartbeats: return "A partner sends their heartbeat"
        case .arrivals: return "A partner arrives at a saved place"
        case .kisses: return "The kiss button"
        case .chat: return "New messages (never what they say)"
        case .us: return "To-dos, notes, dates, games, the jar and the rest of Us"
        case .care: return "A partner is stressed, overwhelmed or running on empty"
        case .dates: return "The day before and on the day"
        case .radar: return "Before a check-in"
        case .bracelet: return "When the bracelet runs low"
        }
    }

    var icon: String {
        switch self {
        case .touches: return "hand.tap.fill"
        case .heartbeats: return "waveform.path.ecg"
        case .arrivals: return "mappin.and.ellipse"
        case .kisses: return "heart.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .us: return "heart.circle.fill"
        case .care: return "hand.raised.fill"
        case .dates: return "calendar"
        case .radar: return "dot.radiowaves.left.and.right"
        case .bracelet: return "battery.25"
        }
    }

    /// Push groups switched off here, shared with partners in the status snapshot.
    static var mutedGroups: [String] { allCases.filter { !$0.isOn }.compactMap(\.pushGroup) }

    /// The kinds shown in Settings (R.A.D.A.R. only with the polyamory features on).
    static var shown: [NotificationKind] { allCases.filter { $0 != .radar || Feature.radar.isOn } }
}

/// Settings → Notifications.
struct NotificationSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tick = 0

    var body: some View {
        List {
            Section {
                ForEach(NotificationKind.shown) { kind in
                    Toggle(isOn: Binding(get: { _ = tick; return kind.isOn }, set: { on in
                        UserDefaults.standard.set(on, forKey: kind.key)
                        tick += 1
                        apply(kind)
                    })) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).foregroundStyle(Theme.title)
                                Text(kind.detail).font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        } icon: {
                            Image(systemName: kind.icon).foregroundStyle(Theme.accent)
                        }
                    }
                    .tint(Theme.accent)
                    .listRowBackground(Theme.ink.opacity(0.06))
                }
            } footer: {
                Text("Things you switch off still arrive and sync — just without a banner or sound. Your partners' phones learn what you've switched off within a minute.")
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

    private func apply(_ kind: NotificationKind) {
        if kind.pushGroup != nil {
            // Tell partners' phones now, so they stop (or start) notifying.
            Task { await model.publishPresence(force: true) }
        } else if kind == .dates || kind == .radar {
            model.scheduleDateReminders()
        }
    }
}
