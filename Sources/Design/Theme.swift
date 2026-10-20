import SwiftUI

/// The app's look, picked under Settings → Theme. Each one changes the backdrop, the glass
/// panels, the colours and the type; the touches keep their own colours in every theme.
enum AppStyle: String, CaseIterable, Identifiable {
    case aero, neon, pastel, mono, aurora, paper, chalk, bubble, raindrop, citrus
    var id: String { rawValue }

    var title: String {
        switch self {
        case .aero: return "Aero Glass"
        case .neon: return "Midnight Neon"
        case .pastel: return "Soft Pastel"
        case .mono: return "Minimal Mono"
        case .aurora: return "Liquid Aurora"
        case .paper: return "Paper & Ink"
        case .chalk: return "Chalkboard"
        case .bubble: return "Bubble"
        case .raindrop: return "Raindrop"
        case .citrus: return "Citrus"
        }
    }

    var blurb: String {
        switch self {
        case .aero: return "Navy sky, drifting light, frosted glass"
        case .neon: return "Black, cyan and magenta glow"
        case .pastel: return "Warm cream, pillowy cards, coral"
        case .mono: return "Black on paper white, hairlines"
        case .aurora: return "Deep night with flowing northern lights"
        case .paper: return "Ruled paper and fountain-pen ink"
        case .chalk: return "A black chalkboard, sketched in chalk"
        case .bubble: return "Frutiger Aero: sky, glossy glass, rising bubbles"
        case .raindrop: return "Frutiger Aero: fresh green, rain on glass"
        case .citrus: return "Frutiger Aero: sunny, juicy, glossy fruit"
        }
    }

    var isLight: Bool { [.pastel, .mono, .paper, .bubble, .raindrop, .citrus].contains(self) }

    /// The glossy Frutiger Aero themes: bright, wet-looking glass with a shine across the top.
    var isAqua: Bool { [.bubble, .raindrop, .citrus].contains(self) }

    /// How round the panels are — sharp for Mono and Paper, soft and pillowy for the Aero ones.
    var corner: CGFloat {
        switch self {
        case .aero: return 24
        case .neon: return 14
        case .pastel: return 28
        case .mono: return 6
        case .aurora: return 26
        case .paper: return 10
        case .chalk: return 18
        case .bubble: return 32
        case .raindrop: return 28
        case .citrus: return 30
        }
    }

    /// The colours this theme can wear (its accent, and the main glow in its backdrop). The
    /// first is the theme's own. Paper & Ink uses its ink colours (`PaperInk`) instead.
    var tints: [(name: String, rgb: Int)] {
        switch self {
        case .aero: return [("Teal", 0x57C3BB), ("Sky", 0x5AB8F0), ("Violet", 0xB18CF0), ("Rose", 0xF07FA8), ("Mint", 0x7FE0A8), ("Gold", 0xF0C35A)]
        case .neon: return [("Cyan", 0x00E5FF), ("Magenta", 0xFF2BD6), ("Acid", 0xB6FF3B), ("Laser", 0xFF3B5C), ("Volt", 0xFFE600), ("Ultraviolet", 0x9D5CFF)]
        case .pastel: return [("Coral", 0xF07F6E), ("Lilac", 0xA98BE8), ("Mint", 0x5DBE96), ("Sky", 0x6FB3E8), ("Peach", 0xF5A35E), ("Rose", 0xE8789E)]
        case .mono: return [("Vermilion", 0xE8452C), ("Cobalt", 0x2850E8), ("Emerald", 0x168A55), ("Black", 0x111111), ("Magenta", 0xD0247A), ("Amber", 0xD98A00)]
        case .aurora: return [("Mint", 0x5EEAD4), ("Violet", 0xA78BFA), ("Pink", 0xFF6FD8), ("Ice", 0x8FD8FF), ("Lime", 0xA3F27A), ("Gold", 0xFBBF5C)]
        case .paper: return []
        case .chalk: return [("Yellow", 0xF4E38C), ("White", 0xF1F0E8), ("Pink", 0xF5A9C4), ("Blue", 0xA9D4F5), ("Green", 0xBDE8A4), ("Orange", 0xF7C98C)]
        case .bubble: return [("Sky", 0x1E9BE8), ("Lagoon", 0x13B5C8), ("Grass", 0x3DBB5C), ("Orchid", 0x9B6CF6), ("Coral", 0xFF7A6B), ("Sun", 0xF5B300)]
        case .raindrop: return [("Mint", 0x12A594), ("Rain", 0x3D8BD9), ("Leaf", 0x5FB83A), ("Iris", 0x7A6CF0), ("Rose", 0xE86A92), ("Dew", 0x2BB3D9)]
        case .citrus: return [("Orange", 0xFF8A00), ("Lime", 0x6DB935), ("Lemon", 0xE6B800), ("Grapefruit", 0xFF5E7E), ("Tangerine", 0xFF6A2B), ("Kiwi", 0x4FAE3D)]
        }
    }
}

/// The colour picked for each theme, kept per theme ("aero=5AB8F0;neon=FF2BD6"), so
/// switching themes and back keeps each one's choice.
enum ThemeTints {
    static let key = "themeTints"

    static func parse(_ raw: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=")
            if kv.count == 2, let v = Int(kv[1], radix: 16) { out[String(kv[0])] = v }
        }
        return out
    }

    static func encode(_ d: [String: Int]) -> String {
        d.sorted { $0.key < $1.key }.map { "\($0.key)=\(String($0.value, radix: 16, uppercase: true))" }.joined(separator: ";")
    }

    /// The picked colour for `style`, or nil for the theme's own.
    static func tint(for style: AppStyle, in raw: String = UserDefaults.standard.string(forKey: key) ?? "") -> Int? {
        guard let v = parse(raw)[style.rawValue], v != style.tints.first?.rgb else { return nil }
        return v
    }
}

/// The ink colours for Paper & Ink. Each tints the paper a little to match.
enum PaperInk: String, CaseIterable, Identifiable {
    case indigo, aqua, teal, sepia, forest, plum, crimson, charcoal
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// (ink, darker ink for text, paper)
    var colors: (ink: Int, deep: Int, paper: Int) {
        switch self {
        case .indigo: return (0x2A3F8F, 0x1C2A5E, 0xF6F1E6)
        case .aqua: return (0x1BA8A8, 0x0D6466, 0xEAF6F3)
        case .teal: return (0x16808A, 0x0E4F57, 0xEEF4F1)
        case .sepia: return (0x8A5A2E, 0x5A3A1C, 0xF6EEDF)
        case .forest: return (0x2F6B45, 0x1E4A2F, 0xF1F3E8)
        case .plum: return (0x7A3270, 0x52204B, 0xF6EFF2)
        case .crimson: return (0xB0303A, 0x7A1E26, 0xF8F0EA)
        case .charcoal: return (0x3A3A3A, 0x1E1E1E, 0xF3F2EE)
        }
    }
}

/// Every colour a theme sets.
struct Palette {
    var bgTop: Color, bgBottom: Color
    /// The base colour for text, hairlines and tints (white on dark themes, ink on light).
    var ink: Color
    var title: Color, subtitle: Color, mutedHeadline: Color
    var accent: Color, accentDeep: Color, accentTop: Color, onAccent: Color
    var magenta: Color, pink: Color, lime: Color, amber: Color, danger: Color
    var touchSent: Color, touchReceived: Color
    /// The panel fill for themes whose panels aren't frosted glass.
    var surface: Color
    var glassTop: Color, glassBottom: Color

    /// The theme's palette, wearing `tint` (a picked colour) as its accent if given.
    static func make(_ style: AppStyle, ink paperInk: PaperInk, tint: Int?) -> Palette {
        var p = make(style, ink: paperInk)
        guard let tint else { return p }
        func shade(_ f: Double) -> Color {
            func ch(_ s: Int) -> Double {
                let v = Double((tint >> s) & 0xFF) / 255
                return f >= 0 ? v + (1 - v) * f : v * (1 + f)
            }
            return Color(red: ch(16), green: ch(8), blue: ch(0))
        }
        let r = Double((tint >> 16) & 0xFF), g = Double((tint >> 8) & 0xFF), b = Double(tint & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        p.accent = Color(rgbInt: tint)
        p.accentDeep = shade(-0.18)
        p.accentTop = shade(0.3)
        p.onAccent = luminance > 0.6 ? Color(rgbInt: 0x111418) : .white
        if style == .neon { p.glassTop = Color(rgbInt: tint).opacity(0.08) }
        return p
    }

    static func make(_ style: AppStyle, ink paperInk: PaperInk) -> Palette {
        func c(_ v: Int) -> Color { Color(rgbInt: v) }
        let white = Color.white
        switch style {
        case .aero:
            return Palette(bgTop: c(0x123A5C), bgBottom: c(0x0B2440), ink: white,
                           title: white, subtitle: c(0xCFE3F2), mutedHeadline: c(0xDDEBF6),
                           accent: c(0x57C3BB), accentDeep: c(0x3FA69E), accentTop: c(0x74D3CB), onAccent: c(0x06283F),
                           magenta: c(0xB173DF), pink: c(0xEC5A89), lime: c(0x9FD257), amber: c(0xECA94B), danger: c(0xFF6B6B),
                           touchSent: c(0x00527B), touchReceived: c(0x003F63), surface: c(0x123A5C),
                           glassTop: white.opacity(0.22), glassBottom: white.opacity(0.07))
        case .neon:
            return Palette(bgTop: c(0x05060C), bgBottom: c(0x040509), ink: c(0xE6F6FF),
                           title: c(0xE6F6FF), subtitle: c(0x8A97B0), mutedHeadline: c(0xC9E9F5),
                           accent: c(0x00E5FF), accentDeep: c(0x00B8D4), accentTop: c(0x6FF3FF), onAccent: c(0x040509),
                           magenta: c(0xFF2BD6), pink: c(0xFF2E74), lime: c(0xB6FF3B), amber: c(0xFFB020), danger: c(0xFF3B5C),
                           touchSent: c(0x061A26), touchReceived: c(0x0B1020), surface: c(0x0A0F1C),
                           glassTop: c(0x00E5FF).opacity(0.08), glassBottom: .clear)
        case .pastel:
            return Palette(bgTop: c(0xFBF5EE), bgBottom: c(0xF6EBE2), ink: c(0x3B2E2A),
                           title: c(0x3B2E2A), subtitle: c(0x8C7A70), mutedHeadline: c(0x5A4A43),
                           accent: c(0xF07F6E), accentDeep: c(0xE8705E), accentTop: c(0xF7A08F), onAccent: white,
                           magenta: c(0xB58CE8), pink: c(0xF28AA8), lime: c(0x7DB98A), amber: c(0xF0A35E), danger: c(0xE0505A),
                           touchSent: c(0xFFE7DE), touchReceived: c(0xEFE7FF), surface: white,
                           glassTop: white.opacity(0.9), glassBottom: white.opacity(0.7))
        case .mono:
            return Palette(bgTop: c(0xF4F3EF), bgBottom: c(0xF4F3EF), ink: c(0x111111),
                           title: c(0x111111), subtitle: c(0x6B6B68), mutedHeadline: c(0x2A2A2A),
                           accent: c(0xE8452C), accentDeep: c(0xC9361F), accentTop: c(0xE8452C), onAccent: white,
                           magenta: c(0x111111), pink: c(0xE8452C), lime: c(0x111111), amber: c(0xE8452C), danger: c(0xE8452C),
                           touchSent: c(0xEAE9E4), touchReceived: c(0xE2E1DC), surface: c(0xF4F3EF),
                           glassTop: .clear, glassBottom: .clear)
        case .aurora:
            return Palette(bgTop: c(0x0A0F2C), bgBottom: c(0x070818), ink: white,
                           title: white, subtitle: c(0xC9C6F2), mutedHeadline: c(0xE2E0FF),
                           accent: c(0x5EEAD4), accentDeep: c(0x2CC9B0), accentTop: c(0x9BF6E6), onAccent: c(0x0A0F2C),
                           magenta: c(0x8B5CF6), pink: c(0xFF6FD8), lime: c(0x3CF2B0), amber: c(0xFBBF5C), danger: c(0xFF6B8A),
                           touchSent: c(0x1A1748), touchReceived: c(0x121038), surface: c(0x14123A),
                           glassTop: white.opacity(0.2), glassBottom: white.opacity(0.05))
        case .paper:
            let p = paperInk.colors
            return Palette(bgTop: c(p.paper), bgBottom: c(p.paper), ink: c(p.deep),
                           title: c(p.deep), subtitle: c(p.deep).opacity(0.68), mutedHeadline: c(p.deep),
                           accent: c(p.ink), accentDeep: c(p.deep), accentTop: c(p.ink), onAccent: white,
                           magenta: c(p.ink), pink: c(0xB0303A), lime: c(0x2F6B45), amber: c(0xA8742A), danger: c(0xB0303A),
                           touchSent: c(p.ink).opacity(0.10), touchReceived: c(p.deep).opacity(0.06), surface: white.opacity(0.55),
                           glassTop: .clear, glassBottom: .clear)
        case .chalk:
            let chalk = c(0xF1F0E8)
            return Palette(bgTop: c(0x26302B), bgBottom: c(0x1B221E), ink: chalk,
                           title: chalk, subtitle: chalk.opacity(0.66), mutedHeadline: chalk.opacity(0.85),
                           accent: c(0xF4E38C), accentDeep: c(0xE6CF62), accentTop: c(0xF8ECAA), onAccent: c(0x1B221E),
                           magenta: c(0xC9B3F0), pink: c(0xF5A9C4), lime: c(0xBDE8A4), amber: c(0xF7C98C), danger: c(0xF59A8F),
                           touchSent: c(0x2E3A34), touchReceived: c(0x29332E), surface: c(0x1B221E),
                           glassTop: .clear, glassBottom: .clear)
        case .bubble:
            return Palette(bgTop: c(0xBFEFFF), bgBottom: c(0x8ED8F8), ink: c(0x0B3556),
                           title: c(0x0B3556), subtitle: c(0x2F6A8F), mutedHeadline: c(0x134A73),
                           accent: c(0x1E9BE8), accentDeep: c(0x0F78C2), accentTop: c(0x7FD0FF), onAccent: white,
                           magenta: c(0x7B6CF6), pink: c(0xFF5E9A), lime: c(0x3DBB5C), amber: c(0xF5A300), danger: c(0xE5484D),
                           touchSent: c(0xDDF3FF), touchReceived: c(0xCDEBFA), surface: white,
                           glassTop: white.opacity(0.85), glassBottom: white.opacity(0.35))
        case .raindrop:
            return Palette(bgTop: c(0xDDF7EE), bgBottom: c(0x8FD9CF), ink: c(0x0D3B3A),
                           title: c(0x0D3B3A), subtitle: c(0x3C6E6A), mutedHeadline: c(0x164F4C),
                           accent: c(0x12A594), accentDeep: c(0x0B7F72), accentTop: c(0x6EDCCB), onAccent: white,
                           magenta: c(0x3D8BD9), pink: c(0xE8578A), lime: c(0x5FB83A), amber: c(0xF0A020), danger: c(0xE5484D),
                           touchSent: c(0xE2F7F1), touchReceived: c(0xD2F0EA), surface: white,
                           glassTop: white.opacity(0.85), glassBottom: white.opacity(0.35))
        case .citrus:
            return Palette(bgTop: c(0xFFF8D6), bgBottom: c(0xFFE08A), ink: c(0x3B2F0B),
                           title: c(0x3B2F0B), subtitle: c(0x7A6420), mutedHeadline: c(0x4A3B0E),
                           accent: c(0xFF8A00), accentDeep: c(0xE06C00), accentTop: c(0xFFB85C), onAccent: white,
                           magenta: c(0xE8457A), pink: c(0xFF5E7E), lime: c(0x6DB935), amber: c(0xFFB000), danger: c(0xD93A3A),
                           touchSent: c(0xFFF1C2), touchReceived: c(0xF3F7C8), surface: white,
                           glassTop: white.opacity(0.85), glassBottom: white.opacity(0.35))
        }
    }
}

/// Visual design tokens. They follow the theme picked in Settings (the root view rebuilds
/// itself when it changes), so screens just use `Theme.accent`, `Theme.title` and so on.
enum Theme {
    static var style: AppStyle { AppStyle(rawValue: UserDefaults.standard.string(forKey: "appStyle") ?? "") ?? .aero }
    static var paperInk: PaperInk { PaperInk(rawValue: UserDefaults.standard.string(forKey: "paperInk") ?? "") ?? .aqua }

    private static var cache: (key: String, palette: Palette)?
    static var p: Palette {
        let s = style, i = paperInk, raw = UserDefaults.standard.string(forKey: ThemeTints.key) ?? ""
        let key = s.rawValue + i.rawValue + raw
        if let cache, cache.key == key { return cache.palette }
        let palette = Palette.make(s, ink: i, tint: ThemeTints.tint(for: s, in: raw))
        cache = (key, palette)
        return palette
    }

    /// Any theme's palette, with its picked colour (for previews).
    static func palette(for style: AppStyle) -> Palette {
        Palette.make(style, ink: paperInk, tint: ThemeTints.tint(for: style))
    }

    static var bgTop: Color { p.bgTop }
    static var bgBottom: Color { p.bgBottom }
    static var ink: Color { p.ink }

    // Glass surfaces.
    static var card: Color { p.ink.opacity(0.10) }
    static var cardStroke: Color { p.ink.opacity(0.28) }
    static var cardStrong: Color { p.ink.opacity(0.16) }
    static var glassTop: Color { p.glassTop }
    static var glassBottom: Color { p.glassBottom }

    // Interactive accent.
    static var accent: Color { p.accent }
    static var accentDeep: Color { p.accentDeep }
    static var teal: Color { p.accent }
    static var cyan: Color { p.accent }
    /// Text on accent-filled buttons.
    static var onAccent: Color { p.onAccent }

    // Highlight colours.
    static var lime: Color { p.lime }
    static var pink: Color { p.pink }
    static var magenta: Color { p.magenta }
    static var amber: Color { p.amber }
    static var danger: Color { p.danger }

    // Touch feed surfaces.
    static var touchSent: Color { p.touchSent }
    static var touchReceived: Color { p.touchReceived }

    // Text.
    static var title: Color { p.title }
    static var subtitle: Color { p.subtitle }
    static var mutedHeadline: Color { p.mutedHeadline }

    static var grid: Color { p.ink.opacity(0.045) }

    static let corner: CGFloat = 20
    static var cardCorner: CGFloat { style.corner }

    static var colorScheme: ColorScheme { style.isLight ? .light : .dark }

    /// The theme's backdrop, used behind every screen.
    static var background: some View { ThemeBackdrop().ignoresSafeArea() }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        font(size, weight, style: style)
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight, style: AppStyle) -> Font {
        switch style {
        case .chalk:
            let bold: [Font.Weight] = [.semibold, .bold, .heavy, .black]
            return .custom(bold.contains(weight) ? "ChalkboardSE-Bold" : weight == .light ? "ChalkboardSE-Light" : "ChalkboardSE-Regular",
                           size: size)
        case .paper: return .system(size: size, weight: weight, design: .serif)
        case .neon: return .system(size: size, weight: weight, design: .monospaced)
        case .mono: return .system(size: size, weight: weight, design: .default)
        case .aero, .pastel, .aurora, .bubble, .raindrop, .citrus: return .system(size: size, weight: weight, design: .rounded)
        }
    }
}

/// Puts the theme's type on every text that doesn't pick its own font.
struct ThemeFonts: ViewModifier {
    func body(content: Content) -> some View {
        switch Theme.style {
        case .chalk:
            content.font(.custom("ChalkboardSE-Regular", size: 17, relativeTo: .body))
        default:
            if #available(iOS 16.1, *) {
                content.fontDesign(fontDesign)
            } else {
                content
            }
        }
    }

    private var fontDesign: Font.Design {
        switch Theme.style {
        case .paper: return .serif
        case .neon: return .monospaced
        case .mono, .chalk: return .default
        case .aero, .pastel, .aurora, .bubble, .raindrop, .citrus: return .rounded
        }
    }
}

/// The backdrop for the current theme.
struct ThemeBackdrop: View {
    var style: AppStyle = Theme.style
    /// False: a still frame (theme picker tiles, where moving bubbles get in the way of taps).
    var animated = true

    var body: some View {
        let glow = ThemeTints.tint(for: style).map { Color(rgbInt: $0) }
        switch style {
        case .aero: AeroSky(glow: glow)
        case .neon: NeonNight(glow: glow)
        case .pastel: PastelHaze(glow: glow)
        case .mono: Color(rgbInt: 0xF4F3EF)
        case .aurora: AuroraSky(glow: glow)
        case .paper: RuledPaper()
        case .chalk: Chalkboard()
        case .bubble: BubbleSky(glow: glow, animated: animated)
        case .raindrop: RainOnGlass(glow: glow, animated: animated)
        case .citrus: CitrusSun(glow: glow)
        }
    }
}

/// A soft round glow of light.
private func bloom(_ color: Color, _ opacity: Double, _ size: CGFloat) -> some View {
    Circle()
        .fill(RadialGradient(colors: [color.opacity(opacity), .clear], center: .center,
                             startRadius: 0, endRadius: size / 2))
        .frame(width: size, height: size)
}

/// The aero sky: navy gradient with soft blooms of teal, violet and pink light that drift
/// slowly, under a faint HUD grid — a quietly futuristic, living backdrop.
struct AeroSky: View {
    var glow: Color?
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0x123A5C), Color(rgbInt: 0x0B2440)], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    bloom(glow ?? Color(rgbInt: 0x57C3BB), 0.34, w * 1.2).position(x: w * 0.15, y: drift ? h * 0.05 : -h * 0.03)
                    bloom(Color(rgbInt: 0xB173DF), 0.26, w * 1.0).position(x: drift ? w * 0.9 : w, y: h * 0.35)
                    bloom(Color(rgbInt: 0xEC5A89), 0.22, w * 0.9).position(x: drift ? w * 0.06 : 0, y: drift ? h * 0.94 : h)
                }
                .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: drift)
                HUDGrid(spacing: 46)
                    .stroke(Color.white.opacity(0.045), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { drift = true }
    }
}

/// Midnight Neon: near-black with a cyan and a magenta glow, under a fine dot grid.
struct NeonNight: View {
    var glow: Color?
    @State private var drift = false
    var body: some View {
        ZStack {
            Color(rgbInt: 0x040509)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    bloom(glow ?? Color(rgbInt: 0x00E5FF), 0.22, w * 1.1).position(x: drift ? w * 0.1 : w * 0.2, y: h * 0.08)
                    bloom(Color(rgbInt: 0xFF2BD6), 0.2, w * 1.1).position(x: drift ? w * 0.95 : w * 0.85, y: h * 0.9)
                }
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: drift)
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.07)))
                            x += 22
                        }
                        y += 22
                    }
                }
            }
        }
        .onAppear { drift = true }
    }
}

/// Soft Pastel: warm cream with peach, lilac and mint haze.
struct PastelHaze: View {
    var glow: Color?
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0xFBF5EE), Color(rgbInt: 0xF6EBE2)], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    bloom(glow ?? Color(rgbInt: 0xFFC9B5), glow == nil ? 0.75 : 0.4, w * 1.2).position(x: drift ? w * 0.1 : w * 0.2, y: h * 0.06)
                    bloom(Color(rgbInt: 0xD9C8FF), 0.6, w * 1.1).position(x: drift ? w * 0.95 : w * 0.85, y: h * 0.45)
                    bloom(Color(rgbInt: 0xC5EFD9), 0.6, w * 1.0).position(x: drift ? w * 0.05 : w * 0.15, y: h * 0.92)
                }
                .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: drift)
            }
        }
        .onAppear { drift = true }
    }
}

/// Liquid Aurora: a deep night sky with ribbons of green, violet and pink light flowing
/// slowly across it, and a few stars.
struct AuroraSky: View {
    var glow: Color?
    @State private var flow = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0x0A0F2C), Color(rgbInt: 0x070818)], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    ribbon(glow ?? Color(rgbInt: 0x3CF2B0), w * 1.5, h * 0.22).rotationEffect(.degrees(flow ? -18 : -8))
                        .position(x: w * 0.5, y: flow ? h * 0.2 : h * 0.15)
                    ribbon(Color(rgbInt: 0x8B5CF6), w * 1.4, h * 0.2).rotationEffect(.degrees(flow ? 14 : 24))
                        .position(x: flow ? w * 0.6 : w * 0.4, y: h * 0.42)
                    ribbon(Color(rgbInt: 0xFF6FD8), w * 1.2, h * 0.16).rotationEffect(.degrees(flow ? -10 : 4))
                        .position(x: w * 0.5, y: flow ? h * 0.78 : h * 0.84)
                }
                .blur(radius: 50)
                .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: flow)
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 11)
                    for _ in 0..<60 {
                        let r = CGFloat(rng.next() * 1.4 + 0.4)
                        let p = CGPoint(x: CGFloat(rng.next()) * size.width, y: CGFloat(rng.next()) * size.height)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)),
                                 with: .color(.white.opacity(rng.next() * 0.5 + 0.15)))
                    }
                }
            }
        }
        .onAppear { flow = true }
    }

    private func ribbon(_ color: Color, _ w: CGFloat, _ h: CGFloat) -> some View {
        Capsule().fill(LinearGradient(colors: [.clear, color.opacity(0.55), color.opacity(0.3), .clear],
                                      startPoint: .leading, endPoint: .trailing))
            .frame(width: w, height: h)
    }
}

/// Paper & Ink: ruled paper in the chosen ink's tint, with a margin line.
struct RuledPaper: View {
    var ink: PaperInk = Theme.paperInk
    var body: some View {
        let c = ink.colors
        ZStack {
            Color(rgbInt: c.paper)
            Canvas { ctx, size in
                var y: CGFloat = 34
                while y < size.height {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(Color(rgbInt: c.ink).opacity(0.09)), lineWidth: 0.7)
                    y += 30
                }
                var margin = Path()
                margin.move(to: CGPoint(x: 38, y: 0)); margin.addLine(to: CGPoint(x: 38, y: size.height))
                ctx.stroke(margin, with: .color(Color(rgbInt: c.ink).opacity(0.18)), lineWidth: 1)
            }
            // A soft darkening at the edges, like a sheet under a lamp.
            RadialGradient(colors: [.clear, Color(rgbInt: c.deep).opacity(0.07)], center: .center, startRadius: 200, endRadius: 600)
        }
    }
}

/// Chalkboard: a dark slate with clouds of chalk dust, half-wiped eraser sweeps and a few
/// faint ghosts of old doodles.
struct Chalkboard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0x26302B), Color(rgbInt: 0x1B221E)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 5)
                // Dust.
                var dust = ctx
                dust.addFilter(.blur(radius: 28))
                for _ in 0..<26 {
                    let w = CGFloat(rng.next() * 220 + 80), h = w * CGFloat(rng.next() * 0.5 + 0.4)
                    let r = CGRect(x: CGFloat(rng.next()) * size.width - w / 2, y: CGFloat(rng.next()) * size.height - h / 2, width: w, height: h)
                    dust.fill(Path(ellipseIn: r), with: .color(.white.opacity(rng.next() * 0.035 + 0.015)))
                }
                // Eraser sweeps.
                var sweep = ctx
                sweep.addFilter(.blur(radius: 10))
                for _ in 0..<5 {
                    var p = Path()
                    let y = CGFloat(rng.next()) * size.height
                    p.move(to: CGPoint(x: -20, y: y))
                    p.addQuadCurve(to: CGPoint(x: size.width + 20, y: y + CGFloat(rng.next() * 80 - 40)),
                                   control: CGPoint(x: size.width / 2, y: y + CGFloat(rng.next() * 120 - 60)))
                    sweep.stroke(p, with: .color(.white.opacity(0.03)), style: StrokeStyle(lineWidth: 46, lineCap: .round))
                }
                // Ghost doodles: little hearts and stars, almost wiped away.
                for i in 0..<6 {
                    let at = CGPoint(x: CGFloat(rng.next()) * size.width, y: CGFloat(rng.next()) * size.height)
                    let s = CGFloat(rng.next() * 18 + 16)
                    let shape = i % 2 == 0 ? Self.heart(at, s) : Self.star(at, s)
                    ctx.stroke(shape, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            // The board's edges are darker.
            RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 220, endRadius: 650)
        }
    }

    static func heart(_ c: CGPoint, _ s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y + s * 0.6))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - s * 0.2), control1: CGPoint(x: c.x - s * 1.1, y: c.y - s * 0.1),
                   control2: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.9))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.6), control1: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.9),
                   control2: CGPoint(x: c.x + s * 1.1, y: c.y - s * 0.1))
        return p
    }

    static func star(_ c: CGPoint, _ s: CGFloat) -> Path {
        var p = Path()
        for i in 0..<6 {
            let a = Double(i % 5) * 4 * .pi / 5 - .pi / 2
            let pt = CGPoint(x: c.x + s * CGFloat(cos(a)), y: c.y + s * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// A small repeatable random source, so a backdrop draws the same way every time.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}

/// A faint evenly-spaced grid of hairlines, drawn across the whole backdrop.
struct HUDGrid: Shape {
    var spacing: CGFloat = 46
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX
        while x <= rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY)); x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y)); y += spacing
        }
        return p
    }
}

/// A panel behind content, in the theme's own material: frosted glass (Aero, Aurora), a
/// glowing neon outline, a pillowy card (Pastel), a hairline box (Mono), a sheet with an
/// inked edge (Paper) or a sketched chalk outline (Chalkboard).
struct GlassBackground<S: Shape>: View {
    let shape: S
    var style: AppStyle = Theme.style
    /// How see-through the panel is (0 solid … 1 nearly clear) and how deep its shadow is
    /// (0 none … 1 deep) — the two sliders under Softness.
    @AppStorage("glassClarity") private var clarity = 0.55
    @AppStorage("glassShadow") private var shadowDepth = 0.6

    var body: some View {
        let p = Theme.palette(for: style)
        switch style {
        case .aero, .aurora:
            shape
                .fill(.ultraThinMaterial)
                .opacity(1 - clarity * 0.75)
                .overlay(shape.fill(LinearGradient(colors: [p.glassTop, p.glassBottom], startPoint: .top, endPoint: .bottom))
                    .opacity(1 - clarity * 0.6))
                // A faint rim-light: the panel edge catches the sky's colours, like holo glass.
                .overlay(shape.stroke(LinearGradient(colors: [p.accent.opacity(0.35), .clear, p.magenta.opacity(0.18)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    .blur(radius: 1.5))
                // The crisp bright top edge over it.
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
                // A soft, wide ambient shadow plus a tight contact shadow.
                .shadow(color: Color.black.opacity(0.22 * shadowDepth), radius: 4 + 22 * shadowDepth, y: 4 + 12 * shadowDepth)
                .shadow(color: Color.black.opacity(0.18 * shadowDepth), radius: 2, y: 1 + shadowDepth)
        case .neon:
            shape
                .fill(p.surface.opacity(0.92 - clarity * 0.45))
                .overlay(shape.fill(LinearGradient(colors: [p.glassTop, p.glassBottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.stroke(LinearGradient(colors: [p.accent.opacity(0.9), p.magenta.opacity(0.6)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: p.accent.opacity(0.35 * shadowDepth), radius: 4 + 10 * shadowDepth)
        case .pastel:
            shape
                .fill(Color.white.opacity(0.92 - clarity * 0.35))
                .overlay(shape.stroke(Color.white, lineWidth: 1))
                .shadow(color: Color(rgbInt: 0xC08060).opacity(0.22 * shadowDepth), radius: 4 + 16 * shadowDepth, y: 3 + 8 * shadowDepth)
        case .mono:
            shape
                .fill(p.surface.opacity(1 - clarity * 0.6))
                .overlay(shape.stroke(p.ink.opacity(0.85), lineWidth: 1))
        case .paper:
            shape
                .fill(p.surface.opacity(1 - clarity * 0.5))
                .overlay(shape.stroke(p.accent.opacity(0.7), lineWidth: 1.2))
                // A hard, offset shadow, like a card cut out and laid on the page.
                .background(shape.fill(p.ink.opacity(0.14 * shadowDepth / 0.6)).offset(x: 3, y: 3))
        case .chalk:
            let chalk = p.ink
            shape
                .fill(Color.black.opacity(0.25 - clarity * 0.15))
                // A sketched outline: a broken main stroke and two fainter, slightly offset
                // passes, the way a chalk line is drawn over twice.
                .overlay(shape.stroke(chalk.opacity(0.8), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [26, 2.5, 14, 1.8, 40, 3])))
                .overlay(shape.stroke(chalk.opacity(0.32), lineWidth: 1).offset(x: 0.9, y: -0.8))
                .overlay(shape.stroke(chalk.opacity(0.18), lineWidth: 1.4).offset(x: -0.7, y: 1))
                .shadow(color: Color.black.opacity(0.3 * shadowDepth), radius: 8 * shadowDepth, y: 3 * shadowDepth)
        case .bubble, .raindrop, .citrus:
            // Aqua glass: milky white, a bright wet shine over the top half, a crisp white rim
            // and a soft glow in the accent colour underneath — Frutiger Aero.
            shape
                .fill(Color.white.opacity(0.62 - clarity * 0.32))
                .overlay(shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                                           .init(color: .white.opacity(0.25), location: 0.48),
                                                           .init(color: .clear, location: 0.5),
                                                           .init(color: p.accent.opacity(0.10), location: 1)],
                                                   startPoint: .top, endPoint: .bottom))
                    .opacity(1 - clarity * 0.5))
                .overlay(shape.stroke(LinearGradient(colors: [.white, .white.opacity(0.55), p.accent.opacity(0.35)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.4))
                .shadow(color: p.accent.opacity(0.28 * shadowDepth), radius: 4 + 14 * shadowDepth, y: 3 + 6 * shadowDepth)
        }
    }
}

/// Bubble: a bright sky with soft clouds of light and glossy bubbles drifting up.
struct BubbleSky: View {
    var glow: Color?
    var animated = true
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0xE6FAFF), Color(rgbInt: 0x9EDFFA), Color(rgbInt: 0x5CC2F0)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.9), .clear], center: UnitPoint(x: 0.2, y: 0.05), startRadius: 10, endRadius: 360)
            RadialGradient(colors: [(glow ?? Color(rgbInt: 0x7CE08A)).opacity(0.45), .clear], center: UnitPoint(x: 0.9, y: 1.05),
                           startRadius: 10, endRadius: 420)
            BubbleParticles(animated: animated)
        }
    }
}

/// The Bubble theme's rising bubbles on their own, so they can float over a background photo.
/// Drawn on the GPU (`drawingGroup`) at a modest frame rate, and still with Reduce Motion or
/// Low Power Mode, so the animation never competes with taps.
struct BubbleParticles: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                TimelineView(.animation(minimumInterval: 1 / 24)) { ctx in canvas(ctx.date.timeIntervalSinceReferenceDate) }
            } else {
                canvas(40)
            }
        }
        .allowsHitTesting(false)
    }

    private func canvas(_ t: Double) -> some View {
        Canvas { g, size in
            var rng = SeededRandom(seed: 21)
            for _ in 0..<16 {
                let r = CGFloat(rng.next() * 30 + 8)
                let speed = rng.next() * 18 + 10
                let x0 = CGFloat(rng.next()) * size.width
                let phase = rng.next() * 1000
                let span = Double(size.height + r * 4)
                let y = size.height + r * 2 - CGFloat((t * speed + phase).truncatingRemainder(dividingBy: span))
                let x = x0 + CGFloat(sin((t + phase) * 0.6)) * 14
                AquaGloss.bubble(&g, center: CGPoint(x: x, y: y), radius: r)
            }
        }
        .drawingGroup()
    }
}

/// Raindrop: fresh green-blue light, with raindrops resting on the glass and a few running down.
struct RainOnGlass: View {
    var glow: Color?
    var animated = true
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0xEFFBF5), Color(rgbInt: 0xA9E6D6), Color(rgbInt: 0x5FC3B8)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.85), .clear], center: UnitPoint(x: 0.8, y: 0.0), startRadius: 10, endRadius: 380)
            RadialGradient(colors: [(glow ?? Color(rgbInt: 0x8BD96B)).opacity(0.4), .clear], center: UnitPoint(x: 0.1, y: 1.0),
                           startRadius: 10, endRadius: 420)
            RainParticles(animated: animated)
        }
    }
}

/// The Raindrop theme's drops on their own, so they can sit on a background photo too. The
/// resting drops are drawn once; only the few running down the glass move (on the GPU).
struct RainParticles: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            resting
            if animated && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in running(ctx.date.timeIntervalSinceReferenceDate) }
            } else {
                running(12)
            }
        }
        .allowsHitTesting(false)
    }

    /// Drops resting on the glass: they never move, so they're drawn once.
    private var resting: some View {
        Canvas { g, size in
            var rng = SeededRandom(seed: 9)
            for _ in 0..<46 {
                let r = CGFloat(rng.next() * 7 + 2.5)
                let p = CGPoint(x: CGFloat(rng.next()) * size.width, y: CGFloat(rng.next()) * size.height)
                AquaGloss.drop(&g, center: p, radius: r)
            }
        }
        .drawingGroup()
    }

    /// A few running down, leaving a faint trail.
    private func running(_ t: Double) -> some View {
        Canvas { g, size in
            var rng = SeededRandom(seed: 77)
            for i in 0..<4 {
                let x = CGFloat(rng.next()) * size.width
                let speed = rng.next() * 40 + 30
                let y = CGFloat((t * speed + Double(i) * 400).truncatingRemainder(dividingBy: Double(size.height + 60))) - 30
                var trail = Path()
                trail.move(to: CGPoint(x: x, y: max(0, y - 90)))
                trail.addLine(to: CGPoint(x: x, y: y))
                g.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.35)]),
                                                      startPoint: CGPoint(x: x, y: y - 90), endPoint: CGPoint(x: x, y: y)),
                         lineWidth: 2.5)
                AquaGloss.drop(&g, center: CGPoint(x: x, y: y), radius: 6)
            }
        }
        .drawingGroup()
    }
}

/// Citrus: sunny yellow to fresh lime, glossy citrus slices at the edges and soft bokeh.
struct CitrusSun: View {
    var glow: Color?
    @State private var spin = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgbInt: 0xFFFBE3), Color(rgbInt: 0xFFE8A0), Color(rgbInt: 0xC7EC8A)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.95), .clear], center: UnitPoint(x: 0.85, y: 0.02), startRadius: 10, endRadius: 340)
            RadialGradient(colors: [(glow ?? Color(rgbInt: 0xFFB347)).opacity(0.35), .clear], center: UnitPoint(x: 0.0, y: 0.55),
                           startRadius: 10, endRadius: 360)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    CitrusSlice(peel: 0xFF9A1F, flesh: 0xFFC14D).frame(width: 240, height: 240)
                        .rotationEffect(.degrees(spin ? 12 : -12)).position(x: w + 30, y: h * 0.16)
                    CitrusSlice(peel: 0x6DB935, flesh: 0xB8E36A).frame(width: 200, height: 200)
                        .rotationEffect(.degrees(spin ? -10 : 10)).position(x: -30, y: h * 0.62)
                    CitrusSlice(peel: 0xF2C200, flesh: 0xFFE680).frame(width: 170, height: 170)
                        .rotationEffect(.degrees(spin ? 8 : -8)).position(x: w * 0.82, y: h + 30)
                }
                .opacity(0.85)
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: spin)
                Canvas { g, size in
                    var rng = SeededRandom(seed: 33)
                    for _ in 0..<24 {
                        let r = CGFloat(rng.next() * 26 + 6)
                        let p = CGPoint(x: CGFloat(rng.next()) * size.width, y: CGFloat(rng.next()) * size.height)
                        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                               with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                                     center: p, startRadius: 0, endRadius: r))
                    }
                }
            }
        }
        .onAppear { spin = true }
    }
}

/// A glossy citrus wheel: peel, pith, juicy segments, and a wet shine.
struct CitrusSlice: View {
    var peel: Int
    var flesh: Int
    var body: some View {
        Canvas { g, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2
            g.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: r * 2, height: r * 2)), with: .color(Color(rgbInt: peel)))
            g.fill(Path(ellipseIn: CGRect(x: r * 0.08, y: r * 0.08, width: r * 1.84, height: r * 1.84)), with: .color(Color(rgbInt: 0xFFF8E1)))
            for i in 0..<10 {
                let a0 = Double(i) * .pi / 5 + 0.05, a1 = a0 + .pi / 5 - 0.1
                var seg = Path()
                seg.move(to: c)
                seg.addArc(center: c, radius: r * 0.86, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                seg.closeSubpath()
                g.fill(seg, with: .radialGradient(Gradient(colors: [Color(rgbInt: flesh).opacity(0.75), Color(rgbInt: flesh)]),
                                                  center: c, startRadius: 0, endRadius: r))
            }
            var shine = Path()
            shine.addEllipse(in: CGRect(x: r * 0.3, y: r * 0.15, width: r * 1.0, height: r * 0.5))
            g.fill(shine, with: .linearGradient(Gradient(colors: [.white.opacity(0.7), .white.opacity(0)]),
                                                startPoint: CGPoint(x: c.x, y: r * 0.15), endPoint: CGPoint(x: c.x, y: r * 0.65)))
        }
    }
}

/// The shared glossy shapes of the Aero themes.
enum AquaGloss {
    /// A soap bubble: a thin bright rim, a faint body, a highlight top-left and a glint bottom-right.
    static func bubble(_ g: inout GraphicsContext, center c: CGPoint, radius r: CGFloat) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        g.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [.white.opacity(0.05), .white.opacity(0.12), .white.opacity(0.55)]),
                                                            center: c, startRadius: 0, endRadius: r))
        g.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: max(1, r * 0.06))
        let hi = CGRect(x: c.x - r * 0.62, y: c.y - r * 0.7, width: r * 0.7, height: r * 0.42)
        g.fill(Path(ellipseIn: hi), with: .color(.white.opacity(0.85)))
        g.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.35, y: c.y + r * 0.35, width: r * 0.22, height: r * 0.22)),
               with: .color(.white.opacity(0.6)))
    }

    /// A raindrop on glass: a dark lower edge, a clear body and a bright highlight.
    static func drop(_ g: inout GraphicsContext, center c: CGPoint, radius r: CGFloat) {
        let rect = CGRect(x: c.x - r, y: c.y - r * 1.1, width: r * 2, height: r * 2.2)
        g.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: r * 0.25)), with: .color(Color(rgbInt: 0x0D3B3A).opacity(0.12)))
        g.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [.white.opacity(0.15), .white.opacity(0.45)]),
                                                            center: CGPoint(x: c.x, y: c.y + r * 0.3), startRadius: 0, endRadius: r * 1.2))
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.75, width: r * 0.55, height: r * 0.45)),
               with: .color(.white.opacity(0.9)))
    }
}

extension View {
    /// Wraps a screen in the theme's backdrop.
    func screenBackground() -> some View {
        ZStack { Theme.background; self }
    }

    /// The theme's panel behind this view, in `shape`.
    func glass<S: Shape>(_ shape: S) -> some View {
        background(GlassBackground(shape: shape))
    }

    /// The theme's panel in a rounded rectangle.
    func glass(cornerRadius: CGFloat = Theme.cardCorner) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A primary (accent) capsule button style — glossy in the glass themes, flat in the
/// paper, mono and chalk ones.
struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    func makeBody(configuration: Configuration) -> some View {
        let glossy = [AppStyle.aero, .aurora, .neon, .pastel, .bubble, .raindrop, .citrus].contains(Theme.style)
        return configuration.label
            .font(Theme.font(17, .heavy))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(
                Capsule().fill(LinearGradient(colors: [Theme.p.accentTop, Theme.accentDeep],
                                              startPoint: .top, endPoint: .bottom))
                    // A specular sheen across the top third, like light on a glass key.
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(glossy ? 0.45 : 0), .clear],
                                                           startPoint: .top, endPoint: .center))
                        .padding(1).mask(Capsule()))
                    .overlay(Capsule().stroke(.white.opacity(glossy ? 0.5 : 0), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(glossy ? 0.45 : 0), radius: 14, y: 5)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A secondary glass capsule button style.
struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .bold))
            .foregroundStyle(Theme.title)
            .frame(maxWidth: .infinity).frame(height: height)
            .glass(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
