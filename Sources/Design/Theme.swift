import SwiftUI

/// Visual design tokens for Bond Touch Beyond — a deep-blue, frosted-glass look with
/// teal / lime / pink accents and glowing neon "touch" strokes.
enum Theme {
    // Background gradient (deep navy blue).
    static let bgTop = Color(rgbInt: 0x1E4A6E)
    static let bgBottom = Color(rgbInt: 0x14304A)

    // Card / surface.
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let cardStrong = Color.white.opacity(0.10)

    // Accents.
    static let teal = Color(rgbInt: 0x48D6C8)
    static let lime = Color(rgbInt: 0xAEE63C)
    static let pink = Color(rgbInt: 0xFF2E74)
    static let magenta = Color(rgbInt: 0xE94BD0)

    // Text.
    static let title = Color.white
    static let subtitle = Color.white.opacity(0.65)
    static let mutedHeadline = Color(rgbInt: 0x5C8FBA)

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
