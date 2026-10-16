import SwiftUI

/// Top-center selector showing "me" and the partners as small ringed avatars; tap a partner
/// to make them active. Mirrors the original app's partner pill.
struct PartnerBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        HStack(spacing: -10) {
            smallAvatar(name: store.profile.name.isEmpty ? "Me" : store.profile.name,
                        color: Color(rgbInt: store.profile.colorRGB), active: true)
            ForEach(model.partners) { partner in
                Button { model.selectedPartnerID = partner.id } label: {
                    smallAvatar(name: partner.displayName,
                                color: Color(rgbInt: partner.colorRGB),
                                active: partner.id == model.selectedPartnerID)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func smallAvatar(name: String, color: Color, active: Bool) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.4))
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
        .overlay(Circle().stroke(active ? Theme.accent : .clear, lineWidth: 2.5))
        .shadow(color: active ? Theme.accent.opacity(0.7) : .clear, radius: 6)
    }
}
