import XCTest
@testable import InkBridgeCore

final class OneEuroFilterTests: XCTestCase {

    private let dt240Hz: UInt64 = 4_166_667 // ~1/240 s in ns

    func test_staticInputConvergesToItself() {
        var f = OneEuroFilter()
        var t: UInt64 = 1_000_000_000
        var output: Float = 0
        for _ in 0..<10 {
            output = f.filter(0.5, timestampNs: t)
            t &+= dt240Hz
        }
        XCTAssertEqual(output, 0.5, accuracy: 1e-6)
    }

    func test_stepResponseCatchesUp() {
        var f = OneEuroFilter()
        var t: UInt64 = 1_000_000_000
        // First sample establishes baseline at 0.0.
        _ = f.filter(0.0, timestampNs: t)
        t &+= dt240Hz
        // Step to 1.0 and feed for 30 frames at 240 Hz.
        var last: Float = 0
        for _ in 0..<30 {
            last = f.filter(1.0, timestampNs: t)
            t &+= dt240Hz
        }
        XCTAssertGreaterThanOrEqual(last, 0.95)
    }

    func test_highFrequencyJitterIsAttenuated() {
        var f = OneEuroFilter()
        var t: UInt64 = 1_000_000_000

        // Warm up a bit at the centre value to populate state.
        for _ in 0..<10 {
            _ = f.filter(0.500, timestampNs: t)
            t &+= dt240Hz
        }

        var minOut = Float.greatestFiniteMagnitude
        var maxOut = -Float.greatestFiniteMagnitude
        let amplitude: Float = 0.001
        for i in 0..<100 {
            let input: Float = 0.500 + (i.isMultiple(of: 2) ? amplitude : -amplitude)
            let out = f.filter(input, timestampNs: t)
            t &+= dt240Hz
            minOut = min(minOut, out)
            maxOut = max(maxOut, out)
        }
        let outAmpPP = maxOut - minOut
        let inAmpPP: Float = 2 * amplitude
        // Output peak-to-peak must be at most 50% of input peak-to-peak.
        XCTAssertLessThanOrEqual(outAmpPP, inAmpPP * 0.5)
    }

    func test_realisticRampHasSmallLag() {
        // Realistic stroke: 0 → 1 over 60 frames at 240 Hz (250 ms).
        // A 10-frame ramp would be a 42 ms full-screen-width zip — not a stroke,
        // a flick. The filter intentionally lags for the first few samples while
        // it estimates velocity; over a real-length stroke that initial lag is
        // negligible.
        var f = OneEuroFilter()
        var t: UInt64 = 1_000_000_000
        var lastInput: Float = 0
        var lastOutput: Float = 0
        let frames = 60
        for i in 0..<frames {
            let v = Float(i) / Float(frames - 1)
            lastOutput = f.filter(v, timestampNs: t)
            lastInput = v
            t &+= dt240Hz
        }
        XCTAssertLessThanOrEqual(abs(lastInput - lastOutput), 0.06)
    }

    func test_resetClearsState() {
        var f = OneEuroFilter()
        var t: UInt64 = 1_000_000_000
        // Drive it for a few samples so internal state is populated.
        for _ in 0..<5 {
            _ = f.filter(0.7, timestampNs: t)
            t &+= dt240Hz
        }
        f.reset()
        // After reset, the very next sample MUST be returned unmodified
        // (no previous state, dt undefined) — same behaviour as a fresh filter.
        let out = f.filter(0.2, timestampNs: t)
        XCTAssertEqual(out, 0.2, accuracy: 1e-6)
    }
}
