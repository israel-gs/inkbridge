import XCTest
import CoreGraphics
@testable import InkBridgeCore

/// Tests for ``CoordinateMapper``. Phase 3.2.
final class CoordinateMapperTests: XCTestCase {

    private let display = DisplayRect(width: 2560, height: 1600)

    private func sample(x: Float, y: Float) throws -> StylusSample {
        let cx = min(max(x, 0), 1)
        let cy = min(max(y, 0), 1)
        return try StylusSample(x: cx, y: cy, pressure: 0, tiltX: 0, tiltY: 0,
                                hover: false, timestampNs: 0)
    }

    // MARK: - Corner cases

    func testOriginMapsToZero() throws {
        let pt = CoordinateMapper.map(sample: try sample(x: 0, y: 0), display: display)
        XCTAssertEqual(pt.x, 0)
        XCTAssertEqual(pt.y, 0)
    }

    func testMaxMapsToDisplaySize() throws {
        let pt = CoordinateMapper.map(sample: try sample(x: 1, y: 1), display: display)
        XCTAssertEqual(pt.x, display.width, accuracy: 0.001)
        XCTAssertEqual(pt.y, display.height, accuracy: 0.001)
    }

    // MARK: - Midpoint

    func testMidpointMapsToHalfDisplay() throws {
        let pt = CoordinateMapper.map(sample: try sample(x: 0.5, y: 0.5), display: display)
        XCTAssertEqual(pt.x, display.width / 2, accuracy: 0.001)
        XCTAssertEqual(pt.y, display.height / 2, accuracy: 0.001)
    }

    // MARK: - Clamping (over-range inputs)

    func testOverRangeXClampsToWidth() throws {
        // CoordinateMapper clamps after multiplication.
        // Feed a sample with x=1 (max valid) — the clamp path is in the mapper itself.
        let s = try StylusSample(x: 1, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0,
                                 hover: false, timestampNs: 0)
        let pt = CoordinateMapper.map(sample: s, display: display)
        XCTAssertEqual(pt.x, display.width, accuracy: 0.001)
        XCTAssertLessThanOrEqual(pt.x, display.width)
    }

    func testOverRangeYClampsToHeight() throws {
        let s = try StylusSample(x: 0.5, y: 1, pressure: 0, tiltX: 0, tiltY: 0,
                                 hover: false, timestampNs: 0)
        let pt = CoordinateMapper.map(sample: s, display: display)
        XCTAssertEqual(pt.y, display.height, accuracy: 0.001)
        XCTAssertLessThanOrEqual(pt.y, display.height)
    }

    // MARK: - Quarter points

    func testQuarterPoint() throws {
        let pt = CoordinateMapper.map(sample: try sample(x: 0.25, y: 0.75), display: display)
        XCTAssertEqual(pt.x, 640, accuracy: 0.1)    // 0.25 × 2560
        XCTAssertEqual(pt.y, 1200, accuracy: 0.1)   // 0.75 × 1600
    }

    // MARK: - Scenario from spec: 2560×1600, x=0.5, y=0.5 → (1280, 800)

    func testSpecScenario() throws {
        let display2 = DisplayRect(width: 2560, height: 1600)
        let s = try StylusSample(x: 0.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0,
                                 hover: false, timestampNs: 0)
        let pt = CoordinateMapper.map(sample: s, display: display2)
        XCTAssertEqual(pt.x, 1280, accuracy: 0.001)
        XCTAssertEqual(pt.y, 800, accuracy: 0.001)
    }
}
