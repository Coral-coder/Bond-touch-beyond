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

    /// How alike two touches are, 0…1, in any mix of formats — "the same general shape",
    /// never needing a perfect copy. Each touch becomes a line over time (where the finger is
    /// on the bar, or nothing); the two lines are lined up by dynamic time warping, so being a
    /// little early, late, faster or slower in places costs little, and positions only need to
    /// be close (within 3 of the 9 count partly). Then a light penalty for a different overall
    /// length or number of presses. A gen-2 on/off rhythm has no positions, so it's compared
    /// by contact only.
    static func matchScore(_ a: [Int], generation ga: Int, _ b: [Int], generation gb: Int) -> Double {
        let positional = ga == 3 && gb == 3
        let la = line(ga == 3 ? a : samples(fromOnOff: a), positions: positional)
        let lb = line(gb == 3 ? b : samples(fromOnOff: b), positions: positional)
        return shapeScore(la, lb)
    }

    /// Same as `matchScore` for two touch-bar touches.
    static func similarity(_ a: [Int], _ b: [Int]) -> Double { matchScore(a, generation: 3, b, generation: 3) }

    /// The score a touch needs to count as a saved meaning (about 75%: the same general shape).
    static func matchThreshold(_ ga: Int, _ gb: Int) -> Double { 0.72 }

    /// A touch as a line over time: the finger's position on the bar per 50 ms sample (two
    /// fingers: their middle), nil where no finger is down. Without `positions`, every
    /// contact is the same height (a rhythm).
    private static func line(_ samples: [Int], positions: Bool) -> [Double?] {
        trimmed(samples).map { s in
            let f = fingers(in: s)
            guard !f.isEmpty else { return nil }
            return positions ? Double(f.reduce(0, +)) / Double(f.count) : 0
        }
    }

    private static func shapeScore(_ a: [Double?], _ b: [Double?]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let ratio = Double(min(a.count, b.count)) / Double(max(a.count, b.count))
        guard ratio >= 0.5 else { return 0 }
        let n = 48
        func resample(_ s: [Double?]) -> [Double?] {
            guard s.count > 1 else { return Array(repeating: s[0], count: n) }
            return (0..<n).map { i in s[min(s.count - 1, Int(Double(i) / Double(n - 1) * Double(s.count - 1) + 0.5))] }
        }
        func cost(_ x: Double?, _ y: Double?) -> Double {
            switch (x, y) {
            case (nil, nil): return 0
            case let (x?, y?): return min(1, abs(x - y) / 3)
            default: return 1
            }
        }
        let ra = resample(a), rb = resample(b)
        // Dynamic time warping within a band (a fifth of the touch), tracking path length.
        let band = max(4, n / 5)
        let inf = Double.greatestFiniteMagnitude
        var d = Array(repeating: Array(repeating: inf, count: n + 1), count: n + 1)
        var len = Array(repeating: Array(repeating: 0, count: n + 1), count: n + 1)
        d[0][0] = 0
        for i in 1...n {
            for j in max(1, i - band)...min(n, i + band) {
                var best = (d[i - 1][j - 1], len[i - 1][j - 1])
                if d[i - 1][j] < best.0 { best = (d[i - 1][j], len[i - 1][j]) }
                if d[i][j - 1] < best.0 { best = (d[i][j - 1], len[i][j - 1]) }
                d[i][j] = best.0 + cost(ra[i - 1], rb[j - 1])
                len[i][j] = best.1 + 1
            }
        }
        let shape = 1 - d[n][n] / Double(max(1, len[n][n]))
        var score = shape * (0.85 + 0.15 * ratio)
        let pressGap = abs(presses(a.map { $0 != nil }) - presses(b.map { $0 != nil }))
        if pressGap == 1 { score *= 0.9 } else if pressGap > 1 { score *= 0.6 }
        return score
    }

    private static func presses(_ c: [Bool]) -> Int {
        var count = 0, prev = false
        for on in c { if on && !prev { count += 1 }; prev = on }
        return count
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
