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

    /// A change of the fingers on the bar: `t` seconds after the touch window opened, the
    /// bar positions (0…8) now touched. Recorded as touch events arrive, independent of any
    /// timer, so nothing depends on the screen keeping up.
    struct BarEvent {
        let t: Double
        let fingers: [Int]
    }

    /// Turns finger changes into 50 ms samples. A slot gets the last finger position seen
    /// during it, so a tap shorter than 50 ms still counts, and a slot with no contact is
    /// "no finger". `duration` is how much of the window to sample (seconds).
    static func samples(from events: [BarEvent], duration: Double) -> [Int] {
        let slot = Double(sampleMs) / 1000
        let count = min(maxSamples, max(0, Int((duration / slot).rounded(.up))))
        var out: [Int] = []
        out.reserveCapacity(count)
        var state: [Int] = []
        var i = 0
        for n in 0..<count {
            let end = Double(n + 1) * slot
            var touched = state
            while i < events.count, events[i].t < end {
                state = events[i].fingers
                if !state.isEmpty { touched = state }
                i += 1
            }
            if !state.isEmpty { touched = state }
            out.append(sample(touched))
        }
        return out
    }

    /// How alike two generation-3 touches are, 0…1: both are resampled to a common length
    /// and compared position by position (a finger within one bar position counts as a
    /// match, as does "no finger" on both). Used to spot a touch that matches a saved
    /// meaning so it sends in that meaning's colour.
    static func similarity(_ a: [Int], _ b: [Int]) -> Double {
        let ta = trimmed(a), tb = trimmed(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let n = 40
        func resample(_ s: [Int]) -> [Int] {
            guard s.count > 1 else { return Array(repeating: s[0], count: n) }
            return (0..<n).map { i in s[min(s.count - 1, Int((Double(i) / Double(n - 1)) * Double(s.count - 1) + 0.5))] }
        }
        let ra = resample(ta), rb = resample(tb)
        var match = 0
        for i in 0..<n {
            let fa = fingers(in: ra[i]).first, fb = fingers(in: rb[i]).first
            if fa == nil, fb == nil { match += 1 }
            else if let fa, let fb, abs(fa - fb) <= 1 { match += 1 }
        }
        return Double(match) / Double(n)
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
