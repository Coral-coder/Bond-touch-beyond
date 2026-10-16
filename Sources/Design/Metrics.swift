import CoreGraphics

/// Layout metrics taken from the original app's readable resource dimensions
/// (res/values/dimens.xml). The Compose layout code itself is obfuscated, so these XML
/// dimensions and the reference screenshots are the authoritative layout sources.
enum Metric {
    /// `button_height`
    static let buttonHeight: CGFloat = 50
    /// `button_horizontal_margin` / `button_bottom_margin`
    static let buttonMargin: CGFloat = 24
    /// `main_margin_horizontal` (onboarding side margin)
    static let onboardingMargin: CGFloat = 40
    /// `dashboard_profile_connection_status_font_size`
    static let connectionStatusFont: CGFloat = 12
    /// `gmp_sys_shape_corner_medium_corner_size`
    static let cornerMedium: CGFloat = 16
    /// `gmp_sys_shape_corner_extra_large_corner_size`
    static let cornerLarge: CGFloat = 28
    /// `fingerprint_icon_size` (Private Space unlock)
    static let unlockIcon: CGFloat = 64
}
