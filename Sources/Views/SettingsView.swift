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
        .onChange(of: color) {
            store.profile.colorRGB = $0.rgbInt
            model.bracelet.setUserColor($0.rgbInt)
            Task { await model.publishProfile() }
        }
    }
}

private struct BraceletSettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        BraceletSettingsContent(bracelet: model.bracelet)
    }
}

/// The bracelet's own settings, as the original app's bracelet screen: vibration strength
/// (Low / Medium / High / Strong, fine-tunable) and — on a Bond Touch More, with its two
/// motors — the balance between them, each felt on the bracelet as you change it; your
/// colour on the bracelet, previewed live; and the device: battery, charging, firmware.
/// Settings are kept and re-sent every time the bracelet pairs.
private struct BraceletSettingsContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @ObservedObject var bracelet: BraceletManager
    // The bracelet manager stores these; read here so the controls show the saved values.
    @AppStorage("BondVibrationLevel") private var level = 80
    @AppStorage("BondVibrationBalance") private var balance = 2
    @State private var color: Color = .pink
    @State private var previewEnd: Task<Void, Never>?

    /// The original's four steps.
    private struct Preset: Identifiable { let name: String; let level: Int; var id: Int { level } }
    private static let presets = [Preset(name: "Low", level: 33), Preset(name: "Medium", level: 58),
                                  Preset(name: "High", level: 80), Preset(name: "Strong", level: 100)]
    private var levels: [Int] { BondGATT.vibrationLevels }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ConnectView()
                if bracelet.isReady { deviceCard }
                vibrationCard
                colorCard
                Button {
                    bracelet.reconnect()
                } label: {
                    Label(model.braceletState == .connected ? "Reconnect" : "Reconnect now",
                          systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.18))
                        .foregroundStyle(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                }
                Text("If it's stuck on \"Connecting\", tap Reconnect with the bracelet awake and nearby.")
                    .font(.caption).foregroundStyle(Theme.subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    bracelet.disconnect()
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
        .onAppear { color = Color(rgbInt: store.profile.colorRGB) }
        .onDisappear { previewEnd?.cancel(); bracelet.endColorPreview() }
    }

    // MARK: Device

    private var deviceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Device").font(Theme.font(15, .heavy)).foregroundStyle(.white)
                row("Model", bracelet.modelNumber ?? (bracelet.isThirdGeneration ? "Bond Touch More" : "Bond Touch"))
                row("Battery", batteryText)
                row("Firmware", bracelet.firmwareVersion ?? "—")
                if let alert = bracelet.batteryAlert {
                    HStack(spacing: 8) {
                        Text("Battery lights").foregroundStyle(Theme.subtitle)
                        Spacer()
                        Circle().fill(Color(rgbInt: alert.lowRGB)).frame(width: 10, height: 10)
                        Text("low \(alert.lowPercent)%").foregroundStyle(.white)
                        Circle().fill(Color(rgbInt: alert.criticalRGB)).frame(width: 10, height: 10)
                        Text("critical \(alert.criticalPercent)%").foregroundStyle(.white)
                    }
                    .font(Theme.font(13))
                }
            }
        }
    }

    private var batteryText: String {
        guard let pct = bracelet.batteryPercent else { return bracelet.charging == true ? "Charging" : "—" }
        return bracelet.charging == true ? "\(pct)% · charging" : "\(pct)%"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.subtitle)
            Spacer()
            Text(value).foregroundStyle(.white).monospacedDigit()
        }
        .font(Theme.font(14))
    }

    // MARK: Vibration

    private var vibrationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vibration").font(Theme.font(15, .heavy)).foregroundStyle(.white)
                Picker("Strength", selection: Binding(get: { nearestPreset }, set: { apply(level: $0) })) {
                    ForEach(Self.presets) { Text($0.name).tag($0.level) }
                }
                .pickerStyle(.segmented)
                // Fine-tune between the bracelet's nine strengths.
                HStack {
                    Image(systemName: "speaker.wave.1").foregroundStyle(Theme.subtitle)
                    Slider(value: Binding(get: { Double(levels.firstIndex(of: level) ?? 6) },
                                          set: { apply(level: levels[Int($0.rounded())]) }),
                           in: 0...Double(levels.count - 1), step: 1)
                        .tint(Theme.accent)
                    Image(systemName: "speaker.wave.3").foregroundStyle(Theme.subtitle)
                }
                .accessibilityLabel("Fine-tune strength")
                if bracelet.isThirdGeneration {
                    // The Bond Touch More's two motors: which side vibrates more.
                    Text("Balance").font(Theme.font(13, .semibold)).foregroundStyle(.white)
                    HStack {
                        Text("Left").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                        Slider(value: Binding(get: { Double(balance) }, set: { apply(balance: Int($0.rounded())) }),
                               in: 0...4, step: 1)
                            .tint(Theme.accent)
                        Text("Right").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    }
                    .accessibilityLabel("Motor balance")
                }
                Text(bracelet.isReady ? "Your bracelet buzzes as you change it."
                                      : "Saved — sent to your bracelet when it connects.")
                    .font(.caption).foregroundStyle(Theme.subtitle)
            }
        }
    }

    private var nearestPreset: Int {
        Self.presets.min { abs($0.level - level) < abs($1.level - level) }?.level ?? 80
    }

    private func apply(level new: Int? = nil, balance newBalance: Int? = nil) {
        let l = new ?? level, b = newBalance ?? balance
        guard l != level || b != balance else { return }
        bracelet.setVibration(level: l, balance: b)
        bracelet.previewVibration(level: l, balance: b)
        level = l; balance = b
    }

    // MARK: Colour

    private var colorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                ColorPicker("Your colour", selection: $color, supportsOpacity: false)
                    .foregroundStyle(.white).font(Theme.font(15, .heavy))
                Text(bracelet.isReady ? "Your bracelet lights up in it while you choose. Your partner sees your touches in this colour."
                                      : "Your partner sees your touches in this colour.")
                    .font(.caption).foregroundStyle(Theme.subtitle)
            }
        }
        .onChange(of: color) { new in
            let rgb = new.rgbInt
            guard rgb != store.profile.colorRGB else { return }
            store.profile.colorRGB = rgb
            bracelet.setUserColor(rgb)
            bracelet.previewColor(rgb)
            // The preview goes out 2 s after the last change.
            previewEnd?.cancel()
            previewEnd = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                bracelet.endColorPreview()
                await model.publishProfile()
            }
        }
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
            GlassCard {
                VStack(spacing: 12) {
                    Toggle("Every day", isOn: $store.dndScheduled).foregroundStyle(.white).tint(Theme.accent)
                    if store.dndScheduled {
                        DatePicker("From", selection: time($store.dndFrom), displayedComponents: .hourAndMinute)
                            .foregroundStyle(.white)
                        DatePicker("To", selection: time($store.dndTo), displayedComponents: .hourAndMinute)
                            .foregroundStyle(.white)
                    }
                }
            }
            Text(store.quiet() ? "Quiet now: incoming touches won't buzz your bracelet or phone. They're still saved in your history."
                               : "When on, incoming touches won't buzz your bracelet or phone. They're still saved in your history.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Spacer()
        }
        .padding(20).navigationTitle("Do not disturb")
    }

    /// Minutes after midnight as a time of day for the picker.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                  second: 0, of: Date()) ?? Date()
        }, set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
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
