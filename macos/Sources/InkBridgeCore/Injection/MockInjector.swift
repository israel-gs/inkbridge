import CoreGraphics

/// Test double for the ``Injector`` protocol.
///
/// Records every `inject` call so tests can assert on event types and
/// coordinates without touching CoreGraphics or posting real system events.
public final class MockInjector: Injector {

    /// All recorded inject calls in order of arrival.
    public private(set) var calls: [(StylusEvent, CGPoint)] = []

    /// When non-nil, the next `inject` call will throw this error.
    public var nextError: InjectorError?

    public init() {}

    public func inject(_ event: StylusEvent, at point: CGPoint) throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
        calls.append((event, point))
    }

    /// Clears recorded calls and resets any pending error.
    public func reset() {
        calls.removeAll()
        nextError = nil
    }
}
