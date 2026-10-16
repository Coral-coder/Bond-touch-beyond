import SwiftUI
import UIKit

/// Records a touch the way the Bond Touch More bar does: the first touch opens a window
/// (5 s by default, up to 10 s); every 50 ms one sample records where up to two fingers
/// are on the bar's 9 positions. Lifting and pausing is fine — the touch is sent when the
/// window runs out, or earlier with "Send now".
@MainActor
final class TouchBarRecorder: ObservableObject {
    @Published private(set) var samples: [Int] = []
    @Published private(set) var recording = false
    @Published private(set) var remaining: Double = 0
    /// Finger positions along the bar, 0…1, as last reported by the surface.
    @Published var fingers: [CGFloat] = []

    var windowSeconds: Double = 5
    /// Called with the finished samples (trimmed) when the window ends or on `finish()`.
    var onFinish: (([Int]) -> Void)?

    private var timer: Timer?
    private var started = Date()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var maxSamples: Int { min(TouchPattern.maxSamples, Int(windowSeconds * 1000) / TouchPattern.sampleMs) }
    var progress: Double { recording ? 1 - remaining / windowSeconds : 0 }

    /// The surface reports the current finger positions (0…1 along the bar).
    func update(_ positions: [CGFloat]) {
        let wasEmpty = fingers.isEmpty
        fingers = positions
        if !positions.isEmpty, wasEmpty { haptic.impactOccurred(intensity: 0.6) }
        if !positions.isEmpty, !recording { start() }
    }

    private func start() {
        samples = []
        recording = true
        started = Date()
        remaining = windowSeconds
        haptic.prepare()
        timer = Timer.scheduledTimer(withTimeInterval: Double(TouchPattern.sampleMs) / 1000, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let bar = fingers.map { Int(($0 * CGFloat(TouchPattern.positions - 1)).rounded()) }
        samples.append(TouchPattern.sample(bar))
        remaining = max(0, windowSeconds - Date().timeIntervalSince(started))
        if samples.count >= maxSamples || remaining <= 0 { finish() }
    }

    /// Ends the window now and delivers the touch (if anything was touched).
    func finish() {
        guard recording else { return }
        stopTimer()
        let touch = TouchPattern.trimmed(samples)
        if !touch.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFinish?(touch)
        }
    }

    /// Discards the current recording.
    func cancel() {
        stopTimer()
        samples = []
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recording = false
        remaining = 0
    }
}

/// A multi-touch surface (UIKit, so two fingers work like on the real bar) that reports
/// finger positions along its long axis, 0 at the start and 1 at the end. Vertical bars
/// put position 8 at the top, as the original app draws it.
struct MultiTouchBar: UIViewRepresentable {
    var vertical: Bool
    var onChange: ([CGFloat]) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.vertical = vertical
        uiView.onChange = onChange
    }

    final class TouchView: UIView {
        var vertical = false
        var onChange: (([CGFloat]) -> Void)?
        private var active: [UITouch] = []

        private func report() {
            let values = active.prefix(2).map { t -> CGFloat in
                let p = t.location(in: self)
                let f = vertical ? 1 - p.y / max(bounds.height, 1) : p.x / max(bounds.width, 1)
                return min(max(f, 0), 1)
            }
            onChange?(Array(values))
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            active += touches.filter { !active.contains($0) }; report()
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report() }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.removeAll { touches.contains($0) }; report()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.removeAll { touches.contains($0) }; report()
        }
    }
}

/// The glowing glass touch bar: finger blobs light up where you touch, in the touch colour.
struct TouchBarSurface: View {
    @ObservedObject var recorder: TouchBarRecorder
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
                ForEach(Array(recorder.fingers.enumerated()), id: \.offset) { _, f in
                    let tint = Color(rgbInt: blend(Double(f)))
                    Circle()
                        .fill(RadialGradient(colors: [.white, tint.opacity(0.9), tint.opacity(0)],
                                             center: .center, startRadius: 2, endRadius: short * 0.75))
                        .frame(width: short * 1.5, height: short * 1.5)
                        .position(point(f, long, short))
                        .blendMode(.screen)
                }
            }
            .clipShape(Capsule())
            .overlay(MultiTouchBar(vertical: vertical) { recorder.update($0) })
        }
        .accessibilityElement()
        .accessibilityLabel("Touch bar")
        .accessibilityHint("Touch, tap and slide; the touch is sent when the timer runs out")
    }

    private func point(_ f: CGFloat, _ long: CGFloat, _ short: CGFloat) -> CGPoint {
        let pad = short / 2
        let along = pad + (long - pad * 2) * f
        return vertical ? CGPoint(x: short / 2, y: long - along) : CGPoint(x: along, y: short / 2)
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
                ColorPicker("Start colour", selection: $startColor).labelsHidden()
                ColorPicker("End colour", selection: $endColor).labelsHidden()
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
            startColor = Color(rgbInt: store.profile.colorRGB)
            recorder.windowSeconds = store.touchWindowSeconds
            recorder.onFinish = { samples in
                lastTouch = samples
                if mode == .createMeaning { saving = true; return }
                Task {
                    await model.sendTouch(pattern: samples, generation: 3,
                                          colorRGB: startColor.rgbInt, endColorRGB: endColor.rgbInt)
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
