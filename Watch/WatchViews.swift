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

struct WatchTouchBarView: View {
    @EnvironmentObject var link: PhoneLink
    @StateObject private var recorder = WatchRecorder()
    @State private var picking = false

    private var color: Color { Color(rgb: link.selected?.colorRGB ?? 0xFF2E74) }

    var body: some View {
        VStack(spacing: 6) {
            Button { picking = true } label: {
                HStack(spacing: 4) {
                    Circle().fill(link.selected?.online == true ? Color(rgb: 0xAEE63C) : .gray).frame(width: 6, height: 6)
                    Text(link.selected?.name ?? "Partner").font(.system(.footnote, design: .rounded).weight(.heavy))
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack {
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.35)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                    if let p = recorder.position {
                        Circle()
                            .fill(RadialGradient(colors: [.white, color, color.opacity(0)], center: .center,
                                                 startRadius: 2, endRadius: geo.size.width * 0.7))
                            .frame(width: geo.size.width * 1.3, height: geo.size.width * 1.3)
                            .position(x: geo.size.width / 2,
                                      y: geo.size.width / 2 + (geo.size.height - geo.size.width) * (1 - p))
                    }
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let h = max(geo.size.height - geo.size.width, 1)
                        recorder.touch(min(max(1 - (v.location.y - geo.size.width / 2) / h, 0), 1))
                    }
                    .onEnded { _ in recorder.touch(nil) })
            }
            .frame(width: 58)

            if recorder.recording {
                HStack(spacing: 6) {
                    ProgressView(value: 1 - recorder.remaining / max(recorder.windowSeconds, 0.1))
                        .tint(accent).frame(width: 50)
                    Button("Send") { recorder.finish() }.font(.caption2.weight(.heavy)).tint(accent)
                }
            } else {
                Text(link.lastSent.map { "Sent " + $0.formatted(date: .omitted, time: .shortened) } ?? "Touch to start")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
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
                        link.sendTouch(pattern: m.pattern, generation: m.generation, startRGB: m.startRGB, endRGB: m.endRGB)
                    } label: {
                        HStack {
                            Circle().fill(LinearGradient(colors: [Color(rgb: m.startRGB), Color(rgb: m.endRGB)],
                                                         startPoint: .leading, endPoint: .trailing))
                                .frame(width: 12, height: 12)
                            Text(m.name).font(.system(.body, design: .rounded).weight(.bold))
                        }
                    }
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
