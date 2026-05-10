import XCTest
@testable import InkBridgeIOS

final class SequenceCounterTests: XCTestCase {

    // ─────────────────────────────────────────────────────────────────────────
    // B.5 Monotonicity
    // ─────────────────────────────────────────────────────────────────────────

    /// Each call to next() must return a value strictly greater than the previous one
    /// (until wrap). A fresh counter starts at 0.
    func test_sequentialCallsAreMonotonic() async {
        let counter = SequenceCounter()
        let v0 = await counter.next()
        let v1 = await counter.next()
        let v2 = await counter.next()
        XCTAssertEqual(v0, 0)
        XCTAssertEqual(v1, 1)
        XCTAssertEqual(v2, 2)
    }

    /// After UINT32_MAX, the next value wraps to 0.
    func test_wrapsAtUInt32Max() async {
        let counter = SequenceCounter(initialValue: UInt32.max)
        let atMax = await counter.next()
        let wrapped = await counter.next()
        XCTAssertEqual(atMax, UInt32.max)
        XCTAssertEqual(wrapped, 0, "Counter must wrap to 0 after UInt32.max")
    }

    /// Values 1 before max, then max, then wrap to 0.
    func test_wrapsCorrectlyNearBoundary() async {
        let counter = SequenceCounter(initialValue: UInt32.max - 1)
        let v0 = await counter.next()
        let v1 = await counter.next()
        let v2 = await counter.next()
        XCTAssertEqual(v0, UInt32.max - 1)
        XCTAssertEqual(v1, UInt32.max)
        XCTAssertEqual(v2, 0)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B.5 Thread-safety (100 concurrent calls produce 100 unique values)
    // ─────────────────────────────────────────────────────────────────────────

    func test_concurrentCallsProduceUniqueValues() async {
        let counter = SequenceCounter()
        let iterationCount = 100

        // Fire 100 concurrent tasks each calling next() once.
        let values: [UInt32] = await withTaskGroup(of: UInt32.self) { group in
            for _ in 0..<iterationCount {
                group.addTask { await counter.next() }
            }
            var results = [UInt32]()
            for await v in group {
                results.append(v)
            }
            return results
        }

        let unique = Set(values)
        XCTAssertEqual(unique.count, iterationCount,
            "Expected \(iterationCount) unique sequence numbers, got \(unique.count). Duplicates detected — thread safety issue.")
    }

    /// Verify that after 100 concurrent increments the counter stands at 100.
    func test_counterValueAfterConcurrentIncrements() async {
        let counter = SequenceCounter()
        let n = 100

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<n {
                group.addTask { _ = await counter.next() }
            }
        }

        // The next value should be exactly n.
        let next = await counter.next()
        XCTAssertEqual(next, UInt32(n))
    }
}
