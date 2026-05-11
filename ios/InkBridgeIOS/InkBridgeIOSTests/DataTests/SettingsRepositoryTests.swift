import XCTest
@testable import InkBridgeIOS

final class SettingsRepositoryTests: XCTestCase {

    // MARK: - Suite-isolated UserDefaults

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "test.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        defaults = nil
        super.tearDown()
    }

    private func makeRepo() -> UserDefaultsSettingsRepository {
        UserDefaultsSettingsRepository(defaults: defaults)
    }

    // MARK: - Defaults (no keys present)

    func test_defaults_hostOverride_isEmpty() {
        let repo = makeRepo()
        XCTAssertEqual(repo.hostOverride, "")
    }

    func test_defaults_port_is4545() {
        let repo = makeRepo()
        XCTAssertEqual(repo.port, 4545)
    }

    func test_defaults_hapticIntensity_is50() {
        let repo = makeRepo()
        XCTAssertEqual(repo.hapticIntensity, 50)
    }

    func test_defaults_autoReconnect_isTrue() {
        let repo = makeRepo()
        XCTAssertTrue(repo.autoReconnect)
    }

    func test_defaults_naturalScroll_isTrue() {
        let repo = makeRepo()
        XCTAssertTrue(repo.naturalScroll)
    }

    func test_defaults_sidebarEdge_isTrailing() {
        let repo = makeRepo()
        XCTAssertEqual(repo.sidebarEdge, .trailing)
    }

    func test_defaults_activeProfileId_isEmpty() {
        let repo = makeRepo()
        XCTAssertEqual(repo.activeProfileId, "")
    }

    // MARK: - Round-trip

    func test_roundTrip_hostOverride() {
        let repo = makeRepo()
        repo.hostOverride = "192.168.1.42"
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.hostOverride, "192.168.1.42")
    }

    func test_roundTrip_port() {
        let repo = makeRepo()
        repo.port = 9999
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.port, 9999)
    }

    func test_roundTrip_hapticIntensity() {
        let repo = makeRepo()
        repo.hapticIntensity = 75
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.hapticIntensity, 75)
    }

    func test_roundTrip_hapticIntensity_zero() {
        let repo = makeRepo()
        repo.hapticIntensity = 0
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.hapticIntensity, 0)
    }

    func test_roundTrip_autoReconnect_false() {
        let repo = makeRepo()
        repo.autoReconnect = false
        let repo2 = makeRepo()
        XCTAssertFalse(repo2.autoReconnect)
    }

    /// Migration: legacy Bool `true` (haptics on) → hapticIntensity == 100.
    func test_migration_legacyHapticsTrue_mapsTo100() {
        defaults.set(true, forKey: "inkbridge.settings.haptics")
        let repo = makeRepo()
        XCTAssertEqual(repo.hapticIntensity, 100)
        // Legacy key must be removed after migration.
        XCTAssertNil(defaults.object(forKey: "inkbridge.settings.haptics"))
    }

    /// Migration: legacy Bool `false` (haptics off) → hapticIntensity == 0.
    func test_migration_legacyHapticsFalse_mapsTo0() {
        defaults.set(false, forKey: "inkbridge.settings.haptics")
        let repo = makeRepo()
        XCTAssertEqual(repo.hapticIntensity, 0)
        XCTAssertNil(defaults.object(forKey: "inkbridge.settings.haptics"))
    }

    func test_roundTrip_naturalScroll_false() {
        let repo = makeRepo()
        repo.naturalScroll = false
        let repo2 = makeRepo()
        XCTAssertFalse(repo2.naturalScroll)
    }

    func test_roundTrip_sidebarEdge_leading() {
        let repo = makeRepo()
        repo.sidebarEdge = .leading
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.sidebarEdge, .leading)
    }

    func test_roundTrip_activeProfileId() {
        let repo = makeRepo()
        let id = UUID().uuidString
        repo.activeProfileId = id
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.activeProfileId, id)
    }

    // MARK: - Multiple writes

    func test_overwrite_port_persistsLatestValue() {
        let repo = makeRepo()
        repo.port = 4545
        repo.port = 8080
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.port, 8080)
    }

    func test_overwrite_sidebarEdge_persistsLatestValue() {
        let repo = makeRepo()
        repo.sidebarEdge = .leading
        repo.sidebarEdge = .trailing
        let repo2 = makeRepo()
        XCTAssertEqual(repo2.sidebarEdge, .trailing)
    }
}
