import Foundation

/// Edge of the screen where the Express Keys sidebar is displayed.
public enum SidebarEdge: String, Codable, Equatable {
    case leading
    case trailing
}

/// All user-facing settings for the InkBridge iOS client.
///
/// Persisted via `SettingsRepository` (UserDefaults). Fields survive app restart
/// and sideload re-signing with the same bundle ID.
public struct Settings: Equatable {
    /// Last-used host IP override (empty means use auto-discovered host).
    public var hostOverride: String
    /// Last-used port.
    public var port: UInt16
    /// Haptic feedback intensity: 0 = off, 1–100 = scaled intensity.
    /// Migrated from legacy Bool field on first load (true → 100, false → 0).
    public var hapticIntensity: Int
    /// Reverses scroll direction to match macOS Natural Scroll setting.
    public var naturalScroll: Bool
    /// Which edge of the screen the Express Keys sidebar occupies.
    public var sidebarEdge: SidebarEdge
    /// The UUID string of the active Express Key profile.
    public var activeProfileId: String
    /// Whether the app auto-reconnects to the last host when foregrounded.
    public var autoReconnect: Bool

    public init(
        hostOverride: String = "",
        port: UInt16 = 4545,
        hapticIntensity: Int = 50,
        naturalScroll: Bool = true,
        sidebarEdge: SidebarEdge = .trailing,
        activeProfileId: String = "",
        autoReconnect: Bool = true
    ) {
        self.hostOverride = hostOverride
        self.port = port
        self.hapticIntensity = hapticIntensity
        self.naturalScroll = naturalScroll
        self.sidebarEdge = sidebarEdge
        self.activeProfileId = activeProfileId
        self.autoReconnect = autoReconnect
    }
}
