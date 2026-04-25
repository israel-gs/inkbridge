import CoreGraphics

/// Port (clean-architecture sense) for stylus event injection.
///
/// macos-injection.md R6 — the concrete CGEventPost-based implementation
/// is the only type that imports CoreGraphics. All domain code depends
/// on this protocol only.
public protocol Injector: AnyObject {
    /// Inject a decoded stylus event at the given display-space point.
    ///
    /// - Parameters:
    ///   - event: The decoded stylus event.
    ///   - point: Display-space coordinate computed by ``CoordinateMapper``.
    /// - Throws: ``InjectorError`` if the event cannot be injected.
    func inject(_ event: StylusEvent, at point: CGPoint) throws

    /// Inject a scroll wheel event (two-finger drag).
    ///
    /// - Parameters:
    ///   - deltaX:     Horizontal scroll delta in points.
    ///   - deltaY:     Vertical scroll delta in points.
    ///   - phaseFlags: 0x00 = continuation (kCGScrollPhase=changed),
    ///                 0x40 = first scroll of gesture (kCGScrollPhase=began),
    ///                 0x80 = lift (kCGScrollPhase=ended; triggers momentum decay).
    /// - Throws: ``InjectorError`` if the event cannot be injected.
    func injectScroll(deltaX: Int16, deltaY: Int16, phaseFlags: UInt8) throws

    /// Inject a zoom/magnification gesture event (two-finger pinch).
    ///
    /// - Parameter scaleDelta: Multiplicative scale delta since last frame. 1.0 = no change.
    /// - Throws: ``InjectorError`` if the event cannot be injected.
    func injectZoom(scaleDelta: Float) throws

    /// Inject a relative cursor movement (single-finger trackpad drag).
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal cursor delta in points (negative = left).
    ///   - deltaY: Vertical cursor delta in points (negative = up).
    /// - Throws: ``InjectorError`` if the event cannot be injected.
    func injectCursorDelta(deltaX: Int16, deltaY: Int16) throws
}

/// Errors thrown by ``Injector`` implementations.
public enum InjectorError: Error, Equatable {
    /// Accessibility permission has not been granted. The caller must surface
    /// the onboarding flow. (macos-injection.md R1)
    case notTrusted
    /// CGEvent creation returned nil (unexpected system failure).
    case eventCreationFailed
}
