import PhotosUI
import SwiftUI

/// Settings — profile header plus a list of sections, matching the original's layout.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Settings").font(.title3.bold()).foregroundStyle(.white).padding(.top, 10)

                MyPhotoPicker(size: 110)
                if model.myPhoto == nil, model.legacySignedIn, FirebaseStorage.appCheckBlocked {
                    Text("Bond Touch's servers won't hand your photo to any app but theirs. Tap your picture and choose the same photo once — it's then shared with your partners.")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                }
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
                    row("Bracelet firmware (recovery)", "") { FirmwareSettingsView() }
                    row("Tutorials", "") { HelpView() }
                    row("Do not disturb", "") { DoNotDisturbView() }
                    row("My people", "") { PeopleView().navigationTitle("My people") }
                    row("Private Space", "") { PrivateSpaceView() }
                    row("Help & Support", "") { HelpView() }
                    row("Bracelet notifications", "") { BraceletNotificationsView() }
                    row("Bond Touch account (beta)", "") { LegacyLoginView() }
                    languageRow
                    AppIconPicker()
                    GlassCard(padding: 20) {
                        Toggle(isOn: Binding(get: { store.keepAliveInBackground },
                                             set: { store.keepAliveInBackground = $0; model.updateKeepAlive() })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stay connected in background").foregroundStyle(.white)
                                Text("Receive and send touches with the phone locked. Needed for partners on the original app; shows the location indicator.")
                                    .font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                        .tint(Theme.accent)
                    }
                    GlassCard(padding: 20) {
                        Stepper(value: $store.touchWindowSeconds, in: 5...10, step: 1) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Touch window: \(Int(store.touchWindowSeconds)) s").foregroundStyle(.white)
                                Text("Time to tap and slide on the touch bar before it sends")
                                    .font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                    }
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

/// Switches the home-screen icon between the new heart-and-infinity icon and the original.
struct AppIconPicker: View {
    @State private var current = UIApplication.shared.alternateIconName

    private let options: [(name: String?, label: String, preview: String)] = [
        (nil, "New", "IconPreviewNew"),
        ("AppIconClassic", "Classic", "IconPreviewClassic"),
    ]

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("App icon").foregroundStyle(.white)
                HStack(spacing: 20) {
                    ForEach(options, id: \.label) { option in
                        Button { choose(option.name) } label: {
                            VStack(spacing: 6) {
                                Image(option.preview).resizable().scaledToFit()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(current == option.name ? Theme.accent : .clear, lineWidth: 3))
                                Text(option.label).font(.caption)
                                    .foregroundStyle(current == option.name ? Theme.accent : Theme.subtitle)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label) app icon")
                        .accessibilityAddTraits(current == option.name ? .isSelected : [])
                    }
                    Spacer()
                }
            }
        }
    }

    private func choose(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons, name != current else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil { DispatchQueue.main.async { current = name } }
        }
    }
}

/// Your avatar; tap it to choose, change or remove your profile photo. The photo is shared
/// with your partners.
struct MyPhotoPicker: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    var size: CGFloat
    @State private var item: PhotosPickerItem?
    @State private var showOptions = false
    @State private var showPicker = false

    var body: some View {
        Button {
            if model.myPhoto == nil { showPicker = true } else { showOptions = true }
        } label: {
            AvatarRing(name: store.profile.name.isEmpty ? "Me" : store.profile.name,
                       ringColor: Color(rgbInt: store.profile.colorRGB), size: size, photo: model.myPhoto)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill").font(.system(size: size * 0.13, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: size * 0.3, height: size * 0.3)
                        .background(Circle().fill(Theme.accent))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.myPhoto == nil ? "Add a profile photo" : "Change your profile photo")
        .photosPicker(isPresented: $showPicker, selection: $item, matching: .images)
        .confirmationDialog("Profile photo", isPresented: $showOptions) {
            Button("Choose a new photo") { showPicker = true }
            Button("Remove photo", role: .destructive) { model.removeMyPhoto() }
        }
        .onChange(of: item) { picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    model.setMyPhoto(image)
                }
                item = nil
            }
        }
    }
}
