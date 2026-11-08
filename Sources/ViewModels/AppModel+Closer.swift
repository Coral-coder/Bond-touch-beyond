import Foundation
import UIKit

/// A partner's kiss, kept on this phone (the newest 30) for CarPlay and the screen.
struct KissEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var bondID: String
    var name: String
    var at = Date()

    private static let key = "receivedKisses"
    static func load() -> [KissEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([KissEvent].self, from: data)) ?? []
    }
    static func save(_ list: [KissEvent]) {
        if let data = try? JSONEncoder().encode(Array(list.prefix(30))) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// A kiss on screen: lips and hearts float up, with Kiss back and Send a touch.
struct KissShow: Identifiable, Equatable {
    var id = UUID()
    var bondID: String
    var name: String
    var matrix: Bool
}

/// The screen in Matrix mode while a touch sent from Matrix plays, then back to your theme.
struct MatrixShow: Identifiable, Equatable {
    var id = UUID()
    var bondID: String
    var name: String
    var label: String
    var seconds: Double
}

/// Glitchy touches, for Matrix mode: the rhythm stutters, the bar jumps, and it's code green.
enum Glitch {
    static let green = 0x00FF41
    static let deepGreen = 0x00B32D

    /// `pattern` (on/off ms for generation 2, 50 ms bar samples for generation 3), glitched:
    /// each press breaks up into a stutter; on the bar, the light skips and drops out.
    static func pattern(_ pattern: [Int], generation: Int) -> [Int] {
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: pattern.reduce(7) { $0 &* 31 &+ $1 }))
        if generation == 3 {
            let samples = pattern.isEmpty ? Array(repeating: TouchPattern.sample([4]), count: 16) : pattern
            return samples.enumerated().map { (i, s) -> Int in
                let r = rng.next()
                guard !TouchPattern.fingers(in: s).isEmpty else { return s }
                if r < 0.14 { return TouchPattern.sample([]) }                         // drops out
                if r < 0.36 { return TouchPattern.sample([Int(rng.next() * Double(TouchPattern.positions))]) } // skips
                return i % 7 == 3 ? TouchPattern.sample([TouchPattern.positions - 1 - (TouchPattern.fingers(in: s).first ?? 0)]) : s
            }
            .prefix(TouchPattern.maxSamples).map { $0 }
        }
        var out: [Int] = []
        let source = pattern.isEmpty ? [200] : pattern
        for (i, ms) in source.enumerated() {
            if i % 2 == 1 { out.append(ms); continue }
            guard ms >= 120 else { out.append(ms); continue }
            // A press → a glitch: on, a flicker off, a sliver on, off, then the rest.
            let a = max(40, Int(Double(ms) * (0.25 + rng.next() * 0.2)))
            let b = max(30, Int(Double(ms) * 0.15))
            out += [a, 35 + Int(rng.next() * 30), b, 30, max(40, ms - a - b)]
        }
        if out.count % 2 == 0, out.count > 1 { out.removeLast() }   // ends on a press
        return Array(out.prefix(60))
    }
}

extension AppModel {
    /// A kiss from `partner` arrived (push, foreground or background): kept for CarPlay, and
    /// on screen if the app is open.
    func receivedKiss(from partner: Partner, matrix: Bool) {
        // One push can reach here twice (shown in the foreground and its background wake).
        if let last = receivedKisses.first, last.bondID == partner.id, Date().timeIntervalSince(last.at) < 3 { return }
        receivedKisses.insert(KissEvent(bondID: partner.id, name: partner.displayName), at: 0)
        if receivedKisses.count > 30 { receivedKisses.removeLast(receivedKisses.count - 30) }
        KissEvent.save(receivedKisses)
        CarPlayActivity.changed()
        guard UIApplication.shared.applicationState == .active else { return }
        let show = KissShow(bondID: partner.id, name: partner.displayName, matrix: matrix)
        kissShow = show
        haptics.play(TouchMessage(senderID: "kiss", pattern: [90, 70, 160], colorRGB: 0xFF2E74))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if self.kissShow?.id == show.id { self.kissShow = nil }
        }
        if matrix { showMatrix(bondID: partner.id, name: partner.displayName, label: "kissed you 💋", seconds: 4.5) }
    }

    /// A touch sent from Matrix mode is playing: the screen goes Matrix for as long as it plays.
    func showMatrix(for touch: TouchMessage) {
        guard UIApplication.shared.applicationState == .active, !isMine(touch) else { return }
        let name = partners.first { $0.id == touch.bondID }?.displayName ?? "Partner"
        let seconds = min(max(Double(TouchPattern.durationMs(touch.pattern, generation: touch.generation)) / 1000 + 1.5, 4), 9)
        let label = touch.meaningLabel.map { "\(touch.meaningEmoji ?? "") \($0)".trimmingCharacters(in: .whitespaces) } ?? "touched you"
        showMatrix(bondID: touch.bondID, name: name, label: label, seconds: seconds)
    }

    func showMatrix(bondID: String, name: String, label: String, seconds: Double) {
        let show = MatrixShow(bondID: bondID, name: name, label: label, seconds: seconds)
        matrixShow = show
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if self.matrixShow?.id == show.id { self.matrixShow = nil }
        }
    }

    /// "Send a touch" from a notification, CarPlay or the kiss card: two soft taps in your colour
    /// (glitched, in Matrix mode).
    @discardableResult
    func sendQuickTouch(toBondID bondID: String) async -> Bool {
        await sendTouch(pattern: [140, 120, 140], generation: 2, colorRGB: store.profile.colorRGB,
                        toBondID: bondID, matchMeaning: false)
    }
}
