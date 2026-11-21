import Foundation

/// Resolves the effective theme from an optional light/dark pair
/// (`theme_light` / `theme_dark`) and the current system appearance.
/// Pure so the pairing rules unit-test without AppKit.
enum ThemePair {
    /// Rules: a set side wins for its own appearance; any unset side (both
    /// keys unset, or the side matching the current appearance) falls back
    /// to the base `theme`, so a pair may cover just one appearance.
    static func effectiveName(
        theme: String,
        light: String?,
        dark: String?,
        isDarkAppearance: Bool
    ) -> String {
        let matchingSide = isDarkAppearance ? dark : light
        return matchingSide ?? theme
    }
}
