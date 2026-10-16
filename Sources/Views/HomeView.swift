import MapKit
import SwiftUI

/// Home: the selected partner on a map with you ("Hello, this is us", days until you meet,
/// distance apart), the touch bar — send a touch with or without a bracelet — quick-send
/// Touch Language chips, and the feed of recent touches drawn as 2D traces.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    // Not observed here: only the touch bar card redraws while a touch is recorded.
    @State private var recorder = TouchBarRecorder()
    @State private var showHeart = false
    @State private var showPeople = false
    @State private var showEncounters = false
    @State private var showCompose = false
    @State private var showPartner = false
    @State private var editingGreeting = false
    @State private var greetingDraft = ""

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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    pairCard
                    HomeTouchBarCard(recorder: recorder, showCompose: $showCompose)
                    meaningChips
                    feed
                    Color.clear.frame(height: 96) // room for the floating tab bar
                }
                .padding(.horizontal, 18)
            }
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
        .onAppear { configureRecorder() }
        .onChange(of: store.touchWindowSeconds) { recorder.windowSeconds = $0 }
    }

    private func configureRecorder() {
        recorder.windowSeconds = store.touchWindowSeconds
        recorder.onFinish = { samples in
            Task {
                await model.sendTouch(pattern: samples, generation: 3,
                                      colorRGB: store.profile.colorRGB, endColorRGB: store.profile.colorRGB)
            }
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

    // MARK: Meanings

    @ViewBuilder private var meaningChips: some View {
        let meanings = model.currentMeanings
        if !meanings.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(meanings) { m in
                        Button {
                            Task {
                                await model.sendTouch(pattern: m.pattern, generation: m.touchGeneration,
                                                      colorRGB: m.colorRGB, endColorRGB: m.endColorRGB)
                            }
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

    @ViewBuilder private var feed: some View {
        if !model.history.isEmpty {
            Text("Recent touches").font(Theme.font(15, .heavy)).foregroundStyle(Theme.mutedHeadline)
                .padding(.horizontal, 4).padding(.top, 4)
            ForEach(model.history.suffix(40).reversed()) { touch in
                touchRow(touch)
            }
        }
    }

    private func touchRow(_ touch: TouchMessage) -> some View {
        let mine = touch.senderID == model.myUserID || touch.senderID == ChatMessage.legacySelf
        return HStack(spacing: 12) {
            TouchViz(pattern: touch.pattern, generation: touch.generation,
                     colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB, height: 36)
            VStack(alignment: .trailing, spacing: 2) {
                Text(mine ? "You" : (partner?.displayName ?? "Partner"))
                    .font(Theme.font(12, .bold)).foregroundStyle(.white)
                Text(touch.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            Button { model.bracelet.play(touch) } label: {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play on bracelet")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glass(cornerRadius: 22)
    }
}

/// The Home touch bar, with its countdown and live trace while a touch is recorded.
private struct HomeTouchBarCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @ObservedObject var recorder: TouchBarRecorder
    @Binding var showCompose: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Touch bar").font(Theme.font(17, .heavy)).foregroundStyle(.white)
                Spacer()
                if recorder.recording {
                    Button("Send now") { recorder.finish() }
                        .font(Theme.font(13, .heavy)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().fill(Theme.accent))
                    CountdownRing(progress: recorder.progress, remaining: recorder.remaining, size: 34)
                } else {
                    Text(model.braceletState == .connected ? "Bracelet connected" : "No bracelet needed")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.14)))
                    Button { showCompose = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.14)))
                    }
                    .accessibilityLabel("Open the full touch bar")
                }
            }
            TouchBarSurface(recorder: recorder, vertical: false,
                            startRGB: store.profile.colorRGB, endRGB: store.profile.colorRGB)
                .frame(height: 72)
            if recorder.recording {
                TouchViz(pattern: recorder.samples, generation: 3,
                         colorRGB: store.profile.colorRGB, height: 34)
            } else {
                Text("Touch to start · tap and slide for \(Int(store.touchWindowSeconds)) s · sends when time's up")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .glass(cornerRadius: 28)
        .disabled(model.selectedPartner == nil)
        .opacity(model.selectedPartner == nil ? 0.5 : 1)
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
