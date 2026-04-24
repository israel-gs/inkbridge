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
}

/// Errors thrown by ``Injector`` implementations.
public enum InjectorError: Error, Equatable {
    /// Accessibility permission has not been granted. The caller must surface
    /// the onboarding flow. (macos-injection.md R1)
    case notTrusted
    /// CGEvent creation returned nil (unexpected system failure).
    case eventCreationFailed
}
