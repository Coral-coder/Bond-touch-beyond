import SwiftUI
import UIKit

extension Color {
    /// Builds a colour from a 0xRRGGBB integer.
    init(rgbInt: Int) {
        self.init(
            red: Double((rgbInt >> 16) & 0xFF) / 255.0,
            green: Double((rgbInt >> 8) & 0xFF) / 255.0,
            blue: Double(rgbInt & 0xFF) / 255.0
        )
    }

    /// Packs the colour into a 0xRRGGBB integer (falls back to pink if unresolvable).
    var rgbInt: Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0xFF4081 }
        return (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }
}
