import CoreLocation
import MapKit
import SwiftUI

/// A partner's screen: their profile photo (from their account), online status and how
/// far apart you are, plus the option to use their photo — softly blurred — as the app
/// background while they're selected, your colour for them, encounters and unbonding.
struct PartnerDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    let partnerID: String

    @State private var color = Color.white
    @State private var showEncounters = false
    @State private var confirmUnbond = false
    @State private var showShare = false
    @State private var shareError: String?
    @State private var inviting = false

    private var partner: Partner? { model.partners.first { $0.id == partnerID } }
    private var photo: UIImage? { model.photo(forBond: partnerID) }

    private var distance: String? {
        guard let me = model.location.coordinate, let lat = partner?.latitude, let lng = partner?.longitude else { return nil }
        let meters = CLLocation(latitude: me.latitude, longitude: me.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lng))
        return MKDistanceFormatter().string(fromDistance: meters)
    }

    private var useBackground: Binding<Bool> {
        Binding(get: { store.photoBackground(for: partnerID) },
                set: { store.photoBackgrounds[partnerID] = $0 })
    }

    var body: some View {
        ZStack {
            AeroSky().ignoresSafeArea()
            if let photo {
                GeometryReader { geo in
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: store.backgroundSoftness, opaque: true)
                        .scaleEffect(1.08).clipped()
                }
                .ignoresSafeArea()
                LinearGradient(colors: [Theme.bgBottom.opacity(0.15), Theme.bgBottom.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }

            if let partner {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        HStack {
                            Button("Done") { dismiss() }
                                .font(Theme.font(16, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(height: 40).glass(Capsule())
                            Spacer()
                        }

                        AvatarRing(name: partner.displayName, ringColor: Color(rgbInt: partner.colorRGB),
                                   size: 132, photo: photo)
                            .padding(.top, 16)
                        Text(partner.displayName).font(Theme.font(30, .heavy)).foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Circle().fill(partner.online ? Theme.lime : Theme.subtitle.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(statusText(partner)).font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "location.fill").foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(distance ?? "—").font(Theme.font(24, .heavy)).foregroundStyle(.white)
                                Text(distance == nil
                                     ? "Share locations on the Map tab to see the distance"
                                     : "between you").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                            }
                            Spacer()
                        }
                        .padding(16).glass(cornerRadius: 22)

                        connectionCard(partner)

                        VStack(spacing: 0) {
                            Toggle(isOn: useBackground) {
                                Text("Use photo as background").font(Theme.font(16, .bold)).foregroundStyle(.white)
                            }
                            .tint(Theme.accent).disabled(photo == nil)
                            .padding(.vertical, 12)
                            Divider().overlay(.white.opacity(0.15))
                            HStack(spacing: 12) {
                                Text("Softness").font(Theme.font(16, .bold)).foregroundStyle(.white)
                                Slider(value: $store.backgroundSoftness, in: 0...40).tint(Theme.accent)
                            }
                            .padding(.vertical, 12)
                            if photo == nil {
                                Text("\(partner.displayName) has no profile photo yet.")
                                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
                            }
                        }
                        .padding(.horizontal, 16).glass(cornerRadius: 22)

                        HStack(spacing: 10) {
                            ColorPicker(selection: $color, supportsOpacity: false) {
                                Text("Colour").font(Theme.font(14, .bold)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).frame(height: 56).glass(cornerRadius: 20)
                            Button { showEncounters = true } label: {
                                Text("Encounters").font(Theme.font(14, .bold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 56).glass(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                            Button { confirmUnbond = true } label: {
                                Text("Unbond").font(Theme.font(14, .bold)).foregroundStyle(Theme.danger)
                                    .frame(maxWidth: .infinity).frame(height: 56).glass(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                }
            }
        }
        .onAppear { if let partner { color = Color(rgbInt: partner.colorRGB) } }
        .onChange(of: color) { new in
            if new.rgbInt != partner?.colorRGB { model.setPartnerColor(new.rgbInt, for: partnerID) }
        }
        .sheet(isPresented: $showEncounters) { EncountersView(bondID: partnerID) }
        .sheet(isPresented: $showShare) {
            InviteCodeSheet(url: model.pendingInviteURL)
        }
        .alert("Can't invite", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
        .confirmationDialog("Unbond from \(partner?.displayName ?? "this partner")?",
                            isPresented: $confirmUnbond, titleVisibility: .visible) {
            Button("Unbond", role: .destructive) {
                if let bond = partner?.bond { Task { await model.removeBond(bond); dismiss() } }
            }
        }
    }

    /// How this partner syncs: iCloud, or the original servers with an invite to move.
    @ViewBuilder private func connectionCard(_ p: Partner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: p.bond.legacy ? "antenna.radiowaves.left.and.right" : "icloud.fill")
                    .foregroundStyle(p.bond.legacy ? Theme.amber : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.bond.legacy ? "Original Bond Touch app" : "On iCloud")
                        .font(Theme.font(16, .bold)).foregroundStyle(.white)
                    Text(p.bond.legacy
                         ? (model.store.chatLinks[p.id] != nil
                            ? "Invite sent — everything moves to iCloud when they accept"
                            : "Touches sync through the original servers; chat needs iCloud")
                         : "Everything syncs privately through iCloud")
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if p.bond.legacy {
                Button {
                    inviting = true
                    Task {
                        await model.inviteToICloudChat(p.id)
                        inviting = false
                        if let msg = model.iCloudStatus { shareError = msg } else { showShare = model.pendingInviteURL != nil }
                    }
                } label: {
                    HStack {
                        if inviting { ProgressView().tint(Theme.onAccent) }
                        Text(model.store.chatLinks[p.id] != nil ? "Send the iCloud invite again" : "Invite \(p.displayName) to iCloud")
                    }
                }
                .buttonStyle(AccentButtonStyle(height: 46))
                .disabled(inviting)
            }
        }
        .padding(16).glass(cornerRadius: 22)
    }

    private func statusText(_ p: Partner) -> String {
        if p.online { return "Online" }
        if let seen = p.lastSeen { return "Last seen " + seen.formatted(.relative(presentation: .named)) }
        return "Offline"
    }
}
