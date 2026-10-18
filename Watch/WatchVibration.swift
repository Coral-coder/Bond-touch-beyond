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
        let pattern = onOff(t)
        switch m {
        case .exact:
            // [on?, ms, on?, ms, …] — presses at least 60 ms so each is felt firmly.
            var vibe: [Any] = []
            for (i, ms) in pattern.enumerated() { vibe.append(i % 2 == 0); vibe.append(i % 2 == 0 ? max(ms, 60) : ms) }
            stopSound?(vibrateID)
            playWithVibration?(vibrateID, nil, ["VibePattern": vibe, "Intensity": 1.0] as NSDictionary)
            return true
        case .buzz:
            var at = 0.0, last = -1.0
            for (i, ms) in pattern.enumerated() {
                if i % 2 == 0, at - last >= 0.45 {
                    last = at
                    DispatchQueue.main.asyncAfter(deadline: .now() + at) { playSound?(vibrateID) }
                }
                at += Double(ms) / 1000
            }
            return true
        case .appleTap, .auto:
            WatchHaptics.playAppleTaps(t)
            return false
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
