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
