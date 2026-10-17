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
            }
            .tabViewStyle(.page)
        }
    }
}

/// Records a touch like the Bond Touch More bar: the first touch opens the window, the bar
/// is sampled every 50 ms for where the finger is on its 9 positions, sent when it ends.
/// Finger changes are logged with their time and sampled from the log, so short taps count.
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
        if position == nil, f != nil { WKInterfaceDevice.current().play(.click) }
        position = f
        if f != nil, !recording { start() }
        guard recording else { return }
        let bar = f.map { [Int(($0 * CGFloat(TouchPattern.positions - 1)).rounded())] } ?? []
        guard bar != current else { return }
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
        timer?.invalidate(); timer = nil
        recording = false; remaining = 0
        events = []; current = []
        let touch = TouchPattern.trimmed(samples)
        if !touch.isEmpty { onFinish?(touch) }
    }
}

/// The watch touch bar. Idle, it is a bar between the partner name and the status line; the
/// moment you touch it, it fills the whole screen until the touch is sent, so you can see
/// exactly where your finger is. Positions are measured against the full screen from the
/// first touch, so nothing jumps when it expands.
struct WatchTouchBarView: View {
    @EnvironmentObject var link: PhoneLink
    @StateObject private var recorder = WatchRecorder()
    @State private var picking = false

    private var color: Color { Color(rgb: link.selected?.colorRGB ?? 0xFF2E74) }
    private var expanded: Bool { recorder.recording || recorder.position != nil }

    var body: some View {
        GeometryReader { root in
            let full = root.size
            let pad = min(full.width, full.height) * 0.12
            ZStack {
                VStack(spacing: 6) {
                    Button { picking = true } label: {
                        HStack(spacing: 4) {
                            Circle().fill(link.selected?.online == true ? Color(rgb: 0xAEE63C) : .gray).frame(width: 6, height: 6)
                            Text(link.selected?.name ?? "Partner").font(.system(.footnote, design: .rounded).weight(.heavy))
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(link.lastSent.map { "Sent " + $0.formatted(date: .omitted, time: .shortened) } ?? "Touch to start")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 22)
                .opacity(expanded ? 0 : 1)
                .allowsHitTesting(!expanded)

                RoundedRectangle(cornerRadius: expanded ? 34 : 29, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: expanded ? 34 : 29, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1))
                    .frame(width: expanded ? full.width : 58, height: expanded ? full.height : full.height * 0.58)
                    .contentShape(Rectangle())
                    // High priority so page swipes don't steal a slide along the bar.
                    .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("screen"))
                        .onChanged { v in
                            let f = 1 - (v.location.y - pad) / max(full.height - pad * 2, 1)
                            recorder.touch(min(max(f, 0), 1))
                        }
                        .onEnded { _ in recorder.touch(nil) })

                if expanded {
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
                    VStack(spacing: 2) {
                        ProgressView(value: 1 - recorder.remaining / max(recorder.windowSeconds, 0.1))
                            .tint(accent).frame(width: full.width * 0.4)
                        Text(String(format: "%.0f s", recorder.remaining.rounded(.up)))
                            .font(.caption2.weight(.heavy)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 6)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: full.width, height: full.height)
            .coordinateSpace(name: "screen")
            .animation(.easeOut(duration: 0.15), value: expanded)
        }
        .ignoresSafeArea()
        .onAppear {
            recorder.windowSeconds = link.windowSeconds
            recorder.onFinish = { samples in
                let rgb = link.selected?.colorRGB ?? 0xFF2E74
                link.sendTouch(pattern: samples, generation: 3, startRGB: rgb, endRGB: rgb)
            }
        }
        .onChange(of: link.windowSeconds) { recorder.windowSeconds = $0 }
        .sheet(isPresented: $picking) { WatchPartnerPicker() }
    }

    /// Screen y for bar position f (0 bottom … 1 top).
    private func y(_ f: CGFloat, _ height: CGFloat, _ pad: CGFloat) -> CGFloat {
        height - pad - (height - pad * 2) * f
    }
}

struct WatchMeaningsView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        let list = link.selected.flatMap { link.meanings[$0.id] } ?? []
        List {
            Section("Send to \(link.selected?.name ?? "partner")") {
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

/// Recent touches with the selected partner; tap one to feel it again.
struct WatchHistoryView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        let list = (link.selected.flatMap { link.history[$0.id] } ?? []).reversed()
        List {
            Section("With \(link.selected?.name ?? "partner")") {
                if list.isEmpty { Text("No touches yet").foregroundStyle(.secondary) }
                ForEach(Array(list)) { t in
                    Button { WatchHaptics.play(t) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: t.bpm != nil ? "heart.fill" : (t.mine ? "arrow.up.right" : "arrow.down.left"))
                                .foregroundStyle(Color(rgb: t.startRGB))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.bpm.map { "\($0) BPM" } ?? t.label ?? (t.mine ? "You" : link.selected?.name ?? "Partner"))
                                    .font(.system(.footnote, design: .rounded).weight(.bold))
                                Text(t.sentAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.fill").font(.caption2).foregroundStyle(accent)
                        }
                    }
                    .accessibilityLabel("Feel it again")
                }
            }
        }
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
