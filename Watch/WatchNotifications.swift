import HealthKit
import SwiftUI
import UserNotifications
import WatchKit

/// A touch read from a touch notification's userInfo (filled in on the iPhone by the
/// notification extension; same keys as `TouchNotification.Key`).
extension WatchTouch {
    init?(notification info: [AnyHashable: Any]) {
        guard let pattern = info["tPattern"] as? [Int], let start = info["tStart"] as? Int else { return nil }
        var d: [String: Any] = ["id": UUID().uuidString, "bond": info["tBond"] as? String ?? "", "pattern": pattern,
                                "gen": info["tGen"] as? Int ?? 2, "start": start, "end": info["tEnd"] as? Int ?? start,
                                "at": info["tAt"] as? Double ?? Date().timeIntervalSince1970, "mine": false]
        if let l = info["tLabel"] as? String { d["label"] = l }
        if let b = info["tBPM"] as? Int { d["bpm"] = b }
        self.init(d)
    }
}

/// The watch's look at a touch notification: who, the meaning, the touch drawn. When it
/// opens, the wrist feels the touch itself — its exact rhythm, and a slide's rise and fall.
/// "Feel it again" plays it once more.
final class TouchNotificationController: WKUserNotificationHostingController<TouchNotificationView> {
    private var title = ""
    private var touch: WatchTouch?

    override var body: TouchNotificationView { TouchNotificationView(title: title, touch: touch) }

    override func didReceive(_ notification: UNNotification) {
        title = notification.request.content.title
        touch = WatchTouch(notification: notification.request.content.userInfo)
        if let touch { WatchHaptics.alert(touch) }
        notificationActions = [UNNotificationAction(identifier: "feel-again", title: "Feel it again", options: [.foreground])]
    }
}

struct TouchNotificationView: View {
    let title: String
    let touch: WatchTouch?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.headline, design: .rounded))
            if let label = touch?.label { Text(label).font(.footnote).foregroundStyle(.secondary) }
            if let bpm = touch?.bpm { Text("💓 \(bpm) BPM").font(.footnote).foregroundStyle(.secondary) }
            if let touch { WatchTouchDrawing(touch: touch).frame(height: 70) }
        }
    }
}

/// A touch drawn small: the bar trace, the tap rhythm as pills, or a heartbeat's EKG.
/// `compact` (the history list) draws thinner on no panel of its own.
struct WatchTouchDrawing: View {
    let touch: WatchTouch
    var compact = false

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: 0x0B2440)).opacity(compact ? 0 : 1))
    }

    private var line: CGFloat { compact ? 3 : 5 }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        if let bpm = touch.bpm {
            drawEKG(&ctx, size, bpm: bpm)
        } else if touch.generation == 3 {
            drawTrace(&ctx, size)
        } else {
            drawTaps(&ctx, size)
        }
    }

    /// Two and a half seconds of EKG at the heartbeat's BPM.
    private func drawEKG(_ ctx: inout GraphicsContext, _ size: CGSize, bpm: Int) {
        let period: Double = 60.0 / Double(min(max(bpm, 30), 220))
        let w: CGFloat = size.width, h: CGFloat = size.height, mid: CGFloat = h * 0.6
        let beat: CGFloat = CGFloat(period / 2.4) * w
        var path = Path()
        path.move(to: CGPoint(x: 0, y: mid))
        var t: Double = 0
        while t < 2.4 {
            let x: CGFloat = CGFloat(t / 2.4) * w
            path.addLine(to: CGPoint(x: x + beat * 0.30, y: mid))
            path.addLine(to: CGPoint(x: x + beat * 0.36, y: mid - h * 0.5))
            path.addLine(to: CGPoint(x: x + beat * 0.42, y: mid + h * 0.3))
            path.addLine(to: CGPoint(x: x + beat * 0.48, y: mid))
            t += period
        }
        path.addLine(to: CGPoint(x: w, y: mid))
        let style = StrokeStyle(lineWidth: max(1.5, line * 0.6), lineCap: .round, lineJoin: .round)
        ctx.stroke(path, with: .color(Color(rgb: touch.startRGB)), style: style)
    }

    /// The bar trace: time across, position on the bar up and down.
    private func drawTrace(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let s: [Int] = TouchPattern.trimmed(touch.pattern)
        let n: Int = max(s.count, 2)
        let inset: CGFloat = line / 2 + 1
        let top: CGFloat = CGFloat(TouchPattern.positions - 1)
        var path = Path()
        var started = false
        for (i, sample) in s.enumerated() {
            guard let f = TouchPattern.fingers(in: sample).first else { started = false; continue }
            let x: CGFloat = inset + (size.width - inset * 2) * CGFloat(i) / CGFloat(n - 1)
            let y: CGFloat = size.height - inset - (size.height - inset * 2) * CGFloat(f) / top
            if started { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)); started = true }
        }
        let gradient = Gradient(colors: [Color(rgb: touch.startRGB), Color(rgb: touch.endRGB)])
        let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }

    /// The tap rhythm: each press a pill as long as it was held.
    private func drawTaps(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let pill: CGFloat = compact ? max(6, size.height * 0.42) : 14
        var at: Double = 0
        var presses: [(Double, Double)] = []
        for (i, ms) in touch.pattern.enumerated() {
            let d = Double(max(ms, 1))
            if i % 2 == 0 { presses.append((at, d)) }
            at += d
        }
        let total: Double = max(presses.last.map { $0.0 + $0.1 } ?? 1, 1)
        let usable: CGFloat = size.width - 8
        for p in presses {
            let x: CGFloat = 4 + usable * CGFloat(p.0 / total)
            let w: CGFloat = max(usable * CGFloat(p.1 / total), pill)
            let rect = CGRect(x: x, y: size.height / 2 - pill / 2, width: w, height: pill)
            ctx.fill(Path(roundedRect: rect, cornerRadius: pill / 2), with: .color(Color(rgb: touch.startRGB)))
        }
    }
}

/// Handles "Feel it again" on a touch notification: the watch app opens and plays it.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        _ = PhoneLink.shared   // start the phone link even on a background launch
    }

    /// The phone woke the watch app to stand in for the bracelet (its bracelet disconnected):
    /// start Stand-in mode, with no screen needed.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        StandIn.shared.start()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let touch = WatchTouch(notification: response.notification.request.content.userInfo) {
            // Give the app a moment to come forward, so the haptics play.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WatchHaptics.play(touch, again: true) }
        }
        completionHandler()
    }
}
