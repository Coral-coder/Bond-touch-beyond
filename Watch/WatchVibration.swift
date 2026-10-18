import Foundation
import SwiftUI
import WatchKit

/// Vibrates the watch in a touch's rhythm with no tone.
///
/// Apple's public watch haptics (`WKInterfaceDevice.play`) always bring a system tone unless
/// the watch is on Silent. This app never ships to the App Store, so it reaches past that:
/// the system's own vibration calls in AudioToolbox, looked up at run time (nothing links
/// against them, so a watch without them just falls back — it never crashes):
///  • **Exact**: `AudioServicesPlaySystemSoundWithVibration` — the whole rhythm as an on/off
///    pattern at full intensity, in one go, silent.
///  • **Buzz**: the system vibration (sound 4095) once per press — silent.
///  • **Apple tap**: the public firm tap (with its tone) — the last resort.
/// The Tap lab page on the watch tries each, so the one that works best can be chosen.
enum WatchVibration {
    enum Method: String, CaseIterable, Identifiable {
        case auto, exact, buzz, appleTap
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .exact: return "Exact rhythm"
            case .buzz: return "Buzz per press"
            case .appleTap: return "Apple tap (tones)"
            }
        }
    }

    static var chosen: Method {
        get { Method(rawValue: UserDefaults.standard.string(forKey: "watchTapMethod") ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "watchTapMethod") }
    }

    private typealias PlayWithVibration = @convention(c) (UInt32, AnyObject?, NSDictionary) -> Void
    private typealias PlaySound = @convention(c) (UInt32) -> Void
    private typealias StopSound = @convention(c) (UInt32) -> Void
    private static let vibrateID: UInt32 = 4095   // kSystemSoundID_Vibrate

    private static let audioToolbox = dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_NOW)

    private static let playWithVibration: PlayWithVibration? = {
        guard let h = audioToolbox, let s = dlsym(h, "AudioServicesPlaySystemSoundWithVibration") else { return nil }
        return unsafeBitCast(s, to: PlayWithVibration.self)
    }()
    private static let playSound: PlaySound? = {
        guard let h = audioToolbox, let s = dlsym(h, "AudioServicesPlaySystemSound") else { return nil }
        return unsafeBitCast(s, to: PlaySound.self)
    }()
    private static let stopSound: StopSound? = {
        guard let h = audioToolbox, let s = dlsym(h, "AudioServicesStopSystemSound") else { return nil }
        return unsafeBitCast(s, to: StopSound.self)
    }()

    /// Which methods this watch has (for the Tap lab).
    static func available(_ m: Method) -> Bool {
        switch m {
        case .auto, .appleTap: return true
        case .exact: return playWithVibration != nil
        case .buzz: return playSound != nil
        }
    }

    /// The method actually used: the chosen one, or (Automatic) the best this watch has.
    static var effective: Method {
        let c = chosen
        if c != .auto { return available(c) ? c : .appleTap }
        if available(.exact) { return .exact }
        if available(.buzz) { return .buzz }
        return .appleTap
    }

    /// The touch as vibration: when each part starts (s), how long it lasts (ms) and how
    /// strong it is (0…1). It follows the touch exactly, at the bar's own 50 ms steps:
    ///  • a tap or press vibrates for exactly as long as the finger was down, at full strength;
    ///  • a slide vibrates the whole time the finger moves, stronger the higher it is on the
    ///    bar (and a touch more with two fingers), so you feel it rise and fall;
    ///  • a heartbeat beats lub-dub at its BPM.
    /// Capped at 10 s.
    static func segments(_ t: WatchTouch) -> [(at: Double, ms: Int, intensity: Double)] {
        var out: [(at: Double, ms: Int, intensity: Double)] = []
        if let bpm = t.bpm {
            let period = 60.0 / Double(min(max(bpm, 30), 220))
            var at = 0.0
            while at < 5 {
                out.append((at, 120, 1.0))
                out.append((at + min(0.22, period * 0.3), 80, 0.55))
                at += period
            }
            return out
        }
        if t.generation == 3 {
            let samples = TouchPattern.trimmed(t.pattern)
            let step = Double(TouchPattern.sampleMs) / 1000
            func level(_ s: Int) -> Double? {
                let f = TouchPattern.fingers(in: s)
                guard let top = f.max() else { return nil }
                let base = 0.35 + 0.65 * Double(top) / Double(TouchPattern.positions - 1)
                return min(1, base + (f.count > 1 ? 0.1 : 0))
            }
            var i = 0
            while i < samples.count, Double(i) * step < 10 {
                guard let l = level(samples[i]) else { i += 1; continue }
                var j = i + 1
                while j < samples.count, level(samples[j]) == l { j += 1 }
                out.append((Double(i) * step, (j - i) * TouchPattern.sampleMs, l))
                i = j
            }
            return out
        }
        var at = 0.0
        for (i, ms) in t.pattern.enumerated() {
            if i % 2 == 0 { out.append((at, max(ms, 40), 1.0)) }
            at += Double(max(ms, 0)) / 1000
            if at > 10 { break }
        }
        return out.isEmpty ? [(0, 200, 1.0)] : out
    }

    /// The touch as on/off milliseconds (presses and gaps), capped at 10 s.
    static func onOff(_ t: WatchTouch) -> [Int] {
        if let bpm = t.bpm {
            let period = Int(60_000 / Double(min(max(bpm, 30), 220)))
            var out: [Int] = []
            var total = 0
            while total < 5000 { out += [140, max(period - 140, 60)]; total += period }
            return out
        }
        let raw = t.generation == 3 ? TouchPattern.onOff(fromSamples: t.pattern) : t.pattern
        var out: [Int] = []
        var total = 0
        for ms in raw where total < 10_000 { out.append(max(ms, 1)); total += max(ms, 1) }
        return out.isEmpty ? [200] : out
    }

    /// Plays a touch's rhythm by `method` (default: the effective one). Returns false only
    /// when it had to fall back to Apple's taps.
    @discardableResult
    static func play(_ t: WatchTouch, method: Method? = nil) -> Bool {
        let m = method.map { $0 == .auto ? effective : (available($0) ? $0 : .appleTap) } ?? effective
        let parts = segments(t)
        playing += 1
        let run = playing
        switch m {
        case .exact:
            // Each part on its own, at its moment and strength, so a slide's strength follows
            // the finger. A newer touch cuts off what's left of this one.
            for part in parts {
                DispatchQueue.main.asyncAfter(deadline: .now() + part.at) {
                    guard run == playing else { return }
                    stopSound?(vibrateID)
                    playWithVibration?(vibrateID, nil, ["VibePattern": [true, part.ms] as [Any],
                                                        "Intensity": part.intensity] as NSDictionary)
                }
            }
            return true
        case .buzz:
            // The system vibration is a fixed ~0.4 s buzz, so only the start of each press.
            var last = -1.0
            for part in parts where part.at - last >= 0.42 {
                last = part.at
                DispatchQueue.main.asyncAfter(deadline: .now() + part.at) {
                    guard run == playing else { return }
                    playSound?(vibrateID)
                }
            }
            return true
        case .appleTap, .auto:
            WatchHaptics.playAppleTaps(t)
            return false
        }
    }

    /// Bumped by every play, so an older touch's remaining parts stop.
    private static var playing = 0
    private static var lastTick: TimeInterval = 0

    /// A tiny silent tick (30 ms, soft) while drawing a touch on the bar: when the finger lands
    /// and each time it reaches another position. At most one every 60 ms. Only the exact
    /// path is short enough; without it there's no tick at all (never an Apple tap and its tone).
    static func tick() {
        guard let playWithVibration else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTick >= 0.06 else { return }
        lastTick = now
        playWithVibration(vibrateID, nil, ["VibePattern": [true, 30] as [Any], "Intensity": 0.6] as NSDictionary)
    }

    /// One firm silent buzz (a touch notification arriving): 180 ms at full intensity, or the
    /// system vibration once if that's what this watch has (or was picked in the Tap lab).
    /// Never Apple's taps.
    static func pulse() {
        if effective != .buzz, let playWithVibration {
            stopSound?(vibrateID)
            playWithVibration(vibrateID, nil, ["VibePattern": [true, 180] as [Any], "Intensity": 1.0] as NSDictionary)
        } else {
            playSound?(vibrateID)
        }
    }
}

/// The Tap lab: feel each way the watch can vibrate a touch, and pick the one that's strong
/// and silent on this watch.
struct WatchTapLabView: View {
    @EnvironmentObject var link: PhoneLink
    @State private var chosen = WatchVibration.chosen

    private let sample = WatchTouch(["id": "lab", "bond": "", "pattern": [200, 150, 200, 150, 500], "gen": 2,
                                     "start": 0xEC5A89, "at": Date().timeIntervalSince1970, "mine": false])!

    var body: some View {
        WatchPage {
            List {
                Section {
                    ForEach(WatchVibration.Method.allCases) { m in
                        Button {
                            chosen = m
                            WatchVibration.chosen = m
                            WatchVibration.play(sample, method: m)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).font(.system(.footnote, design: .rounded).weight(.bold))
                                    if !WatchVibration.available(m) {
                                        Text("Not on this watch").font(.caption2).foregroundStyle(.secondary)
                                    } else if m == .auto {
                                        Text("Uses: \(WatchVibration.effective.title)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if chosen == m { Image(systemName: "checkmark").foregroundStyle(Color(rgb: 0x57C3BB)) }
                            }
                        }
                    }
                } header: {
                    Text("Tap lab")
                } footer: {
                    Text("Tap each to feel it. Pick the one that's strong and silent — touches use it.")
                }
            }
        }
    }
}
