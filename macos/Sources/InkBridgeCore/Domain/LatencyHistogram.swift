import Foundation

/// One bucket of a latency histogram. `rangeMs` is the bucket's value range
/// expressed in milliseconds (so the UI can render directly without unit
/// conversion). `count` is the number of samples that fell into this bucket.
public struct HistogramBin: Equatable {
    public let rangeMs: ClosedRange<Double>
    public let count: Int

    public init(rangeMs: ClosedRange<Double>, count: Int) {
        self.rangeMs = rangeMs
        self.count = count
    }

    /// Midpoint of the bucket in ms. Useful as the X coordinate of a `BarMark`.
    public var midpointMs: Double {
        (rangeMs.lowerBound + rangeMs.upperBound) / 2
    }
}

/// Pure histogram bucketing. Takes raw nanosecond samples (matching
/// `LatencyTracker`'s internal buffer) and returns `buckets` equal-width bins
/// over `[0, max]` with values reported in milliseconds.
///
/// - When `samples` is empty, returns `buckets` empty bins covering `0...0`.
/// - When `buckets` is `0`, returns an empty array.
public func latencyHistogram(samples: [Double], buckets: Int) -> [HistogramBin] {
    guard buckets > 0 else { return [] }

    guard !samples.isEmpty, let maxNs = samples.max() else {
        return Array(repeating: HistogramBin(rangeMs: 0...0, count: 0), count: buckets)
    }

    let maxMs = maxNs / 1_000_000.0
    let widthMs = maxMs / Double(buckets)

    var counts = Array(repeating: 0, count: buckets)
    for sampleNs in samples {
        let sampleMs = sampleNs / 1_000_000.0
        // Map sample to bucket index. Last bucket is inclusive of upper bound.
        var idx: Int
        if widthMs == 0 {
            idx = 0
        } else {
            idx = Int(sampleMs / widthMs)
            if idx >= buckets { idx = buckets - 1 }
        }
        counts[idx] += 1
    }

    return (0..<buckets).map { i in
        let lo = Double(i) * widthMs
        let hi = Double(i + 1) * widthMs
        return HistogramBin(rangeMs: lo...hi, count: counts[i])
    }
}
