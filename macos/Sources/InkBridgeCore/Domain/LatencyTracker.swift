import Foundation

/// Measures wire-to-inject latency for InkBridge stylus frames.
///
/// ## Clock domain warning
///
/// Android `System.nanoTime()` and macOS `DispatchTime.now().uptimeNanoseconds`
/// are both monotonic clocks referenced to device boot time, but they run on
/// completely independent hardware and are never synchronized. The raw difference
/// `arrivalNs - wireNs` is dominated by clock skew between the two devices and is
/// NOT a reliable absolute latency measurement.
///
/// Three metrics are exposed to reflect this:
///
/// - **wireToArrival**: `arrivalNs − wireNs`. UNRELIABLE — polluted by cross-device
///   clock skew (potentially hundreds of milliseconds). Useful only for relative
///   trend analysis over time (did it get worse?), not for absolute values.
///
/// - **arrivalToInject**: `injectNs − arrivalNs`. RELIABLE — both timestamps are
///   captured on the macOS side, so this is true Mac-internal processing latency:
///   the time from when the Network framework delivers the frame to when
///   `CGEventPost` returns.
///
/// - **total**: `injectNs − wireNs`. UNRELIABLE for absolute value (clock skew),
///   but changes in this metric over sessions reflect real end-to-end trends.
///
/// For actionable performance work, focus on `arrivalToInject` percentiles.
/// Alarm on `wireToArrival` only when the *trend* degrades, not on the absolute value.
public struct LatencyTracker {

    // MARK: - Snapshot

    /// A point-in-time view of collected latency statistics.
    public struct Snapshot {
        /// Total number of samples collected since last reset.
        public let samples: Int

        // MARK: wireToArrival (UNRELIABLE — cross-device clock skew)

        /// Median `arrivalNs − wireNs` in milliseconds.
        /// UNRELIABLE absolute value; use for trend analysis only.
        public let wireToArrivalP50Ms: Double
        /// 95th-percentile `arrivalNs − wireNs` in milliseconds.
        /// UNRELIABLE absolute value; use for trend analysis only.
        public let wireToArrivalP95Ms: Double
        /// 99th-percentile `arrivalNs − wireNs` in milliseconds.
        /// UNRELIABLE absolute value; use for trend analysis only.
        public let wireToArrivalP99Ms: Double

        // MARK: arrivalToInject (RELIABLE — Mac-internal)

        /// Median `injectNs − arrivalNs` in milliseconds.
        /// RELIABLE: measures Mac-side processing time only (no clock skew).
        public let arrivalToInjectP50Ms: Double
        /// 95th-percentile `injectNs − arrivalNs` in milliseconds. RELIABLE.
        public let arrivalToInjectP95Ms: Double
        /// 99th-percentile `injectNs − arrivalNs` in milliseconds. RELIABLE.
        public let arrivalToInjectP99Ms: Double

        // MARK: total (UNRELIABLE — dominated by cross-device clock skew)

        /// Median `injectNs − wireNs` in milliseconds.
        /// UNRELIABLE absolute value; dominated by cross-device clock skew.
        public let totalP50Ms: Double
        /// 95th-percentile `injectNs − wireNs` in milliseconds. UNRELIABLE.
        public let totalP95Ms: Double
        /// 99th-percentile `injectNs − wireNs` in milliseconds. UNRELIABLE.
        public let totalP99Ms: Double

        /// Mean `injectNs − arrivalNs` (Mac-internal, RELIABLE) in milliseconds.
        public let arrivalToInjectMeanMs: Double

        /// Raw arrival-to-inject samples (ns) currently in the ring buffer.
        /// Length `≤ LatencyTracker.capacity`. Order is unspecified (the ring
        /// may have wrapped) but bucketing is order-independent.
        ///
        /// Exposed so the UI can render a histogram via `latencyHistogram`
        /// without needing to plumb the entire tracker.
        public let arrivalToInjectSamplesNs: [Double]

        /// A snapshot with all-zero values, used as a placeholder before any samples arrive.
        public static let zero = Snapshot(
            samples: 0,
            wireToArrivalP50Ms: 0, wireToArrivalP95Ms: 0, wireToArrivalP99Ms: 0,
            arrivalToInjectP50Ms: 0, arrivalToInjectP95Ms: 0, arrivalToInjectP99Ms: 0,
            totalP50Ms: 0, totalP95Ms: 0, totalP99Ms: 0,
            arrivalToInjectMeanMs: 0,
            arrivalToInjectSamplesNs: []
        )
    }

    // MARK: - Ring buffer

    /// Maximum number of samples retained. Older samples are evicted when full.
    public static let capacity = 256

    private var wireToArrivalNs: [Double]
    private var arrivalToInjectNs: [Double]
    private var totalNs: [Double]
    private var head: Int = 0
    private var count: Int = 0

    // MARK: - Init

    public init() {
        wireToArrivalNs = Array(repeating: 0, count: Self.capacity)
        arrivalToInjectNs = Array(repeating: 0, count: Self.capacity)
        totalNs = Array(repeating: 0, count: Self.capacity)
    }

    // MARK: - Mutation

    /// Records a single latency observation.
    ///
    /// - Parameters:
    ///   - wireNs:    `timestamp_ns` from the packet header (Android `System.nanoTime()`).
    ///                **Different clock domain** — see type-level documentation.
    ///   - arrivalNs: `DispatchTime.now().uptimeNanoseconds` when the listener yielded the frame.
    ///   - injectNs:  `DispatchTime.now().uptimeNanoseconds` after `CGEventPost` returns.
    public mutating func record(wireNs: UInt64, arrivalNs: UInt64, injectNs: UInt64) {
        // Use signed arithmetic to handle any temporary clock skew without crashing.
        let wta = Double(Int64(bitPattern: arrivalNs) - Int64(bitPattern: wireNs))
        let ati = Double(Int64(bitPattern: injectNs)  - Int64(bitPattern: arrivalNs))
        let tot = Double(Int64(bitPattern: injectNs)  - Int64(bitPattern: wireNs))

        wireToArrivalNs[head]    = wta
        arrivalToInjectNs[head]  = ati
        totalNs[head]            = tot

        head = (head + 1) % Self.capacity
        if count < Self.capacity { count += 1 }
    }

    /// Clears all recorded samples.
    public mutating func reset() {
        head = 0
        count = 0
    }

    // MARK: - Query

    /// Computes statistics over the current ring-buffer contents.
    ///
    /// Sorting is O(N log N) on N ≤ 256 — safe to call from the main actor
    /// after each batch of frames, but avoid calling in a tight per-frame loop.
    public func snapshot() -> Snapshot {
        guard count > 0 else { return .zero }

        let wta = percentiles(of: wireToArrivalNs, count: count)
        let ati = percentiles(of: arrivalToInjectNs, count: count)
        let tot = percentiles(of: totalNs, count: count)
        let mean = arrivalToInjectNs.prefix(count).reduce(0, +) / Double(count)

        return Snapshot(
            samples: count,
            wireToArrivalP50Ms:     wta.p50 / 1_000_000,
            wireToArrivalP95Ms:     wta.p95 / 1_000_000,
            wireToArrivalP99Ms:     wta.p99 / 1_000_000,
            arrivalToInjectP50Ms:   ati.p50 / 1_000_000,
            arrivalToInjectP95Ms:   ati.p95 / 1_000_000,
            arrivalToInjectP99Ms:   ati.p99 / 1_000_000,
            totalP50Ms:             tot.p50 / 1_000_000,
            totalP95Ms:             tot.p95 / 1_000_000,
            totalP99Ms:             tot.p99 / 1_000_000,
            arrivalToInjectMeanMs:  mean    / 1_000_000,
            arrivalToInjectSamplesNs: Array(arrivalToInjectNs.prefix(count))
        )
    }

    // MARK: - Private helpers

    private struct Percentiles {
        let p50: Double
        let p95: Double
        let p99: Double
    }

    /// Returns p50/p95/p99 by sorting a slice of the ring buffer.
    ///
    /// Uses the first `count` elements. For a ring buffer that has wrapped,
    /// elements are not necessarily in chronological order, but percentile
    /// computation only requires an unordered set — so this is correct.
    private func percentiles(of buffer: [Double], count: Int) -> Percentiles {
        let sorted = buffer.prefix(count).sorted()
        return Percentiles(
            p50: sorted[percentileIndex(0.50, count: count)],
            p95: sorted[percentileIndex(0.95, count: count)],
            p99: sorted[percentileIndex(0.99, count: count)]
        )
    }

    /// Clamps the percentile index into [0, count − 1].
    private func percentileIndex(_ fraction: Double, count: Int) -> Int {
        let raw = Int((fraction * Double(count - 1)).rounded())
        return min(max(raw, 0), count - 1)
    }
}
