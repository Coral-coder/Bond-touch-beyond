import SwiftUI

/// The partner selector: one glass pill holding each partner's photo (not yourself),
/// centred, scrolling sideways when there are more than fit. Tap a photo to select that
/// partner; the selected one gets a bright ring. A partner without a photo shows their
/// initial. Tap the bar 5× quickly to open the hidden debug panel.
struct PartnerBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    @State private var taps = 0
    @State private var lastTap = Date.distantPast
    @State private var showDebug = false

    /// Just wide enough for the partners' photos (it scrolls if they don't all fit).
    private var contentWidth: CGFloat {
        model.partners.isEmpty ? 150 : CGFloat(model.partners.count) * 42 + CGFloat(model.partners.count - 1) * 8 + 12
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.partners.isEmpty {
                        Text("No partners yet")
                            .font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                            .padding(.horizontal, 14).frame(height: 40)
                    }
                    ForEach(model.partners) { partner in
                        chip(partner)
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
