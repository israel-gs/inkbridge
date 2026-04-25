import XCTest
@testable import InkBridgeCore

final class CurveRegistryTests: XCTestCase {

    private final class StubStore: CurveStore {
        var defaultCurve: PressureCurve = .linear
        var overrides: [String: PressureCurve] = [:]
        var saveDefaultCallCount = 0
        var saveOverridesCallCount = 0

        func loadDefault() -> PressureCurve { defaultCurve }
        func saveDefault(_ curve: PressureCurve) {
            defaultCurve = curve
            saveDefaultCallCount += 1
        }
        func loadOverrides() -> [String: PressureCurve] { overrides }
        func saveOverrides(_ overrides: [String: PressureCurve]) {
            self.overrides = overrides
            saveOverridesCallCount += 1
        }
    }

    @MainActor
    func test_curveForNilReturnsDefault() {
        let store = StubStore()
        let registry = CurveRegistry(store: store)
        XCTAssertEqual(registry.curve(for: nil), .linear)
    }

    @MainActor
    func test_curveForKnownBundleReturnsOverride() {
        let store = StubStore()
        store.overrides = ["org.kde.krita": .hard]
        let registry = CurveRegistry(store: store)
        XCTAssertEqual(registry.curve(for: "org.kde.krita"), .hard)
    }

    @MainActor
    func test_curveForUnknownBundleReturnsDefault() {
        let store = StubStore()
        store.defaultCurve = .soft
        let registry = CurveRegistry(store: store)
        XCTAssertEqual(registry.curve(for: "com.unknown.app"), .soft)
    }

    @MainActor
    func test_setOverridePersists() {
        let store = StubStore()
        let registry = CurveRegistry(store: store)
        registry.setOverride(.hard, for: "org.kde.krita")
        XCTAssertEqual(store.overrides["org.kde.krita"], .hard)
        XCTAssertEqual(store.saveOverridesCallCount, 1)
    }

    @MainActor
    func test_removeOverridePersists() {
        let store = StubStore()
        store.overrides = ["org.kde.krita": .hard, "com.adobe.Photoshop": .soft]
        let registry = CurveRegistry(store: store)
        registry.removeOverride(for: "org.kde.krita")
        XCTAssertNil(store.overrides["org.kde.krita"])
        XCTAssertEqual(store.overrides["com.adobe.Photoshop"], .soft)
    }

    @MainActor
    func test_setDefaultPersists() {
        let store = StubStore()
        let registry = CurveRegistry(store: store)
        registry.setDefault(.soft)
        XCTAssertEqual(store.defaultCurve, .soft)
        XCTAssertEqual(store.saveDefaultCallCount, 1)
    }

    @MainActor
    func test_initLoadsFromStore() {
        let store = StubStore()
        store.defaultCurve = .hard
        store.overrides = ["org.kde.krita": .soft]
        let registry = CurveRegistry(store: store)
        XCTAssertEqual(registry.curve(for: nil), .hard)
        XCTAssertEqual(registry.curve(for: "org.kde.krita"), .soft)
    }
}
