import CoreGraphics
import Foundation
import UIKit

/// The rich touch notification shared by the app, the notification service extension (which
/// decrypts the partner's push and fills this in) and the long-press view / watch view
/// (which draw and play it). Everything here stays on the user's own devices.
enum TouchNotification {
    static let category = "TOUCH"
    static let touchBackAction = "touch-back"
    static let heartbeatAction = "heartbeat"
    static let feelAgainAction = "feel-again"
    /// The touch notification sound, bundled in the phone and watch apps: a soft kiss, then a
    /// gentle two-note futuristic bell (made by scripts/make_touch_chime.py — pure synthesis).
    /// It also makes the phone vibrate and the watch tap the wrist (they only vibrate for a
    /// notification with a sound).
    static let sound = "touch-chime.wav"
    /// Just the kiss, for "Thinking of you" (the kiss button).
    static let kissSound = "kiss.wav"

    /// The touch, in the notification's userInfo, under these keys.
    enum Key {
        static let bond = "tBond", pattern = "tPattern", generation = "tGen", start = "tStart", end = "tEnd"
        static let label = "tLabel", emoji = "tEmoji", bpm = "tBPM", sentAt = "tAt"
    }

    static func userInfo(_ t: TouchMessage, bondID: String) -> [String: Any] {
        var d: [String: Any] = [Key.bond: bondID, Key.pattern: t.pattern, Key.generation: t.generation,
                                Key.start: t.colorRGB, Key.end: t.endColorRGB, Key.sentAt: t.sentAt.timeIntervalSince1970]
        if let l = t.meaningLabel { d[Key.label] = l }
        if let e = t.meaningEmoji { d[Key.emoji] = e }
        if let b = t.heartbeatBPM { d[Key.bpm] = b }
        return d
    }

    /// The touch read back from a notification's userInfo.
    static func touch(from info: [AnyHashable: Any]) -> TouchMessage? {
        guard let pattern = info[Key.pattern] as? [Int], let start = info[Key.start] as? Int else { return nil }
        return TouchMessage(bondID: info[Key.bond] as? String ?? "", senderID: "partner", pattern: pattern,
                            generation: info[Key.generation] as? Int ?? 2, colorRGB: start,
                            endColorRGB: info[Key.end] as? Int ?? start,
                            sentAt: (info[Key.sentAt] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date(),
                            meaningLabel: info[Key.label] as? String, meaningEmoji: info[Key.emoji] as? String,
                            heartbeatBPM: info[Key.bpm] as? Int)
    }

    /// A picture of the touch for the banner's thumbnail: the bar trace, the tap rhythm, or
    /// the heartbeat's EKG, on the app's navy, as a PNG file in the temporary folder.
    static func imageFile(_ t: TouchMessage) -> URL? {
        let size = CGSize(width: 360, height: 200)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            UIColor(red: 0.04, green: 0.14, blue: 0.25, alpha: 1).setFill()
            g.fill(CGRect(origin: .zero, size: size))
            draw(t, in: CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 22), g)
        }
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("touch-\(UUID().uuidString).png")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    static func color(_ rgb: Int, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }

    private static func mix(_ a: Int, _ b: Int, _ t: CGFloat) -> UIColor {
        func c(_ v: Int, _ s: Int) -> CGFloat { CGFloat((v >> s) & 0xFF) }
        func m(_ s: Int) -> CGFloat { (c(a, s) + (c(b, s) - c(a, s)) * t) / 255 }
        return UIColor(red: m(16), green: m(8), blue: m(0), alpha: 1)
    }

    private static func draw(_ t: TouchMessage, in r: CGRect, _ g: CGContext) {
        g.setLineCap(.round); g.setLineJoin(.round)
        if let bpm = t.heartbeatBPM {
            g.setStrokeColor(color(t.colorRGB).cgColor); g.setLineWidth(5)
            g.setShadow(offset: .zero, blur: 10, color: color(t.colorRGB, alpha: 0.8).cgColor)
            let steps = Int(r.width)
            for i in 0...steps {
                let x = r.minX + CGFloat(i)
                let y = r.midY - CGFloat(EKG.level(elapsed: 2.4 * Double(i) / Double(steps) + 0.05, bpm: bpm)) * r.height * 0.45
                if i == 0 { g.move(to: CGPoint(x: x, y: y)) } else { g.addLine(to: CGPoint(x: x, y: y)) }
            }
            g.strokePath()
        } else if t.generation == 3 {
            let s = TouchPattern.trimmed(t.pattern), n = max(s.count, 2)
            var previous: Int?
            for (i, sample) in s.enumerated() {
                let p = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(n - 1), y: 0)
                guard let f = TouchPattern.fingers(in: sample).first else { previous = nil; continue }
                let y = r.maxY - r.height * CGFloat(f) / CGFloat(TouchPattern.positions - 1)
                let c = mix(t.colorRGB, t.endColorRGB, CGFloat(i) / CGFloat(n))
                g.setStrokeColor(c.cgColor); g.setFillColor(c.cgColor); g.setLineWidth(10)
                g.setShadow(offset: .zero, blur: 10, color: c.withAlphaComponent(0.8).cgColor)
                if let pf = previous {
                    let px = r.minX + r.width * CGFloat(i - 1) / CGFloat(n - 1)
                    g.move(to: CGPoint(x: px, y: r.maxY - r.height * CGFloat(pf) / CGFloat(TouchPattern.positions - 1)))
                    g.addLine(to: CGPoint(x: p.x, y: y)); g.strokePath()
                } else {
                    g.fillEllipse(in: CGRect(x: p.x - 5, y: y - 5, width: 10, height: 10))
                }
                previous = f
            }
        } else {
            var presses: [(Double, Double)] = []
            var at = 0.0
            for (i, ms) in t.pattern.enumerated() { if i % 2 == 0 { presses.append((at, Double(max(ms, 1)))) }; at += Double(max(ms, 1)) }
            let total = max(presses.last.map { $0.0 + $0.1 } ?? 1, 1)
            let dot: CGFloat = 26
            for (i, p) in presses.enumerated() {
                let c = mix(t.colorRGB, t.endColorRGB, presses.count > 1 ? CGFloat(i) / CGFloat(presses.count - 1) : 0)
                g.setFillColor(c.cgColor)
                g.setShadow(offset: .zero, blur: 10, color: c.withAlphaComponent(0.8).cgColor)
                let x = r.minX + r.width * CGFloat(p.0 / total)
                let w = max(r.width * CGFloat(p.1 / total), dot)
                g.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: r.midY - dot / 2, width: w, height: dot), cornerRadius: dot / 2).cgPath)
                g.fillPath()
            }
        }
    }
}
