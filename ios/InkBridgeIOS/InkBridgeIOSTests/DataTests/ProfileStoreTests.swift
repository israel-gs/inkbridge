import XCTest
@testable import InkBridgeIOS

final class ProfileStoreTests: XCTestCase {

    // MARK: - Suite-isolated UserDefaults

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Fresh suite per test — completely isolated from app's real UserDefaults.
        let suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore() -> ProfileStore {
        ProfileStore(defaults: defaults)
    }

    private func makeProfile(name: String = "Test") -> ExpressKeyProfile {
        let keys = (0 ..< expressKeyCount).map { i in
            ExpressKey(
                label: "Key \(i)",
                keyCode: UInt8(i + 1),
                modifiers: ExpressKeyModifiers.cmd,
                holdMode: .oneShot
            )
        }
        return ExpressKeyProfile(name: name, keys: keys)
    }

    // MARK: - Round-trip

    func test_roundTrip_saveAndLoad_returnsEqualProfiles() throws {
        let store = makeStore()
        let profiles = [makeProfile(name: "Alpha"), makeProfile(name: "Beta")]

        store.saveProfiles(profiles)
        let loaded = store.loadProfiles()

        XCTAssertEqual(loaded, profiles)
    }

    func test_roundTrip_multipleProfiles_preservesOrder() {
        let store = makeStore()
        let profiles = (0..<4).map { makeProfile(name: "Profile \($0)") }

        store.saveProfiles(profiles)
        let loaded = store.loadProfiles()

        XCTAssertEqual(loaded.count, 4)
        for (i, profile) in profiles.enumerated() {
            XCTAssertEqual(loaded[i].id, profile.id)
            XCTAssertEqual(loaded[i].name, profile.name)
        }
    }

    // MARK: - Empty defaults

    func test_emptyDefaults_load_returnsBuiltInDefault() {
        let store = makeStore()
        // Nothing saved → should return the built-in default profile
        let loaded = store.loadProfiles()

        XCTAssertEqual(loaded.count, 1, "Should return exactly one default profile")
        XCTAssertEqual(loaded[0].keys.count, expressKeyCount)
    }

    // MARK: - Corrupted blob

    func test_corruptedBlob_load_returnsBuiltInDefault() {
        let store = makeStore()
        // Write garbage bytes directly to the UserDefaults key
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: ProfileStore.defaultsKey)

        let loaded = store.loadProfiles()

        XCTAssertEqual(loaded.count, 1, "Corrupted data should fall back to built-in default")
        XCTAssertEqual(loaded[0].name, "Default")
    }

    func test_malformedJSON_load_returnsBuiltInDefault() {
        let store = makeStore()
        let badJSON = "{\"version\": 1, \"profiles\": \"not-an-array\"}"
        defaults.set(Data(badJSON.utf8), forKey: ProfileStore.defaultsKey)

        let loaded = store.loadProfiles()

        XCTAssertEqual(loaded.count, 1, "Malformed JSON should fall back to built-in default")
    }

    // MARK: - Schema versioning

    func test_savedJSON_containsVersionField() throws {
        let store = makeStore()
        store.saveProfiles([makeProfile()])

        guard let data = defaults.data(forKey: ProfileStore.defaultsKey) else {
            XCTFail("No data found in UserDefaults after save")
            return
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = json?["version"] as? Int

        XCTAssertEqual(version, 1, "Serialized JSON must include \"version\": 1")
    }

    // MARK: - Overwrite

    func test_save_overwritesPreviousProfiles() {
        let store = makeStore()

        store.saveProfiles([makeProfile(name: "First")])
        store.saveProfiles([makeProfile(name: "Second"), makeProfile(name: "Third")])

        let loaded = store.loadProfiles()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Second")
        XCTAssertEqual(loaded[1].name, "Third")
    }
}
