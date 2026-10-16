import SwiftUI

/// Settings — profile header plus a list of sections, matching the original's layout.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Settings").font(.title3.bold()).foregroundStyle(.white).padding(.top, 10)

                AvatarRing(name: store.profile.name.isEmpty ? "Me" : store.profile.name,
                           ringColor: Color(rgbInt: store.profile.colorRGB), size: 110)
                Text(store.profile.name.isEmpty ? "Me" : store.profile.name)
                    .font(.title2.bold()).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(connectionText)
                }
                .font(.subheadline).foregroundStyle(Theme.subtitle)

                VStack(spacing: 12) {
                    row("Personal details", "") { PersonalDetailsView() }
                    row("My Bond Touch Bracelet", "") { BraceletSettingsView() }
                    row("Tutorials", "") { HelpView() }
                    row("Do not disturb", "") { DoNotDisturbView() }
                    row("My people", "") { PeopleView().navigationTitle("My people") }
                    row("Private Space", "") { PrivateSpaceView() }
                    row("Help & Support", "") { HelpView() }
                    row("Bracelet notifications", "") { BraceletNotificationsView() }
                    row("Bond Touch account (beta)", "") { LegacyLoginView() }
                    languageRow
                }
                Text("Bond Touch Beyond").font(.caption2).foregroundStyle(Theme.subtitle).padding(.top, 8)
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder private func row<Destination: View>(_ title: String, _ icon: String,
                                                     @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination().screenBackground().navigationBarTitleDisplayMode(.inline)
        } label: {
            GlassCard(padding: 20) {
                HStack(spacing: 14) {
                    Text(title).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle).font(.footnote)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Language is controlled by iOS per-app settings; link straight to them.
    private var languageRow: some View {
        Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
            GlassCard(padding: 20) {
                HStack(spacing: 14) {
                    Text("Language").foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle).font(.footnote)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var connectionText: String {
        switch model.braceletState {
        case .connected: return "Connected"
        case .scanning, .connecting: return "Connecting…"
        case .bluetoothOff: return "Bluetooth off"
        case .disconnected: return "Not connected"
        }
    }
}

private struct PersonalDetailsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var color: Color = .pink
    var body: some View {
        Form {
            TextField("Name", text: $store.profile.name)
            ColorPicker("Your colour", selection: $color)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Personal details")
        .onAppear { color = Color(rgbInt: store.profile.colorRGB) }
        .onChange(of: color) { store.profile.colorRGB = $0.rgbInt; Task { await model.publishProfile() } }
    }
}

private struct BraceletSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ConnectView()
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Vibration strength: \(Int(store.vibrationStrength))").foregroundStyle(.white)
                        Slider(value: $store.vibrationStrength, in: 0...255, step: 5).tint(Theme.accent)
                    }
                }
                Button(role: .destructive) {
                    model.bracelet.disconnect()
                } label: {
                    Text("Disconnect bracelet")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.danger.opacity(0.18))
                        .foregroundStyle(Theme.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                }
            }
            .padding(20)
        }
        .navigationTitle("My Bond Touch Bracelet")
    }
}

/// Toggles whether the bracelet buzzes for app notifications (ANCS in the original).
private struct BraceletNotificationsView: View {
    @AppStorage("braceletNotifications") private var enabled = true
    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                Toggle("Buzz for notifications", isOn: $enabled)
                    .foregroundStyle(.white).tint(Theme.accent)
            }
            Text("When on, your bracelet buzzes for incoming touches and messages.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Spacer()
        }
        .padding(20).navigationTitle("Bracelet notifications")
    }
}

private struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pairing").font(.headline).foregroundStyle(.white)
                Text("Open My Bond Touch Bracelet and tap Connect with the bracelet awake and nearby. The app pairs with BOND, Bond More, BOND 4 and BOND MINI bracelets.")
                    .foregroundStyle(Theme.subtitle)
                Text("Sending a touch").font(.headline).foregroundStyle(.white)
                Text("Tap the rhythm on your bracelet, or send a saved Touch Language meaning. Your partner feels it on theirs.")
                    .foregroundStyle(Theme.subtitle)
            }
            .padding(20)
        }
        .navigationTitle("Help & Support")
    }
}

private struct DoNotDisturbView: View {
    @EnvironmentObject var store: LocalStore
    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                Toggle("Do not disturb", isOn: $store.doNotDisturb).foregroundStyle(.white).tint(Theme.accent)
            }
            Text("When on, incoming touches won't buzz your bracelet.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Spacer()
        }
        .padding(20).navigationTitle("Do not disturb")
    }
}

private struct ComingSoonView: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(Theme.subtitle)
            Text("\(title) is coming soon.").foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle(title)
    }
}
