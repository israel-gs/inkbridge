import CoreGraphics
import Foundation

/// Pure geometry helpers used by `TouchRouter`.
///
/// All functions are static, free of side effects, and import nothing from UIKit.
/// They operate on `CGPoint` (CoreGraphics) only, which is available on all Apple platforms.
public enum GestureGeometry {

    /// Returns the centroid (arithmetic mean position) of the given points.
    ///
    /// - Returns: `CGPoint.zero` if `points` is empty.
    public static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Returns the average Euclidean distance from the centroid to each point in `points`.
    ///
    /// This is a simple measure of "spread" or "size" of the touch cluster.
    /// - Returns: `0` if `points` has fewer than 2 elements.
    public static func spread(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        let c = centroid(points)
        let totalDistance = points.reduce(CGFloat(0)) { $0 + distance(c, $1) }
        return totalDistance / CGFloat(points.count)
    }

    /// Euclidean distance between two points.
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
