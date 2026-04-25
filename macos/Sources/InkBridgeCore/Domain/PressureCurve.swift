import Foundation
import simd

/// A user-tunable mapping from raw stylus pressure `[0, 1]` to output pressure
/// `[0, 1]`, expressed as a cubic Bézier whose endpoints are pinned to
/// `(0, 0)` and `(1, 1)`. Only the two interior control points are mutable.
///
/// `apply(raw)` solves `B_x(t) = raw` for `t` (Newton iteration seeded with
/// `t = raw`) and returns `B_y(t)`. The Bézier is monotone in X when
/// `0 ≤ p1.x ≤ p2.x ≤ 1`; the constructor does not enforce this — invalid
/// points still produce defined output, but the curve will not be a function.
public struct PressureCurve: Equatable, Codable {

    public let p1: SIMD2<Float>
    public let p2: SIMD2<Float>

    public init(p1: SIMD2<Float>, p2: SIMD2<Float>) {
        self.p1 = p1
        self.p2 = p2
    }

    // MARK: - Presets

    /// Identity. Output equals raw input. Default for new users.
    public static let linear = PressureCurve(
        p1: SIMD2<Float>(0.33, 0.33),
        p2: SIMD2<Float>(0.67, 0.67)
    )

    /// Lower mid-range pressure for fine line work. Soft strokes are lighter.
    public static let soft = PressureCurve(
        p1: SIMD2<Float>(0.40, 0.10),
        p2: SIMD2<Float>(0.85, 0.55)
    )

    /// Faster ramp into mid pressure for confident strokes.
    public static let hard = PressureCurve(
        p1: SIMD2<Float>(0.15, 0.45),
        p2: SIMD2<Float>(0.60, 0.90)
    )

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case p1x, p1y, p2x, p2y }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.p1 = SIMD2<Float>(
            try c.decode(Float.self, forKey: .p1x),
            try c.decode(Float.self, forKey: .p1y)
        )
        self.p2 = SIMD2<Float>(
            try c.decode(Float.self, forKey: .p2x),
            try c.decode(Float.self, forKey: .p2y)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p1.x, forKey: .p1x)
        try c.encode(p1.y, forKey: .p1y)
        try c.encode(p2.x, forKey: .p2x)
        try c.encode(p2.y, forKey: .p2y)
    }

    // MARK: - Apply

    /// Maps `raw ∈ [0, 1]` to the curve's `y`. Out-of-range values are clamped.
    public func apply(_ raw: Float) -> Float {
        if raw <= 0 { return 0 }
        if raw >= 1 { return 1 }

        // Solve B_x(t) = raw for t. Use Newton-Raphson seeded at t = raw.
        // For valid monotone curves this converges in < 6 iterations to 1e-6.
        var t: Float = raw
        for _ in 0..<6 {
            let xt = bezierX(t)
            let dx = bezierXDerivative(t)
            // Guard against zero derivative (degenerate curve).
            if abs(dx) < 1e-6 { break }
            let next = t - (xt - raw) / dx
            // Keep t in [0, 1].
            t = min(max(next, 0), 1)
            if abs(xt - raw) < 1e-5 { break }
        }
        let y = bezierY(t)
        return min(max(y, 0), 1)
    }

    // MARK: - Bézier helpers

    /// Cubic Bézier X with endpoints (0, _) and (1, _).
    /// B_x(t) = 3(1-t)²t·p1.x + 3(1-t)t²·p2.x + t³.
    private func bezierX(_ t: Float) -> Float {
        let u = 1 - t
        return 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t
    }

    /// dB_x/dt = 3(1-t)²·p1.x + 6(1-t)t·(p2.x - p1.x) + 3t²·(1 - p2.x).
    private func bezierXDerivative(_ t: Float) -> Float {
        let u = 1 - t
        return 3 * u * u * p1.x
             + 6 * u * t * (p2.x - p1.x)
             + 3 * t * t * (1 - p2.x)
    }

    /// Cubic Bézier Y with endpoints (_, 0) and (_, 1).
    /// B_y(t) = 3(1-t)²t·p1.y + 3(1-t)t²·p2.y + t³.
    private func bezierY(_ t: Float) -> Float {
        let u = 1 - t
        return 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t
    }
}
