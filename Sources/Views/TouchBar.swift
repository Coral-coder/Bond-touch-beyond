import SwiftUI
import UIKit

/// Records a touch the way the Bond Touch More bar does: the first touch opens a window
/// (5 s by default, up to 10 s); the bar is sampled every 50 ms for where up to two fingers
/// are on its 9 positions. Lifting and pausing is fine — the touch is sent when the window
/// runs out, or earlier with "Send now".
///
/// Every finger change is logged with the touch's own timestamp and the 50 ms samples are
/// computed from that log, so a short tap or a fast slide is never lost to a late timer.
@MainActor
final class TouchBarRecorder: ObservableObject {
    /// Finger positions along the bar (0…1), for drawing only. A separate object so the
    /// screens holding the recorder don't redraw on every finger movement.
    final class Fingers: ObservableObject {
        @Published var positions: [CGFloat] = []
    }

    @Published private(set) var samples: [Int] = []
    @Published private(set) var recording = false
    /// Seconds left, in 0.1 s steps.
    @Published private(set) var remaining: Double = 0
    let fingers = Fingers()

    var windowSeconds: Double = 5
    /// Called with the finished samples (trimmed) when the window ends or on `finish()`.
    var onFinish: (([Int]) -> Void)?

    private var events: [TouchPattern.BarEvent] = []
    private var current: [Int] = []
    private var started: TimeInterval = 0
    private var link: CADisplayLink?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var progress: Double { recording ? 1 - remaining / windowSeconds : 0 }
    private var window: Double { min(windowSeconds, Double(TouchPattern.maxSamples * TouchPattern.sampleMs) / 1000) }

    /// The surface reports the fingers (0…1 along the bar) and the event's timestamp
    /// (system uptime, as UITouch reports it).
    func update(_ positions: [CGFloat], at time: TimeInterval) {
        let wasEmpty = fingers.positions.isEmpty
        fingers.positions = positions
        if !positions.isEmpty, wasEmpty { haptic.impactOccurred(intensity: 0.6) }
        if !positions.isEmpty, !recording { start(at: time) }
        guard recording else { return }
        let bar = positions.prefix(2).map { Int(($0 * CGFloat(TouchPattern.positions - 1)).rounded()) }
        guard bar != current else { return }
        current = bar
        events.append(.init(t: max(0, time - started), fingers: bar))
    }

    private func start(at time: TimeInterval) {
        events = []
        current = []
        samples = []
        started = time
        recording = true
        remaining = window
        haptic.prepare()
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)   // keeps running while anything scrolls
        self.link = link
    }

    fileprivate func tick() {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        if elapsed >= window { finish(); return }
        let left = (max(0, window - elapsed) * 10).rounded(.up) / 10
        if left != remaining { remaining = left }
        let n = Int(elapsed * 1000) / TouchPattern.sampleMs
        if n != samples.count { samples = TouchPattern.samples(from: events, duration: Double(n * TouchPattern.sampleMs) / 1000) }
    }

    /// Ends the window now and delivers the touch (if anything was touched).
    func finish() {
        guard recording else { return }
        let elapsed = min(window, ProcessInfo.processInfo.systemUptime - started)
        // A finger still down at the end counts up to the end of the window.
        samples = TouchPattern.samples(from: events, duration: elapsed)
        stop()
        let touch = TouchPattern.trimmed(samples)
        if !touch.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFinish?(touch)
        }
    }

    /// Discards the current recording.
    func cancel() {
        stop()
        samples = []
    }

    private func stop() {
        link?.invalidate()
        link = nil
        recording = false
        remaining = 0
        events = []
        current = []
    }

    /// CADisplayLink retains its target; this breaks the cycle.
    @MainActor private final class Ticker: NSObject {
        weak var owner: TouchBarRecorder?
        init(_ owner: TouchBarRecorder) { self.owner = owner }
        @objc func tick() { owner?.tick() }
    }
}

/// A multi-touch surface (UIKit, so two fingers work like on the real bar) that reports
/// finger positions along its long axis, 0 at the first position mark and 1 at the last.
/// Vertical bars put position 8 at the top, as the original app draws it.
///
/// While a finger is on it, any scroll view around it stops scrolling, and scroll views
/// don't hold back its touches, so taps register the moment they happen.
struct MultiTouchBar: UIViewRepresentable {
    var vertical: Bool
    var onChange: ([CGFloat], TimeInterval) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.isMultipleTouchEnabled = true
        v.isExclusiveTouch = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.vertical = vertical
        uiView.onChange = onChange
    }

    final class TouchView: UIView {
        var vertical = false
        var onChange: (([CGFloat], TimeInterval) -> Void)?
        private var active: [UITouch] = []
        private var lockedScrollViews: [UIScrollView] = []

        private var scrollViews: [UIScrollView] {
            var out: [UIScrollView] = []
            var v = superview
            while let s = v { if let sv = s as? UIScrollView { out.append(sv) }; v = s.superview }
            return out
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scrollViews.forEach { $0.delaysContentTouches = false }
        }

        private func report(_ event: UIEvent?) {
            let long = vertical ? bounds.height : bounds.width
            let short = vertical ? bounds.width : bounds.height
            let pad = min(short / 2, long / 4)
            let values = active.prefix(2).map { t -> CGFloat in
                let p = t.location(in: self)
                let along = vertical ? long - p.y : p.x
                return min(max((along - pad) / max(long - pad * 2, 1), 0), 1)
            }
            onChange?(Array(values), event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        }

        private func lockScrolling(_ lock: Bool) {
            if lock {
                guard lockedScrollViews.isEmpty else { return }
                lockedScrollViews = scrollViews.filter(\.isScrollEnabled)
                lockedScrollViews.forEach { $0.isScrollEnabled = false }
            } else {
                lockedScrollViews.forEach { $0.isScrollEnabled = true }
                lockedScrollViews = []
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            active += touches.filter { !active.contains($0) }
            lockScrolling(true)
            report(event)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.removeAll { touches.contains($0) }
            report(event)
            if active.isEmpty { lockScrolling(false) }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchesEnded(touches, with: event)
        }
    }
}

/// The glowing glass touch bar: finger blobs light up where you touch, in the touch colour.
struct TouchBarSurface: View {
    let recorder: TouchBarRecorder
    var vertical = false
    var startRGB: Int
    var endRGB: Int

    var body: some View {
        GeometryReader { geo in
            let long = vertical ? geo.size.height : geo.size.width
            let short = vertical ? geo.size.width : geo.size.height
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.28)],
                                         startPoint: vertical ? .leading : .top,
                                         endPoint: vertical ? .trailing : .bottom))
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                // The bar's 9 position marks.
                ForEach(0..<TouchPattern.positions, id: \.self) { i in
                    Circle().fill(.white.opacity(0.18)).frame(width: 4, height: 4)
                        .position(point(CGFloat(i) / CGFloat(TouchPattern.positions - 1), long, short))
                }
                FingerGlow(fingers: recorder.fingers, vertical: vertical,
                           startRGB: startRGB, endRGB: endRGB)
            }
            .clipShape(Capsule())
            .overlay(MultiTouchBar(vertical: vertical) { recorder.update($0, at: $1) })
        }
        .accessibilityElement()
        .accessibilityLabel("Touch bar")
        .accessibilityHint("Touch, tap and slide; the touch is sent when the timer runs out")
    }

    private func point(_ f: CGFloat, _ long: CGFloat, _ short: CGFloat) -> CGPoint {
        barPoint(f, long: long, short: short, vertical: vertical)
    }
}

/// Where position `f` (0…1) sits on a bar; matches MultiTouchBar's mapping.
private func barPoint(_ f: CGFloat, long: CGFloat, short: CGFloat, vertical: Bool) -> CGPoint {
    let pad = min(short / 2, long / 4)
    let along = pad + (long - pad * 2) * f
    return vertical ? CGPoint(x: short / 2, y: long - along) : CGPoint(x: along, y: short / 2)
}

/// The glowing blobs under the fingers; the only part that redraws as fingers move.
private struct FingerGlow: View {
    @ObservedObject var fingers: TouchBarRecorder.Fingers
    var vertical: Bool
    var startRGB: Int
    var endRGB: Int

    var body: some View {
        GeometryReader { geo in
            let long = vertical ? geo.size.height : geo.size.width
            let short = vertical ? geo.size.width : geo.size.height
            ForEach(Array(fingers.positions.enumerated()), id: \.offset) { _, f in
                let tint = Color(rgbInt: blend(Double(f)))
                Circle()
                    .fill(RadialGradient(colors: [.white, tint.opacity(0.9), tint.opacity(0)],
                                         center: .center, startRadius: 2, endRadius: short * 0.75))
                    .frame(width: short * 1.5, height: short * 1.5)
                    .position(barPoint(f, long: long, short: short, vertical: vertical))
                    .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
    }

    private func blend(_ t: Double) -> Int {
        func c(_ v: Int, _ s: Int) -> Double { Double((v >> s) & 0xFF) }
        let r = c(startRGB, 16) + (c(endRGB, 16) - c(startRGB, 16)) * t
        let g = c(startRGB, 8) + (c(endRGB, 8) - c(startRGB, 8)) * t
        let b = c(startRGB, 0) + (c(endRGB, 0) - c(startRGB, 0)) * t
        return (Int(r) << 16) | (Int(g) << 8) | Int(b)
    }
}

/// The countdown ring shown while a touch is being recorded.
struct CountdownRing: View {
    var progress: Double
    var remaining: Double
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: size * 0.1)
            Circle().trim(from: 0, to: max(0, 1 - progress))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.1f", remaining))
                .font(Theme.font(size * 0.28, .heavy)).foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityLabel(String(format: "%.1f seconds left", remaining))
    }
}

/// Full-screen touch composer: a tall bar, a live 2D preview, the colour gradient, and
/// Send now / Save as meaning.
struct ComposeTouchView: View {
    /// `.send`: the touch goes to the partner when the window ends. `.createMeaning`:
    /// nothing is sent; the recorded touch is saved to the Touch Language.
    enum Mode { case send, createMeaning }
    var mode: Mode = .send

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = TouchBarRecorder()
    @State private var startColor = Color(rgbInt: 0xFF2E74)
    @State private var endColor = Color(rgbInt: 0xBE5BFF)
    /// False until the user picks a colour: a plain touch sends in your own colour (or a
    /// matched meaning's), not a fixed default.
    @State private var colorCustomized = false
    @State private var lastTouch: [Int] = []
    @State private var saving = false
    @State private var meaningName = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Close") { recorder.cancel(); dismiss() }
                    .font(Theme.font(16, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 40).glass(Capsule())
                Spacer()
                Text(mode == .send ? "To \(model.selectedPartner?.displayName ?? "partner")" : "New touch")
                    .font(Theme.font(17, .heavy)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 80, height: 40)
            }

            VStack(spacing: 10) {
                Text(recorder.recording ? "Recording…"
                     : (lastTouch.isEmpty ? "Touch the bar to start" : (mode == .send ? "Sent" : "Recorded — save it below")))
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                TouchViz(pattern: recorder.recording ? recorder.samples : lastTouch, generation: 3,
                         colorRGB: startColor.rgbInt, endColorRGB: endColor.rgbInt, height: 90)
                    .padding(.horizontal, 4)
                Text("Time → · position on the bar ↕").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            .padding(16)
            .glass(cornerRadius: 28)

            HStack(alignment: .center, spacing: 24) {
                TouchBarSurface(recorder: recorder, vertical: true,
                                startRGB: startColor.rgbInt, endRGB: endColor.rgbInt)
                    .frame(width: 110)
                VStack(spacing: 8) {
                    CountdownRing(progress: recorder.progress,
                                  remaining: recorder.recording ? recorder.remaining : store.touchWindowSeconds)
                    Text("Pauses are fine —\nsends at 0").multilineTextAlignment(.center)
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                Text("Colour").font(Theme.font(15, .bold)).foregroundStyle(.white)
                LinearGradient(colors: [startColor, endColor], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 22).clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 2))
                // The custom setter marks the colour customized only on a real picker edit,
                // not when onAppear sets the default (which assigns the @State directly).
                ColorPicker("Start colour", selection: Binding(
                    get: { startColor }, set: { startColor = $0; colorCustomized = true })).labelsHidden()
                ColorPicker("End colour", selection: Binding(
                    get: { endColor }, set: { endColor = $0; colorCustomized = true })).labelsHidden()
            }
            .padding(14).glass(cornerRadius: 22)

            HStack(spacing: 12) {
                Button("Save as meaning") { saving = true }
                    .buttonStyle(GlassButtonStyle(height: 54))
                    .disabled(recorder.samples.isEmpty && lastTouch.isEmpty)
                Button(mode == .send ? "Send now" : "Done") { recorder.finish() }
                    .buttonStyle(AccentButtonStyle(height: 54))
                    .disabled(!recorder.recording)
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 20)
        .background(AppBackground())
        .onAppear {
            // Default to your own colour (single colour), not a fixed pink/violet.
            startColor = Color(rgbInt: store.profile.colorRGB)
            endColor = Color(rgbInt: store.profile.colorRGB)
            recorder.windowSeconds = store.touchWindowSeconds
            recorder.onFinish = { samples in
                lastTouch = samples
                if mode == .createMeaning { saving = true; return }
                // Regular touches send in your colour, unless you picked a colour, or the
                // touch closely matches a saved meaning (then its colour).
                let colors: (Int, Int)
                if colorCustomized {
                    colors = (startColor.rgbInt, endColor.rgbInt)
                } else if let m = model.closeMeaning(pattern: samples, generation: 3) {
                    colors = (m.colorRGB, m.endColorRGB)
                } else {
                    colors = (store.profile.colorRGB, store.profile.colorRGB)
                }
                Task {
                    await model.sendTouch(pattern: samples, generation: 3,
                                          colorRGB: colors.0, endColorRGB: colors.1)
                }
            }
        }
        .alert("Save as meaning", isPresented: $saving) {
            TextField("Name, e.g. Love you", text: $meaningName)
            Button("Save") {
                let pattern = recorder.recording ? TouchPattern.trimmed(recorder.samples) : lastTouch
                guard !pattern.isEmpty else { return }
                let m = TouchMeaning(label: meaningName.isEmpty ? "Touch" : String(meaningName.prefix(20)),
                                     emoji: "", colorRGB: startColor.rgbInt, endColorRGB: endColor.rgbInt,
                                     pattern: pattern, isNew: true, generation: 3)
                Task { await model.addMeaning(m) }
                meaningName = ""
                if mode == .createMeaning { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
