import XCTest
@testable import InkBridgeCore

@MainActor
final class FrontmostAppDetectorTests: XCTestCase {

    func test_initialBundleIdMatchesProvider() {
        var current: String? = "org.kde.krita"
        let detector = FrontmostAppDetector(provider: { current })
        XCTAssertEqual(detector.currentBundleId, "org.kde.krita")
        // Subsequent reads do not call provider — value is cached.
        current = "com.something.else"
        XCTAssertEqual(detector.currentBundleId, "org.kde.krita")
    }

    func test_refreshUpdatesCachedValue() {
        var current: String? = "org.kde.krita"
        let detector = FrontmostAppDetector(provider: { current })
        XCTAssertEqual(detector.currentBundleId, "org.kde.krita")
        current = "com.adobe.Photoshop"
        detector.refresh()
        XCTAssertEqual(detector.currentBundleId, "com.adobe.Photoshop")
    }

    func test_nilProviderResultIsHandled() {
        let detector = FrontmostAppDetector(provider: { nil })
        XCTAssertNil(detector.currentBundleId)
    }
}
