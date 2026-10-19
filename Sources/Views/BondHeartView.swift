import SwiftUI

/// Bond Heart — the heartbeat pendant: its status and pairing, the heartbeat it's wearing
/// and how often it was felt, recording a heartbeat, the library, and heartbeats shared
/// with you through the original Bond Touch account.
struct BondHeartView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        BondHeartHome(pendant: model.pendant, library: model.heartLibrary)
            .navigationTitle("Bond Heart")
            .onAppear { model.pendant.activate() }
    }
}

/// Colours offered for a heartbeat (the light it shows on the pendant), like the
/// original's colour wheel.
enum HeartPalette {
    static let colors: [Int] = [0xE85D75, 0xFF3B5C, 0xFF8A3D, 0xFFC93C, 0x9FD257, 0x34D1BF,
                                0x4FA8FF, 0x7B61FF, 0xC86BFA, 0xFF6FD8, 0xFFFFFF]
}

/// A glowing heart in a heartbeat's colour; beats (on the EKG's R spike) when `bpm` is set.
struct HeartGlyph: View {
    var colorRGB: Int
    var size: CGFloat = 44
    var bpm: Int? = nil
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: bpm == nil)) { context in
            let beat = bpm.map { max(0, EKG.level(elapsed: context.date.timeIntervalSince(start), bpm: $0)) } ?? 0
            Image(systemName: "heart.fill")
                .font(.system(size: size))
                .foregroundStyle(LinearGradient(colors: [Color(rgbInt: colorRGB), Color(rgbInt: colorRGB).opacity(0.7)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(rgbInt: colorRGB).opacity(0.5 + 0.4 * beat), radius: 8 + 10 * beat)
                .scaleEffect(1 + 0.12 * beat)
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .accessibilityHidden(true)
    }
}

private struct BondHeartHome: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var pendant: HeartPendant
    @ObservedObject var library: HeartLibrary
    @State private var countText: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PendantCard(pendant: pendant)
                wearingCard
                VStack(spacing: 12) {
                    link("Record a heartbeat", "waveform.path.ecg",
                         "Your fingertip on the camera, or your Apple Watch") { RecordHeartbeatView() }
                    link("Library", "heart.text.square",
                         library.items.isEmpty ? "All heartbeats in one place" : "\(library.items.count) heartbeat\(library.items.count == 1 ? "" : "s")") {
                        HeartLibraryView()
                    }
                    link("Shared & requests", "envelope.open", sharedSubtitle) { HeartSharedView() }
                    link("Tutorials", "book", "Get to know your Heart") { HeartTutorialsView() }
                }
                Color.clear.frame(height: 12)
            }
            .padding(20)
        }
        .task { if model.legacySignedIn { await model.heartSync() } }
    }

    private var sharedSubtitle: String {
        guard model.legacySignedIn else { return "Send & ask by email (Bond Touch account)" }
        let n = library.pending.count + library.requests.filter { model.isReceived($0) }.count
        return n == 0 ? "Send or ask for a heartbeat by email" : "\(n) waiting for you"
    }

    @ViewBuilder private var wearingCard: some View {
        GlassCard {
            if let hb = library.worn {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        HeartGlyph(colorRGB: hb.colorRGB, size: 34, bpm: hb.bpm)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wearing").font(.caption).foregroundStyle(Theme.subtitle)
                            Text(hb.title).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                        }
                        Spacer()
                        Text("\(hb.bpm)").font(Theme.font(24, .heavy)).foregroundStyle(Theme.title).monospacedDigit()
                        Text("BPM").font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
                    }
                    EKGView(bpm: hb.bpm, colorRGB: hb.colorRGB).frame(height: 44)
                    Text("Grab the heart by touching the front light area. You’ll feel it beating after a few seconds.")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                    if let countText {
                        Text(countText).font(.footnote).foregroundStyle(Theme.title)
                    }
                    HStack(spacing: 10) {
                        Button("Heartbeat count") {
                            run {
                                do {
                                    let n = try await model.feltCount()
                                    let since = (library.wornAt ?? hb.createdAt).formatted(date: .abbreviated, time: .omitted)
                                    countText = "You felt this heartbeat \(n) time\(n == 1 ? "" : "s") since \(since)."
                                } catch { countText = error.localizedDescription }
                            }
                        }
                        .buttonStyle(GlassButtonStyle(height: 40))
                        if model.legacySignedIn {
                            Button("Share count") {
                                run { countText = await model.shareFeltCount() ?? "Heartbeat count successfully sent!" }
                            }
                            .buttonStyle(GlassButtonStyle(height: 40))
                        }
                    }
                    .disabled(busy || !pendant.state.isUsable)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "heart.slash").font(.title2).foregroundStyle(Theme.subtitle)
                    Text("You're not wearing any heartbeat. Select one from your library or add a new one.")
                        .font(.footnote).foregroundStyle(Theme.subtitle)
                }
            }
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }

    @ViewBuilder private func link<Destination: View>(_ title: String, _ icon: String, _ subtitle: String,
                                                      @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination().screenBackground().navigationBarTitleDisplayMode(.inline)
        } label: {
            GlassCard(padding: 18) {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.title3).foregroundStyle(Theme.pink).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(Theme.title).font(Theme.font(16, .bold))
                        Text(subtitle).font(.caption).foregroundStyle(Theme.subtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle).font(.footnote)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// The pendant: status, battery, firmware, and pairing / reconnecting / forgetting it.
struct PendantCard: View {
    @ObservedObject var pendant: HeartPendant
    @State private var confirmForget = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    HeartGlyph(colorRGB: pendant.state.isUsable ? 0xEC5A89 : 0x8FA7BA, size: 36,
                               bpm: pendant.state.isUsable ? 64 : nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Bond Heart").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                        Text(pendant.state.text).font(.caption).foregroundStyle(Theme.subtitle)
                    }
                    Spacer()
                    if let b = pendant.battery {
                        Label("\(b)%", systemImage: b > 60 ? "battery.100" : b > 25 ? "battery.50" : "battery.25")
                            .font(Theme.font(14, .bold)).foregroundStyle(b > 25 ? Theme.title : Theme.amber)
                    }
                }
                if let hint {
                    Text(hint).font(.footnote).foregroundStyle(Theme.subtitle)
                }
                if let e = pendant.lastEvent {
                    Text(e).font(.footnote).foregroundStyle(Theme.amber)
                }
                if let fw = pendant.firmware {
                    Text("Firmware \(fw.text)").font(.caption2).foregroundStyle(Theme.subtitle)
                }
                if !pendant.isPaired {
                    Button(pendant.state == .searching ? "Searching…" : "Connect Heart") { pendant.startPairing() }
                        .buttonStyle(AccentButtonStyle(height: 46))
                        .disabled(pendant.state == .searching || pendant.state == .connecting)
                } else {
                    HStack(spacing: 10) {
                        if !pendant.state.isUsable {
                            Button("Search again") { pendant.activate() }
                                .buttonStyle(GlassButtonStyle(height: 40))
                        } else {
                            Button("Update battery") { pendant.refreshBattery() }
                                .buttonStyle(GlassButtonStyle(height: 40))
                        }
                        Button("Disconnect") { confirmForget = true }
                            .buttonStyle(GlassButtonStyle(height: 40))
                    }
                }
            }
        }
        .confirmationDialog("Disconnect this Heart?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Disconnect this Heart", role: .destructive) { pendant.forget() }
        } message: {
            Text("In order to fully disconnect it, make sure to unpair “BondHeart” in Bluetooth Settings.")
        }
    }

    private var hint: String? {
        switch pendant.state {
        case .idle:
            return "Make sure your Heart is charged, close to your phone and Bluetooth is on."
        case .searching:
            return "Wake your Heart: press both surfaces and tap until it flashes and you feel a short vibration. Keep it near your phone."
        case .connecting, .authenticating:
            return "Keep your Heart near your phone. iOS may ask to pair with “BondHeart” — allow it."
        case .oobe:
            return "Your pendant should be flashing right now. Double-tap it again to continue."
        case .dfuNeeded:
            return "A new firmware version is available for your Bond Heart. This app can't update the pendant yet (the Bond Touch app can); it works as it is."
        case .needsBattery:
            return "Battery low. Charge your Heart in its box: a blinking red light means charging, green means full."
        case .dfuMode:
            return "Your Heart is waiting for a firmware update. Finish it with the Bond Touch app."
        case .bluetoothOff, .unauthorized:
            return "Your Heart needs Bluetooth to work. Turn it on, and allow Bluetooth for this app in Settings."
        case .connected:
            return nil
        }
    }
}

/// The original's Bond Heart tutorials, as short cards.
struct HeartTutorialsView: View {
    private struct Lesson: Identifiable {
        let title: String, icon: String, lines: [String]
        var id: String { title }
    }

    private let lessons: [Lesson] = [
        Lesson(title: "Waking up", icon: "hand.tap", lines: ["Press firmly on the light area, tap until it flashes, and feel a short vibration. Keep your Heart near your phone.",
          "To pair it, wake it, tap Connect Heart, then double-tap the pendant again while it flashes."]),
        Lesson(title: "Recording a heartbeat", icon: "waveform.path.ecg", lines: ["We do so by detecting your blood flow using your phone’s flashlight. Just place your finger over it and over your camera at the same time.",
          "Keep the camera covered and stay still for 15 seconds.",
          "Pick a color and give it the name of your special someone, then store it in your library. An Apple Watch recording works too."]),
        Lesson(title: "Battery and charging", icon: "battery.75", lines: ["Don’t ditch the box! It’s also a charging dock. Remove the upper tray and run your cable through the small hole on the back.",
          "A blinking red light means your Heart is charging. When the light is green, it's fully charged.",
          "Bond Heart needs to charge at least every 15 days. Check its battery here while waking it up."]),
        Lesson(title: "Feeling the heartbeat", icon: "heart.circle", lines: ["Grab the heart by touching the front light area. You’ll feel it beating after a few seconds. Don’t forget to wear a heartbeat before trying to feel one."]),
        Lesson(title: "Heartbeat count", icon: "number", lines: ["Every time you hold the heart to feel its beat, that moment is counted.",
          "Share this count with up to 3 loved ones (add their emails to the heartbeat), once every 24 hours."]),
        Lesson(title: "Send & ask for a heartbeat", icon: "envelope", lines: ["You can send or request a heartbeat to and from your loved ones; all you need is their Bond Touch account email.",
          "You can also send a heartbeat to a partner's bracelet from its page in the library."]),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(lessons) { lesson in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(lesson.title, systemImage: lesson.icon).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                            ForEach(lesson.lines, id: \.self) { line in
                                Text(line).font(.footnote).foregroundStyle(Theme.subtitle)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Tutorials")
    }
}
