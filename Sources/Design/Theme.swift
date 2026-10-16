import SwiftUI

/// Visual design tokens for Bond Touch Beyond, matched to the original app: a medium
/// navy-blue background, a teal/cyan interactive accent, a muted steel-blue headline,
/// and neon lime/pink glowing "touch" strokes.
enum Theme {
    // Background gradient (medium navy blue).
    static let bgTop = Color(rgbInt: 0x1E4A6E)
    static let bgBottom = Color(rgbInt: 0x163A5A)

    // Card / surface (translucent over the navy).
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let cardStrong = Color.white.opacity(0.10)

    // Interactive accent — teal/cyan (tab bar, buttons, avatar rings, icons).
    static let accent = Color(rgbInt: 0x3ED9CE)
    static let teal = Color(rgbInt: 0x3ED9CE)
    static let cyan = Color(rgbInt: 0x3ED9CE)

    // Touch stroke colours (neon).
    static let lime = Color(rgbInt: 0xAEE63C)
    static let pink = Color(rgbInt: 0xFF2E74)
    static let magenta = Color(rgbInt: 0xBE5BFF)
    static let amber = Color(rgbInt: 0xF5A623)
    static let danger = Color(rgbInt: 0xEB4C43)

    // Touch feed surfaces.
    static let touchSent = Color(rgbInt: 0x00527B)
    static let touchReceived = Color(rgbInt: 0x003F63)

    // Text.
    static let title = Color.white
    static let subtitle = Color(rgbInt: 0x8CA7BE)
    /// The big "Hello, this is us" headline — a muted steel-blue, barely lighter than bg.
    static let mutedHeadline = Color(rgbInt: 0x3E6E9E)

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
