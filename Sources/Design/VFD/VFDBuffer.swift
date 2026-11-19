import SwiftUI
import UIKit

/// Amber VFD: the whole screen is one grid of square cells, like a vacuum-fluorescent
/// dot-matrix display. Everything is drawn by lighting whole cells in a `VFDBuffer`, then the
/// buffer is painted in one Canvas (`VFDDisplay`).

// MARK: - Palette

/// The display's colours: one base colour (amber unless another is picked) and the text, dim
/// and alarm colours that go with it. Cells hold an index into these.
enum VFDPalette {
    static let amber = 0xFFB014
    /// The base colours to pick from (Settings → Base colour). Amber first: the theme's own.
    static let bases: [(name: String, rgb: Int)] = [
        ("Amber", amber), ("Green", 0x3CFF6E), ("Teal", 0x30FFD8),
        ("Blue", 0x48A8FF), ("Pink", 0xFF5CB8), ("White", 0xF0F0F0),
    ]
    /// Unlit cells: near-black grey, so the matrix shows faintly up close.
    static let unlit = 0x090909

    struct Colors { let base: Int, text: Int, dim: Int, alarm: Int }

    /// The colours for `tint` (a picked base colour; nil for amber).
    static func current(tint: Int?) -> Colors {
        let base = tint ?? amber
        if base == amber { return Colors(base: amber, text: 0xFFE8C4, dim: 0x966428, alarm: 0xFF5028) }
        func ch(_ v: Int, _ s: Int) -> Int { (v >> s) & 0xFF }
        func rgb(_ r: Int, _ g: Int, _ b: Int) -> Int { (min(255, r) << 16) | (min(255, g) << 8) | min(255, b) }
        let r = ch(base, 16), g = ch(base, 8), b = ch(base, 0)
        // Warm white leaning towards the base; a dim version of the base for labels and tracks.
        let text = rgb(Int((Double(r) * 0.25 + 191).rounded()), Int((Double(g) * 0.25 + 191).rounded()), Int((Double(b) * 0.25 + 191).rounded()))
        let dim = rgb(Int(Double(r) * 0.58 + 6), Int(Double(g) * 0.58 + 6), Int(Double(b) * 0.58 + 6))
        // Red-orange alarms, unless the base itself is red: then alarms are white.
        let alarm = (r > 200 && g < 120) ? 0xFFFFFF : 0xFF5028
        return Colors(base: base, text: text, dim: dim, alarm: alarm)
    }
}

/// What a cell holds: 0 unlit, then the palette. Indices from `swatch` on are extra colours a
/// screen sets for itself (the base-colour swatches).
enum V {
    static let off: UInt8 = 0
    static let base: UInt8 = 1
    static let text: UInt8 = 2
    static let dim: UInt8 = 3
    static let alarm: UInt8 = 4
    static let swatch: UInt8 = 5
}

// MARK: - Text sizes

enum VFDSize {
    case small, mid, big

    var table: [UInt32: [UInt32]] {
        switch self {
        case .small: return VFDFont.small
        case .mid: return VFDFont.mid
        case .big: return VFDFont.big
        }
    }
    /// Glyph width, cap height, advance and line height, in cells.
    var width: Int { switch self { case .small: return 5; case .mid: return 10; case .big: return 15 } }
    var cap: Int { switch self { case .small: return 7; case .mid: return 14; case .big: return 21 } }
    var advance: Int { switch self { case .small: return 6; case .mid: return 12; case .big: return 18 } }
    var line: Int { switch self { case .small: return 10; case .mid: return 19; case .big: return 28 } }
}

/// A tappable rectangle, in cells.
struct VFDHit {
    let x: Int, y: Int, w: Int, h: Int
    let action: () -> Void
    func contains(_ c: Int, _ r: Int) -> Bool { c >= x && c < x + w && r >= y && r < y + h }
}

// MARK: - The frame buffer

final class VFDBuffer {
    let cols: Int, rows: Int
    private(set) var cells: [UInt8]
    /// Cells outside the clip aren't drawn (the scrolling content stays between the header
    /// and the tab bar).
    private var clipX0 = 0, clipY0 = 0, clipX1: Int, clipY1: Int
    private(set) var hits: [VFDHit] = []
    /// Colours for the cells set to `V.swatch` and up.
    var swatches: [Int] = []

    init(cols: Int, rows: Int) {
        self.cols = max(1, cols); self.rows = max(1, rows)
        cells = [UInt8](repeating: 0, count: self.cols * self.rows)
        clipX1 = self.cols; clipY1 = self.rows
    }

    func clip(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        clipX0 = max(0, x); clipY0 = max(0, y); clipX1 = min(cols, x + w); clipY1 = min(rows, y + h)
    }
    func unclip() { clipX0 = 0; clipY0 = 0; clipX1 = cols; clipY1 = rows }

    /// A colour for a swatch cell; returns its index.
    func swatch(_ rgb: Int) -> UInt8 {
        swatches.append(rgb)
        return V.swatch + UInt8(min(swatches.count - 1, 200))
    }

    // MARK: Cells

    @inline(__always) func set(_ c: Int, _ r: Int, _ v: UInt8) {
        guard c >= clipX0, c < clipX1, r >= clipY0, r < clipY1 else { return }
        cells[r * cols + c] = v
    }
    func fill(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ v: UInt8) {
        guard w > 0, h > 0 else { return }
        for y in r..<(r + h) { for x in c..<(c + w) { set(x, y, v) } }
    }
    func hline(_ c: Int, _ r: Int, _ w: Int, _ v: UInt8, step: Int = 1) {
        guard w > 0 else { return }
        for x in stride(from: c, to: c + w, by: max(1, step)) { set(x, r, v) }
    }
    func vline(_ c: Int, _ r: Int, _ h: Int, _ v: UInt8, step: Int = 1) {
        guard h > 0 else { return }
        for y in stride(from: r, to: r + h, by: max(1, step)) { set(c, y, v) }
    }
    func box(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ v: UInt8, step: Int = 1) {
        hline(c, r, w, v, step: step); hline(c, r + h - 1, w, v, step: step)
        vline(c, r, h, v, step: step); vline(c + w - 1, r, h, v, step: step)
    }
    /// A one-cell line (Bresenham).
    func line(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, _ v: UInt8) {
        var x = c0, y = r0
        let dx = abs(c1 - c0), dy = -abs(r1 - r0), sx = c0 < c1 ? 1 : -1, sy = r0 < r1 ? 1 : -1
        var err = dx + dy
        while true {
            set(x, y, v)
            if x == c1 && y == r1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }
    /// A picture as rows of "#" (lit) and "." (unlit).
    func bitmap(_ c: Int, _ r: Int, _ rows: [String], _ v: UInt8) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { set(c + x, r + y, v) }
        }
    }

    // MARK: Text (the row is the top of the capitals)

    /// The glyphs for `s`: characters the font lacks are folded (é → e) or dropped (emoji).
    static func glyphs(_ s: String) -> [UInt32] {
        var out: [UInt32] = []
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if VFDFont.small[v] != nil { out.append(v); continue }
            if v == 0xFE0F || v == 0x200D || (0x1F3FB...0x1F3FF).contains(v) { continue }
            if v == 0x2019 || v == 0x2018 { out.append(v); continue }
            let folded = String(scalar).folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            if let f = folded.unicodeScalars.first, folded.unicodeScalars.count == 1, VFDFont.small[f.value] != nil {
                out.append(f.value); continue
            }
            if scalar.properties.isEmojiPresentation || scalar.properties.isEmoji && v > 0x2000 { continue }
            if scalar.properties.isWhitespace { out.append(0x20); continue }
            out.append(0x3F)  // ?
        }
        return out
    }

    static func width(_ s: String, _ size: VFDSize = .small) -> Int {
        let n = glyphs(s).count
        return n == 0 ? 0 : n * size.advance - (size.advance - size.width)
    }

    @discardableResult
    func text(_ c: Int, _ r: Int, _ s: String, _ size: VFDSize = .small, _ v: UInt8 = V.text) -> Int {
        var x = c
        let table = size.table
        for g in Self.glyphs(s) {
            if let rows = table[g] ?? table[0x3F] {
                for (y, bits) in rows.enumerated() where bits != 0 {
                    for b in 0..<size.width where bits & (1 << UInt32(b)) != 0 { set(x + b, r + y, v) }
                }
            }
            x += size.advance
        }
        return x
    }
    @discardableResult
    func textRight(_ end: Int, _ r: Int, _ s: String, _ size: VFDSize = .small, _ v: UInt8 = V.text) -> Int {
        let start = end - Self.width(s, size)
        text(start, r, s, size, v)
        return start
    }
    func textCenter(_ c: Int, _ w: Int, _ r: Int, _ s: String, _ size: VFDSize = .small, _ v: UInt8 = V.text) {
        text(c + (w - Self.width(s, size)) / 2, r, s, size, v)
    }
    /// `s`, cut with "…" to fit `maxW` cells.
    static func fit(_ s: String, _ maxW: Int, _ size: VFDSize = .small) -> String {
        if width(s, size) <= maxW { return s }
        let n = max(0, (maxW + size.advance - size.width) / size.advance - 1)
        var kept = ""
        for ch in s {
            if glyphs(kept + String(ch)).count > n { break }
            kept.append(ch)
        }
        return kept.trimmingCharacters(in: .whitespaces) + "…"
    }
    @discardableResult
    func textFit(_ c: Int, _ r: Int, _ s: String, _ maxW: Int, _ size: VFDSize = .small, _ v: UInt8 = V.text) -> Int {
        text(c, r, Self.fit(s, maxW, size), size, v)
    }
    /// Word-wrapped text; returns the row below the last line.
    @discardableResult
    func paragraph(_ c: Int, _ r: Int, _ s: String, _ maxW: Int, _ size: VFDSize = .small,
                   _ v: UInt8 = V.text, maxLines: Int = 99) -> Int {
        let lines = Self.wrap(s, maxW, size, maxLines: maxLines)
        for (i, line) in lines.enumerated() { text(c, r + i * size.line, line, size, v) }
        return r + lines.count * size.line
    }
    static func wrap(_ s: String, _ maxW: Int, _ size: VFDSize = .small, maxLines: Int = 99) -> [String] {
        let per = max(1, (maxW + size.advance - size.width) / size.advance)
        var lines: [String] = []
        for para in s.components(separatedBy: "\n") {
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
                var w = word
                // A word longer than the line is broken.
                while glyphs(w).count > per {
                    if !cur.isEmpty { lines.append(cur); cur = "" }
                    lines.append(String(w.prefix(per))); w = String(w.dropFirst(per))
                }
                let t = cur.isEmpty ? w : cur + " " + w
                if glyphs(t).count <= per { cur = t } else { lines.append(cur); cur = w }
            }
            lines.append(cur)
        }
        while lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            lines[maxLines - 1] = fit(lines[maxLines - 1] + " …", maxW, size)
        }
        return lines
    }

    // MARK: Widgets

    /// A solid block with the text cut out (unlit). Returns its height.
    @discardableResult
    func inverted(_ c: Int, _ r: Int, _ w: Int, _ s: String, _ size: VFDSize = .small, _ v: UInt8 = V.base) -> Int {
        let h = size.cap + 4 + (size == .small ? 1 : 0)
        fill(c, r, w, h, v)
        textCenter(c, w, r + 2, Self.fit(s, w - 4, size), size, V.off)
        return h
    }

    /// An LED bar: a dotted dim track, and optionally a lit fill, a lit zone and 3-cell markers.
    func ledBar(_ c: Int, _ r: Int, _ w: Int, fill frac: Double? = nil, zone: (Double, Double)? = nil,
                markers: [(Double, UInt8)] = [], h: Int = 6, _ v: UInt8 = V.base) {
        for y in stride(from: r + 1, to: r + h - 1, by: 2) { hline(c, y, w, V.dim, step: 2) }
        if let frac { fill(c, r, Int((Double(w) * min(1, max(0, frac))).rounded()), h, v) }
        if let zone {
            let a = Int((Double(w) * zone.0).rounded()), b = Int((Double(w) * zone.1).rounded())
            fill(c + a, r + 1, b - a, h - 2, v)
        }
        for (m, mv) in markers {
            let x = c + min(w - 3, max(0, Int((Double(w) * m).rounded()) - 1))
            fill(x, r, 3, h, mv)
        }
    }

    /// A one-cell line chart over a dotted dim baseline.
    func chart(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ values: [Double], _ v: UInt8 = V.base,
               lo: Double? = nil, hi: Double? = nil) {
        hline(c, r + h - 1, w, V.dim, step: 2)
        guard values.count > 1, w > 1, h > 3 else { return }
        let lo = lo ?? values.min() ?? 0, hi = hi ?? values.max() ?? 1
        let span = max(1e-9, hi - lo)
        var last: (Int, Int)?
        for (i, value) in values.enumerated() {
            let x = c + Int((Double(i) * Double(w - 1) / Double(values.count - 1)).rounded())
            let y = r + h - 2 - Int(((min(hi, max(lo, value)) - lo) / span * Double(h - 3)).rounded())
            if let last { line(last.0, last.1, x, y, v) }
            last = (x, y)
        }
    }

    /// [ON|OFF], right-aligned at `end`; the chosen half is lit with its word cut out.
    @discardableResult
    func toggle(_ end: Int, _ r: Int, on: Bool) -> (x: Int, w: Int) {
        let half = 21, w = half * 2 - 1, c = end - w
        box(c, r, w, 11, V.dim)
        if on {
            fill(c, r, half, 11, V.base)
            textCenter(c, half, r + 2, "ON", .small, V.off)
            textCenter(c + half - 1, half, r + 2, "OFF", .small, V.dim)
        } else {
            fill(c + half - 1, r, half, 11, V.dim)
            textCenter(c, half, r + 2, "ON", .small, V.dim)
            textCenter(c + half - 1, half, r + 2, "OFF", .small, V.off)
        }
        return (c, w)
    }

    /// [-] value [+], right-aligned at `end`. Returns the minus and plus boxes' left columns.
    @discardableResult
    func stepper(_ end: Int, _ r: Int, _ value: String) -> (minus: Int, plus: Int, w: Int) {
        let bw = 11, mid = max(22, Self.width(value) + 8), c = end - (bw * 2 + mid)
        box(c, r, bw, 11, V.dim); text(c + 3, r + 2, "-", .small, V.base)
        textCenter(c + bw, mid, r + 2, value, .small, V.base)
        box(c + bw + mid, r, bw, 11, V.dim); text(c + bw + mid + 3, r + 2, "+", .small, V.base)
        return (c, c + bw + mid, bw)
    }

    /// [OPTION]: lit with the word cut out when chosen, else a dim box. Returns its width.
    @discardableResult
    func option(_ c: Int, _ r: Int, _ s: String, selected: Bool, _ v: UInt8 = V.base) -> Int {
        let w = Self.width(s) + 6
        if selected { fill(c, r, w, 11, v); text(c + 3, r + 2, s, .small, V.off) }
        else { box(c, r, w, 11, V.dim); text(c + 3, r + 2, s, .small, V.text) }
        return w
    }

    // MARK: Taps

    /// Registers a tap rectangle (clipped to what's visible now). Later ones win.
    func hit(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ action: @escaping () -> Void) {
        let x0 = max(c, clipX0), y0 = max(r, clipY0), x1 = min(c + w, clipX1), y1 = min(r + h, clipY1)
        guard x1 > x0, y1 > y0 else { return }
        hits.append(VFDHit(x: x0, y: y0, w: x1 - x0, h: y1 - y0, action: action))
    }

}

// MARK: - Grid metrics

/// Where the grid sits on this screen: 5 device pixels a cell on 3x screens, 4 on 2x, so the
/// lit 4×4 (or 3×3) pixel squares and the 1-pixel gaps line up with the device pixels.
struct VFDMetrics: Equatable {
    let pitchPx: Int
    let scale: CGFloat
    let cols: Int, rows: Int
    /// The first row below the status bar and the first row of the home indicator.
    let top: Int, bottom: Int

    var pitch: CGFloat { CGFloat(pitchPx) / scale }
    var lit: CGFloat { CGFloat(pitchPx - 1) / scale }

    init(size: CGSize, safe: EdgeInsets, scale: CGFloat) {
        self.scale = max(1, scale)
        pitchPx = self.scale >= 3 ? 5 : 4
        let wPx = Int((size.width * self.scale).rounded()), hPx = Int((size.height * self.scale).rounded())
        cols = max(1, wPx / pitchPx); rows = max(1, hPx / pitchPx)
        func cellsUp(_ pt: CGFloat) -> Int { Int((pt * self.scale / CGFloat(pitchPx)).rounded(.up)) }
        top = min(rows, cellsUp(safe.top))
        bottom = max(top, rows - cellsUp(safe.bottom))
    }

    func cell(at p: CGPoint) -> (Int, Int) { (Int(p.x / pitch), Int(p.y / pitch)) }
}

// MARK: - Painting

/// Paints a buffer: black, the unlit grid as one tiled cell, then one path per colour.
struct VFDDisplay: View {
    let buffer: VFDBuffer
    let metrics: VFDMetrics
    let colors: VFDPalette.Colors

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let m = metrics
            let gridRect = CGRect(x: 0, y: 0, width: CGFloat(m.cols) * m.pitch, height: CGFloat(m.rows) * m.pitch)
            ctx.fill(Path(gridRect), with: .tiledImage(Image(uiImage: VFDDisplay.tile(m)).interpolation(.none),
                                                       origin: .zero, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1))
            var palette: [Int] = [0, colors.base, colors.text, colors.dim, colors.alarm]
            palette += buffer.swatches
            var paths = [Path](repeating: Path(), count: palette.count)
            let cols = buffer.cols
            buffer.cells.withUnsafeBufferPointer { cells in
                for r in 0..<buffer.rows {
                    let row = r * cols
                    for c in 0..<cols {
                        let v = Int(cells[row + c])
                        guard v != 0, v < palette.count else { continue }
                        paths[v].addRect(CGRect(x: CGFloat(c) * m.pitch, y: CGFloat(r) * m.pitch, width: m.lit, height: m.lit))
                    }
                }
            }
            for i in 1..<palette.count where !paths[i].isEmpty {
                ctx.fill(paths[i], with: .color(Color(rgbInt: palette[i])), style: FillStyle(antialiased: false))
            }
        }
    }

    private static var tiles: [Int: UIImage] = [:]
    /// One unlit cell: a near-black square and its 1-pixel black gap.
    static func tile(_ m: VFDMetrics) -> UIImage {
        let key = m.pitchPx * 10 + Int(m.scale)
        if let t = tiles[key] { return t }
        let format = UIGraphicsImageRendererFormat()
        format.scale = m.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: m.pitch, height: m.pitch), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: m.pitch, height: m.pitch))
            UIColor(Color(rgbInt: VFDPalette.unlit)).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: m.lit, height: m.lit))
        }
        tiles[key] = image
        return image
    }
}

/// The theme's backdrop outside the pixel screens (sheets, the theme picker tile): black with
/// the unlit grid.
struct VFDBackdrop: View {
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        GeometryReader { geo in
            let m = VFDMetrics(size: geo.size, safe: EdgeInsets(), scale: displayScale)
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .tiledImage(Image(uiImage: VFDDisplay.tile(m)).interpolation(.none), origin: .zero,
                                           sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1))
            }
        }
        .ignoresSafeArea()
    }
}
