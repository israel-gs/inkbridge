import XCTest
@testable import InkBridgeCore

/// Tests for ``LatencyTracker``.
///
/// All clocks are faked — no real sockets, no CGEventPost, no DispatchTime.
final class LatencyTrackerTests: XCTestCase {

    // MARK: - Empty snapshot

    func testSnapshotOnEmptyTrackerReturnsZero() {
        let tracker = LatencyTracker()
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.samples, 0)
        XCTAssertEqual(snap.arrivalToInjectP50Ms, 0)
        XCTAssertEqual(snap.arrivalToInjectMeanMs, 0)
    }

    // MARK: - Single sample

    func testSingleSampleArrivalToInjectIsAccurate() {
        var tracker = LatencyTracker()
        // wire=0, arrival=1ms, inject=2ms
        tracker.record(wireNs: 0, arrivalNs: 1_000_000, injectNs: 2_000_000)
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.samples, 1)
        // arrivalToInject = inject - arrival = 1ms
        XCTAssertEqual(snap.arrivalToInjectP50Ms, 1.0, accuracy: 0.001)
        XCTAssertEqual(snap.arrivalToInjectP95Ms, 1.0, accuracy: 0.001)
        XCTAssertEqual(snap.arrivalToInjectP99Ms, 1.0, accuracy: 0.001)
        XCTAssertEqual(snap.arrivalToInjectMeanMs, 1.0, accuracy: 0.001)
    }

    func testSingleSampleWireToArrivalReflectsDiff() {
        var tracker = LatencyTracker()
        // wireNs uses Int64 signed arithmetic to handle cross-device skew
        tracker.record(wireNs: 0, arrivalNs: 5_000_000, injectNs: 6_000_000)
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.wireToArrivalP50Ms, 5.0, accuracy: 0.001)
    }

    func testSingleSampleTotalIsWireToInject() {
        var tracker = LatencyTracker()
        tracker.record(wireNs: 0, arrivalNs: 3_000_000, injectNs: 7_000_000)
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.totalP50Ms, 7.0, accuracy: 0.001)
    }

    // MARK: - Percentile correctness

    func testP50P95P99WithKnownDataSet() {
        var tracker = LatencyTracker()
        // Inject 100 samples with arrivalToInject = 1ms, 2ms, …, 100ms
        for i in 1...100 {
            let arrival: UInt64 = 0
            let inject = UInt64(i) * 1_000_000
            tracker.record(wireNs: 0, arrivalNs: arrival, injectNs: inject)
        }
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.samples, 100)
        // With 100 samples, p50 ≈ index 49 → 50ms, p95 ≈ index 94 → 95ms, p99 ≈ index 98 → 99ms
        XCTAssertEqual(snap.arrivalToInjectP50Ms, 50.0, accuracy: 1.5)
        XCTAssertEqual(snap.arrivalToInjectP95Ms, 95.0, accuracy: 1.5)
        XCTAssertEqual(snap.arrivalToInjectP99Ms, 99.0, accuracy: 1.5)
    }

    func testMeanIsCorrect() {
        var tracker = LatencyTracker()
        // 4 samples: 1ms, 2ms, 3ms, 4ms → mean = 2.5ms
        for i in 1...4 {
            tracker.record(wireNs: 0, arrivalNs: 0, injectNs: UInt64(i) * 1_000_000)
        }
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.arrivalToInjectMeanMs, 2.5, accuracy: 0.001)
    }

    // MARK: - Ring buffer wrap

    func testRingBufferEvictsOldestSamples() {
        var tracker = LatencyTracker()
        // Fill past capacity (256) with 1ms samples.
        for _ in 0..<LatencyTracker.capacity {
            tracker.record(wireNs: 0, arrivalNs: 0, injectNs: 1_000_000)
        }
        // Sample count must not exceed capacity.
        XCTAssertEqual(tracker.snapshot().samples, LatencyTracker.capacity)

        // Add one more sample (999ms) — oldest slot evicted.
        tracker.record(wireNs: 0, arrivalNs: 0, injectNs: 999_000_000)

        let snap = tracker.snapshot()
        // Buffer must still be exactly at capacity after the overwrite.
        XCTAssertEqual(snap.samples, LatencyTracker.capacity)
        // p50 should still be 1ms (majority of buffer unchanged).
        XCTAssertEqual(snap.arrivalToInjectP50Ms, 1.0, accuracy: 0.01)
        // The outlier shifts the mean above 1ms (mean > 1ms + epsilon because one slot is 999ms).
        XCTAssertGreaterThan(snap.arrivalToInjectMeanMs, 1.0)
    }

    func testSampleCountClampsAtCapacity() {
        var tracker = LatencyTracker()
        for i in 0..<(LatencyTracker.capacity + 50) {
            tracker.record(wireNs: 0, arrivalNs: 0, injectNs: UInt64(i) * 1_000_000)
        }
        XCTAssertEqual(tracker.snapshot().samples, LatencyTracker.capacity)
    }

    // MARK: - Reset

    func testResetClearsAllSamples() {
        var tracker = LatencyTracker()
        tracker.record(wireNs: 0, arrivalNs: 0, injectNs: 5_000_000)
        tracker.reset()
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.samples, 0)
        XCTAssertEqual(snap.arrivalToInjectP50Ms, 0)
    }

    // MARK: - Signed delta (skew tolerance)

    func testRecordHandlesArrivalBeforeWire() {
        // Simulates extreme clock skew where wireNs > arrivalNs (impossible physically
        // but can happen due to cross-device clock drift). Must not crash.
        var tracker = LatencyTracker()
        tracker.record(wireNs: 10_000_000, arrivalNs: 5_000_000, injectNs: 6_000_000)
        let snap = tracker.snapshot()
        XCTAssertEqual(snap.samples, 1)
        // arrivalToInject is always positive: inject (6ms) − arrival (5ms) = 1ms
        XCTAssertEqual(snap.arrivalToInjectP50Ms, 1.0, accuracy: 0.001)
        // wireToArrival is negative here: arrival (5ms) − wire (10ms) = −5ms
        XCTAssertLessThan(snap.wireToArrivalP50Ms, 0)
    }
}
