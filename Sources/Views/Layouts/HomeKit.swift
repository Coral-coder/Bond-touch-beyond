import MapKit
import SwiftUI
import UIKit

/// The home screen's layout, picked under Settings → Layout. Every layout shows the same
/// things — partners, sending a touch, meanings, the heartbeat, recent touches — arranged
/// differently. Themes and colours apply to all of them.
enum HomeLayout: String, CaseIterable, Identifiable {
    case classic, focus, conversation, bento, deck, timeline, orbit, oneHand, bubbles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .focus: return "Focus Pad"
        case .conversation: return "Conversation"
        case .bento: return "Bento"
        case .deck: return "Partner Deck"
        case .timeline: return "Timeline"
        case .orbit: return "Orbit"
        case .oneHand: return "One-Hand"
        case .bubbles: return "Bubbles"
        }
    }

    var blurb: String {
        switch self {
        case .classic: return "Pair card, touch bar, meanings, history"
        case .focus: return "One big ring you touch directly"
        case .conversation: return "Touches as a message thread"
        case .bento: return "A dashboard of tiles"
        case .deck: return "A card per person, swipe between"
        case .timeline: return "Your day together on a line"
        case .orbit: return "Your people circling you"
        case .oneHand: return "Every control in thumb reach"
        case .bubbles: return "Everything in floating glossy bubbles"
        }
    }

    var icon: String {
        switch self {
        case .classic: return "rectangle.grid.1x2"
        case .focus: return "circle.circle"
        case .conversation: return "bubble.left.and.bubble.right"
        case .bento: return "square.grid.2x2"
        case .deck: return "rectangle.stack"
        case .timeline: return "point.topleft.down.curvedto.point.bottomright.up"
        case .orbit: return "circle.dotted"
        case .oneHand: return "hand.thumbsup"
        case .bubbles: return "circle.hexagongrid.fill"
        }
    }
}

/// Shows Home in the picked layout.
struct HomeRouter: View {
    @AppStorage("homeLayout") private var layout = HomeLayout.classic.rawValue

    var body: some View {
        switch HomeLayout(rawValue: layout) ?? .classic {
        case .classic: HomeView()
        case .focus: FocusPadHome()
        case .conversation: ConversationHome()
        case .bento: BentoHome()
        case .deck: PartnerDeckHome()
        case .timeline: TimelineHome()
        case .orbit: OrbitHome()
        case .oneHand: OneHandHome()
        case .bubbles: BubbleHome()
        }
    }
}

// MARK: - Shared pieces

extension AppModel {
    func isMine(_ t: TouchMessage) -> Bool { t.senderID == myUserID || t.senderID == ChatMessage.legacySelf }

    /// Touches with `bondID` (the selected partner by default), newest first.
    func recentTouches(with bondID: String? = nil, limit: Int = 40) -> [TouchMessage] {
        guard let id = bondID ?? selectedPartnerID else { return [] }
        return Array(history.filter { $0.bondID == id }.suffix(limit).reversed())
    }

    /// "1,092 km apart", when both locations are known.
    func distanceText(to partner: Partner?) -> String? {
        guard let a = location.coordinate, let lat = partner?.latitude, let lng = partner?.longitude else { return nil }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: lat, longitude: lng))
        return Units.distanceText(meters) + " apart"
    }

    /// "Online · bracelet on" style status for a partner.
    func statusText(_ p: Partner) -> String {
        var parts = [p.online ? "Online" : (p.lastSeen.map { "Seen " + $0.formatted(.relative(presentation: .named)) } ?? "Offline")]
        if p.presence?.watchStandIn == true { parts.append("watch on") }
        else if let b = p.presence?.bracelet { parts.append(b ? "bracelet on" : "bracelet off") }
        return parts.joined(separator: " · ")
    }
}

extension LocalStore {
    /// "12 days until you meet", or nil when no date is set.
    func meetText(for bondID: String?) -> String? {
        guard let date = nextMeeting(for: bondID) else { return nil }
        let cal = Calendar.current
        let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0)
        return days == 0 ? "You meet today" : "\(days) day\(days == 1 ? "" : "s") until you meet"
    }
}

/// A touch drawn: its trace or tap rhythm, or a heartbeat's EKG.
struct TouchGlyph: View {
    let touch: TouchMessage
    var height: CGFloat = 40

    var body: some View {
        if let bpm = touch.heartbeatBPM {
            EKGView(bpm: bpm, colorRGB: touch.colorRGB, lineWidth: max(1.6, height * 0.06)).frame(height: height)
        } else {
            TouchViz(pattern: touch.pattern, generation: touch.generation,
                     colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB, height: height)
        }
    }
}

/// The partner's photo (or initial) with an online dot.
struct PartnerFace: View {
    @EnvironmentObject var model: AppModel
    let partner: Partner
    var size: CGFloat = 44
    var selected = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarRing(name: partner.displayName, ringColor: Color(rgbInt: partner.colorRGB), size: size,
                       photo: model.photo(forBond: partner.id), ringWidth: selected ? nil : 0)
            if partner.online {
                Circle().fill(Theme.lime).frame(width: size * 0.24, height: size * 0.24)
                    .overlay(Circle().stroke(Theme.bgBottom, lineWidth: 1.5))
            }
        }
    }
}

/// Your own photo.
struct MyFace: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    var size: CGFloat = 44

    var body: some View {
        AvatarRing(name: store.profile.name.isEmpty ? "Me" : store.profile.name,
                   ringColor: Color(rgbInt: store.profile.colorRGB), size: size, photo: model.myPhoto)
    }
}

/// One-tap meanings, as a sideways row of chips.
struct MeaningChipRow: View {
    @EnvironmentObject var model: AppModel
    var height: CGFloat = 38

    var body: some View {
        let meanings = model.currentMeanings
        if !meanings.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(meanings) { m in MeaningChip(meaning: m, height: height) }
                }
                .padding(.vertical, 2).padding(.horizontal, 2)
            }
        }
    }
}

struct MeaningChip: View {
    @EnvironmentObject var model: AppModel
    let meaning: TouchMeaning
    var height: CGFloat = 38

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task { await model.sendMeaning(meaning) }
        } label: {
            HStack(spacing: 6) {
                if meaning.emoji.isEmpty {
                    Circle().fill(LinearGradient(colors: [Color(rgbInt: meaning.colorRGB), Color(rgbInt: meaning.endColorRGB)],
                                                 startPoint: .leading, endPoint: .trailing))
                        .frame(width: 12, height: 12)
                } else {
                    Text(meaning.emoji).font(.system(size: 14))
                }
                Text(meaning.label).font(Theme.font(14, .bold)).foregroundStyle(Theme.title).lineLimit(1)
            }
            .padding(.horizontal, 14).frame(height: height)
            .glass(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send \(meaning.label)")
    }
}

/// One tap sends your heartbeat (the heart beats while it goes); long press for options.
struct HeartbeatButton: View {
    @EnvironmentObject var model: AppModel
    var size: CGFloat = 46
    var cornerRadius: CGFloat? = nil
    @State private var showHeart = false
    @State private var note: String?

    var body: some View {
        TimelineView(.animation(paused: !model.sendingHeartbeat)) { ctx in
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(model.sendingHeartbeat ? Theme.pink : Theme.title)
                .scaleEffect(model.sendingHeartbeat ? Self.beat(ctx.date) : 1)
                .frame(width: size, height: size)
                .background(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.sendingHeartbeat else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task {
                if await model.sendHeartbeat() == nil {
                    note = model.statusLine.isEmpty ? "Couldn't send your heartbeat." : model.statusLine
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    note = nil
                }
            }
        }
        .onLongPressGesture { showHeart = true }
        .overlay(alignment: .bottom) {
            if let note {
                Text(note).font(Theme.font(11, .semibold)).foregroundStyle(Theme.title)
                    .fixedSize().padding(8).glass(cornerRadius: 12).offset(y: size * 0.5 + 18)
            }
        }
        .sheet(isPresented: $showHeart) { NavigationStack { HeartView().navigationTitle("Heartbeat") } }
        .accessibilityLabel("Send my heartbeat")
        .accessibilityHint("Long press for heartbeat options")
        .accessibilityAddTraits(.isButton)
    }

    static func beat(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.85) / 0.85
        let lub = t < 0.15 ? sin(t / 0.15 * .pi) * 0.22 : 0
        let dub = t > 0.22 && t < 0.34 ? sin((t - 0.22) / 0.12 * .pi) * 0.12 : 0
        return 1 + CGFloat(lub + dub)
    }
}

/// A touch surface right on the home screen: touch it and the touch records (same 50 ms
/// sampling and window as the full touch bar) and sends to the selected partner when the
/// window runs out — in your colour, or a matching meaning's.
struct InlineTouchPad: View {
    enum Kind { case bar, ring }
    var shape: Kind = .bar
    var title = "Touch"
    var hint = "tap & slide"

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @StateObject private var recorder = TouchBarRecorder()

    var body: some View {
        ZStack {
            switch shape {
            case .bar:
                TouchBarSurface(recorder: recorder, vertical: false,
                                startRGB: store.profile.colorRGB, endRGB: store.profile.colorRGB)
            case .ring:
                RingTouchSurface(recorder: recorder, rgb: store.profile.colorRGB)
            }
            label.allowsHitTesting(false)
        }
        .disabled(model.selectedPartner == nil)
        .opacity(model.selectedPartner == nil ? 0.5 : 1)
        .onAppear {
            recorder.windowSeconds = store.touchWindowSeconds
            recorder.onFinish = { samples in
                let colors = model.closeMeaning(pattern: samples, generation: 3)
                    .map { ($0.colorRGB, $0.endColorRGB) } ?? (store.profile.colorRGB, store.profile.colorRGB)
                Task {
                    await model.sendTouch(pattern: samples, generation: 3, colorRGB: colors.0,
                                          endColorRGB: colors.1, matchMeaning: true)
                }
            }
        }
        .onDisappear { recorder.cancel() }
    }

    @ViewBuilder private var label: some View {
        if recorder.recording {
            Text(String(format: "%.1f", recorder.remaining))
                .font(Theme.font(shape == .ring ? 30 : 16, .heavy)).monospacedDigit().foregroundStyle(Theme.title)
                .opacity(0.8)
        } else {
            VStack(spacing: 2) {
                Text(model.selectedPartner == nil ? "Pick a partner" : title)
                    .font(Theme.font(shape == .ring ? 22 : 16, .heavy)).foregroundStyle(Theme.title)
                Text(hint).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
        }
    }
}

/// A round touch surface: going around the ring is going along the bar (from the bottom,
/// clockwise, position 0 → 8); the middle is the middle of the bar. Two fingers work.
struct RingTouchSurface: View {
    let recorder: TouchBarRecorder
    var rgb: Int

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .stroke(AngularGradient(gradient: Gradient(colors: [Theme.accent, Theme.magenta, Theme.pink, Theme.accent]), center: .center),
                            lineWidth: d * 0.05)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 18)
                Circle().fill(Theme.bgBottom.opacity(0.55)).padding(d * 0.04)
                ForEach(0..<TouchPattern.positions, id: \.self) { i in
                    Circle().fill(Theme.ink.opacity(0.3)).frame(width: 5, height: 5)
                        .position(Self.point(CGFloat(i) / CGFloat(TouchPattern.positions - 1), d: d, inset: d * 0.12))
                }
                RingGlow(fingers: recorder.fingers, rgb: rgb, d: d)
            }
            .frame(width: d, height: d)
            .overlay(RingTouchCatcher { recorder.update($0, at: $1) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel("Touch ring")
        .accessibilityHint("Touch, tap and slide around; the touch is sent when the timer runs out")
    }

    /// Where position `f` (0…1) sits on the ring.
    static func point(_ f: CGFloat, d: CGFloat, inset: CGFloat) -> CGPoint {
        let a = Double.pi / 2 + Double(f) * 2 * .pi * (8.0 / 9.0)   // from the bottom, clockwise, with a gap
        let r = d / 2 - inset
        return CGPoint(x: d / 2 + r * CGFloat(cos(a + .pi / 9)), y: d / 2 + r * CGFloat(sin(a + .pi / 9)))
    }
}

private struct RingGlow: View {
    @ObservedObject var fingers: TouchBarRecorder.Fingers
    var rgb: Int
    var d: CGFloat

    var body: some View {
        ForEach(Array(fingers.positions.enumerated()), id: \.offset) { _, f in
            Circle()
                .fill(RadialGradient(colors: [.white, Color(rgbInt: rgb).opacity(0.9), Color(rgbInt: rgb).opacity(0)],
                                     center: .center, startRadius: 2, endRadius: d * 0.14))
                .frame(width: d * 0.3, height: d * 0.3)
                .position(RingTouchSurface.point(f, d: d, inset: d * 0.12))
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

/// Reports fingers on the ring as bar positions (0…1).
private struct RingTouchCatcher: UIViewRepresentable {
    var onChange: ([CGFloat], TimeInterval) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.isMultipleTouchEnabled = true
        v.isExclusiveTouch = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: CatcherView, context: Context) { uiView.onChange = onChange }

    final class CatcherView: UIView {
        var onChange: (([CGFloat], TimeInterval) -> Void)?
        private var active: [UITouch] = []

        private func report(_ event: UIEvent?) {
            let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2
            let values = active.prefix(2).map { t -> CGFloat in
                let p = t.location(in: self)
                let dx = p.x - c.x, dy = p.y - c.y
                if (dx * dx + dy * dy).squareRoot() < r * 0.28 { return 0.5 }   // the middle
                // Angle measured clockwise from the bottom, past the small gap there.
                var a = atan2(Double(dy), Double(dx)) - .pi / 2 - .pi / 9
                while a < 0 { a += 2 * .pi }
                return CGFloat(min(1, a / (2 * .pi * 8 / 9)))
            }
            onChange?(Array(values), event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2
            return hypot(point.x - c.x, point.y - c.y) <= r
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            active += touches.filter { !active.contains($0) }; report(event)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.removeAll { touches.contains($0) }; report(event)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
    }
}

/// A small round glass button with an icon.
struct RoundIconButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.37, weight: .semibold)).foregroundStyle(Theme.title)
                .frame(width: size, height: size).glass(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The sheets every layout can open: people, a partner's details, the full touch bar.
struct HomeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var people: Bool
    @Binding var partner: Bool
    @Binding var compose: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $people) { NavigationStack { PeopleView().navigationTitle("People") } }
            .sheet(isPresented: $partner) { if let p = model.selectedPartner { PartnerDetailView(partnerID: p.id) } }
            .fullScreenCover(isPresented: $compose) { ComposeTouchView() }
    }
}
