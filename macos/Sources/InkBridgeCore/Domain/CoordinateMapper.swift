import CoreGraphics

/// Maps normalized stylus coordinates to display-space points.
///
/// Pure function — no state, no side effects. Maps the normalized [0,1]
/// position from ``StylusSample`` to a ``CGPoint`` in display points.
/// Coordinates are clamped to display bounds regardless of input range.
///
/// macos-injection.md R5 — targets the main display only.
public enum CoordinateMapper {

    /// Maps normalized [0,1] coordinates to display-space ``CGPoint``.
    ///
    /// - Parameters:
    ///   - sample: The stylus sample carrying x/y in [0,1].
    ///   - display: The target display's size in points.
    /// - Returns: Clamped ``CGPoint`` in display coordinate space.
    public static func map(sample: StylusSample, display: DisplayRect) -> CGPoint {
        let px = (CGFloat(sample.x) * display.width).clamped(to: 0...display.width)
        let py = (CGFloat(sample.y) * display.height).clamped(to: 0...display.height)
        return CGPoint(x: px, y: py)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
