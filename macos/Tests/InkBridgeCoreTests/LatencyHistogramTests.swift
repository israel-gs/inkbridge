import XCTest
@testable import InkBridgeCore

final class LatencyHistogramTests: XCTestCase {

    func test_emptyInputReturnsZeroBins() {
        let bins = latencyHistogram(samples: [], buckets: 12)
        XCTAssertEqual(bins.count, 12)
        XCTAssertTrue(bins.allSatisfy { $0.count == 0 })
    }

    func test_uniformInputConcentratesInOneBin() {
        let bins = latencyHistogram(samples: [1, 1, 1, 1], buckets: 4)
        let counts = bins.map(\.count)
        XCTAssertEqual(counts.reduce(0, +), 4)
        XCTAssertEqual(counts.filter { $0 > 0 }.count, 1)
    }

    func test_binCountSumEqualsSampleCount() {
        let samples: [Double] = [0.5, 1.2, 3.7, 4.1, 5.0, 6.6, 8.9, 9.2, 10.0]
        let bins = latencyHistogram(samples: samples, buckets: 6)
        XCTAssertEqual(bins.map(\.count).reduce(0, +), samples.count)
    }

    func test_binRangesAreContiguousAndAscending() {
        let samples: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let bins = latencyHistogram(samples: samples, buckets: 5)
        for i in 0..<bins.count - 1 {
            XCTAssertLessThan(bins[i].rangeMs.lowerBound, bins[i + 1].rangeMs.lowerBound)
            XCTAssertEqual(bins[i].rangeMs.upperBound, bins[i + 1].rangeMs.lowerBound, accuracy: 1e-9)
        }
    }

    func test_lastBinUpperBoundEqualsMaxSampleInMs() {
        // Helper takes ns, returns ms — input 1_000_000 ns = 1.0 ms.
        let samples: [Double] = [100_000, 500_000, 1_000_000]
        let bins = latencyHistogram(samples: samples, buckets: 4)
        XCTAssertEqual(bins.last!.rangeMs.upperBound, 1.0, accuracy: 1e-9)
    }

    func test_zeroBucketsReturnsEmpty() {
        XCTAssertEqual(latencyHistogram(samples: [1, 2, 3], buckets: 0), [])
    }

    func test_midpointMsIsCenterOfRange() {
        let bin = HistogramBin(rangeMs: 2.0...4.0, count: 5)
        XCTAssertEqual(bin.midpointMs, 3.0, accuracy: 1e-9)
    }
}
