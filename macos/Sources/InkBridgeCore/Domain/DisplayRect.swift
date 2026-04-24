import CoreGraphics

/// The target display's frame in points.
///
/// Used by ``CoordinateMapper`` to convert normalized [0,1] coordinates
/// to display-space ``CGPoint`` values.
public struct DisplayRect: Equatable {
    /// Display width in points.
    public let width: CGFloat
    /// Display height in points.
    public let height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
}
