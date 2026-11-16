import SwiftUI

/// What's new: from Settings → What's new (it no longer pops up after updates). One section
/// per build since 59, newest first, then the earlier highlights.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: AppModel
    @State private var showPartner = false

    /// Where "Show me" takes you.
    enum Go {
        case route(AppRoute)        // a tab, or a part of Us
        case partner                // the selected partner's page
        case people, profile, notifications, totwoo, themes, displaySize
    }

    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var go: Go? = nil
        var id: String { title }
    }

    struct Section: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    /// Newest first, one section per TestFlight build since 59, then the earlier highlights.
    /// Add a section at the top for each build.
    static let sections: [Section] = [
        Section(title: "Build 77", items: [
            Item(icon: "photo.fill", title: "Photos in chat work",
                 detail: "Photos now send every time: they're sized to fit before they go.", go: .route(.chat)),
            Item(icon: "timer", title: "View timers on photos",
                 detail: "When you send a photo, choose how long it can be viewed: 3 seconds to a minute, or no limit. The timer starts when it's opened; when it ends, the photo is deleted from that phone. It stays locked in the chat until tapped.", go: .route(.chat)),
            Item(icon: "lock.shield.fill", title: "Photos locked down",
                 detail: "Photos are encrypted end to end, and again on your phone with a key that never leaves it. They're kept out of backups, hidden while the screen is recorded, and you're told if a screenshot is taken."),
            Item(icon: "star.fill", title: "New app icons",
                 detail: "The app has a new icon, a heart of stars, and six more to choose from: star infinity, infinity heart, your stars, heartbeat, infinity of stars and minimal. The two earlier icons are still there. Settings → App icon."),
            Item(icon: "sparkles", title: "What's new pops up",
                 detail: "This screen opens once after each update. It's always in Settings too."),
        ]),
        Section(title: "Build 76", items: [
            Item(icon: "gauge", title: "Where we stand",
                 detail: "A new part of Us, one for each relationship. Say how close you feel, what kind of relationship it is (Anchor, Comet, FWB, your own words) and whether you're happy with it. You both see how you line up, never each other's number unless you share it.", go: .route(.us("stand"))),
            Item(icon: "sparkles", title: "Wishes",
                 detail: "Things you'd like that aren't there yet, closer or with more space. Your partner answers Yes, let's, Not yet or Let's talk. A Not yet sets when it can come back, so nobody is pressed. A wish can stay hidden until you both want the same thing.", go: .route(.us("stand"))),
            Item(icon: "hands.sparkles.fill", title: "Promises",
                 detail: "Turn a wish into a promise, with a day if you like. Gentle reminders as it comes up; one that slips by can be renewed, changed or let go. Kept ones gather into What we've done for each other, with thank-yous.", go: .route(.us("stand"))),
            Item(icon: "person.3.fill", title: "Check-ins and All of us",
                 detail: "A check-in as often as suits you, which offers to move on a rough day. Mark a quiet season, or pause. When three or more of you are all connected, an All of us space appears by itself. Before unbonding, you can export your relationship to keep.", go: .route(.us("stand"))),
            Item(icon: "flame.fill", title: "Streaks",
                 detail: "Each partner's page shows how many days in a row you've been in touch, and your best. Any touch, kiss, heartbeat or message counts, either way. Missing a day just starts it again.", go: .partner),
            Item(icon: "bell.and.waves.left.and.right.fill", title: "Gentle nudges",
                 detail: "When it's been a while (you choose how long, per partner), when you haven't answered, the evening before you meet, when someone's been quiet for a week, and to keep a streak going. Each has Kiss and Send a touch built in. Nothing is ever sent for you, and no one is told. Settings → Notifications → Nudges.", go: .notifications),
            Item(icon: "scale.3d", title: "Balance",
                 detail: "With more than one partner, People shows who you reached out to this week, and Sundays bring a private summary. Only you see it.", go: .people),
            Item(icon: "calendar.badge.checkmark", title: "Meeting countdown resets",
                 detail: "\"You meet today\" no longer sticks. It clears when that day ends, or as soon as you're together: both phones within about 100 ft on the day.", go: .partner),
            Item(icon: "list.bullet.rectangle", title: "What's new, build by build",
                 detail: "This screen now lists every build since 59."),
        ]),
        Section(title: "Build 75", items: [
            Item(icon: "person.2.badge.gearshape.fill", title: "Partners don't vanish",
                 detail: "A hiccup in iCloud could make a partner disappear for good. Now they stay. If iCloud can't find a bond for several days, it moves to People → Recently removed, where Restore puts it back.", go: .people),
        ]),
        Section(title: "Build 74", items: [
            Item(icon: "chevron.left.forwardslash.chevron.right", title: "Matrix replays",
                 detail: "Replaying a touch that was sent from Matrix plays it in Matrix mode again, your own included.", go: .route(.home)),
        ]),
        Section(title: "Build 73", items: [
            Item(icon: "waveform.path.ecg", title: "One beat, one buzz",
                 detail: "A heartbeat on the bracelet is one vibration per beat, with nothing in between.", go: .route(.home)),
            Item(icon: "wrench.and.screwdriver.fill", title: "Theme list fixed",
                 detail: "Scrolling Settings with the themes open no longer crashes.", go: .themes),
        ]),
        Section(title: "Build 72", items: [
            Item(icon: "chevron.left.forwardslash.chevron.right", title: "Matrix",
                 detail: "A new theme: digital rain in code greens, led by glitching hearts, with your partner's face coming through in the code. Touches you send from it glitch, and play in Matrix mode on your partner's phone.", go: .themes),
            Item(icon: "mouth.fill", title: "Kisses",
                 detail: "A kiss now says \"{name} kissed you! 💋\". Every notification has Kiss back and Send a touch, and a partner's page has both buttons too. A kiss that arrives with the app open floats up the screen.", go: .partner),
            Item(icon: "waveform.path.ecg", title: "Heartbeats in time",
                 detail: "A heartbeat goes to the bracelet as one message, so it beats steadily instead of drifting.", go: .route(.home)),
            Item(icon: "person.wave.2.fill", title: "Notifications from your partner",
                 detail: "Touches and kisses arrive as messages from your partner, with their name on top, so Siri can read them out.", go: .notifications),
            Item(icon: "hand.tap.fill", title: "Easier tab bar",
                 detail: "The whole tab takes the tap, at every display size.", go: .displaySize),
        ]),
        Section(title: "Build 71", items: [
            Item(icon: "person.crop.circle.fill", title: "My profile",
                 detail: "Your own page: a line about you, pronouns, birthday and the things you like. Your partners see it, and Us shows both profiles side by side.", go: .profile),
            Item(icon: "heart.fill", title: "Feel their pulse",
                 detail: "Tap a partner's pulse to feel it on your bracelet, phone and watch.", go: .partner),
            Item(icon: "textformat.size", title: "Display size",
                 detail: "Everything is a little smaller by default; Settings → Display size has Smaller, Small and Standard.", go: .displaySize),
            Item(icon: "sparkles", title: "totwoo jewellery",
                 detail: "Pair a totwoo piece and your partners' touches light it in their colour.", go: .totwoo),
        ]),
        Section(title: "Build 70", items: [
            Item(icon: "bolt.horizontal.fill", title: "Lighter syncing with Android partners",
                 detail: "Partners paired across iPhone and Android sync only what changed, using far less.", go: .people),
        ]),
        Section(title: "Build 69", items: [
            Item(icon: "iphone.gen3.radiowaves.left.and.right", title: "Pair with Android",
                 detail: "New pairings work with partners on Android, and without iCloud. Existing partners carry on as before.", go: .people),
        ]),
        Section(title: "Build 68", items: [
            Item(icon: "chart.xyaxis.line", title: "Charts show the last reading",
                 detail: "Stress & mood charts end at the last reading, with its date and time, and show heart rate. A partner's last report stays until a new one replaces it.", go: .route(.us("stress"))),
        ]),
        Section(title: "Build 67", items: [
            Item(icon: "waveform.path.ecg.rectangle.fill", title: "Everyone's HRV on one chart",
                 detail: "Your partners' heart-rate variability together, with smooth lines that no longer swing between readings.", go: .route(.us("stress"))),
        ]),
        Section(title: "Build 66", items: [
            Item(icon: "applewatch", title: "Watch stand-in, your choice",
                 detail: "Stand-in mode is opt-in and ends itself after an hour. The watch app only comes forward once, when a connected bracelet drops off."),
        ]),
        Section(title: "Build 65", items: [
            Item(icon: "map.fill", title: "Map fixed",
                 detail: "A crash around partner pins on the map is gone.", go: .route(.map)),
        ]),
        Section(title: "Build 64", items: [
            Item(icon: "sparkles", title: "What's new stays out of the way",
                 detail: "It no longer pops up after updates. It's always in Settings → What's new."),
        ]),
        Section(title: "Build 63", items: [
            Item(icon: "dot.radiowaves.left.and.right", title: "Partners stay live",
                 detail: "Partners show online while the app is in the background, refresh when you open it, and show when their last reading was taken.", go: .route(.map)),
        ]),
        Section(title: "Build 62", items: [
            Item(icon: "applewatch.radiowaves.left.and.right", title: "Smoother touches on the watch",
                 detail: "A received touch held in one place plays as one steady vibration."),
        ]),
        Section(title: "Build 61", items: [
            Item(icon: "hand.point.up.left.fill", title: "Feel it while you draw on the watch",
                 detail: "One steady vibration while your finger is on the watch's touch bar."),
        ]),
        Section(title: "Build 60", items: [
            Item(icon: "location.fill", title: "Location like Find My",
                 detail: "Low-power location in the background with a fresh fix when it's asked for, so sharing costs far less battery.", go: .route(.map)),
        ]),
        Section(title: "Build 59", items: [
            Item(icon: "chart.line.uptrend.xyaxis", title: "Stress as a filled line",
                 detail: "The stress chart is a filled line, and the watch pages use the whole screen.", go: .route(.us("stress"))),
        ]),
        Section(title: "Earlier", items: [
            Item(icon: "person.3.sequence.fill", title: "Room for up to 10 partners",
                 detail: "With more than three, the others gather in a cluster on the partner bar — tap it and everyone bursts out around it to pick from."),
            Item(icon: "rainbow", title: "Rainbow wave",
                 detail: "In Touch Language: a light that runs up and down the bar through the whole rainbow. Feel it, or send it — partners on this update see the rainbow too."),
            Item(icon: "hand.tap.fill", title: "Feel what you send",
                 detail: "The phone buzzes under your finger while you draw a touch — sharper toward the end of the bar — and knocks twice when it's sent."),
            Item(icon: "applewatch.radiowaves.left.and.right", title: "Watch notifications you notice",
                 detail: "The chime, then the touch itself — the watch's motor driven directly in the touch's exact rhythm."),
            Item(icon: "waveform.path.ecg", title: "Heartbeats you feel, not hear",
                 detail: "No more beep: heartbeats are haptics only, and draw like a heart monitor as they play — on the card too."),
            Item(icon: "scope", title: "Touch Language recognises your touches",
                 detail: "A touch with the same general shape as a saved one now counts as it — a bit early, late, faster or slower is fine."),
            Item(icon: "pencil.and.scribble", title: "Edit saved touches",
                 detail: "Tap a saved touch (or its pencil) to change its name, emoji and colours, and draw its pattern with your finger."),
            Item(icon: "arrow.up.forward.app.fill", title: "Notifications open the right place",
                 detail: "Tapping a notification opens what it's about, for the partner it's from: the chat, the game, the to-do list, the note, your dates, Stress & mood, or Home for a touch."),
            Item(icon: "bell.slash.fill", title: "Quiet while you're in the app",
                 detail: "With the app open — playing a game or anything else — notifications stay quiet; touches still play. Only a chat message shows, and not for the chat you're reading."),
            Item(icon: "heart.circle", title: "The kiss button",
                 detail: "On Home next to the heartbeat: one tap sends a kiss."),
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
                 detail: "This screen, any time from Settings."),
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
                                    .font(.system(size: Theme.s(18), weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                                    Text(item.detail).font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let go = item.go { showMe(go, item.title).padding(.top, 4) }
                                }
                            }
                            .accessibilityElement(children: .contain)
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
        .sheet(isPresented: $showPartner) {
            if let p = model.selectedPartner { PartnerDetailView(partnerID: p.id) }
        }
    }

    private func showMeLabel() -> some View {
        HStack(spacing: 4) {
            Text("Show me")
            Image(systemName: "arrow.right")
        }
        .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Theme.accent.opacity(0.14)))
        .contentShape(Capsule())
    }

    /// A button that opens the feature: a pushed screen, the partner's page, or a tab.
    @ViewBuilder private func showMe(_ go: Go, _ title: String) -> some View {
        switch go {
        case .route(let route):
            Button {
                dismiss()
                model.route = route
            } label: { showMeLabel() }
            .buttonStyle(.plain).accessibilityLabel("Show me \(title)")
        case .partner:
            if model.selectedPartner != nil {
                Button { showPartner = true } label: { showMeLabel() }
                    .buttonStyle(.plain).accessibilityLabel("Show me \(title)")
            }
        default:
            NavigationLink { destination(go) } label: { showMeLabel() }
                .buttonStyle(.plain).accessibilityLabel("Show me \(title)")
        }
    }

    @ViewBuilder private func destination(_ go: Go) -> some View {
        switch go {
        case .people: PeopleView().navigationTitle("My people")
        case .profile: MyProfileView().screenBackground()
        case .notifications: NotificationSettingsView().screenBackground()
        case .totwoo: TotwooView().screenBackground()
        case .themes:
            ScrollView { ThemePickerCard().padding(16) }
                .screenBackground().navigationTitle("Themes")
                .onAppear { UserDefaults.standard.set(true, forKey: "themePickerOpen") }
        case .displaySize:
            ScrollView { DisplaySizeCard().padding(16) }
                .screenBackground().navigationTitle("Display size")
        case .route, .partner: EmptyView()
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? ""
        let b = info?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }
}
