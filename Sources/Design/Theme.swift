import SwiftUI

/// Visual design tokens for Bond Touch Beyond. Palette extracted from the original
/// app's Compose theme (BondColorSchemeKt): a deep navy background with violet and
/// cyan/mint accents, Google Sans type, and the navy touch surfaces used in the feed.
enum Theme {
    // Background gradient (deep navy blue) — original screen palette #00486F→#000F21.
    static let bgTop = Color(rgbInt: 0x00486F)
    static let bgBottom = Color(rgbInt: 0x000F21)

    // Card / surface.
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let cardStrong = Color.white.opacity(0.10)

    // Accents (from BondColorSchemeKt).
    static let accent = Color(rgbInt: 0x7B61FF)   // primary violet
    static let cyan = Color(rgbInt: 0x008EC4)     // secondary blue
    static let teal = Color(rgbInt: 0x3EE1D2)     // mint-teal
    static let lime = Color(rgbInt: 0x00FF9D)     // mint-green
    static let pink = Color(rgbInt: 0xE85D75)
    static let magenta = Color(rgbInt: 0xAA52F4)
    static let amber = Color(rgbInt: 0xF5A623)
    static let danger = Color(rgbInt: 0xEB4C43)

    // Touch feed surfaces (background_touch_view_v3_*).
    static let touchSent = Color(rgbInt: 0x00527B)
    static let touchReceived = Color(rgbInt: 0x003F63)

    // Text.
    static let title = Color(rgbInt: 0xFEFEFF)
    static let subtitle = Color(rgbInt: 0x868D99)
    static let mutedHeadline = Color(rgbInt: 0x7594A6)

    static let corner: CGFloat = 20
    static let cardCorner: CGFloat = 22

    /// Full-screen background used by every screen.
    static var background: some View {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// Wraps a screen in the app's gradient background.
    func screenBackground() -> some View {
        ZStack { Theme.background; self }
    }
}
