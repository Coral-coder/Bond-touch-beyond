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

/// The watch's look at a touch notification: who, the meaning, the touch drawn — and when it
/// opens, the touch plays on the wrist in its own rhythm. "Feel it again" replays it.
final class TouchNotificationController: WKUserNotificationHostingController<TouchNotificationView> {
    private var title = ""
    private var touch: WatchTouch?

    override var body: TouchNotificationView { TouchNotificationView(title: title, touch: touch) }

    override func didReceive(_ notification: UNNotification) {
        title = notification.request.content.title
        touch = WatchTouch(notification: notification.request.content.userInfo)
        if let touch { WatchHaptics.play(touch) }
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

/// A touch drawn small: the bar trace, or the tap rhythm as pills.
struct WatchTouchDrawing: View {
    let touch: WatchTouch

    var body: some View {
        Canvas { ctx, size in
            let color = Color(rgb: touch.startRGB)
            if touch.generation == 3 {
                let s = TouchPattern.trimmed(touch.pattern), n = max(s.count, 2)
                var path = Path(), started = false
                for (i, sample) in s.enumerated() {
                    guard let f = TouchPattern.fingers(in: sample).first else { started = false; continue }
                    let p = CGPoint(x: 6 + (size.width - 12) * CGFloat(i) / CGFloat(n - 1),
                                    y: size.height - 6 - (size.height - 12) * CGFloat(f) / CGFloat(TouchPattern.positions - 1))
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            } else {
                var at = 0.0, presses: [(Double, Double)] = []
                for (i, ms) in touch.pattern.enumerated() { if i % 2 == 0 { presses.append((at, Double(max(ms, 1)))) }; at += Double(max(ms, 1)) }
                let total = max(presses.last.map { $0.0 + $0.1 } ?? 1, 1)
                for p in presses {
                    let x = 4 + (size.width - 8) * CGFloat(p.0 / total)
                    let w = max((size.width - 8) * CGFloat(p.1 / total), 14)
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: size.height / 2 - 7, width: w, height: 14), cornerRadius: 7),
                             with: .color(color))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: 0x0B2440)))
    }
}

/// Handles "Feel it again" on a touch notification: the watch app opens and plays it.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let touch = WatchTouch(notification: response.notification.request.content.userInfo) {
            // Give the app a moment to come forward, so the haptics play.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WatchHaptics.play(touch) }
        }
        completionHandler()
    }
}
