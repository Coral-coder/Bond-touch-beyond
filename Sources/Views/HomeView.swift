import MapKit
import SwiftUI

/// Home: the selected partner on a map with you ("Hello, this is us", days until you meet,
/// distance apart), the touch bar — send a touch with or without a bracelet — quick-send
/// Touch Language chips, and the feed of recent touches drawn as 2D traces.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showHeart = false
    @State private var kissSent = false
    @State private var showMoodCheckIn = false
    /// A heartbeat send's problem (no heart rate, no partner…), shown briefly under the top bar.
    @State private var heartNote: String?
    @State private var showPeople = false
    @State private var showEncounters = false
    @State private var showCompose = false
    @State private var showPartner = false
    @State private var editingGreeting = false
    @State private var greetingDraft = ""
    @State private var meaningFromTouch: TouchMessage?
    @State private var meaningName = ""
    @State private var editingCards = false
    /// The cards on this home, in order (arranged from the cards button).
    @AppStorage(HomeCard.key) private var cardsRaw = ""

    private var partner: Partner? { model.selectedPartner }

    private var daysToNextMeeting: Int? {
        guard let date = store.nextMeeting(for: model.selectedPartnerID) else { return nil }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                         to: cal.startOfDay(for: date)).day ?? 0)
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar
                .overlay(alignment: .bottom) {
                    if let heartNote {
                        Text(heartNote)
                            .font(Theme.font(12, .semibold)).foregroundStyle(Theme.title)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .glass(cornerRadius: 16)
                            .padding(.horizontal, 24)
                            .offset(y: 46)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(1)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: heartNote)
            // Your cards, in your order; only Recent touches scrolls (and takes the room left).
            let cards = HomeCard.decode(cardsRaw)
            ForEach(cards) { card($0) }
            if !cards.contains(.feed) { Spacer(minLength: 0) }
        }
        .padding(.bottom, TabBarSpace.fixed)
        .sheet(isPresented: $editingCards) { HomeCardsEditor() }
        .sheet(isPresented: $showMoodCheckIn) { MoodCheckInSheet() }
        .sheet(isPresented: $showHeart) {
            NavigationStack { HeartView().navigationTitle("Heartbeat") }
        }
        .sheet(isPresented: $showPeople) {
            NavigationStack { PeopleView().navigationTitle("People") }
        }
        .sheet(isPresented: $showEncounters) {
            EncountersView(bondID: model.selectedPartnerID)
        }
        .sheet(isPresented: $showPartner) {
            if let partner { PartnerDetailView(partnerID: partner.id) }
        }
        .fullScreenCover(isPresented: $showCompose) { ComposeTouchView() }
        .sheet(isPresented: $editingGreeting) {
            GreetingEditor(text: $greetingDraft) {
                model.setGreeting(greetingDraft, for: model.selectedPartnerID)
            }
            .presentationDetents([.height(240)])
        }
        .alert("Save as meaning", isPresented: Binding(get: { meaningFromTouch != nil },
                                                       set: { if !$0 { meaningFromTouch = nil } })) {
            TextField("Name, e.g. Love you", text: $meaningName)
            Button("Save") {
                if let t = meaningFromTouch {
                    let pattern = t.generation == 3 ? TouchPattern.trimmed(t.pattern) : t.pattern
                    let m = TouchMeaning(label: meaningName.isEmpty ? "Touch" : String(meaningName.prefix(20)),
                                         emoji: "", colorRGB: t.colorRGB, endColorRGB: t.endColorRGB,
                                         pattern: pattern, isNew: true, generation: t.generation)
                    Task { await model.addMeaning(m) }
                }
                meaningName = ""
                meaningFromTouch = nil
            }
            Button("Cancel", role: .cancel) { meaningFromTouch = nil }
        } message: {
            Text("Save this touch to your Touch Language so you can send it again with one tap.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Heartbeat, mood and kiss share one pill, so the partners get the room.
            HStack(spacing: 0) {
                heartButton
                if Feature.stress.isOn {
                    Button { showMoodCheckIn = true } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                            .frame(width: 38, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mood check-in")
                }
                kissButton
            }
            .padding(.horizontal, 4)
            .glass(Capsule())
            Spacer(minLength: 0)
            PartnerBar()
            Spacer(minLength: 0)
            Menu {
                Button { editingCards = true } label: { Label("Arrange home cards", systemImage: "square.grid.2x2") }
                Button { showPeople = true } label: { Label("People", systemImage: "person.2") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.title)
                    .frame(width: 44, height: 44)
                    .glass(Circle())
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// One tap sends your heartbeat (the icon beats while it goes); a long press opens the
    /// heartbeat screen.
    private var heartButton: some View {
        TimelineView(.animation(paused: !model.sendingHeartbeat)) { ctx in
            Image(systemName: "heart.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.sendingHeartbeat ? Theme.pink : Theme.title)
                .scaleEffect(model.sendingHeartbeat ? heartScale(ctx.date) : 1)
                .frame(width: 38, height: 44)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.sendingHeartbeat else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task {
                if await model.sendHeartbeat() == nil {
                    heartNote = model.statusLine.isEmpty ? "Couldn't send your heartbeat." : model.statusLine
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    heartNote = nil
                }
            }
        }
        .onLongPressGesture { showHeart = true }
        .accessibilityLabel("Send my heartbeat")
        .accessibilityHint("Long press for heartbeat options")
        .accessibilityAddTraits(.isButton)
    }

    /// Sends a kiss: the partner's phone (and watch) plays just the kiss sound, "Thinking of you".
    private var kissButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task {
                if await model.sendKiss() {
                    kissSent = true
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    kissSent = false
                } else {
                    heartNote = model.statusLine
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    heartNote = nil
                }
            }
        } label: {
            Text(kissSent ? "✓" : "💋")
                .font(.system(size: 18))
                .foregroundStyle(Theme.title)
                .frame(width: 38, height: 44)
                .scaleEffect(kissSent ? 1.12 : 1)
                .animation(.spring(response: 0.3), value: kissSent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send a kiss")
    }

    /// Lub-dub size while sending.
    private func heartScale(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.85) / 0.85
        let lub = t < 0.15 ? sin(t / 0.15 * .pi) * 0.22 : 0
        let dub = t > 0.22 && t < 0.34 ? sin((t - 0.22) / 0.12 * .pi) * 0.12 : 0
        return 1 + CGFloat(lub + dub)
    }

    // MARK: Pair card (map + greeting)

    private var myCoordinate: CLLocationCoordinate2D? { model.location.coordinate }

    private var partnerCoordinate: CLLocationCoordinate2D? {
        guard let lat = partner?.latitude, let lng = partner?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var distanceText: String? {
        guard let a = myCoordinate, let b = partnerCoordinate else { return nil }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        return Units.distanceText(meters) + " apart"
    }

    private var pairCard: some View {
        ZStack(alignment: .bottom) {
            pairBackdrop
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            greetingDraft = store.greeting(for: model.selectedPartnerID)
                            editingGreeting = true
                        } label: {
                            Text(store.greeting(for: model.selectedPartnerID))
                                .font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                                .multilineTextAlignment(.leading).lineLimit(2)
                                .shadow(color: .black.opacity(0.5), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit the greeting")
                        Button { showEncounters = true } label: {
                            Text(meetText).font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
                        }
                        .buttonStyle(.plain)
                        TogetherChip().padding(.top, 4)
                    }
                    Spacer()
                    if let distanceText {
                        Text(distanceText).font(Theme.font(13, .bold)).foregroundStyle(Theme.subtitle)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, Theme.bgBottom.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
        .frame(height: 200)
        .overlay(alignment: .topTrailing) {
            if partner != nil {
                Button { showPartner = true } label: {
                    Image(systemName: "info").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.title)
                        .frame(width: 34, height: 34).glass(Circle())
                }
                .buttonStyle(.plain).padding(12)
                .accessibilityLabel("Partner details")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glass(cornerRadius: 28)
    }

    private var meetText: String {
        guard let days = daysToNextMeeting else { return "When do you meet next?" }
        return days == 0 ? "You meet today" : "\(days) day\(days == 1 ? "" : "s") until you meet"
    }

    @ViewBuilder private var pairBackdrop: some View {
        let me = AvatarRing(name: store.profile.name.isEmpty ? "Me" : store.profile.name,
                            ringColor: Color(rgbInt: store.profile.colorRGB), size: 52, photo: model.myPhoto)
        if let a = myCoordinate, let b = partnerCoordinate, let partner {
            PairMap(me: a, partner: b, meView: AnyView(me),
                    partnerView: AnyView(partnerAvatar(partner, size: 56)))
        } else {
            HStack(spacing: -12) {
                me
                if let partner {
                    Button { showPartner = true } label: { partnerAvatar(partner, size: 76) }
                        .buttonStyle(.plain)
                } else {
                    Button { showPeople = true } label: {
                        ZStack {
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .foregroundStyle(Theme.subtitle)
                            Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.title)
                        }
                        .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a partner")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 60)
        }
    }

    private func partnerAvatar(_ p: Partner, size: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB), size: size,
                       photo: model.photo(forBond: p.id))
            if p.online {
                Circle().fill(Theme.lime).frame(width: size * 0.22, height: size * 0.22)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .overlay(alignment: .topTrailing) { MoodBadge(partner: p, size: size).offset(x: size * 0.08, y: -size * 0.06) }
    }

    // MARK: Touch

    /// Opens the full-screen touch bar, where there's room to tap and slide properly.
    private var sendTouchButton: some View {
        Button { showCompose = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap.fill").font(.system(size: 20, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send a touch").font(Theme.font(17, .heavy))
                    Text(partner == nil ? "Pick a partner first"
                         : "Tap and slide on the big bar · \(model.braceletState == .connected ? "bracelet connected" : "no bracelet needed")")
                        .font(Theme.font(12)).foregroundStyle(Theme.onAccent.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 18).frame(height: 66)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.p.accentTop, Theme.accentDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.ink.opacity(0.45), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.25), radius: 10, y: 5)
            )
        }
        .buttonStyle(.plain)
        .disabled(partner == nil)
        .opacity(partner == nil ? 0.5 : 1)
        .accessibilityLabel("Send a touch")
        .accessibilityHint("Opens the full-screen touch bar")
    }

    // MARK: Meanings

    @ViewBuilder private var meaningChips: some View {
        let meanings = model.currentMeanings
        if !meanings.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(meanings) { m in
                        Button {
                            Task { await model.sendMeaning(m) }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(LinearGradient(colors: [Color(rgbInt: m.colorRGB), Color(rgbInt: m.endColorRGB)],
                                                             startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 12, height: 12)
                                Text(m.label).font(Theme.font(14, .bold)).foregroundStyle(Theme.title).lineLimit(1)
                            }
                            .padding(.horizontal, 14).frame(height: 38)
                            .glass(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send \(m.label)")
                    }
                }
                .padding(.vertical, 2)
            }
            .noTabBarGap()
        }
    }

    // MARK: Feed

    /// Touches for the selected partner only, newest first.
    private var partnerHistory: [TouchMessage] {
        guard let id = model.selectedPartnerID else { return [] }
        return Array(model.history.filter { $0.bondID == id }.suffix(40).reversed())
    }

    /// Recent touches — the only scrolling region on Home: a framed glass panel with a fixed
    /// header, and the touches scrolling inside it (clipped to the frame, faded at its edges).
    @ViewBuilder private var feed: some View {
        let touches = partnerHistory
        VStack(alignment: .leading, spacing: 8) {
            if partner != nil {
                HStack {
                    Text("Recent touches with \(partner?.displayName ?? "partner")")
                        .font(Theme.font(15, .heavy)).foregroundStyle(Theme.mutedHeadline)
                    Spacer()
                    if !touches.isEmpty {
                        Label("Swipe to save", systemImage: "hand.draw")
                            .font(Theme.font(11)).foregroundStyle(Theme.subtitle).labelStyle(.titleAndIcon)
                    }
                }
                .padding(.horizontal, 16)
                if !touches.isEmpty { summary(touches).padding(.horizontal, -6) }
            }
            if touches.isEmpty {
                if partner != nil {
                    Text("No touches yet with \(partner?.displayName ?? "partner"). Send one above.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                Spacer(minLength: 0)
            } else {
                // A native list: smooth momentum scrolling, and the system swipe action to save a
                // touch as a meaning (a custom drag on each row fought the scrolling).
                List {
                    ForEach(touches) { touch in
                        touchRow(touch)
                            .modifier(SurfaceBubble(active: true, id: touch.id, sentAt: touch.sentAt,
                                                    colorRGB: touch.colorRGB))
                            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { meaningName = ""; meaningFromTouch = touch } label: {
                                    Label("Meaning", systemImage: "star.fill")
                                }
                                .tint(Theme.accent)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.visible)
                .environment(\.defaultMinListRowHeight, 1)
                .animation(.spring(response: 0.55, dampingFraction: 0.8), value: touches.map(\.id))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // Rows fade out at the frame's top and bottom edges instead of being cut.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                             .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(.top, 14).padding(.bottom, 6)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity, alignment: .top)
        .glass(cornerRadius: 26)
        .padding(.horizontal, 12)
    }

    @ViewBuilder private func card(_ c: HomeCard) -> some View {
        switch c {
        case .pair: pairCard.padding(.horizontal, 18)
        case .send: sendTouchButton.padding(.horizontal, 18)
        case .meanings: meaningChips.padding(.horizontal, 18)
        case .weather: if let partner, Feature.weather.isOn { WeatherButton(partner: partner).padding(.horizontal, 18) }
        case .together: TogetherHomeCard().padding(.horizontal, 18)
        case .feed: feed
        }
    }

    /// "Last sent 5 min ago · Last received 2 hr ago", as the original's history header.
    private func summary(_ touches: [TouchMessage]) -> some View {
        let isMine: (TouchMessage) -> Bool = { $0.senderID == model.myUserID || $0.senderID == ChatMessage.legacySelf }
        let sent = touches.first(where: isMine)?.sentAt
        let received = touches.first(where: { !isMine($0) })?.sentAt
        let missed = touches.filter { !isMine($0) && $0.missed == true }.count
        func ago(_ d: Date?) -> String {
            guard let d else { return "never" }
            return d.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
        var parts = ["Last sent \(ago(sent))", "Last received \(ago(received))"]
        if missed > 0 { parts.append("\(missed) missed") }
        return Text(parts.joined(separator: " · "))
            .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            .padding(.horizontal, 22)
    }

    /// The compact status in a card's corner: a clock while sending, one tick when sent, two
    /// when seen, a red retry when it failed; for a partner's touch, a bell if it was missed.
    @ViewBuilder private func statusMark(_ touch: TouchMessage, mine: Bool) -> some View {
        if mine, let delivery = touch.delivery {
            switch delivery {
            case .sending:
                Image(systemName: "clock").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.subtitle)
                    .accessibilityLabel("Sending")
            case .sent:
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.subtitle)
                    .accessibilityLabel("Sent")
            case .seen:
                HStack(spacing: -4) {
                    Image(systemName: "checkmark"); Image(systemName: "checkmark")
                }
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accent)
                .accessibilityElement(children: .ignore).accessibilityLabel("Seen")
            case .failed:
                Button { Task { await model.resend(touch) } } label: {
                    Label("Retry", systemImage: "exclamationmark.circle.fill")
                        .font(Theme.font(10, .bold)).foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Failed to send. Tap to retry.")
            }
        } else if !mine, touch.missed == true {
            Image(systemName: "bell.slash.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber)
                .accessibilityLabel("Missed: this touch arrived but didn't play")
        }
    }

    /// Sending… / Sent / Seen / Failed (tap to send again), as the original.
    @ViewBuilder private func deliveryLabel(_ touch: TouchMessage, _ delivery: TouchMessage.Delivery) -> some View {
        switch delivery {
        case .sending:
            Text("Sending…").font(Theme.font(10, .semibold)).foregroundStyle(Theme.subtitle)
        case .sent:
            Label("Sent", systemImage: "checkmark").font(Theme.font(10, .semibold)).foregroundStyle(Theme.subtitle)
        case .seen:
            Label("Seen", systemImage: "checkmark.circle.fill").font(Theme.font(10, .semibold)).foregroundStyle(Theme.accent)
        case .failed:
            Button { Task { await model.resend(touch) } } label: {
                Label("Failed · Retry", systemImage: "exclamationmark.circle.fill")
                    .font(Theme.font(10, .bold)).foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Failed to send. Tap to retry.")
        }
    }

    /// Height of a history card; the touch is drawn across all of it.
    private static let rowHeight: CGFloat = 84

    private func touchRow(_ touch: TouchMessage) -> some View {
        let mine = touch.senderID == model.myUserID || touch.senderID == ChatMessage.legacySelf
        let meaning = model.meaningTag(for: touch)
        let h = Self.rowHeight
        return ZStack(alignment: .trailing) {
            // The touch fills the whole card, edge to edge.
            Group {
                if let bpm = touch.heartbeatBPM {
                    EKGView(bpm: bpm, colorRGB: touch.colorRGB, start: model.heartbeatStart(for: touch), lineWidth: 3)
                        .padding(.vertical, 10)
                } else {
                    TouchViz(pattern: touch.pattern, generation: touch.generation,
                             colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: h)
            .overlay(alignment: .topLeading) {
                if let bpm = touch.heartbeatBPM {
                    // A heartbeat is listed as its EKG, with the BPM.
                    Label("\(bpm) BPM", systemImage: "heart.fill")
                        .font(Theme.font(12, .heavy)).foregroundStyle(Theme.title)
                        .shadow(color: Theme.bgBottom, radius: 3)
                        .shadow(color: Theme.bgBottom.opacity(0.8), radius: 6)
                        .padding(12)
                        .accessibilityLabel("Heartbeat, \(bpm) beats per minute")
                }
            }
            .overlay {
                // A touch that is a saved meaning wears its name right across it — just the
                // words, lifted off the drawing by a soft shadow (no pill around them).
                if touch.heartbeatBPM == nil, let meaning {
                    HStack(spacing: 6) {
                        if !meaning.emoji.isEmpty { Text(meaning.emoji).font(.system(size: 17)) }
                        Text(meaning.label).font(Theme.font(16, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.title)
                    .shadow(color: Theme.bgBottom, radius: 2)
                    .shadow(color: Theme.bgBottom.opacity(0.9), radius: 7)
                    .padding(.trailing, 120)   // centred on the part of the card not under the details
                    .accessibilityLabel("Meaning: \(meaning.label)")
                }
            }

            // Who and when, and replay centred on the right, over a soft scrim.
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(mine ? "You" : (partner?.displayName ?? "Partner"))
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                    Text(touch.sentAt.formatted(date: .omitted, time: .shortened))
                        .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                Button { model.feel(touch) } label: {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.title)
                        .frame(width: 32, height: 32).background(Circle().fill(Theme.ink.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play on bracelet")
            }
            .fixedSize()
            .padding(.leading, 28).padding(.trailing, 12)
            .frame(maxHeight: .infinity)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .leading, endPoint: .trailing))
        }
        // Delivered / seen (or missed) in the card's bottom-right corner, clear of the
        // meaning bubble and the play button.
        .overlay(alignment: .bottomTrailing) {
            statusMark(touch, mine: mine)
                .padding(.trailing, 10).padding(.bottom, 5)
        }
        .frame(height: h)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glass(cornerRadius: 22)
    }
}

/// A small non-interactive map framing you and your partner.
struct PairMap: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    let me: CLLocationCoordinate2D
    let partner: CLLocationCoordinate2D
    let meView: AnyView
    let partnerView: AnyView

    private struct Pin: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
    }

    private var region: MKCoordinateRegion {
        let minLat = min(me.latitude, partner.latitude), maxLat = max(me.latitude, partner.latitude)
        let minLng = min(me.longitude, partner.longitude), maxLng = max(me.longitude, partner.longitude)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.8, 0.02),
                                   longitudeDelta: max((maxLng - minLng) * 1.6, 0.02)))
    }

    var body: some View {
        Map(coordinateRegion: .constant(region), interactionModes: [],
            annotationItems: [Pin(id: 0, coordinate: me), Pin(id: 1, coordinate: partner)]) { pin in
            // Map pins are hosted outside this view's hierarchy and don't inherit its
            // environment: hand the model and store on, or a face that reads them
            // (PartnerFace) crashes.
            MapAnnotation(coordinate: pin.coordinate) {
                (pin.id == 0 ? meView : partnerView).environmentObject(model).environmentObject(store)
            }
        }
        .colorScheme(Theme.colorScheme)
        .allowsHitTesting(false)
    }
}

/// Small sheet to edit the per-partner home greeting.
private struct GreetingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let onSave: () -> Void

    static let presets = ["Hey look it's us", "In touch with ourselves", "We're just a touch away",
                          "You complete me", "Better together"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("This greeting shows on Home for this partner.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Greeting", text: $text, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.roundedBorder)
                // The original dashboard's ready-made messages.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.presets, id: \.self) { preset in
                            Button(preset) { text = preset }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(Color.accentColor.opacity(text == preset ? 0.35 : 0.15)))
                                .buttonStyle(.plain)
                        }
                    }
                }
                .noTabBarGap()
                Spacer()
            }
            .padding()
            .navigationTitle("Greeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        }
    }
}

/// Swipe a history row left to reveal a "Save as meaning" action (the feed is a VStack, not
/// a List, so this stands in for `.swipeActions`). A full swipe triggers it; a short swipe
/// reveals the button to tap.
private struct SwipeToSave<Content: View>: View {
    var onSave: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    /// Decided at the start of each drag: sideways swipes reveal the action, anything
    /// else is left to the scroll view.
    @State private var horizontal: Bool?
    private let actionWidth: CGFloat = 92
    private let trigger: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: fire) {
                VStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 16, weight: .bold))
                    Text("Meaning").font(Theme.font(11, .bold))
                }
                .foregroundStyle(Theme.onAccent)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)

            content()
                .offset(x: offset)
                // Simultaneous, so the history list still scrolls (an exclusive drag gesture on a
                // row takes vertical drags away from the scroll view).
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            if horizontal == nil {
                                horizontal = abs(v.translation.width) > abs(v.translation.height) * 1.5
                            }
                            guard horizontal == true else { return }
                            if v.translation.width < 0 { offset = max(v.translation.width, -trigger - 40) }
                            else if offset != 0 { offset = min(0, offset + v.translation.width) }
                        }
                        .onEnded { v in
                            defer { horizontal = nil }
                            guard horizontal == true else { return }
                            if -v.translation.width > trigger { fire() }
                            else {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = -v.translation.width > actionWidth * 0.6 ? -actionWidth : 0
                                }
                            }
                        }
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Save as meaning") { onSave() }
    }

    private func fire() {
        withAnimation(.spring(response: 0.3)) { offset = 0 }
        onSave()
    }
}

/// A touch (or heartbeat) arriving in the history rises into place like a bubble coming up
/// to the surface — floating up from below, swelling slightly, then settling — and sends out
/// ripples in its colour as it "breaks the surface". Only for one that just arrived (seconds
/// old, sent or received), and only once, so scrolling back past it doesn't replay it.
private struct SurfaceBubble: ViewModifier {
    let active: Bool
    let id: UUID
    let sentAt: Date
    let colorRGB: Int

    @State private var risen = false
    @State private var rippling = false
    /// The rings exist only while a new touch ripples in (they used to stay behind as an oval).
    @State private var showRipples = false
    private static var played: Set<UUID> = []

    private var fresh: Bool { active && Date().timeIntervalSince(sentAt) < 15 && !Self.played.contains(id) }

    func body(content: Content) -> some View {
        content
            .scaleEffect(risen ? 1 : 0.82)
            .offset(y: risen ? 0 : 70)
            .opacity(risen ? 1 : 0)
            .background {
                // Ripples: three rings spreading out from the card, one after another.
                if showRipples {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .stroke(Color(rgbInt: colorRGB).opacity(rippling ? 0 : 0.75), lineWidth: rippling ? 1 : 3)
                            .scaleEffect(x: rippling ? 1.25 + CGFloat(i) * 0.12 : 0.9, y: rippling ? 1.9 + CGFloat(i) * 0.35 : 0.9)
                            .animation(.easeOut(duration: 1.3).delay(Double(i) * 0.22), value: rippling)
                    }
                }
                .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard fresh else { risen = true; return }
                Self.played.insert(id)
                showRipples = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { showRipples = false }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { risen = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { rippling = true }
            }
    }
}
