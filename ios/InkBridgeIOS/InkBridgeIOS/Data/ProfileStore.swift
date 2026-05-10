import Foundation
import Observation

// MARK: - StoredProfilesDocument

/// Versioned container for JSON persistence.
/// Schema version 1: flat array of profiles wrapped with a version tag.
private struct StoredProfilesDocument: Codable {
    var version: Int = 1
    var profiles: [ExpressKeyProfile]
}

// MARK: - ProfileStore

/// Persists and loads `[ExpressKeyProfile]` via UserDefaults (JSON-encoded).
///
/// # Fail-closed contract
/// If the stored data is absent, corrupted, or from a future schema version that
/// cannot be decoded, `loadProfiles()` silently returns the built-in default
/// profile rather than throwing. This prevents the app from being stuck in a
/// broken state after an upgrade.
///
/// # Schema versioning
/// Every serialized document includes `"version": 1`. Future versions can
/// perform migrations in `loadProfiles()` before decoding the profiles array.
///
/// # Usage
/// ```swift
/// let store = ProfileStore()
/// var profiles = store.loadProfiles()
/// profiles[0].keys[0].label = "Undo"
/// store.saveProfiles(profiles)
/// ```
@Observable
public final class ProfileStore {

    // MARK: - UserDefaults key (internal so tests can verify the stored JSON directly)

    static let defaultsKey = "inkbridge.profiles"

    // MARK: - Private

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Loads all profiles from UserDefaults.
    /// Returns the built-in default profile if no data is present or decoding fails.
    public func loadProfiles() -> [ExpressKeyProfile] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return [.makeDefault()]
        }
        do {
            let document = try decoder.decode(StoredProfilesDocument.self, from: data)
            return document.profiles
        } catch {
            // Fail-closed: corrupted or incompatible data → built-in default.
            return [.makeDefault()]
        }
    }

    /// Persists the given profiles to UserDefaults.
    public func saveProfiles(_ profiles: [ExpressKeyProfile]) {
        let document = StoredProfilesDocument(version: 1, profiles: profiles)
        guard let data = try? encoder.encode(document) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
