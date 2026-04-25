import CoreGraphics

/// Test double for the ``Injector`` protocol.
///
/// Records every `inject`, `injectScroll`, and `injectZoom` call so tests can
/// assert on event types and values without touching CoreGraphics or posting real
/// system events.
public final class MockInjector: Injector {

    /// All recorded inject calls in order of arrival.
    public private(set) var calls: [(StylusEvent, CGPoint)] = []

    /// All recorded scroll injection calls: (deltaX, deltaY, phaseFlags).
    public private(set) var scrollCalls: [(Int16, Int16, UInt8)] = []

    /// All recorded zoom injection calls: scaleDelta values.
    public private(set) var zoomCalls: [Float] = []

    /// All recorded cursor delta injection calls: (deltaX, deltaY).
    public private(set) var cursorDeltaCalls: [(Int16, Int16)] = []

    /// All recorded key injection calls: (keyCode, modifiers, action).
    public private(set) var keyCalls: [(UInt8, UInt8, KeyAction)] = []

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

    public func injectScroll(deltaX: Int16, deltaY: Int16, phaseFlags: UInt8) throws {
        scrollCalls.append((deltaX, deltaY, phaseFlags))
    }

    public func injectZoom(scaleDelta: Float) throws {
        zoomCalls.append(scaleDelta)
    }

    public func injectCursorDelta(deltaX: Int16, deltaY: Int16) throws {
        cursorDeltaCalls.append((deltaX, deltaY))
    }

    public func injectKey(keyCode: UInt8, modifiers: UInt8, action: KeyAction) throws {
        keyCalls.append((keyCode, modifiers, action))
    }

    /// Clears recorded calls and resets any pending error.
    public func reset() {
        calls.removeAll()
        scrollCalls.removeAll()
        zoomCalls.removeAll()
        cursorDeltaCalls.removeAll()
        keyCalls.removeAll()
        nextError = nil
    }
}
