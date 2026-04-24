import XCTest
@testable import InkBridgeCore

/// Placeholder test suite. Proves the XCTest runner is wired correctly.
/// Replace / extend with codec and domain tests during Phase 1.
final class InkBridgeCoreTests: XCTestCase {

    func testRunnerIsConfiguredCorrectly() {
        // Trivial assertion — the test runner works if we reach this line.
        XCTAssertEqual(InkBridgeCore.version, "0.0.0-foundation")
    }
}
