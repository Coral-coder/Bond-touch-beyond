import MapKit
import SwiftUI

/// Home: the selected partner on a map with you ("Hello, this is us", days until you meet,
/// distance apart), the touch bar — send a touch with or without a bracelet — quick-send
/// Touch Language chips, and the feed of recent touches drawn as 2D traces.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showHeart = false
    @State private var showPeople = false
    @State private var showEncounters = false
    @State private var showCompose = false
    @State private var showPartner = false
    @State private var editingGreeting = false
    @State private var greetingDraft = ""
    @State private var meaningFromTouch: TouchMessage?
    @State private var meaningName = ""

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
            // Fixed above the feed; only Recent touches scrolls.
            VStack(alignment: .leading, spacing: 14) {
                pairCard
                sendTouchButton
                meaningChips
            }
            .padding(.horizontal, 18)
            feed
        }
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
        HStack(spacing: 10) {
            iconButton("heart.fill", label: "Heartbeat") { showHeart = true }
            PartnerBar()
            iconButton("person.2.fill", label: "People") { showPeople = true }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .glass(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
        return MKDistanceFormatter().string(fromDistance: meters) + " apart"
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
                                .font(Theme.font(22, .heavy)).foregroundStyle(.white)
                                .multilineTextAlignment(.leading).lineLimit(2)
                                .shadow(color: .black.opacity(0.5), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit the greeting")
                        Button { showEncounters = true } label: {
                            Text(meetText).font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
                        }
                        .buttonStyle(.plain)
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
                    Image(systemName: "info").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
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
                            Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
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
                    .fill(LinearGradient(colors: [Color(rgbInt: 0x74D3CB), Theme.accentDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.45), lineWidth: 1))
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
                                Text(m.label).font(Theme.font(14, .bold)).foregroundStyle(.white).lineLimit(1)
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
        }
    }

    // MARK: Feed

    /// Touches for the selected partner only, newest first.
    private var partnerHistory: [TouchMessage] {
        guard let id = model.selectedPartnerID else { return [] }
        return Array(model.history.filter { $0.bondID == id }.suffix(40).reversed())
    }

    /// Recent touches — the only scrolling region on Home. A fixed header, then the list.
    @ViewBuilder private var feed: some View {
        let touches = partnerHistory
        VStack(alignment: .leading, spacing: 10) {
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
                .padding(.horizontal, 22)
            }
            if touches.isEmpty {
                if partner != nil {
                    Text("No touches yet with \(partner?.displayName ?? "partner"). Send one above.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(touches) { touch in
                            SwipeToSave(onSave: { meaningName = ""; meaningFromTouch = touch }) {
                                touchRow(touch)
                            }
                        }
                        Color.clear.frame(height: 96) // room for the floating tab bar
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func touchRow(_ touch: TouchMessage) -> some View {
        let mine = touch.senderID == model.myUserID || touch.senderID == ChatMessage.legacySelf
        let meaning = model.meaningTag(for: touch)
        return HStack(spacing: 12) {
            Group {
                if let bpm = touch.heartbeatBPM {
                    // A heartbeat is listed as its EKG, with the BPM.
                    EKGView(bpm: bpm, colorRGB: touch.colorRGB)
                        .frame(height: 64)
                        .overlay(alignment: .topLeading) {
                            Label("\(bpm) BPM", systemImage: "heart.fill")
                                .font(Theme.font(12, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.45)))
                                .accessibilityLabel("Heartbeat, \(bpm) beats per minute")
                        }
                } else {
                    TouchViz(pattern: touch.pattern, generation: touch.generation,
                             colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB, height: 64)
                }
            }
                .frame(maxWidth: .infinity)
                .overlay {
                    // A touch that is a saved meaning wears its name right across it.
                    if touch.heartbeatBPM == nil, let meaning {
                        HStack(spacing: 6) {
                            if !meaning.emoji.isEmpty { Text(meaning.emoji).font(.system(size: 17)) }
                            Text(meaning.label).font(Theme.font(16, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .overlay(Capsule().stroke(Color(rgbInt: touch.colorRGB).opacity(0.9), lineWidth: 1.5))
                        .shadow(color: Color(rgbInt: touch.colorRGB).opacity(0.6), radius: 8)
                        .accessibilityLabel("Meaning: \(meaning.label)")
                    }
                }
            VStack(alignment: .trailing, spacing: 2) {
                Text(mine ? "You" : (partner?.displayName ?? "Partner"))
                    .font(Theme.font(12, .bold)).foregroundStyle(.white)
                Text(touch.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                Button { model.feel(touch) } label: {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play on bracelet")
                .padding(.top, 2)
            }
            .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glass(cornerRadius: 22)
    }
}

/// A small non-interactive map framing you and your partner.
private struct PairMap: View {
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
            MapAnnotation(coordinate: pin.coordinate) {
                pin.id == 0 ? meView : partnerView
            }
        }
        .colorScheme(.dark)
        .allowsHitTesting(false)
    }
}

/// Small sheet to edit the per-partner home greeting.
private struct GreetingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("This greeting shows on Home for this partner.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Greeting", text: $text, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.roundedBorder)
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
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            if v.translation.width < 0 { offset = max(v.translation.width, -trigger - 40) }
                            else if offset != 0 { offset = min(0, offset + v.translation.width) }
                        }
                        .onEnded { v in
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
