import Foundation
import Observation

// MARK: - SettingsRepository (protocol)

/// Contract for reading and writing user settings.
/// Abstracted so tests and future backends (e.g. CloudKit sync) can substitute.
public protocol SettingsRepository: AnyObject {
    var hostOverride: String { get set }
    var port: UInt16 { get set }
    var haptics: Bool { get set }
    var naturalScroll: Bool { get set }
    var sidebarEdge: SidebarEdge { get set }
    var activeProfileId: String { get set }
}

// MARK: - UserDefaults keys

private enum Keys {
    static let hostOverride   = "inkbridge.settings.hostOverride"
    static let port           = "inkbridge.settings.port"
    static let haptics        = "inkbridge.settings.haptics"
    static let naturalScroll  = "inkbridge.settings.naturalScroll"
    static let sidebarEdge    = "inkbridge.settings.sidebarEdge"
    static let activeProfileId = "inkbridge.settings.activeProfileId"
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

    public var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Keys.haptics) }
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

    // MARK: - Private

    private let defaults: UserDefaults

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load persisted values or fall back to defaults.
        self.hostOverride = defaults.string(forKey: Keys.hostOverride) ?? ""

        let rawPort = defaults.integer(forKey: Keys.port)
        self.port = rawPort > 0 ? UInt16(rawPort) : 4545

        // `bool(forKey:)` returns false when key is absent — but we want `true` as default.
        // Use `object(forKey:)` to distinguish "not set" from "explicitly false".
        if defaults.object(forKey: Keys.haptics) != nil {
            self.haptics = defaults.bool(forKey: Keys.haptics)
        } else {
            self.haptics = true
        }

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
    }
}
