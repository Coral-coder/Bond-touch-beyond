import AudioToolbox
import CoreHaptics
import UIKit

/// Plays a touch or heartbeat on the phone's own vibration motor, the way the bracelet would —
/// the stand-in when the bracelet isn't connected.
///
/// iOS only lets an app drive the haptic engine while it's in the foreground. In the background
/// the partner's push notification buzzes the phone instead, and the bracelet plays the touch
/// when it reconnects.
final class PhoneHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    private var canPlay: Bool { UIApplication.shared.applicationState == .active }

    /// Replays a touch's rhythm. Generation 2 (on/off milliseconds): each press is a buzz of
    /// its length. Generation 3 (50 ms bar samples): finger contact buzzes, getting sharper
    /// toward the end of the bar, so a slide feels like it moves; two fingers feel stronger.
    func play(_ touch: TouchMessage) {
        play(touch.generation == 3 ? Self.events(samples: touch.pattern) : Self.events(onOff: touch.pattern))
    }

    /// A heartbeat: a strong "lub" and a softer "dub" per beat, at `bpm`, for `seconds`.
    func playHeartbeat(bpm: Int, seconds: Double = 5) {
        let period = 60.0 / Double(min(max(bpm, 30), 220))
        var events: [CHHapticEvent] = []
        var t = 0.0
        while t < seconds {
            events.append(Self.buzz(at: t, duration: 0.12, intensity: 1.0, sharpness: 0.25))
            if period > 0.4 { events.append(Self.buzz(at: t + 0.22, duration: 0.08, intensity: 0.55, sharpness: 0.2)) }
            t += period
        }
        play(events)
    }

    // MARK: - In the background

    /// The touch's rhythm while the app runs in the background, where iOS doesn't let apps
    /// drive the haptic engine: the system vibration, once per press (a heartbeat: once per
    /// beat). Each system buzz lasts ~0.4 s, so presses closer than that merge into one.
    func playRhythmInBackground(_ touch: TouchMessage) {
        // Best: the system's own patterned vibration (private; looked up at run time, so it
        // simply isn't used where missing) — the exact rhythm at full strength, in one go.
        if let vibrate = Self.playWithVibration {
            var on: [Int] = []
            if let bpm = touch.heartbeatBPM {
                let period = Int(EKG.period(bpm: bpm) * 1000)
                var total = 0
                while total < 5000 { on += [140, max(period - 140, 60)]; total += period }
            } else {
                var total = 0
                for ms in touch.onOffMs where total < 10_000 { on.append(max(ms, 1)); total += max(ms, 1) }
            }
            var vibe: [Any] = []
            for (i, ms) in on.enumerated() { vibe.append(i % 2 == 0); vibe.append(i % 2 == 0 ? max(ms, 60) : ms) }
            vibrate(kSystemSoundID_Vibrate, nil, ["VibePattern": vibe, "Intensity": 1.0] as NSDictionary)
            return
        }
        var starts: [Double] = []
        if let bpm = touch.heartbeatBPM {
            let period = EKG.period(bpm: bpm)
            var at = 0.0
            while at < 5 { starts.append(at + EKG.spikeAt); at += period }
        } else {
            var at = 0.0
            for (i, ms) in touch.onOffMs.enumerated() {
                if i % 2 == 0 { starts.append(at) }
                at += Double(max(ms, 0)) / 1000
                if at > 10 { break }
            }
        }
        var last = -1.0
        let bg = UIApplication.shared.beginBackgroundTask(withName: "touch-rhythm")
        for s in starts where s - last >= 0.45 {
            last = s
            DispatchQueue.main.asyncAfter(deadline: .now() + s) { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + last + 1) { UIApplication.shared.endBackgroundTask(bg) }
    }

    private typealias PlayWithVibration = @convention(c) (UInt32, AnyObject?, NSDictionary) -> Void
    private static let playWithVibration: PlayWithVibration? = {
        guard let h = dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_NOW),
              let s = dlsym(h, "AudioServicesPlaySystemSoundWithVibration") else { return nil }
        return unsafeBitCast(s, to: PlayWithVibration.self)
    }()

    // MARK: - Patterns

    private static func events(onOff pattern: [Int]) -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []
        var t = 0.0
        for (i, ms) in pattern.enumerated() {
            let d = Double(max(ms, 0)) / 1000
            if i % 2 == 0, d > 0 { events.append(buzz(at: t, duration: max(d, 0.04), intensity: 1, sharpness: 0.4)) }
            t += d
            if t > 10 { break }
        }
        return events
    }

    private static func events(samples: [Int]) -> [CHHapticEvent] {
        let slot = Double(TouchPattern.sampleMs) / 1000
        var events: [CHHapticEvent] = []
        for (i, sample) in samples.prefix(TouchPattern.maxSamples).enumerated() where sample != TouchPattern.none {
            let fingers = TouchPattern.fingers(in: sample)
            guard !fingers.isEmpty else { continue }
            let position = Double(fingers.reduce(0, +)) / Double(fingers.count) / Double(TouchPattern.positions - 1)
            events.append(buzz(at: Double(i) * slot, duration: slot,
                               intensity: fingers.count > 1 ? 1.0 : 0.8, sharpness: Float(0.15 + 0.7 * position)))
        }
        return events
    }

    private static func buzz(at time: Double, duration: Double, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                      relativeTime: time, duration: duration)
    }

    // MARK: - Engine

    private func play(_ events: [CHHapticEvent]) {
        guard canPlay, !events.isEmpty else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = startedEngine() else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)   // no Core Haptics: one plain buzz
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try player?.stop(atTime: CHHapticTimeImmediate)
            player = try engine.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func startedEngine() -> CHHapticEngine? {
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        }
        try? engine?.start()
        return engine
    }
}
