import XCTest
@testable import InkBridgeCore

final class PressureCurveTests: XCTestCase {

    func test_linearPresetIsIdentity() {
        let c = PressureCurve.linear
        for raw in stride(from: Float(0), through: 1, by: 0.05) {
            XCTAssertEqual(c.apply(raw), raw, accuracy: 1e-3)
        }
    }

    func test_clampsBelowZero() {
        let c = PressureCurve.linear
        XCTAssertEqual(c.apply(-0.5), 0.0)
        XCTAssertEqual(c.apply(-1.0), 0.0)
    }

    func test_clampsAboveOne() {
        let c = PressureCurve.linear
        XCTAssertEqual(c.apply(1.5), 1.0)
        XCTAssertEqual(c.apply(100.0), 1.0)
    }

    func test_endpointsExact() {
        for c in [PressureCurve.linear, .soft, .hard] {
            XCTAssertEqual(c.apply(0.0), 0.0, accuracy: 1e-4)
            XCTAssertEqual(c.apply(1.0), 1.0, accuracy: 1e-4)
        }
    }

    func test_softCurveBelowsLinear() {
        // Soft maps mid-range pressure to LOWER output (lighter strokes).
        let c = PressureCurve.soft
        XCTAssertLessThan(c.apply(0.5), 0.5)
    }

    func test_hardCurveAboveLinear() {
        // Hard maps mid-range pressure to HIGHER output (heavier strokes).
        let c = PressureCurve.hard
        XCTAssertGreaterThan(c.apply(0.5), 0.5)
    }

    func test_monotonicNonDecreasing() {
        for c in [PressureCurve.linear, .soft, .hard] {
            var prev: Float = 0
            for i in 0...100 {
                let raw = Float(i) / 100.0
                let out = c.apply(raw)
                XCTAssertGreaterThanOrEqual(
                    out, prev - 1e-4,
                    "non-monotone for \(c) at raw=\(raw): prev=\(prev) out=\(out)"
                )
                prev = out
            }
        }
    }

    func test_codableRoundTrip() throws {
        let original = PressureCurve(p1: SIMD2<Float>(0.2, 0.7), p2: SIMD2<Float>(0.8, 0.3))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PressureCurve.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
