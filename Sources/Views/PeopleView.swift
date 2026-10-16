import SwiftUI

/// "My people" — accepted partners, any pending invites you created, and a way to add more.
/// A pending invite (a share no one has accepted) is shown separately and can be cancelled;
/// it is never treated as an active partner.
struct PeopleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.partners.isEmpty && model.pendingBonds.isEmpty {
                    Text("You haven't added a partner yet.")
                        .foregroundStyle(Theme.subtitle)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 50)
                }

                if !model.partners.isEmpty {
                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.partners.enumerated()), id: \.element.id) { index, partner in
                                partnerRow(partner)
                                if index < model.partners.count - 1 {
                                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 60)
                                }
                            }
                        }
                    }
                }

                ForEach(model.pendingBonds) { bond in
                    pendingRow(bond)
                }

                NavigationLink {
                    PairingView().screenBackground().navigationTitle("Add partner")
                } label: {
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.plus").foregroundStyle(Theme.accent)
                            Text("Add a partner").foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle).font(.footnote)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .screenBackground()
    }

    private func partnerRow(_ partner: Partner) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(Color(rgbInt: partner.colorRGB)).frame(width: 40, height: 40)
                if partner.online {
                    Circle().fill(Theme.lime).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.bgTop, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(partner.displayName).foregroundStyle(.white)
                Text(presenceText(partner)).font(.caption).foregroundStyle(Theme.subtitle)
            }
            Spacer()
            if partner.id == model.selectedPartnerID {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedPartnerID = partner.id }
        .contextMenu {
            Button(role: .destructive) { Task { await model.removeBond(partner.bond) } } label: {
                Label("Remove partner", systemImage: "trash")
            }
        }
    }

    private func pendingRow(_ bond: Bond) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                Circle().fill(Color.white.opacity(0.12)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "hourglass").foregroundStyle(Theme.subtitle))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending invite").foregroundStyle(.white)
                    Text("Waiting for your partner to accept").font(.caption).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                Button(role: .destructive) { Task { await model.removeBond(bond) } } label: {
                    Text("Cancel").foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presenceText(_ p: Partner) -> String {
        if p.online { return "Online now" }
        if let seen = p.lastSeen {
            return "Last seen " + seen.formatted(.relative(presentation: .named))
        }
        return "Offline"
    }
}
