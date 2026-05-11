import SwiftUI

// MARK: - InkBridge Design-System Colors
//
// Source of truth: Android client color definitions.
// • inkAccent   — #22D3EE  (connected-state cyan, matches Android Color(0xFF22D3EE))
// • inkBlack    — #0A0A0A  (OLED-friendly background, matches Android #0A0A0A)
// • inkDotBright— #3F3F3F  (dot grid when connected, matches Android #3F3F3F)
// • inkDotDim   — #262626  (dot grid when disconnected, matches Android #262626)

public extension Color {
    /// Connected-state cyan accent. Android: `Color(0xFF22D3EE)`.
    static let inkAccent = Color(red: 0x22 / 255.0, green: 0xD3 / 255.0, blue: 0xEE / 255.0)

    /// OLED-friendly near-black background. Android: `#0A0A0A`.
    static let inkBlack = Color(white: 0x0A / 255.0)

    /// Dot-grid color when connected. Android: `#3F3F3F`.
    static let inkDotBright = Color(white: 0x3F / 255.0)

    /// Dot-grid color when disconnected. Android: `#262626`.
    static let inkDotDim = Color(white: 0x26 / 255.0)
}
