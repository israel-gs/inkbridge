import Foundation
import Observation

// MARK: - SettingsRepository (protocol)

/// Contract for reading and writing user settings.
/// Abstracted so tests and future backends (e.g. CloudKit sync) can substitute.
public protocol SettingsRepository: AnyObject {
    var hostOverride: String { get set }
    var port: UInt16 { get set }
    /// Haptic feedback intensity: 0 = off, 1–100 = scaled intensity.
    var hapticIntensity: Int { get set }
    var naturalScroll: Bool { get set }
    var sidebarEdge: SidebarEdge { get set }
    var activeProfileId: String { get set }
    /// Whether the app auto-reconnects to the last host when foregrounded.
    var autoReconnect: Bool { get set }
}

// MARK: - UserDefaults keys

private enum Keys {
    static let hostOverride    = "inkbridge.settings.hostOverride"
    static let port            = "inkbridge.settings.port"
    /// Legacy Bool key — read once to migrate to `hapticIntensity`, then removed.
    static let hapticsLegacy   = "inkbridge.settings.haptics"
    static let hapticIntensity = "inkbridge.settings.hapticIntensity"
    static let naturalScroll   = "inkbridge.settings.naturalScroll"
    static let sidebarEdge     = "inkbridge.settings.sidebarEdge"
    static let activeProfileId = "inkbridge.settings.activeProfileId"
    static let autoReconnect   = "inkbridge.settings.autoReconnect"
}

// MARK: - UserDefaultsSettingsRepository

/// `@Observable` concrete implementation backed by `UserDefaults`.
///
/// Each property reads and writes its own dedicated key. Values are
/// initialized from UserDefaults (or sensible defaults if absent) when
/// the repository is instantiated.
///
/// `@Observable` makes SwiftUI views automatically re-render when any
/// property changes without requiring manual `objectWillChange.send()` calls.
@Observable
public final class UserDefaultsSettingsRepository: SettingsRepository {

    // MARK: - Properties

    public var hostOverride: String {
        didSet { defaults.set(hostOverride, forKey: Keys.hostOverride) }
    }

    public var port: UInt16 {
        didSet { defaults.set(Int(port), forKey: Keys.port) }
    }

    public var hapticIntensity: Int {
        didSet { defaults.set(hapticIntensity, forKey: Keys.hapticIntensity) }
    }

    public var naturalScroll: Bool {
        didSet { defaults.set(naturalScroll, forKey: Keys.naturalScroll) }
    }

    public var sidebarEdge: SidebarEdge {
        didSet { defaults.set(sidebarEdge.rawValue, forKey: Keys.sidebarEdge) }
    }

    public var activeProfileId: String {
        didSet { defaults.set(activeProfileId, forKey: Keys.activeProfileId) }
    }

    public var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) }
    }

    // MARK: - Private

    private let defaults: UserDefaults

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load persisted values or fall back to defaults.
        self.hostOverride = defaults.string(forKey: Keys.hostOverride) ?? ""

        let rawPort = defaults.integer(forKey: Keys.port)
        self.port = rawPort > 0 ? UInt16(rawPort) : 4545

        // Haptic intensity — migrates the legacy Bool key if present.
        // Legacy true → 100, legacy false → 0. New key wins if it already exists.
        if defaults.object(forKey: Keys.hapticIntensity) != nil {
            let raw = defaults.integer(forKey: Keys.hapticIntensity)
            self.hapticIntensity = max(0, min(100, raw))
        } else if defaults.object(forKey: Keys.hapticsLegacy) != nil {
            // First launch after migration: convert Bool → Int and clean up legacy key.
            let legacyBool = defaults.bool(forKey: Keys.hapticsLegacy)
            let migratedValue = legacyBool ? 100 : 0
            self.hapticIntensity = migratedValue
            defaults.removeObject(forKey: Keys.hapticsLegacy)
            defaults.set(migratedValue, forKey: Keys.hapticIntensity)
        } else {
            self.hapticIntensity = 50 // default: mid-level
        }

        // `bool(forKey:)` returns false when key is absent — but we want `true` as default.
        // Use `object(forKey:)` to distinguish "not set" from "explicitly false".
        if defaults.object(forKey: Keys.naturalScroll) != nil {
            self.naturalScroll = defaults.bool(forKey: Keys.naturalScroll)
        } else {
            self.naturalScroll = true
        }

        if let rawEdge = defaults.string(forKey: Keys.sidebarEdge),
           let edge = SidebarEdge(rawValue: rawEdge) {
            self.sidebarEdge = edge
        } else {
            self.sidebarEdge = .trailing
        }

        self.activeProfileId = defaults.string(forKey: Keys.activeProfileId) ?? ""

        if defaults.object(forKey: Keys.autoReconnect) != nil {
            self.autoReconnect = defaults.bool(forKey: Keys.autoReconnect)
        } else {
            self.autoReconnect = true
        }
    }
}
