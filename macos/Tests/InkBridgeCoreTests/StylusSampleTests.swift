import XCTest
@testable import InkBridgeCore

/// Tests for ``StylusSample`` range validation. Phase 3.1.
final class StylusSampleTests: XCTestCase {

    // MARK: - Valid construction

    func testValidSampleDoesNotThrow() throws {
        _ = try StylusSample(x: 0.5, y: 0.5, pressure: 0.5,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
    }

    func testBoundaryValues() throws {
        // All fields at minimum
        _ = try StylusSample(x: 0, y: 0, pressure: 0,
                             tiltX: -9000, tiltY: -9000, hover: false, timestampNs: 0)
        // All fields at maximum
        _ = try StylusSample(x: 1, y: 1, pressure: 1,
                             tiltX: 9000, tiltY: 9000, hover: true, timestampNs: UInt64.max)
    }

    // MARK: - x validation

    func testXBelowZeroThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: -0.01, y: 0.5, pressure: 0,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
        ) { error in
            guard case StylusSampleError.xOutOfRange(let v) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(v, -0.01, accuracy: 0.0001)
        }
    }

    func testXAboveOneThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 1.01, y: 0.5, pressure: 0,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
        ) { error in
            XCTAssertTrue(error is StylusSampleError)
        }
    }

    // MARK: - y validation

    func testYBelowZeroThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: -0.001, pressure: 0,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
        )
    }

    func testYAboveOneThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 1.5, pressure: 0,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
        )
    }

    // MARK: - pressure validation

    func testPressureBelowZeroThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 0.5, pressure: -0.1,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
        ) { error in
            guard case StylusSampleError.pressureOutOfRange = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testPressureAboveOneThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 0.5, pressure: 1.001,
                             tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
        )
    }

    // MARK: - tiltX validation

    func testTiltXBelowMinThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 0.5, pressure: 0,
                             tiltX: -9001, tiltY: 0, hover: false, timestampNs: 0)
        ) { error in
            guard case StylusSampleError.tiltXOutOfRange = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testTiltXAboveMaxThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 0.5, pressure: 0,
                             tiltX: 9001, tiltY: 0, hover: false, timestampNs: 0)
        )
    }

    // MARK: - tiltY validation

    func testTiltYBelowMinThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 0.5, pressure: 0,
                             tiltX: 0, tiltY: -9001, hover: false, timestampNs: 0)
        ) { error in
            guard case StylusSampleError.tiltYOutOfRange = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testTiltYAboveMaxThrows() {
        XCTAssertThrowsError(
            try StylusSample(x: 0.5, y: 0.5, pressure: 0,
                             tiltX: 0, tiltY: 9001, hover: false, timestampNs: 0)
        )
    }
}
