import XCTest
@testable import InkBridgeCore

/// Characterization tests for ``CGEventInjector.momentumDeltas(_:_:maxFrames:)``.
///
/// This is a pure static function — no CGEvents, no Tasks, no side effects.
/// All tests verify the documented contract in the source-level comment:
/// - Below threshold (absMag < 10) → empty.
/// - Above threshold → at least 1 delta.
/// - Each successive |delta| < previous |delta| (decay toward zero).
/// - Terminates within maxFrames.
/// - Negative initial deltas decay toward 0 from the negative side.
/// - Pure-axis cases (one axis zero).
/// - Both axes nonzero — both decay together.
@available(macOS 13, *)
final class MomentumDeltasTests: XCTestCase {

    // MARK: - Threshold

    func testBelowThresholdReturnsEmpty_zeroDelta() {
        // absMag = 0 < 10 → empty
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 0, initialDeltaY: 0)
        XCTAssertTrue(result.isEmpty, "Zero delta must return empty (absMag=0 < 10)")
    }

    func testBelowThresholdReturnsEmpty_absMagNine() {
        // absMag = |4| + |5| = 9 < 10 → empty
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 4, initialDeltaY: 5)
        XCTAssertTrue(result.isEmpty, "absMag=9 must return empty (< threshold 10)")
    }

    func testBelowThresholdReturnsEmpty_absMagExactlyNine() {
        // absMag = 9 + 0 = 9 → empty
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 9, initialDeltaY: 0)
        XCTAssertTrue(result.isEmpty, "absMag exactly 9 is below threshold 10")
    }

    func testAtThresholdReturnsAtLeastOne() {
        // absMag = 10 → at least 1 delta (the began frame)
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 10, initialDeltaY: 0)
        XCTAssertFalse(result.isEmpty, "absMag=10 should produce at least the began frame")
    }

    func testAboveThresholdReturnsAtLeastOneDelta() {
        // absMag = 30 + 20 = 50 → several decay frames
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 30, initialDeltaY: 20)
        XCTAssertGreaterThanOrEqual(result.count, 1, "Must produce at least 1 delta above threshold")
    }

    // MARK: - Decay

    func testDecayIsMonotonicallyDecreasing_positiveX() {
        // Each successive |dx| must be ≤ previous |dx| (decaying toward 0).
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 100, initialDeltaY: 0)
        XCTAssertFalse(result.isEmpty)
        for i in 1..<result.count {
            let prev = abs(Int(result[i-1].0))
            let curr = abs(Int(result[i].0))
            XCTAssertLessThanOrEqual(curr, prev,
                "Frame \(i): |dx|=\(curr) should be ≤ previous |dx|=\(prev)")
        }
    }

    func testDecayIsMonotonicallyDecreasing_positiveY() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 0, initialDeltaY: 80)
        XCTAssertFalse(result.isEmpty)
        for i in 1..<result.count {
            let prev = abs(Int(result[i-1].1))
            let curr = abs(Int(result[i].1))
            XCTAssertLessThanOrEqual(curr, prev,
                "Frame \(i): |dy|=\(curr) should be ≤ previous |dy|=\(prev)")
        }
    }

    func testDecayIsMonotonicallyDecreasing_bothAxes() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 60, initialDeltaY: 40)
        XCTAssertFalse(result.isEmpty)
        for i in 1..<result.count {
            let prevMag = abs(Int(result[i-1].0)) + abs(Int(result[i-1].1))
            let currMag = abs(Int(result[i].0)) + abs(Int(result[i].1))
            XCTAssertLessThanOrEqual(currMag, prevMag,
                "Frame \(i): combined magnitude should not increase")
        }
    }

    // MARK: - maxFrames bound

    func testTerminatesWithinMaxFrames_defaultBound() {
        // With large initial deltas and default maxFrames=80, count must be ≤ 81
        // (1 began frame + up to 80 decay frames).
        let result = CGEventInjector.momentumDeltas(initialDeltaX: Int16.max, initialDeltaY: Int16.max)
        XCTAssertLessThanOrEqual(result.count, 81, "Result must not exceed maxFrames+1 (began + maxFrames)")
    }

    func testTerminatesWithinMaxFrames_customBound() {
        let maxFrames = 5
        let result = CGEventInjector.momentumDeltas(
            initialDeltaX: Int16.max,
            initialDeltaY: Int16.max,
            maxFrames: maxFrames
        )
        // 1 began frame + at most maxFrames decay frames = maxFrames+1 total
        XCTAssertLessThanOrEqual(result.count, maxFrames + 1,
            "Must not exceed maxFrames+1 when custom maxFrames=\(maxFrames) is passed")
    }

    func testTerminatesEarlyWhenBelowHalfPixel() {
        // A small but above-threshold initial velocity should decay to < 0.5 px
        // well before 80 frames, so count should be much less than 81.
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 10, initialDeltaY: 0)
        // With 0.93 decay per frame: 10 * 0.93^n < 0.5 → n ≈ 42. Definitely < 81.
        XCTAssertLessThan(result.count, 81, "Small initial velocity should decay early")
    }

    // MARK: - Negative initial deltas

    func testNegativeInitialDeltaX_decaysTowardZero() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: -50, initialDeltaY: 0)
        XCTAssertFalse(result.isEmpty)
        // All dx values should be negative (decay stays on the negative side until clamped to 0).
        // The last frame before termination may be 0 due to rounding, but none should flip positive.
        for (i, frame) in result.enumerated() {
            XCTAssertLessThanOrEqual(frame.0, 0,
                "Frame \(i): negative initial dx should not flip positive; got \(frame.0)")
        }
    }

    func testNegativeInitialDeltaY_decaysTowardZero() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 0, initialDeltaY: -60)
        XCTAssertFalse(result.isEmpty)
        for (i, frame) in result.enumerated() {
            XCTAssertLessThanOrEqual(frame.1, 0,
                "Frame \(i): negative initial dy should not flip positive; got \(frame.1)")
        }
    }

    // MARK: - Pure-axis cases

    func testPureXAxis_yIsZeroThroughout() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 50, initialDeltaY: 0)
        XCTAssertFalse(result.isEmpty)
        for (i, frame) in result.enumerated() {
            XCTAssertEqual(frame.1, 0, "Pure X axis: dy must be 0 at every frame, was \(frame.1) at frame \(i)")
        }
    }

    func testPureYAxis_xIsZeroThroughout() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 0, initialDeltaY: 50)
        XCTAssertFalse(result.isEmpty)
        for (i, frame) in result.enumerated() {
            XCTAssertEqual(frame.0, 0, "Pure Y axis: dx must be 0 at every frame, was \(frame.0) at frame \(i)")
        }
    }

    // MARK: - Both axes nonzero

    func testBothAxesNonzero_firstFrameMatchesInitialRounded() {
        let dx: Int16 = 30
        let dy: Int16 = -20
        let result = CGEventInjector.momentumDeltas(initialDeltaX: dx, initialDeltaY: dy)
        XCTAssertFalse(result.isEmpty)
        // The began frame (index 0) is the initial delta rounded to Int16.
        XCTAssertEqual(result[0].0, dx, "Began frame dx must equal initial (no decay yet)")
        XCTAssertEqual(result[0].1, dy, "Began frame dy must equal initial (no decay yet)")
    }

    func testBothAxesNonzero_bothDecayTogether() {
        let result = CGEventInjector.momentumDeltas(initialDeltaX: 40, initialDeltaY: -30)
        XCTAssertFalse(result.isEmpty)
        // Both axes should show decay (magnitude reduction) from frame 0 to the last frame.
        let firstMagX = abs(Int(result.first!.0))
        let lastMagX  = abs(Int(result.last!.0))
        let firstMagY = abs(Int(result.first!.1))
        let lastMagY  = abs(Int(result.last!.1))
        XCTAssertGreaterThanOrEqual(firstMagX, lastMagX, "X should decay over time")
        XCTAssertGreaterThanOrEqual(firstMagY, lastMagY, "Y should decay over time")
    }
}
