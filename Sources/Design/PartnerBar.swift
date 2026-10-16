import SwiftUI

/// The partner selector: one glass pill holding a chip per partner (not yourself), scrolling
/// sideways when there are more than fit. Tap a chip to select that partner; the selected
/// one is a bright pill. Tap the bar 5× quickly to open the hidden debug panel.
struct PartnerBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    @State private var taps = 0
    @State private var lastTap = Date.distantPast
    @State private var showDebug = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if model.partners.isEmpty {
                    Text("No partners yet")
                        .font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                        .padding(.horizontal, 14).frame(height: 40)
                }
                ForEach(model.partners) { partner in
                    chip(partner)
                }
            }
            .padding(4)
        }
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
            HStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarRing(name: partner.displayName, ringColor: Color(rgbInt: partner.colorRGB),
                               size: 32, photo: model.photo(forBond: partner.id), ringWidth: 0)
                    if partner.online {
                        Circle().fill(Theme.lime).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
                Text(partner.displayName)
                    .font(Theme.font(14, selected ? .heavy : .bold))
                    .lineLimit(1)
            }
            .padding(.leading, 4).padding(.trailing, 12)
            .frame(height: 40)
            .foregroundStyle(selected ? Theme.onAccent : .white)
            .background(Capsule().fill(selected
                ? AnyShapeStyle(LinearGradient(colors: [.white, Color(rgbInt: 0xDDEFF5)], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Color.clear)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func registerDebugTap() {
        let now = Date()
        taps = now.timeIntervalSince(lastTap) > 1.5 ? 1 : taps + 1
        lastTap = now
        if taps >= 5 { taps = 0; showDebug = true }
    }
}
