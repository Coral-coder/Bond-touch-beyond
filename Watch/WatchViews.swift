import SwiftUI
import WatchKit

extension Color {
    init(rgb: Int) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

private let accent = Color(rgb: 0x3ED9CE)

struct WatchRootView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        if link.partners.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "iphone").font(.title2).foregroundStyle(accent)
                Text("Open Bond Touch Beyond on your iPhone to see your partners.")
                    .font(.footnote).multilineTextAlignment(.center)
            }
            .padding()
        } else {
            TabView {
                WatchTouchBarView()
                WatchMeaningsView()
                WatchHistoryView()
                WatchStandInView()
                WatchTapLabView()
            }
            .tabViewStyle(.page)
        }
    }
}

/// Records a touch like the Bond Touch More bar: the first touch opens the window, the bar
/// is sampled every 50 ms for where the finger is on its 9 positions, sent when it ends.
/// Finger changes are logged with their time and sampled from the log, so short taps count.
/// The watch vibrates steadily the whole time the finger is down, so you feel the touch.
final class WatchRecorder: ObservableObject {
    @Published var position: CGFloat?
    @Published private(set) var recording = false
    @Published private(set) var remaining: Double = 0
    var windowSeconds: Double = 5
    var onFinish: (([Int]) -> Void)?
    private var timer: Timer?
    private var started: TimeInterval = 0
    private var events: [TouchPattern.BarEvent] = []
    private var current: [Int] = []

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var window: Double { min(windowSeconds, Double(TouchPattern.maxSamples * TouchPattern.sampleMs) / 1000) }

    func touch(_ f: CGFloat?) {
        position = f
        if f != nil, !recording { start() }
        guard recording else { return }
        let bar = f.map { [Int(($0 * CGFloat(TouchPattern.positions - 1)).rounded())] } ?? []
        guard bar != current else { return }
        if bar.isEmpty != current.isEmpty { WatchVibration.hold(!bar.isEmpty) }   // landed or lifted
        current = bar
        events.append(.init(t: max(0, now - started), fingers: bar))
    }

    private func start() {
        events = []; current = []
        recording = true; started = now; remaining = window
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        remaining = max(0, window - (now - started))
        if remaining <= 0 { finish() }
    }

    func finish() {
        guard recording else { return }
        let samples = TouchPattern.samples(from: events, duration: min(window, now - started))
        if !current.isEmpty { WatchVibration.hold(false) }
        timer?.invalidate(); timer = nil
        recording = false; remaining = 0
        events = []; current = []
        let touch = TouchPattern.trimmed(samples)
        if !touch.isEmpty { onFinish?(touch) }
    }

    /// Stops without sending (the bar was closed mid-touch).
    func cancel() {
        if !current.isEmpty { WatchVibration.hold(false) }
        timer?.invalidate(); timer = nil
        recording = false; remaining = 0; position = nil
        events = []; current = []
    }
}

/// The first page: the partner, and one round Touch button. Tapping it opens the touch bar
/// full screen; when the touch is sent it closes and the button says "Sent" for a moment.
struct WatchTouchBarView: View {
    @EnvironmentObject var link: PhoneLink
    @State private var drawing = false
    @State private var sentFlash = 0   // > 0 while "Sent" shows; a counter so flashes don't cut each other short

    private var color: Color { Color(rgb: link.selected?.colorRGB ?? 0xFF2E74) }

    var body: some View {
        WatchPage {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Button { drawing = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: sentFlash > 0 ? "checkmark" : "hand.point.up.left.fill")
                            .font(.system(size: 30, weight: .bold))
                        Text(sentFlash > 0 ? "Sent" : "Touch")
                            .font(.system(.footnote, design: .rounded).weight(.heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 92, height: 92)
                    .background(Circle().fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                                             startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send a touch to \(link.selected?.name ?? "your partner")")
                Spacer(minLength: 0)
                Text(link.lastSent.map { "Sent " + $0.formatted(date: .omitted, time: .shortened) } ?? "Tap, then slide or tap the bar")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: sentFlash > 0)
        }
        .fullScreenCover(isPresented: $drawing) {
            WatchTouchBarScreen { flashSent() }
                .environmentObject(link)
        }
    }

    private func flashSent() {
        sentFlash += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { sentFlash = max(sentFlash - 1, 0) }
    }
}

/// The touch bar, filling the screen so you can see exactly where your finger is. The first
/// touch opens the recording window; when it ends the touch is sent and the bar closes. If
/// it isn't touched within a few seconds it closes by itself.
struct WatchTouchBarScreen: View {
    let onSent: () -> Void
    @EnvironmentObject var link: PhoneLink
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = WatchRecorder()
    @State private var sent = false

    init(onSent: @escaping () -> Void) { self.onSent = onSent }

    private var color: Color { Color(rgb: link.selected?.colorRGB ?? 0xFF2E74) }

    var body: some View {
        GeometryReader { root in
            let full = root.size
            let pad = min(full.width, full.height) * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1))
                    .contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("screen"))
                        .onChanged { v in
                            guard !sent else { return }   // finger still down after sending
                            let f = 1 - (v.location.y - pad) / max(full.height - pad * 2, 1)
                            recorder.touch(min(max(f, 0), 1))
                        }
                        .onEnded { _ in if !sent { recorder.touch(nil) } })

                // The bar's 9 positions, and the glow under the finger.
                ForEach(0..<TouchPattern.positions, id: \.self) { i in
                    Circle().fill(.white.opacity(0.25)).frame(width: 4, height: 4)
                        .position(x: full.width / 2, y: y(CGFloat(i) / 8, full.height, pad))
                }
                .allowsHitTesting(false)
                if let p = recorder.position {
                    Circle()
                        .fill(RadialGradient(colors: [.white, color, color.opacity(0)], center: .center,
                                             startRadius: 2, endRadius: full.width * 0.45))
                        .frame(width: full.width * 0.9, height: full.width * 0.9)
                        .position(x: full.width / 2, y: y(p, full.height, pad))
                        .allowsHitTesting(false)
                }
                Group {
                    if recorder.recording {
                        VStack(spacing: 2) {
                            ProgressView(value: 1 - recorder.remaining / max(recorder.windowSeconds, 0.1))
                                .tint(accent).frame(width: full.width * 0.4)
                            Text(String(format: "%.0f s", recorder.remaining.rounded(.up)))
                                .font(.caption2.weight(.heavy)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.top, 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        Text("Slide or tap").font(.system(.footnote, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: full.width, height: full.height)
            .coordinateSpace(name: "screen")
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            recorder.windowSeconds = link.windowSeconds
            recorder.onFinish = { samples in
                sent = true
                let rgb = link.selected?.colorRGB ?? 0xFF2E74
                link.sendTouch(pattern: samples, generation: 3, startRGB: rgb, endRGB: rgb)
                onSent()
            }
        }
        // The window ended (sent, or nothing to send): back to the button.
        .onChange(of: recorder.recording) { if !$0 { dismiss() } }
        // Opened by mistake: close if the bar isn't touched.
        .task {
            guard (try? await Task.sleep(nanoseconds: 6_000_000_000)) != nil else { return }
            if !recorder.recording && !sent { dismiss() }
        }
        .onDisappear { recorder.cancel(); recorder.onFinish = nil }
    }

    /// Screen y for bar position f (0 bottom … 1 top).
    private func y(_ f: CGFloat, _ height: CGFloat, _ pad: CGFloat) -> CGFloat {
        height - pad - (height - pad * 2) * f
    }
}

/// A watch page, using the whole screen like the touch bar does. On watchOS 10 the partner
/// header sits in the toolbar beside the clock and the page's content runs edge to edge,
/// scrolling under it; on watchOS 9 the header sits at the top and the content fills the rest
/// down to the bottom edge.
struct WatchPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        if #available(watchOS 10.0, *) {
            NavigationStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { WatchPartnerHeader() }
                    }
            }
        } else {
            VStack(spacing: 0) {
                WatchPartnerHeader().padding(.bottom, 4)
                content.frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct WatchMeaningsView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        let list = link.selected.flatMap { link.meanings[$0.id] } ?? []
        WatchPage {
            List {
                Section("Touch Language") {
                    if list.isEmpty {
                        Text("No saved touches yet").foregroundStyle(.secondary)
                    }
                    ForEach(list) { m in
                        Button {
                            link.sendMeaning(m)
                        } label: {
                            HStack {
                                Circle().fill(LinearGradient(colors: [Color(rgb: m.startRGB), Color(rgb: m.endRGB)],
                                                             startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 12, height: 12)
                                Text(m.name).font(.system(.body, design: .rounded).weight(.bold))
                                if m.favourite { Spacer(); Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Recent touches with the selected partner, each drawn as it was (trace, taps or EKG) in a
/// slim row with who, the meaning and when. Tap one to feel it again.
struct WatchHistoryView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        let list = (link.selected.flatMap { link.history[$0.id] } ?? []).reversed()
        WatchPage {
            List {
                Section("Recent touches") {
                    if list.isEmpty { Text("No touches yet").foregroundStyle(.secondary) }
                    ForEach(Array(list)) { t in
                        Button { WatchHaptics.play(t, again: true) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: t.mine ? "arrow.up.right" : "arrow.down.left")
                                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                                    Text(caption(t)).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
                                    Spacer(minLength: 2)
                                    Text(t.sentAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                                }
                                WatchTouchDrawing(touch: t, compact: true).frame(height: 18)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .accessibilityLabel("\(caption(t)) at \(t.sentAt.formatted(date: .omitted, time: .shortened)). Feel it again")
                    }
                }
            }
        }
    }

    /// Who, and the meaning or heartbeat if it was one: "Alex · Love you", "You · 72 BPM".
    private func caption(_ t: WatchTouch) -> String {
        let who = t.mine ? "You" : (link.selected?.name ?? "Partner")
        if let bpm = t.bpm { return "\(who) · ♥ \(bpm)" }
        if let label = t.label { return "\(who) · \(label)" }
        return who
    }
}

/// The selected partner, pinned at the top of every watch screen: tap to switch partners.
struct WatchPartnerHeader: View {
    @EnvironmentObject var link: PhoneLink
    @State private var picking = false

    /// In the toolbar (watchOS 10) it sizes to its content beside the clock instead of
    /// spanning the screen.
    private var compact: Bool {
        if #available(watchOS 10.0, *) { return true }
        return false
    }

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 5) {
                Circle().fill(link.selected?.online == true ? Color(rgb: 0xAEE63C) : .gray).frame(width: 6, height: 6)
                Circle().fill(Color(rgb: link.selected?.colorRGB ?? 0xFF2E74)).frame(width: 10, height: 10)
                Text(link.selected?.name ?? "Partner").font(.system(.footnote, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                if link.partners.count > 1 { Image(systemName: "chevron.down").font(.caption2) }
            }
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(link.partners.count < 2)
        .accessibilityLabel("Partner: \(link.selected?.name ?? "none"). Tap to switch.")
        .sheet(isPresented: $picking) { WatchPartnerPicker() }
    }
}

struct WatchPartnerPicker: View {
    @EnvironmentObject var link: PhoneLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(link.partners) { p in
            Button {
                link.select(p.id); dismiss()
            } label: {
                HStack {
                    Circle().fill(Color(rgb: p.colorRGB)).frame(width: 14, height: 14)
                    Text(p.name)
                    Spacer()
                    if p.id == link.selected?.id { Image(systemName: "checkmark").foregroundStyle(accent) }
                }
            }
        }
    }
}
