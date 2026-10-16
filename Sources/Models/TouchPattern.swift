import Foundation

/// The two touch formats the original backend and bracelets use (docs/BTM_TOUCH_FORMAT.md).
///
/// - **Generation 2** (Bond Touch / BT2 / BT4 / mini): an on/off millisecond list —
///   even indices finger down, odd indices finger up.
/// - **Generation 3** (Bond Touch More, the capacitive bar): one sample every 50 ms, each a
///   byte saying where the fingers are on the bar's 9 positions: `0xFF` no finger,
///   `0xF0 | p` one finger at position p (0…8), `(p2 << 4) | p1` two fingers. At most 200
///   samples (10 s). A slide is just consecutive samples whose position changes.
enum TouchPattern {
    static let sampleMs = 50
    static let maxSamples = 200
    static let positions = 9
    static let none = 0xFF

    /// One sample byte for zero, one or two fingers (positions are clamped to 0…8).
    static func sample(_ fingers: [Int]) -> Int {
        let p = fingers.prefix(2).map { min(max($0, 0), positions - 1) }
        switch p.count {
        case 0: return none
        case 1: return 0xF0 | p[0]
        default: return (p[1] << 4) | p[0]
        }
    }

    /// The finger positions in one sample (empty when no finger is down).
    static func fingers(in sample: Int) -> [Int] {
        let lo = sample & 0x0F, hi = (sample >> 4) & 0x0F
        return [lo, hi].filter { $0 < positions }
    }

    /// Strips leading/trailing "no finger" samples and caps the length at 200.
    static func trimmed(_ samples: [Int]) -> [Int] {
        guard let first = samples.firstIndex(where: { $0 != none }),
              let last = samples.lastIndex(where: { $0 != none }) else { return [] }
        return Array(samples[first...last].prefix(maxSamples))
    }

    /// Generation 3 → 2: any sample with a finger is "on", in 50 ms steps (position is lost).
    static func onOff(fromSamples samples: [Int]) -> [Int] {
        var out: [Int] = []
        var on = true
        var run = 0
        for s in trimmed(samples) {
            let isOn = !fingers(in: s).isEmpty
            if isOn == on { run += sampleMs } else { out.append(run); on = isOn; run = sampleMs }
        }
        if run > 0, on { out.append(run) }
        return out.isEmpty ? [200] : out
    }

    /// Generation 2 → 3, as the original app does for a BTM: "on" becomes the sample
    /// `0x35` (two fingers, at positions 5 and 3), "off" becomes no finger.
    static func samples(fromOnOff onOff: [Int]) -> [Int] {
        var out: [Int] = []
        for (i, ms) in onOff.enumerated() {
            let count = max(1, Int((Double(ms) / Double(sampleMs)).rounded()))
            out += Array(repeating: i % 2 == 0 ? 0x35 : none, count: count)
            if out.count >= maxSamples { break }
        }
        return Array(out.prefix(maxSamples))
    }

    /// Duration of a pattern in milliseconds.
    static func durationMs(_ pattern: [Int], generation: Int) -> Int {
        generation == 3 ? pattern.count * sampleMs : pattern.reduce(0, +)
    }
}
