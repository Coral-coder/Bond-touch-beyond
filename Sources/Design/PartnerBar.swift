import SwiftUI

/// The partner selector: one glass pill holding each partner's photo (not yourself). Up to
/// three sit side by side; with more, the bar shows the selected partner and a cluster of
/// the others that bursts open on a tap — everyone (up to 10) fanned out around it — to pick
/// from. The selected one gets a bright ring; a partner without a photo shows their initial.
/// Tap the bar 5× quickly to open the hidden debug panel.
struct PartnerBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    @State private var taps = 0
    @State private var lastTap = Date.distantPast
    @State private var showDebug = false
    @State private var burst = false
    /// Where the cluster is on screen, so the burst opens from it.
    @State private var clusterFrame: CGRect = .zero

    /// More than this many partners and the others cluster.
    private static let inline = 3
    private var clustered: Bool { model.partners.count > Self.inline }
    private var selected: Partner? { model.partners.first { $0.id == model.selectedPartnerID } ?? model.partners.first }
    private var others: [Partner] { model.partners.filter { $0.id != selected?.id } }

    /// Just wide enough for the partners' photos (it scrolls if they don't all fit).
    private var contentWidth: CGFloat {
        if model.partners.isEmpty { return 150 }
        if clustered { return 42 + 8 + clusterWidth + 12 }
        return CGFloat(model.partners.count) * 42 + CGFloat(model.partners.count - 1) * 8 + 12
    }
    private var clusterWidth: CGFloat { 36 + 14 * CGFloat(min(3, others.count) - 1) + 8 }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.partners.isEmpty {
                        Text("No partners yet")
                            .font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                            .padding(.horizontal, 14).frame(height: 40)
                    }
                    if clustered, let selected {
                        chip(selected)
                        cluster
                    } else {
                        ForEach(model.partners) { partner in
                            chip(partner)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)   // centred when they fit
            }
        }
        .frame(maxWidth: contentWidth)
        .frame(height: 48)
        .glass(Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded { registerDebugTap() })
        .sheet(isPresented: $showDebug) { DebugView() }
        .fullScreenCover(isPresented: $burst) {
            PartnerBurst(partners: Array(model.partners.prefix(10)), origin: clusterFrame) { picked in
                if let picked { model.selectedPartnerID = picked }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { burst = false }
            }
            .modifier(ClearCoverBackground())
        }
    }

    /// The other partners, stacked, with how many there are; a tap bursts them open.
    private var cluster: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { burst = true }
        } label: {
            ZStack(alignment: .leading) {
                ForEach(Array(others.prefix(3).enumerated()), id: \.element.id) { i, p in
                    AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB), size: 36,
                               photo: model.photo(forBond: p.id), ringWidth: 0)
                        .overlay(Circle().stroke(Theme.bgBottom.opacity(0.8), lineWidth: 2))
                        .offset(x: CGFloat(i) * 14)
                        .zIndex(Double(3 - i))
                }
            }
            .frame(width: clusterWidth, height: 42, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Text("\(others.count)")
                    .font(Theme.font(10, .heavy)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Theme.accent))
                    .offset(x: 4, y: -4)
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { clusterFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { clusterFrame = $0 }
            })
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(others.count) more partners")
        .accessibilityHint("Shows everyone to pick from")
    }

    private func chip(_ partner: Partner) -> some View {
        let selected = partner.id == model.selectedPartnerID
        return Button {
            withAnimation(.spring(response: 0.3)) { model.selectedPartnerID = partner.id }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AvatarRing(name: partner.displayName, ringColor: Color(rgbInt: partner.colorRGB),
                           size: 36, photo: model.photo(forBond: partner.id), ringWidth: 0)
                    .overlay(Circle().stroke(selected ? Theme.accent : .clear, lineWidth: 2.5).padding(-3))
                    .opacity(selected ? 1 : 0.75)
                if partner.online {
                    Circle().fill(Theme.lime).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            .frame(width: 42, height: 42)
            .overlay(alignment: .topTrailing) { MoodBadge(partner: partner, size: 36).offset(x: 4, y: -4) }
            .scaleEffect(selected ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(partner.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func registerDebugTap() {
        let now = Date()
        taps = now.timeIntervalSince(lastTap) > 1.5 ? 1 : taps + 1
        lastTap = now
        if taps >= 5 { taps = 0; showDebug = true }
    }
}

/// The partner cluster burst open: everyone fanned out in two rings below the bar (four on
/// the inner ring, up to six on the outer), springing out one after another.
/// Tap someone to pick them; tap anywhere else to fold it back.
private struct PartnerBurst: View {
    @EnvironmentObject var model: AppModel
    let partners: [Partner]
    let origin: CGRect
    let done: (String?) -> Void
    @State private var open = false

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: origin.midX == 0 ? geo.size.width / 2 : origin.midX,
                                 y: origin.midY == 0 ? 80 : origin.midY)
            ZStack {
                Color.black.opacity(open ? 0.35 : 0).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close(nil) }
                ForEach(Array(partners.enumerated()), id: \.element.id) { i, p in
                    let spot = position(i, in: geo.size, from: center)
                    bubble(p)
                        .position(open ? spot : center)
                        .scaleEffect(open ? 1 : 0.3)
                        .opacity(open ? 1 : 0)
                        .animation(.spring(response: 0.38, dampingFraction: 0.7).delay(Double(i) * 0.025), value: open)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { open = true }
    }

    /// Fanned below the bar, centred on the screen: up to four on an inner ring (105 pt out,
    /// 30°–150°), the rest — up to six — on an outer ring (200 pt out, 35°–145°), so the
    /// bubbles never overlap; kept on screen.
    private func position(_ i: Int, in size: CGSize, from c: CGPoint) -> CGPoint {
        let inner = min(4, partners.count)
        let ring = i < inner ? 0 : 1
        let onRing = ring == 0 ? inner : partners.count - inner
        let k = ring == 0 ? i : i - inner
        let radius: CGFloat = ring == 0 ? 105 : 200
        let (from, span): (Double, Double) = ring == 0 ? (30, 120) : (35, 110)
        let t = onRing == 1 ? 0.5 : Double(k) / Double(onRing - 1)
        let angle = (from + span * t) * .pi / 180
        let x = size.width / 2 + CGFloat(cos(angle)) * radius
        let y = c.y + CGFloat(sin(angle)) * radius
        return CGPoint(x: min(max(x, 40), size.width - 40), y: min(max(y, 60), size.height - 60))
    }

    private func bubble(_ p: Partner) -> some View {
        let selected = p.id == model.selectedPartnerID
        return Button { close(p.id) } label: {
            VStack(spacing: 4) {
                AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB), size: 56,
                           photo: model.photo(forBond: p.id), ringWidth: 0)
                    .overlay(Circle().stroke(selected ? Theme.accent : .white.opacity(0.7), lineWidth: selected ? 3 : 1.5).padding(-3))
                    .overlay(alignment: .topTrailing) { MoodBadge(partner: p, size: 56).offset(x: 4, y: -4) }
                    .overlay(alignment: .bottomTrailing) {
                        if p.online {
                            Circle().fill(Theme.lime).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 1.5))
                        }
                    }
                Text(p.displayName).font(Theme.font(12, .bold)).foregroundStyle(.white).lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .frame(maxWidth: 80)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func close(_ picked: String?) {
        if picked != nil { UISelectionFeedbackGenerator().selectionChanged() }
        open = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { done(picked) }
    }
}

/// A full-screen cover that shows what's behind it (iOS 16.4+; earlier it's just dimmed).
private struct ClearCoverBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationBackground(.clear) } else { content }
    }
}
