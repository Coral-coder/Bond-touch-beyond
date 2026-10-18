import CoreHaptics
import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The long-press view of a touch notification: the touch replays as an animation (drawn as
/// the app draws it) and the phone buzzes in its rhythm; Touch back / Send my heartbeat
/// are the notification's buttons.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = ReplayModel()
    private var engine: CHHapticEngine?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ReplayView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: view.bounds.width, height: 220)
    }

    func didReceive(_ notification: UNNotification) {
        guard let touch = TouchNotification.touch(from: notification.request.content.userInfo) else { return }
        model.touch = touch
        model.start = Date()
        buzz(touch)
    }

    /// The touch's rhythm on the phone's motor (best effort — a quiet no-op where unavailable).
    private func buzz(_ t: TouchMessage) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() else { return }
        self.engine = engine
        var events: [CHHapticEvent] = []
        func tap(_ at: Double, _ d: Double, _ i: Float) {
            events.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                                                     CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)],
                                        relativeTime: at, duration: d))
        }
        if let bpm = t.heartbeatBPM {
            let period = EKG.period(bpm: bpm)
            var at = 0.0
            while at < 5 { tap(at + EKG.spikeAt, 0.1, 1); at += period }
        } else {
            var at = 0.0
            for (i, ms) in t.onOffMs.enumerated() {
                let d = Double(max(ms, 0)) / 1000
                if i % 2 == 0, d > 0 { tap(at, max(d, 0.04), 1) }
                at += d
                if at > 10 { break }
            }
        }
        guard !events.isEmpty, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }
}

final class ReplayModel: ObservableObject {
    @Published var touch: TouchMessage?
    @Published var start = Date()
}

/// The touch drawn across the view, revealed left to right in real time, on a loop; a
/// heartbeat is drawn as its live EKG.
struct ReplayView: View {
    @ObservedObject var model: ReplayModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0x123A5C), Color(rgbInt: 0x0B2440)], startPoint: .top, endPoint: .bottom)
            if let t = model.touch {
                if let bpm = t.heartbeatBPM {
                    EKGView(bpm: bpm, colorRGB: t.colorRGB, start: model.start, lineWidth: 4).padding(.vertical, 24)
                } else {
                    TimelineView(.animation) { ctx in
                        let duration = max(Double(t.onOffMs.reduce(0, +)) / 1000, 0.6)
                        let progress = min(1, ctx.date.timeIntervalSince(model.start)
                            .truncatingRemainder(dividingBy: duration + 1.2) / duration)
                        TouchViz(pattern: t.pattern, generation: t.generation, colorRGB: t.colorRGB,
                                 endColorRGB: t.endColorRGB, height: 150)
                            .mask(alignment: .leading) {
                                GeometryReader { g in Rectangle().frame(width: g.size.width * progress) }
                            }
                            .padding(.horizontal, 16)
                    }
                }
                if let label = t.meaningLabel, t.heartbeatBPM == nil {
                    VStack {
                        Text([t.meaningEmoji, label].compactMap { $0 }.joined(separator: " "))
                            .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.45)))
                        Spacer()
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}
