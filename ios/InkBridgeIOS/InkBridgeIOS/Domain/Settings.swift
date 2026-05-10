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
    /// Whether haptic feedback fires on Express Key taps.
    public var haptics: Bool
    /// Reverses scroll direction to match macOS Natural Scroll setting.
    public var naturalScroll: Bool
    /// Which edge of the screen the Express Keys sidebar occupies.
    public var sidebarEdge: SidebarEdge
    /// The UUID string of the active Express Key profile.
    public var activeProfileId: String

    public init(
        hostOverride: String = "",
        port: UInt16 = 4545,
        haptics: Bool = true,
        naturalScroll: Bool = true,
        sidebarEdge: SidebarEdge = .trailing,
        activeProfileId: String = ""
    ) {
        self.hostOverride = hostOverride
        self.port = port
        self.haptics = haptics
        self.naturalScroll = naturalScroll
        self.sidebarEdge = sidebarEdge
        self.activeProfileId = activeProfileId
    }
}
