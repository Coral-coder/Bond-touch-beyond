import SwiftUI

/// Visual design tokens for Bond Touch Beyond — "aero glass": a deep navy sky with soft
/// teal / violet / pink light, frosted glass panels with a bright top edge, the original
/// app's teal accent, and neon touch colours. Type is SF Rounded throughout.
enum Theme {
    // Sky.
    static let bgTop = Color(rgbInt: 0x123A5C)
    static let bgBottom = Color(rgbInt: 0x0B2440)

    // Glass surfaces.
    static let card = Color.white.opacity(0.10)
    static let cardStroke = Color.white.opacity(0.28)
    static let cardStrong = Color.white.opacity(0.16)
    static let glassTop = Color.white.opacity(0.22)
    static let glassBottom = Color.white.opacity(0.07)

    // Interactive accent — teal/cyan, softened a touch so it reads calm, not neon.
    static let accent = Color(rgbInt: 0x57C3BB)
    static let accentDeep = Color(rgbInt: 0x3FA69E)
    static let teal = Color(rgbInt: 0x57C3BB)
    static let cyan = Color(rgbInt: 0x57C3BB)
    /// Text on accent-filled buttons.
    static let onAccent = Color(rgbInt: 0x06283F)

    // Touch stroke colours (neon).
    static let lime = Color(rgbInt: 0x9FD257)
    static let pink = Color(rgbInt: 0xEC5A89)
    static let magenta = Color(rgbInt: 0xB173DF)
    static let amber = Color(rgbInt: 0xECA94B)
    static let danger = Color(rgbInt: 0xFF6B6B)

    // Touch feed surfaces.
    static let touchSent = Color(rgbInt: 0x00527B)
    static let touchReceived = Color(rgbInt: 0x003F63)

    // Text.
    static let title = Color.white
    static let subtitle = Color(rgbInt: 0xCFE3F2)
    static let mutedHeadline = Color(rgbInt: 0xDDEBF6)

    // A faint HUD grid drawn over the sky for a subtle sci-fi depth.
    static let grid = Color.white.opacity(0.045)

    static let corner: CGFloat = 20
    static let cardCorner: CGFloat = 24

    /// The plain sky, used behind every screen.
    static var background: some View { AeroSky().ignoresSafeArea() }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// The aero sky: navy gradient with soft blooms of teal, violet and pink light that drift
/// slowly, under a faint HUD grid — a quietly futuristic, living backdrop.
struct AeroSky: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    bloom(Theme.accent, 0.34, w * 1.2).position(x: w * 0.15, y: drift ? h * 0.05 : -h * 0.03)
                    bloom(Theme.magenta, 0.26, w * 1.0).position(x: drift ? w * 0.9 : w, y: h * 0.35)
                    bloom(Theme.pink, 0.22, w * 0.9).position(x: drift ? w * 0.06 : 0, y: drift ? h * 0.94 : h)
                }
                .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: drift)
                HUDGrid(spacing: 46)
                    .stroke(Theme.grid, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { drift = true }
    }

    private func bloom(_ color: Color, _ opacity: Double, _ size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), .clear], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
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

/// The frosted glass panel look: blur, a light-to-clear fill, a bright top edge and a soft
/// drop shadow.
struct GlassBackground<S: Shape>: View {
    let shape: S
    /// How see-through the glass is (0 frosted … 1 nearly clear) and how deep its shadow is
    /// (0 none … 1 deep) — the two sliders under Softness.
    @AppStorage("glassClarity") private var clarity = 0.55
    @AppStorage("glassShadow") private var shadowDepth = 0.6

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .opacity(1 - clarity * 0.75)
            .overlay(shape.fill(LinearGradient(colors: [Theme.glassTop, Theme.glassBottom],
                                               startPoint: .top, endPoint: .bottom))
                .opacity(1 - clarity * 0.6))
            // A faint teal rim-light: the panel edge catches the sky's accent, like holo glass.
            .overlay(shape.stroke(LinearGradient(colors: [Theme.accent.opacity(0.35), .clear, Theme.magenta.opacity(0.18)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .blur(radius: 1.5))
            // The crisp bright top edge over it.
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
            // A soft, wide ambient shadow plus a tight contact shadow — it reads as glass
            // floating a little above the sky instead of a grey smudge.
            .shadow(color: Color.black.opacity(0.22 * shadowDepth), radius: 4 + 22 * shadowDepth, y: 4 + 12 * shadowDepth)
            .shadow(color: Color.black.opacity(0.18 * shadowDepth), radius: 2, y: 1 + shadowDepth)
    }
}

extension View {
    /// Wraps a screen in the app's sky background.
    func screenBackground() -> some View {
        ZStack { Theme.background; self }
    }

    /// Frosted glass behind this view, in `shape`.
    func glass<S: Shape>(_ shape: S) -> some View {
        background(GlassBackground(shape: shape))
    }

    /// Frosted glass in a rounded rectangle.
    func glass(cornerRadius: CGFloat = Theme.cardCorner) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A primary (accent) capsule button style — glossy teal with dark text.
struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(17, .heavy))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(
                Capsule().fill(LinearGradient(colors: [Color(rgbInt: 0x74D3CB), Theme.accentDeep],
                                              startPoint: .top, endPoint: .bottom))
                    // A specular sheen across the top third, like light on a glass key.
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                           startPoint: .top, endPoint: .center))
                        .padding(1).mask(Capsule()))
                    .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.45), radius: 14, y: 5)
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: height)
            .glass(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
