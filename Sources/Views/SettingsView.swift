import PhotosUI
import SwiftUI

/// Settings — profile header plus a list of sections, matching the original's layout.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Settings").font(.title3.bold()).foregroundStyle(Theme.title).padding(.top, 10)

                MyPhotoPicker(size: 110)
                if model.myPhoto == nil, model.legacySignedIn, FirebaseStorage.appCheckBlocked {
                    Text("Bond Touch's servers won't hand your photo to any app but theirs. Tap your picture and choose the same photo once — it's then shared with your partners.")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                }
                Text(store.profile.name.isEmpty ? "Me" : store.profile.name)
                    .font(.title2.bold()).foregroundStyle(Theme.title)
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(connectionText)
                }
                .font(.subheadline).foregroundStyle(Theme.subtitle)

                VStack(spacing: 12) {
                    ThemePickerCard()
                    LayoutPickerCard()
                    row("Personal details", "") { PersonalDetailsView() }
                    row("My Bond Touch Bracelet", "") { BraceletSettingsView() }
                    row("Bracelet firmware (recovery)", "") { FirmwareSettingsView() }
                    row("Bond Heart", "") { BondHeartView() }
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
                                Text("Stay connected in background").foregroundStyle(Theme.title)
                                Text("Keeps the app running with the phone locked or the app closed, so every touch reaches your bracelet right away. Shows the location indicator.")
                                    .font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                        .tint(Theme.accent)
                    }
                    NeonStyleCard()
                    GlassCard(padding: 20) {
                        Toggle(isOn: $store.watchStandsIn) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Watch stands in for the bracelet").foregroundStyle(Theme.title)
                                Text("When your bracelet disconnects, your watch wakes up and plays every touch on your wrist. Stops when the bracelet is back. Uses watch battery while it stands in.")
                                    .font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                        .tint(Theme.accent)
                    }
                    GlassCard(padding: 20) {
                        Stepper(value: $store.touchWindowSeconds, in: 5...10, step: 1) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Touch window: \(Int(store.touchWindowSeconds)) s").foregroundStyle(Theme.title)
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
                    Text(title).foregroundStyle(Theme.title)
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
                    Text("Language").foregroundStyle(Theme.title)
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
    @EnvironmentObject var recovery: FirmwareRecovery
    @ObservedObject var bracelet: BraceletManager
    @State private var confirmUpdate: BraceletManager.FirmwareUpdate?
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
                if recovery.isUpdate, recovery.phase != .idle { updateStatusCard }
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
                Text("Device").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                row("Model", bracelet.modelNumber ?? (bracelet.isThirdGeneration ? "Bond Touch More" : "Bond Touch"))
                row("Battery", batteryText)
                row("Firmware", bracelet.firmwareVersion ?? "—")
                if let update = bracelet.updateAvailable, !updateRunning { updateButton(update) }
                if let alert = bracelet.batteryAlert {
                    HStack(spacing: 8) {
                        Text("Battery lights").foregroundStyle(Theme.subtitle)
                        Spacer()
                        Circle().fill(Color(rgbInt: alert.lowRGB)).frame(width: 10, height: 10)
                        Text("low \(alert.lowPercent)%").foregroundStyle(Theme.title)
                        Circle().fill(Color(rgbInt: alert.criticalRGB)).frame(width: 10, height: 10)
                        Text("critical \(alert.criticalPercent)%").foregroundStyle(Theme.title)
                    }
                    .font(Theme.font(13))
                }
            }
        }
    }

    // MARK: Firmware update

    private var updateRunning: Bool {
        switch recovery.phase {
        case .restarting, .flashing: return true
        default: return false
        }
    }

    /// "Firmware 3.1.0 → Update to 3.1.1": confirmed first, then the bracelet restarts in
    /// update mode and is flashed with the firmware built into the app.
    private func updateButton(_ update: BraceletManager.FirmwareUpdate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { confirmUpdate = update } label: {
                Label("Update to \(update.latest)", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(AccentButtonStyle(height: 40))
            Text(bracelet.batteryAllowsUpdate
                 ? "A new firmware version is available for your bracelet."
                 : "Battery too low. Charge the bracelet above 40 % (or put it on its charger) to install the update.")
                .font(.caption).foregroundStyle(bracelet.batteryAllowsUpdate ? Theme.subtitle : Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Update firmware to \(update.latest)?",
               isPresented: Binding(get: { confirmUpdate != nil }, set: { if !$0 { confirmUpdate = nil } })) {
            Button("Update") {
                if let u = confirmUpdate { recovery.startUpdate(u) }
                confirmUpdate = nil
            }
            Button("Cancel", role: .cancel) { confirmUpdate = nil }
        } message: {
            Text("Keep the bracelet close and the app open; the update takes a few minutes. The bracelet restarts and reconnects on its own.")
        }
    }

    /// While an update runs the bracelet isn't connected, so its progress shows here (and
    /// in the banner on every screen).
    private var updateStatusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Firmware update").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                switch recovery.phase {
                case .restarting:
                    Text("Restarting in update mode…").font(Theme.font(14)).foregroundStyle(Theme.subtitle)
                    ProgressView().tint(Theme.accent)
                case .flashing(_, let progress):
                    Text("Updating… \(progress)%").font(Theme.font(14)).foregroundStyle(Theme.subtitle)
                    ProgressView(value: Double(progress), total: 100).tint(Theme.accent)
                case .done:
                    Text("Update completed. Your bracelet's firmware is up to date.")
                        .font(Theme.font(14)).foregroundStyle(Theme.lime)
                case .failed(_, let message):
                    Text("Failed to update the firmware. \(message)")
                        .font(Theme.font(14)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                case .idle, .needsFirmware:
                    EmptyView()
                }
                if !updateRunning {
                    Button("OK") { recovery.dismiss() }.buttonStyle(GlassButtonStyle(height: 40))
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
            Text(value).foregroundStyle(Theme.title).monospacedDigit()
        }
        .font(Theme.font(14))
    }

    // MARK: Vibration

    private var vibrationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vibration").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
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
                    Text("Balance").font(Theme.font(13, .semibold)).foregroundStyle(Theme.title)
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
                    .foregroundStyle(Theme.title).font(Theme.font(15, .heavy))
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

/// How the bracelet tells you about a new Private Space message (the original's General /
/// Secret notifications). Feel each one on the bracelet.
private struct BraceletNotificationsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("braceletNotifyStyle") private var style = AppModel.BraceletNotify.general.rawValue

    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("New messages", selection: $style) {
                        Text("Off").tag(AppModel.BraceletNotify.off.rawValue)
                        Text("General").tag(AppModel.BraceletNotify.general.rawValue)
                        Text("Secret").tag(AppModel.BraceletNotify.secret.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Text(detail).font(.footnote).foregroundStyle(Theme.subtitle)
                    if style != AppModel.BraceletNotify.off.rawValue {
                        Button("Feel it on my bracelet") {
                            let s = AppModel.BraceletNotify(rawValue: style) ?? .general
                            _ = model.bracelet.play(AppModel.notification(s, colorRGB: model.selectedPartner?.colorRGB ?? model.store.profile.colorRGB),
                                                    holdIfOffline: false)
                        }
                        .disabled(!model.bracelet.isReady)
                    }
                }
            }
            Text("At most one every 30 seconds, and never during Do Not Disturb.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Spacer()
        }
        .padding(20).navigationTitle("Bracelet notifications")
    }

    private var detail: String {
        switch AppModel.BraceletNotify(rawValue: style) ?? .general {
        case .off: return "Your bracelet stays still for new messages."
        case .general: return "A quick triple buzz in your partner's colour."
        case .secret: return "A rainbow sweep — only you know what it means."
        }
    }
}

private struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pairing").font(.headline).foregroundStyle(Theme.title)
                Text("Open My Bond Touch Bracelet and tap Connect with the bracelet awake and nearby. The app pairs with BOND, Bond More, BOND 4 and BOND MINI bracelets.")
                    .foregroundStyle(Theme.subtitle)
                Text("Sending a touch").font(.headline).foregroundStyle(Theme.title)
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
                Toggle("Do not disturb", isOn: $store.doNotDisturb).foregroundStyle(Theme.title).tint(Theme.accent)
            }
            GlassCard {
                VStack(spacing: 12) {
                    Toggle("Every day", isOn: $store.dndScheduled).foregroundStyle(Theme.title).tint(Theme.accent)
                    if store.dndScheduled {
                        DatePicker("From", selection: time($store.dndFrom), displayedComponents: .hourAndMinute)
                            .foregroundStyle(Theme.title)
                        DatePicker("To", selection: time($store.dndTo), displayedComponents: .hourAndMinute)
                            .foregroundStyle(Theme.title)
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
            Text("\(title) is coming soon.").foregroundStyle(Theme.title)
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
                Text("App icon").foregroundStyle(Theme.title)
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

/// The neon touch lines' thickness and glow, with a live example of a slide and a tap rhythm.
/// Settings → Layout: how Home is arranged, folded away until tapped.
private struct LayoutPickerCard: View {
    @AppStorage("homeLayout") private var layout = HomeLayout.classic.rawValue
    @AppStorage("layoutPickerOpen") private var open = false

    private var current: HomeLayout { HomeLayout(rawValue: layout) ?? .classic }

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Text("Layout").foregroundStyle(Theme.title)
                        Spacer()
                        Text(current.title).font(.subheadline).foregroundStyle(Theme.subtitle)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.subtitle)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Layout, \(current.title)")
                .accessibilityHint(open ? "Hides the layouts" : "Shows the layouts")
                if open {
                    ForEach(HomeLayout.allCases) { l in
                        let on = l == current
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            layout = l.rawValue
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: l.icon).font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(on ? Theme.onAccent : Theme.title)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(on ? Theme.accent : Theme.ink.opacity(0.1)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(l.title).font(Theme.font(15, .bold)).foregroundStyle(on ? Theme.accent : Theme.title)
                                    Text(l.blurb).font(.caption).foregroundStyle(Theme.subtitle)
                                }
                                Spacer()
                                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// Settings → Theme: every look as a small live preview, and for Paper & Ink, the ink colour.
private struct ThemePickerCard: View {
    @AppStorage("appStyle") private var appStyle = AppStyle.aero.rawValue
    @AppStorage("paperInk") private var paperInk = PaperInk.aqua.rawValue
    /// Folded away until tapped, so it doesn't take over Settings. Stays open across the
    /// redraw a theme change causes.
    @AppStorage("themePickerOpen") private var open = false
    @AppStorage(ThemeTints.key) private var themeTints = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Text("Theme").foregroundStyle(Theme.title)
                        Spacer()
                        Text(currentTitle).font(.subheadline).foregroundStyle(Theme.subtitle)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.subtitle)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Theme, \(currentTitle)")
                .accessibilityHint(open ? "Hides the themes" : "Shows the themes")
                if open {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppStyle.allCases) { style in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            appStyle = style.rawValue
                        } label: { tile(style) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(style.title) theme")
                        .accessibilityHint(style.blurb)
                        .accessibilityAddTraits(appStyle == style.rawValue ? .isSelected : [])
                    }
                }
                if let style = AppStyle(rawValue: appStyle), style != .paper {
                    Text("Colour").font(.caption).foregroundStyle(Theme.subtitle)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(style.tints.indices, id: \.self) { i in
                                let tint = style.tints[i]
                                let picked = (ThemeTints.tint(for: style, in: themeTints) ?? style.tints[0].rgb) == tint.rgb
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    var d = ThemeTints.parse(themeTints)
                                    d[style.rawValue] = tint.rgb == style.tints[0].rgb ? nil : tint.rgb
                                    themeTints = ThemeTints.encode(d)
                                } label: {
                                    VStack(spacing: 4) {
                                        Circle().fill(Color(rgbInt: tint.rgb))
                                            .frame(width: 34, height: 34)
                                            .overlay(Circle().stroke(Theme.ink.opacity(0.2), lineWidth: 1))
                                            .padding(3)
                                            .overlay(Circle().stroke(picked ? Theme.title : .clear, lineWidth: 2))
                                        Text(tint.name).font(.caption2)
                                            .foregroundStyle(picked ? Theme.title : Theme.subtitle)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(tint.name)")
                                .accessibilityAddTraits(picked ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if appStyle == AppStyle.paper.rawValue {
                    Text("Ink").font(.caption).foregroundStyle(Theme.subtitle)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(PaperInk.allCases) { ink in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    paperInk = ink.rawValue
                                } label: {
                                    VStack(spacing: 4) {
                                        Circle().fill(Color(rgbInt: ink.colors.ink))
                                            .frame(width: 34, height: 34)
                                            .overlay(Circle().stroke(Color(rgbInt: ink.colors.paper), lineWidth: 3).padding(2))
                                            .overlay(Circle().stroke(paperInk == ink.rawValue ? Theme.title : .clear, lineWidth: 2))
                                        Text(ink.title).font(.caption2)
                                            .foregroundStyle(paperInk == ink.rawValue ? Theme.title : Theme.subtitle)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(ink.title) ink")
                                .accessibilityAddTraits(paperInk == ink.rawValue ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                }
            }
        }
    }

    private var currentTitle: String {
        let style = AppStyle(rawValue: appStyle) ?? .aero
        if style == .paper { return "\(style.title) · \((PaperInk(rawValue: paperInk) ?? .aqua).title)" }
        let rgb = ThemeTints.tint(for: style, in: themeTints) ?? style.tints[0].rgb
        return "\(style.title) · \(style.tints.first { $0.rgb == rgb }?.name ?? "")"
    }

    /// A small window onto the theme: its backdrop, one of its panels with a touch drawn on
    /// it, and its name in its own type.
    private func tile(_ style: AppStyle) -> some View {
        let p = Theme.palette(for: style)
        let selected = appStyle == style.rawValue
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                ThemeBackdrop(style: style)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(p.accent).frame(width: 10, height: 10)
                        Text("Aa").font(Theme.font(15, .bold, style: style)).foregroundStyle(p.title)
                        Spacer()
                    }
                    Capsule().fill(LinearGradient(colors: [p.accent, p.magenta], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 5)
                        .shadow(color: style == .neon ? p.accent.opacity(0.8) : .clear, radius: 4)
                }
                .padding(10)
                .background(GlassBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), style: style))
                .padding(12)
            }
            .frame(height: 96)
            .clipShape(shape)
            .overlay(shape.stroke(selected ? Theme.accent : Theme.ink.opacity(0.15), lineWidth: selected ? 3 : 1))
            .environment(\.colorScheme, style.isLight ? .light : .dark)
            HStack(spacing: 4) {
                Text(style.title).font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.title).lineLimit(1)
                if selected { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent) }
            }
        }
    }
}

private struct NeonStyleCard: View {
    @AppStorage("neonWidth") private var width = 1.0
    @AppStorage("neonGlow") private var glow = 1.0

    /// A slide up the bar, a hold, and back down — for the example.
    private static let slide: [Int] = {
        var positions: [Int] = []
        for i in 0..<14 { positions.append(Int((Double(i) * 8.0 / 13.0).rounded())) }
        for _ in 0..<5 { positions.append(8) }
        for i in 0..<16 { positions.append(8 - Int((Double(i) * 8.0 / 15.0).rounded())) }
        return positions.map { TouchPattern.sample([$0]) }
    }()

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Touch style").foregroundStyle(Theme.title)
                TouchViz(pattern: Self.slide, generation: 3, colorRGB: 0x57C3BB, endColorRGB: 0xB173DF, height: 64)
                TouchViz(pattern: [160, 140, 160, 140, 500], generation: 2, colorRGB: 0xEC5A89, endColorRGB: 0xB173DF, height: 40)
                HStack(spacing: 10) {
                    Text("Line").font(.caption).foregroundStyle(Theme.subtitle).frame(width: 40, alignment: .leading)
                    Slider(value: $width, in: 0.4...2.2).tint(Theme.accent).accessibilityLabel("Line thickness")
                }
                HStack(spacing: 10) {
                    Text("Glow").font(.caption).foregroundStyle(Theme.subtitle).frame(width: 40, alignment: .leading)
                    Slider(value: $glow, in: 0...2.5).tint(Theme.accent).accessibilityLabel("Glow")
                }
                Button("Reset") { width = 1; glow = 1 }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
    }
}
