import XCTest
import CoreGraphics
@testable import InkBridgeCore

/// Tests for ``MockInjector`` behaviour and the Injector protocol contract.
/// Verifies that decoded frames feed correctly through CoordinateMapper + MockInjector.
/// Phase 3.3.
final class MockInjectorTests: XCTestCase {

    private let display = DisplayRect(width: 1920, height: 1080)
    private var injector: MockInjector!

    override func setUp() {
        super.setUp()
        injector = MockInjector()
    }

    // MARK: - Basic recording

    func testInjectMoveIsRecorded() throws {
        let event = StylusEvent.move(x: 0.5, y: 0.5, pressure: 32767, tiltX: 0, tiltY: 0)
        let point = CGPoint(x: 960, y: 540)
        try injector.inject(event, at: point)
        XCTAssertEqual(injector.calls.count, 1)
        XCTAssertEqual(injector.calls[0].0, event)
        XCTAssertEqual(injector.calls[0].1, point)
    }

    func testInjectProximityIsRecorded() throws {
        let event = StylusEvent.proximity(entering: true)
        try injector.inject(event, at: .zero)
        XCTAssertEqual(injector.calls.count, 1)
        XCTAssertEqual(injector.calls[0].0, event)
    }

    func testInjectButtonIsRecorded() throws {
        let event = StylusEvent.button(buttons: 0x08)
        try injector.inject(event, at: .zero)
        XCTAssertEqual(injector.calls.count, 1)
        XCTAssertEqual(injector.calls[0].0, event)
    }

    func testMultipleCallsAccumulate() throws {
        try injector.inject(.proximity(entering: true), at: .zero)
        try injector.inject(.move(x: 0.1, y: 0.2, pressure: 0, tiltX: 0, tiltY: 0), at: CGPoint(x: 1, y: 2))
        try injector.inject(.proximity(entering: false), at: .zero)
        XCTAssertEqual(injector.calls.count, 3)
    }

    // MARK: - Error injection

    func testNextErrorIsThrown() throws {
        injector.nextError = .notTrusted
        XCTAssertThrowsError(try injector.inject(.proximity(entering: true), at: .zero)) { error in
            XCTAssertEqual(error as? InjectorError, .notTrusted)
        }
        // After the error, next call succeeds.
        XCTAssertNoThrow(try injector.inject(.proximity(entering: false), at: .zero))
    }

    // MARK: - Reset

    func testResetClearsCalls() throws {
        try injector.inject(.proximity(entering: true), at: .zero)
        injector.reset()
        XCTAssertTrue(injector.calls.isEmpty)
    }

    // MARK: - Integration: decoded frame → CoordinateMapper → MockInjector

    func testDecodedMoveFrameFeedsCorrectPoint() throws {
        // Build a frame with x=0.5, y=0.5 on a 1920×1080 display.
        let frameData = try BinaryStylusCodec.encode(
            .move(x: 0.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0),
            flags: 0x00,
            sequence: 1,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(frameData)

        // Map coordinates.
        let sample = try StylusSample(x: 0.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0,
                                      hover: false, timestampNs: 0)
        let point = CoordinateMapper.map(sample: sample, display: display)

        try injector.inject(frame.event, at: point)

        XCTAssertEqual(injector.calls.count, 1)
        XCTAssertEqual(injector.calls[0].1.x, 960, accuracy: 0.001)
        XCTAssertEqual(injector.calls[0].1.y, 540, accuracy: 0.001)
    }
}
