import SwiftUI
import UIKit

/// Matrix mode's backdrop: digital rain in code greens on black. Each falling stream is led by
/// a glitching heart; behind it trail half-width katakana and digits, bright at the head and
/// fading to deep green. A face (the partner's photo, or yours) comes through in the code: the
/// glyphs are brighter where the face is lighter, so it surfaces in shades of green as the rain
/// runs over it. Now and then a band of the screen tears sideways — the glitch.
///
/// Everything is worked out from the time, not kept from frame to frame, so it costs nothing
/// when still (`animated` false) and never drifts.
struct MatrixRain: View {
    var face: UIImage? = nil
    var animated = true
    /// 1 for the backdrop; more for a Matrix touch arriving (faster, denser, brighter).
    var intensity: Double = 1
    var glow: Color? = nil

    @State private var faceMap: MatrixFaceMap?

    static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ012345789Z:=*+<>¦")
    static let hearts = ["♥", "♡", "❥", "♥"]
    /// The code greens, brightest first: the heart lead, the head, the body, the tail.
    static let lead = Color(red: 0.80, green: 1.0, blue: 0.84)
    static let shades = [Color(red: 0.55, green: 1.0, blue: 0.62), Color(red: 0.0, green: 1.0, blue: 0.255),
                         Color(red: 0.0, green: 0.70, blue: 0.18), Color(red: 0.0, green: 0.42, blue: 0.11)]

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                    rain(t: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                rain(t: 1_000)     // a still frame (the theme picker's tile)
            }
        }
        .background {
            ZStack {
                Color.black
                // The face, very faint and green, so its shape holds together under the code.
                if let face {
                    Image(uiImage: face).resizable().scaledToFill()
                        .grayscale(1).colorMultiply(Color(red: 0.1, green: 1, blue: 0.3))
                        .opacity(0.16).blur(radius: 1.5)
                        .clipped()
                }
                if let glow { RadialGradient(colors: [glow.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 520) }
            }
        }
        .clipped()
        .task(id: face.map { ObjectIdentifier($0) }) {
            guard let face else { faceMap = nil; return }
            faceMap = await Task.detached(priority: .utility) { MatrixFaceMap(face) }.value
        }
    }

    /// One frame of the rain. The glyphs are small pictures drawn once (`MatrixGlyphs`), so the
    /// canvas holds no child views (which a scrolling list kept rebuilding).
    private func rain(t: Double) -> some View {
        Canvas { ctx, size in
            guard size.width.isFinite, size.height.isFinite, size.width > 1, size.height > 1 else { return }
            let atlas = MatrixGlyphs.shared
            let shades = atlas.shades.map { row in row.map { ctx.resolve(Image(uiImage: $0)) } }
            let hearts = atlas.hearts.map { ctx.resolve(Image(uiImage: $0)) }
            draw(&ctx, size: size, t: t) { id in
                id >= 9000 ? hearts[(id - 9000) % hearts.count] : shades[min(id / 1000, shades.count - 1)][(id % 1000) % atlas.glyphCount]
            }
        }
    }

    private static func hash(_ a: Int, _ b: Int, _ c: Int = 0) -> Int {
        var h = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791))
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33
        return Int(h % 1_000_003)
    }
    private static func unit(_ a: Int, _ b: Int, _ c: Int = 0) -> Double { Double(hash(a, b, c)) / 1_000_003 }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                      glyph: @escaping (Int) -> GraphicsContext.ResolvedImage) {
        let cell: CGFloat = 15
        let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
        let map = faceMap

        // A glitch: for a fraction of a second, every ~2.5 s, a band of rows tears sideways.
        let tick = Int(t * 0.4)
        let glitchOn = (t * 0.4 - Double(tick)) < 0.07 * intensity
        let bandTop = Int(Self.unit(tick, 1) * Double(rows)), bandRows = 2 + Int(Self.unit(tick, 2) * 6)
        let bandShift = (Self.unit(tick, 3) - 0.5) * 30

        func put(_ id: Int, col: Int, row: Int, opacity: Double, jitter: CGFloat = 0) {
            guard opacity > 0.02 else { return }
            let symbol = glyph(id)
            var x = CGFloat(col) * cell + cell / 2 + jitter
            if glitchOn, row >= bandTop, row < bandTop + bandRows { x += bandShift }
            var c = ctx
            c.opacity = min(1, opacity)
            c.draw(symbol, at: CGPoint(x: x, y: CGFloat(row) * cell + cell / 2))
        }

        // The face, in the code: steady glyphs where the face is light, changing slowly.
        if let map {
            let slow = Int(t * 1.2)
            for col in 0..<cols {
                for row in 0..<rows {
                    let lum = map.luminance(x: (Double(col) + 0.5) / Double(cols), y: (Double(row) + 0.5) / Double(rows),
                                            aspect: Double(size.width / max(size.height, 1)))
                    guard lum > 0.42 else { continue }
                    let g = Self.hash(col, row, slow + col % 3) % Self.glyphs.count
                    let shade = lum > 0.8 ? 1 : lum > 0.6 ? 2 : 3
                    put(shade * 1000 + g, col: col, row: row, opacity: (lum - 0.38) * 0.75)
                }
            }
        }

        // The rain: two streams per column, each led by a heart.
        let streams = intensity > 1.2 ? 3 : 2
        for col in 0..<cols {
            for s in 0..<streams {
                let seed = col * 7 + s * 1931
                let speed = (7 + Self.unit(seed, 11) * 13) * intensity
                let length = 8 + Int(Self.unit(seed, 12) * 20)
                let gap = Double(rows) * (0.15 + Self.unit(seed, 13) * 0.9) / intensity
                let period = Double(rows + length) + gap
                let head = (t * speed + Self.unit(seed, 14) * period).truncatingRemainder(dividingBy: period)
                let headRow = Int(head)
                for k in 0..<length {
                    let row = headRow - k
                    guard row >= 0, row < rows else { continue }
                    let lum = map?.luminance(x: (Double(col) + 0.5) / Double(cols), y: (Double(row) + 0.5) / Double(rows),
                                             aspect: Double(size.width / max(size.height, 1))) ?? 0.5
                    let fade = 1 - Double(k) / Double(length)
                    let lift = map == nil ? 1 : 0.55 + lum * 0.9      // brighter over the face
                    if k == 0 {
                        // The lead heart, glitching: it flickers between hearts and jumps a pixel or two.
                        let g = Self.hash(col, Int(t * 9), s)
                        let jitter: CGFloat = g % 9 == 0 ? CGFloat(g % 5) - 2 : 0
                        put(9000 + g % Self.hearts.count, col: col, row: row, opacity: g % 13 == 0 ? 0.45 : 1, jitter: jitter)
                        continue
                    }
                    let rate = 2 + Self.unit(col, row) * 10
                    let g = Self.hash(col, row, Int(t * rate)) % Self.glyphs.count
                    let shade = k < 2 ? 0 : fade > 0.6 ? 1 : fade > 0.3 ? 2 : 3
                    put(shade * 1000 + g, col: col, row: row, opacity: min(1, (0.25 + fade * 0.85) * lift))
                }
            }
        }
    }
}

/// The rain's glyphs as small pictures, drawn once: every glyph in each code green, and the
/// glowing heart leads.
final class MatrixGlyphs {
    static let shared = MatrixGlyphs()
    let shades: [[UIImage]]
    let hearts: [UIImage]
    var glyphCount: Int { MatrixRain.glyphs.count }

    private init() {
        func picture(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, glow: UIColor?) -> UIImage {
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let glow {
                let shadow = NSShadow()
                shadow.shadowColor = glow
                shadow.shadowBlurRadius = 5
                shadow.shadowOffset = .zero
                attrs[.shadow] = shadow
            }
            let string = NSAttributedString(string: text, attributes: attrs)
            let box = CGSize(width: 22, height: 22)
            return UIGraphicsImageRenderer(size: box).image { _ in
                let s = string.size()
                string.draw(at: CGPoint(x: (box.width - s.width) / 2, y: (box.height - s.height) / 2))
            }
        }
        shades = MatrixRain.shades.map { shade in
            MatrixRain.glyphs.map { picture(String($0), size: 14, weight: .medium, color: UIColor(shade), glow: nil) }
        }
        hearts = MatrixRain.hearts.map {
            picture($0, size: 15, weight: .black, color: UIColor(MatrixRain.lead), glow: UIColor(MatrixRain.shades[1]))
        }
    }
}

/// A photo reduced to a small grid of brightness (0…1), contrast-stretched, for drawing it in
/// code. Built once per photo, off the main thread.
struct MatrixFaceMap: Sendable {
    let width = 48, height = 96
    private let values: [Double]
    private let imageAspect: Double

    init(_ image: UIImage) {
        imageAspect = Double(image.size.width / max(image.size.height, 1))
        var pixels = [UInt8](repeating: 0, count: 48 * 96)
        if let cg = image.cgImage,
           let ctx = CGContext(data: &pixels, width: 48, height: 96, bitsPerComponent: 8, bytesPerRow: 48,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            // Aspect-fill into a tall 1:2 grid, as the photo fills a phone screen.
            let target = 48.0 / 96.0
            var draw = CGRect(x: 0, y: 0, width: 48, height: 96)
            if imageAspect > target { draw.size.width = 96 * imageAspect; draw.origin.x = (48 - draw.width) / 2 }
            else { draw.size.height = 48 / imageAspect; draw.origin.y = (96 - draw.height) / 2 }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: draw)
        }
        let raw = pixels.map { Double($0) / 255 }
        let lo = raw.sorted()[raw.count / 20], hi = raw.sorted()[raw.count * 19 / 20]
        values = raw.map { min(1, max(0, ($0 - lo) / max(hi - lo, 0.05))) }
    }

    /// Brightness at (x, y), 0…1 across the screen; `aspect` is the screen's width / height.
    func luminance(x: Double, y: Double, aspect: Double) -> Double {
        // The grid is 1:2; a screen of another shape crops it the way aspect-fill would.
        let gridAspect = 0.5
        var u = x, v = y
        if aspect > gridAspect { v = 0.5 + (y - 0.5) * gridAspect / aspect } else { u = 0.5 + (x - 0.5) * aspect / gridAspect }
        let col = min(width - 1, max(0, Int(u * Double(width))))
        let row = min(height - 1, max(0, Int(v * Double(height))))
        return values[row * width + col]
    }
}
