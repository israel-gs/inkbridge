import Foundation

/// Persistence backend for the pressure-curve registry.
///
/// Implementations are responsible for atomicity within their own backend
/// (e.g. `UserDefaults` is atomic per key). The registry calls `save*` after
/// every mutation; there is no batched commit.
public protocol CurveStore: AnyObject {
    func loadDefault() -> PressureCurve
    func saveDefault(_ curve: PressureCurve)
    func loadOverrides() -> [String: PressureCurve]
    func saveOverrides(_ overrides: [String: PressureCurve])
}

/// In-memory pressure curve registry keyed by macOS bundle identifier.
///
/// Lives on the MainActor: the SwiftUI editor reads/writes from the main thread
/// and `CGEventInjector` (also `@MainActor`) reads from the inject hot path.
/// No queue hops, no locks needed.
@MainActor
public final class CurveRegistry {

    private let store: CurveStore
    public private(set) var defaultCurve: PressureCurve
    public private(set) var overrides: [String: PressureCurve]

    public init(store: CurveStore) {
        self.store = store
        self.defaultCurve = store.loadDefault()
        self.overrides = store.loadOverrides()
    }

    /// Resolves the curve to apply for the given app. Falls back to default
    /// when `bundleId` is nil or no override exists.
    public func curve(for bundleId: String?) -> PressureCurve {
        guard let bundleId, let override = overrides[bundleId] else {
            return defaultCurve
        }
        return override
    }

    /// Adds or replaces an override for `bundleId` and persists.
    public func setOverride(_ curve: PressureCurve, for bundleId: String) {
        overrides[bundleId] = curve
        store.saveOverrides(overrides)
    }

    /// Removes the override for `bundleId` (noop if absent) and persists.
    public func removeOverride(for bundleId: String) {
        overrides.removeValue(forKey: bundleId)
        store.saveOverrides(overrides)
    }

    /// Replaces the default curve and persists.
    public func setDefault(_ curve: PressureCurve) {
        defaultCurve = curve
        store.saveDefault(curve)
    }
}

/// `UserDefaults`-backed `CurveStore`. JSON-encoded under stable keys so the
/// payload is human-readable in `defaults read`.
public final class UserDefaultsCurveStore: CurveStore {
    private let defaults: UserDefaults
    private let defaultKey = "signalq.curve.default"
    private let overridesKey = "signalq.curve.overrides"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadDefault() -> PressureCurve {
        guard let data = defaults.data(forKey: defaultKey),
              let curve = try? JSONDecoder().decode(PressureCurve.self, from: data) else {
            return .linear
        }
        return curve
    }

    public func saveDefault(_ curve: PressureCurve) {
        if let data = try? JSONEncoder().encode(curve) {
            defaults.set(data, forKey: defaultKey)
        }
    }

    public func loadOverrides() -> [String: PressureCurve] {
        guard let data = defaults.data(forKey: overridesKey),
              let overrides = try? JSONDecoder().decode([String: PressureCurve].self, from: data) else {
            return [:]
        }
        return overrides
    }

    public func saveOverrides(_ overrides: [String: PressureCurve]) {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: overridesKey)
        }
    }
}
