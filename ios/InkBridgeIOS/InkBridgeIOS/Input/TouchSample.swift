import CoreGraphics
import Foundation

/// A single captured touch point from the UIView touch system.
///
/// `TouchSample` is a pure value type — no UIKit dependency beyond `CGPoint` (CoreGraphics).
/// This lets the touch pipeline be tested without a running UI.
///
/// The canvas layer creates `TouchSample` values in `touchesBegan/Moved/Ended/Cancelled`
/// and passes them to `TouchRouter.process(_:phase:)`.
public struct TouchSample: Equatable, Sendable {
    /// A stable identifier for the finger. Maps directly to `UITouch.hashValue` in the canvas.
    public let id: UUID

    /// Position in the view's coordinate space (points, not pixels).
    public let location: CGPoint

    /// Timestamp from `UITouch.timestamp` (seconds since system boot).
    /// Do NOT use `Date().timeIntervalSinceReferenceDate` here — UITouch timestamps are
    /// already on the same clock as `CACurrentMediaTime()`.
    public let timestamp: TimeInterval

    public init(id: UUID, location: CGPoint, timestamp: TimeInterval) {
        self.id = id
        self.location = location
        self.timestamp = timestamp
    }
}
