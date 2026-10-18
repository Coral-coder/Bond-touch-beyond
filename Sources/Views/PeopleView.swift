import SwiftUI

/// "My people" — accepted partners, any pending invites you created, and a way to add more.
/// A pending invite (a share no one has accepted) is shown separately and can be cancelled;
/// it is never treated as an active partner.
struct PeopleView: View {
    @EnvironmentObject var model: AppModel
    @State private var reordering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(model.incomingInvites) { bond in
                    inviteRow(bond)
                }

                if model.partners.isEmpty && model.pendingBonds.isEmpty && model.incomingInvites.isEmpty {
                    Text("You haven't added a partner yet.")
                        .foregroundStyle(Theme.subtitle)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 50)
                }

                if model.partners.count > 1 {
                    HStack {
                        Spacer()
                        Button { reordering = true } label: {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                                .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                        }
                        .accessibilityHint("Choose the order of your partners")
                    }
                }
                if !model.partners.isEmpty {
                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.partners.enumerated()), id: \.element.id) { index, partner in
                                partnerRow(partner)
                                if index < model.partners.count - 1 {
                                    Divider().overlay(Theme.ink.opacity(0.08)).padding(.leading, 60)
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
                            Text("Add a partner").foregroundStyle(Theme.title)
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
        .sheet(isPresented: $reordering) { ReorderPartnersSheet() }
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
                Text(partner.displayName).foregroundStyle(Theme.title)
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
                Circle().fill(Theme.ink.opacity(0.12)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "hourglass").foregroundStyle(Theme.subtitle))
                VStack(alignment: .leading, spacing: 2) {
                    Text(bond.legacy ? bond.partnerName : "Pending invite").foregroundStyle(Theme.title)
                    Text(bond.legacy ? "Invite sent · waiting for them to accept" : "Waiting for your partner to accept")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                Button(role: .destructive) { Task { await model.removeBond(bond) } } label: {
                    Text("Cancel").foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A bond invite another original-app user sent to this account.
    private func inviteRow(_ bond: Bond) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Circle().fill(Theme.accent.opacity(0.25)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "envelope.fill").foregroundStyle(Theme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bond.partnerName).foregroundStyle(Theme.title)
                        Text("wants to bond with you").font(.caption).foregroundStyle(Theme.subtitle)
                    }
                    Spacer()
                }
                HStack(spacing: 12) {
                    Button { Task { await model.legacyAccept(bond) } } label: {
                        Text("Accept").font(.headline).frame(maxWidth: .infinity).frame(height: 40)
                            .background(Theme.accent).foregroundStyle(Theme.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
                    }
                    Button { Task { await model.removeBond(bond) } } label: {
                        Text("Decline").font(.headline).frame(maxWidth: .infinity).frame(height: 40)
                            .background(Theme.ink.opacity(0.08)).foregroundStyle(Theme.title)
                            .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
                    }
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

/// Drag partners into the order you like (top first). Home's partner bar, the lists and the
/// bracelet's partner slots follow it — the partner on top is slot 1.
private struct ReorderPartnersSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var order: [Partner] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { p in
                        HStack(spacing: 12) {
                            AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB), size: 36,
                                       photo: model.photo(forBond: p.id), ringWidth: 2)
                            Text(p.displayName).font(Theme.font(16, .bold))
                        }
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag to reorder. The partner at the top is slot 1 on your bracelet.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder partners")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.reorderPartners(order.map(\.id)); dismiss() }
                }
            }
        }
        .onAppear { order = model.partners }
        .preferredColorScheme(Theme.colorScheme)
    }
}
