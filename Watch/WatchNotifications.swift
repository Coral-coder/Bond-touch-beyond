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
        Canvas { ctx, size in
            let color = Color(rgb: touch.startRGB)
            let line = compact ? max(2.5, size.height * 0.16) : 5
            let pill = compact ? max(6, size.height * 0.42) : 14
            if let bpm = touch.bpm {
                // Two seconds of EKG at its BPM.
                let period = 60.0 / Double(min(max(bpm, 30), 220)), w = size.width, mid = size.height * 0.6
                var path = Path()
                path.move(to: CGPoint(x: 0, y: mid))
                var t = 0.0
                while t < 2.4 {
                    let x = CGFloat(t / 2.4) * w, beat = CGFloat(period / 2.4) * w
                    path.addLine(to: CGPoint(x: x + beat * 0.30, y: mid))
                    path.addLine(to: CGPoint(x: x + beat * 0.36, y: mid - size.height * 0.5))
                    path.addLine(to: CGPoint(x: x + beat * 0.42, y: mid + size.height * 0.3))
                    path.addLine(to: CGPoint(x: x + beat * 0.48, y: mid))
                    t += period
                }
                path.addLine(to: CGPoint(x: w, y: mid))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1.5, line * 0.6), lineCap: .round, lineJoin: .round))
            } else if touch.generation == 3 {
                let s = TouchPattern.trimmed(touch.pattern), n = max(s.count, 2)
                var path = Path(), started = false
                for (i, sample) in s.enumerated() {
                    guard let f = TouchPattern.fingers(in: sample).first else { started = false; continue }
                    let inset = line / 2 + 1
                    let p = CGPoint(x: inset + (size.width - inset * 2) * CGFloat(i) / CGFloat(n - 1),
                                    y: size.height - inset - (size.height - inset * 2) * CGFloat(f) / CGFloat(TouchPattern.positions - 1))
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
                ctx.stroke(path, with: .shading(.linearGradient(Gradient(colors: [color, Color(rgb: touch.endRGB)]),
                                                                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))),
                           style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            } else {
                var at = 0.0, presses: [(Double, Double)] = []
                for (i, ms) in touch.pattern.enumerated() { if i % 2 == 0 { presses.append((at, Double(max(ms, 1)))) }; at += Double(max(ms, 1)) }
                let total = max(presses.last.map { $0.0 + $0.1 } ?? 1, 1)
                for p in presses {
                    let x = 4 + (size.width - 8) * CGFloat(p.0 / total)
                    let w = max((size.width - 8) * CGFloat(p.1 / total), pill)
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: size.height / 2 - pill / 2, width: w, height: pill), cornerRadius: pill / 2),
                             with: .color(color))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: 0x0B2440)).opacity(compact ? 0 : 1))
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
