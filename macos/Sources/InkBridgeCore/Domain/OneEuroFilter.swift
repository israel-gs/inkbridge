import Foundation

/// One-Euro low-pass filter (Casiez, Roussel, Vogel 2012).
///
/// Adaptive cutoff: aggressive smoothing at low velocity, relaxed smoothing at
/// high velocity. Solves the lag-vs-jitter tradeoff that plain EMA cannot.
///
/// Used per-axis: hold one instance for X and one for Y. Do NOT share state.
///
/// Implementation is a value type with mutating methods so the caller's storage
/// dictates lifetime. No `Foundation.Date`, no `DispatchTime` — timestamps are
/// passed in by the caller for deterministic, hermetic testing.
public struct OneEuroFilter {

    // MARK: - Parameters

    /// Minimum cutoff frequency (Hz). Lower → more smoothing at rest.
    public let minCutoff: Float
    /// Cutoff slope (unitless). Higher → cutoff rises faster with velocity.
    public let beta: Float
    /// Cutoff frequency (Hz) for the velocity low-pass stage.
    public let dCutoff: Float

    // MARK: - State

    private var lastValue: Float?
    private var lastFilteredDerivative: Float = 0
    private var lastTimestampNs: UInt64?

    // MARK: - Init

    /// Default parameters chosen for stylus position tracking at 60-240 Hz.
    ///
    /// `minCutoff = 5.0` Hz keeps rest-state smoothing aggressive enough to
    /// kill sensor jitter (~32 ms time constant) without visible lag. The
    /// 1.0 Hz default from the original paper would push tau to 159 ms — fine
    /// for slow gesture tracking, way too laggy for drawing.
    ///
    /// `beta = 0.5` makes the adaptive cutoff climb fast under any real motion
    /// so fast strokes pass through with negligible filter contribution.
    public init(minCutoff: Float = 5.0, beta: Float = 0.5, dCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    // MARK: - API

    /// Applies one filter step.
    ///
    /// First call (or first call after `reset()`) returns the input value
    /// unchanged because the time delta and previous value are undefined.
    public mutating func filter(_ value: Float, timestampNs: UInt64) -> Float {
        guard let lastValue, let lastTimestampNs else {
            self.lastValue = value
            self.lastTimestampNs = timestampNs
            return value
        }

        let dtNs = Int64(bitPattern: timestampNs) - Int64(bitPattern: lastTimestampNs)
        guard dtNs > 0 else {
            // Out-of-order or duplicate timestamp — ignore, return last.
            return lastValue
        }
        let dt = Float(dtNs) / 1_000_000_000.0

        // Stage 1: velocity (raw derivative) → low-pass at fixed dCutoff.
        let dValue = (value - lastValue) / dt
        let alphaD = Self.alpha(cutoff: dCutoff, dt: dt)
        let filteredDerivative = alphaD * dValue + (1 - alphaD) * lastFilteredDerivative

        // Stage 2: derive adaptive cutoff from |dValue_filtered|, low-pass value.
        let cutoff = minCutoff + beta * abs(filteredDerivative)
        let alpha = Self.alpha(cutoff: cutoff, dt: dt)
        let filteredValue = alpha * value + (1 - alpha) * lastValue

        self.lastValue = filteredValue
        self.lastFilteredDerivative = filteredDerivative
        self.lastTimestampNs = timestampNs
        return filteredValue
    }

    /// Clears all internal state. The next `filter` call behaves as the first.
    public mutating func reset() {
        lastValue = nil
        lastFilteredDerivative = 0
        lastTimestampNs = nil
    }

    // MARK: - Private

    /// Smoothing factor for an EMA at `cutoff` Hz given sampling interval `dt`.
    /// Standard formula: τ = 1 / (2π·cutoff), α = 1 / (1 + τ/dt).
    private static func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1.0 / (2 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}
