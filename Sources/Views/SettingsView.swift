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
                           color: Color(rgbInt: store.profile.colorRGB), size: 110)
                Text(store.profile.name.isEmpty ? "Me" : store.profile.name)
                    .font(.title2.bold()).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(connectionText)
                }
                .font(.subheadline).foregroundStyle(Theme.subtitle)

                VStack(spacing: 12) {
                    row("Personal details", "person.text.rectangle") { PersonalDetailsView() }
                    row("My Bond Touch Bracelet", "applewatch") { BraceletSettingsView() }
                    row("Do not disturb", "moon.fill") { DoNotDisturbView() }
                    row("My people", "person.2.fill") { PeopleView().navigationTitle("My people") }
                    row("Private Space", "lock.fill") { ComingSoonView(title: "Private Space") }
                    row("Legacy data", "externaldrive.fill") { LegacyDataView() }
                    row("Help & Support", "questionmark.circle.fill") { ComingSoonView(title: "Help & Support") }
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
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: icon).foregroundStyle(Theme.teal).frame(width: 24)
                    Text(title).foregroundStyle(.white)
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
                        Slider(value: $store.vibrationStrength, in: 0...255, step: 5)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("My Bond Touch Bracelet")
    }
}

private struct DoNotDisturbView: View {
    @EnvironmentObject var store: LocalStore
    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                Toggle("Do not disturb", isOn: $store.doNotDisturb).foregroundStyle(.white).tint(Theme.teal)
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
