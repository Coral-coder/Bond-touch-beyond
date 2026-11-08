import Foundation

/// An EKG-shaped heartbeat: the trace sits on the baseline between beats, and each beat is a
/// small P bump, a sharp spike up (R) and straight down (S), then a soft T wave — like a
/// heart monitor. Shared by the screen (`EKGView`), the bracelet and the beep.
enum EKG {
    /// When, in seconds after a beat starts, the R spike peaks (the beep plays then).
    static let spikeAt = 0.18

    /// Seconds per beat at `bpm` (30…220).
    static func period(bpm: Int) -> Double { 60.0 / Double(min(max(bpm, 30), 220)) }

    /// The trace height (−1…1, 0 = baseline) `t` seconds after a beat starts. The beat keeps
    /// its real shape; only a very fast heart squeezes it to fit the period.
    static func level(_ t: Double, bpm: Int) -> Double {
        let squeeze = min(1, period(bpm: bpm) / 0.5)
        let x = t / squeeze
        func bump(_ at: Double, _ width: Double, _ height: Double) -> Double {
            let d = (x - at) / width
            return height * exp(-d * d)
        }
        return bump(0.08, 0.025, 0.12)      // P
            + bump(0.155, 0.010, -0.12)     // Q
            + bump(spikeAt, 0.012, 1.0)     // R — up
            + bump(0.205, 0.012, -0.75)     // S — down
            + bump(0.36, 0.040, 0.26)       // T
    }

    /// The trace height at `elapsed` seconds into a heartbeat that started at 0.
    static func level(elapsed: Double, bpm: Int) -> Double {
        guard elapsed >= 0 else { return 0 }
        return level(elapsed.truncatingRemainder(dividingBy: period(bpm: bpm)), bpm: bpm)
    }

    /// The heartbeat on a Bond Touch More bar, as 50 ms samples in one message: each beat is
    /// one pulse, the spike up to one end of the bar and down to the other (200 ms), and
    /// everything between pulses is the "no finger" sample, so nothing vibrates (or lights)
    /// between beats. The gaps keep the rhythm inside the message itself.
    static func samples(bpm: Int, seconds: Double = 5) -> [Int] {
        let total = min(TouchPattern.maxSamples, Int(seconds * 1000) / TouchPattern.sampleMs)
        let perBeat = max(6, Int((period(bpm: bpm) * 1000).rounded()) / TouchPattern.sampleMs)
        let pulse = [6, 8, 0, 2]      // up and down the bar: the beat
        var out: [Int] = []
        while out.count < total {
            for k in 0..<perBeat where out.count < total {
                out.append(k < pulse.count ? TouchPattern.sample([pulse[k]]) : TouchPattern.sample([]))
            }
        }
        return out
    }

    /// The heartbeat for bracelets that only buzz on/off (and the original backend): one firm
    /// buzz per beat, and nothing between beats.
    static func onOff(bpm: Int, seconds: Double = 5) -> [Int] {
        let periodMs = Int(period(bpm: bpm) * 1000)
        let beats = max(1, Int(seconds * 1000) / periodMs)
        var pattern: [Int] = []
        for i in 0..<beats {
            pattern.append(150)                                          // the beat (on)
            if i < beats - 1 { pattern.append(max(periodMs - 150, 80)) } // still (off)
        }
        return pattern
    }

    /// The heartbeat colour.
    static let colorRGB = 0xE85D75
}

/// A heartbeat on screen right now: the partner's arriving, or one replayed from history.
struct HeartbeatShow: Identifiable, Equatable {
    let id = UUID()
    let bpm: Int
    let colorRGB: Int
    let name: String
    let start: Date
    let seconds: Double
    /// The heartbeat touch it's playing, so its card in the history can draw along live.
    var touchID: UUID? = nil
}
