import SwiftUI

/// What's new: shown once after each update (a new build number), and any time from Settings →
/// What's new. Lists everything since build 40, newest first.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    struct Section: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    /// Newest first. Add to the top for each build; trim when it no longer needs to go back to 40.
    static let sections: [Section] = [
        Section(title: "This update", items: [
            Item(icon: "bell.slash.fill", title: "Quiet while you're in the app",
                 detail: "With the app open — playing a game or anything else — notifications stay quiet; touches still play. Only a chat message shows, and not for the chat you're reading."),
            Item(icon: "heart.circle", title: "The kiss button",
                 detail: "On Home next to the heartbeat: one tap sends a kiss — your partner hears it, \"Thinking of you\"."),
            Item(icon: "face.smiling", title: "Mood check-in on Home",
                 detail: "A button next to the heartbeat: pick how you feel, set your energy and send it to your partners in two taps."),
            Item(icon: "chart.bar.xaxis", title: "Stress charts scroll with the page",
                 detail: "Pick 24, 12, 6 or 3 hours; zoomed in, slide the charts sideways. A finger on the charts scrolls the page again."),
            Item(icon: "bolt.fill", title: "Smoother partner page",
                 detail: "Bubbles and raindrops are drawn once and slid by the system, and photo backgrounds are blurred once, so screens no longer lag."),
            Item(icon: "waveform.path.ecg", title: "Partner heart data is back",
                 detail: "Busy Apple Watches could push the last day's readings out of what was shared. Both phones need this update."),
            Item(icon: "map.fill", title: "Feature tour",
                 detail: "A quick swipe through what the app can do. It opens once, and any time from Settings → Feature tour."),
            Item(icon: "sparkles", title: "What's new",
                 detail: "This screen, after every update, and any time from Settings."),
        ]),
        Section(title: "Themes", items: [
            Item(icon: "drop.fill", title: "Bubble, Raindrop and Citrus",
                 detail: "Glossy Frutiger Aero themes. Bubbles and raindrops also float over a photo background. They pick on the first tap now."),
            Item(icon: "paintpalette.fill", title: "Ten looks, each with colours",
                 detail: "Aero Glass, Midnight Neon, Soft Pastel, Minimal Mono, Liquid Aurora, Paper & Ink, Chalkboard and the Aero three, each with its own colour choices. Settings keeps its place when you switch."),
        ]),
        Section(title: "Home", items: [
            Item(icon: "rectangle.grid.1x2.fill", title: "Home layouts",
                 detail: "Classic, Focus Pad, Conversation, Bento, Partner Deck, Timeline, Orbit, One-Hand, Bubbles, Minimal and Minimal 2 — Settings → Layout."),
            Item(icon: "square.grid.2x2.fill", title: "Movable Classic cards",
                 detail: "Reorder, remove and add the cards on the Classic home."),
            Item(icon: "face.smiling.inverse", title: "Their mood on their photo",
                 detail: "Your partner's mood emoji sits on their photo across Home and the partner bar."),
            Item(icon: "hand.tap.fill", title: "A calmer send screen",
                 detail: "Shows when a touch was sent, with a little animation. Auto-send can be switched off to record up to 10 s and send when you're ready. Cancel and Clear are there too."),
        ]),
        Section(title: "Us", items: [
            Item(icon: "heart.circle.fill", title: "Your shared space",
                 detail: "Together counter, anniversaries and birthdays with reminders, what you each like, to-dos, notes and a whiteboard, all synced over iCloud."),
            Item(icon: "hand.raised.fill", title: "Touch Language on Us",
                 detail: "Touch Language is the first tile on Us. Tap Arrange to drag the tiles into your own order."),
            Item(icon: "gamecontroller.fill", title: "Games",
                 detail: "Pool with real physics (shots replay on your partner's phone), chess, checkers, backgammon, Battleship, and co-op Story together and Same wavelength."),
            Item(icon: "bubble.left.and.text.bubble.right.fill", title: "Relationship tools",
                 detail: "Question of the day, appreciation jar, love-language check-ins, date roulette, memory lane, agreements and repair tools."),
            Item(icon: "person.3.fill", title: "Polyamory features",
                 detail: "R.A.D.A.R. check-ins, a poly calendar, and metamours & compersion. These switch on when you have two or more partners."),
        ]),
        Section(title: "Stress & mood", items: [
            Item(icon: "battery.75percent", title: "Your personal battery",
                 detail: "Worked out from Apple Health (HRV against your usual, resting heart rate, sleep) plus the moods you log. Shared quietly with partners, who are only notified when you're stressed or overwhelmed."),
            Item(icon: "chart.bar.fill", title: "24-hour stress and HRV charts",
                 detail: "A bar for every reading, from calm to high, on your page and on your partners' profiles."),
        ]),
        Section(title: "Widgets & Watch", items: [
            Item(icon: "square.text.square.fill", title: "Widgets",
                 detail: "Send a meaning, Last touch, Together, Their weather and Their mood, on the Home Screen and the Lock Screen."),
            Item(icon: "applewatch", title: "Apple Watch",
                 detail: "A complication with the last touch, haptics that follow the touch exactly, and compact history rows."),
        ]),
        Section(title: "And more", items: [
            Item(icon: "bell.badge.fill", title: "Notifications settings",
                 detail: "A switch for every kind of notification. What you switch off arrives silently, so everything still syncs. Notifications never include chat content."),
            Item(icon: "cloud.sun.fill", title: "Their weather",
                 detail: "The weather where your partner is, with Units for °F or °C and miles or km."),
            Item(icon: "bubble.left.fill", title: "Chat",
                 detail: "Opens at the latest message, follows new ones, and has a jump-to-latest arrow when you scroll up."),
            Item(icon: "rectangle.bottomthird.inset.filled", title: "Nothing under the tab bar",
                 detail: "Every list and screen ends with room to scroll clear of the tab bar."),
            Item(icon: "switch.2", title: "Settings → Features",
                 detail: "Switch off any part of the app you don't use."),
            Item(icon: "music.note", title: "New notification chime",
                 detail: "A soft kiss, then a gentle glow of notes."),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new").font(Theme.font(30, .heavy)).foregroundStyle(Theme.title)
                    Text("Version \(Self.version)").font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
                }
                ForEach(Self.sections) { section in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(section.title.uppercased())
                            .font(Theme.font(12, .bold)).tracking(0.8).foregroundStyle(Theme.accent)
                        ForEach(section.items) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                                    Text(item.detail).font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(cornerRadius: Theme.cardCorner)
                }
                Button("Continue") { dismiss() }
                    .buttonStyle(AccentButtonStyle(height: 52))
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? ""
        let b = info?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }
}

/// When to show What's new by itself: once for each new build, not on a first install (there's
/// nothing to compare with yet), never in demo mode.
@MainActor
enum WhatsNew {
    private static let key = "whatsNew.lastBuild"
    private static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    /// Whether to show it now; notes this build as seen either way. `existingUser`: a profile
    /// is already set up (a brand-new install has nothing to catch up on).
    static func check(existingUser: Bool) -> Bool {
        guard !AppModel.isDemo, !build.isEmpty else { return false }
        let last = UserDefaults.standard.string(forKey: key)
        guard last != build else { return false }
        markSeen()
        return existingUser
    }

    static func markSeen() { UserDefaults.standard.set(build, forKey: key) }
}
