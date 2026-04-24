import CoreGraphics
import ApplicationServices
import Foundation

/// Concrete ``Injector`` that posts real CGEvents to the HID event tap.
///
/// macos-injection.md R1–R4, R6–R8.
///
/// - Accessibility permission is checked once at init and stored in `isTrusted`.
///   Each `inject` call re-verifies trust to catch revocation mid-session.
/// - CGEventPost is never called during unit tests — use ``MockInjector`` instead.
/// - Stroke routing (.mouseMoved vs .leftMouseDragged vs .leftMouseDown/.leftMouseUp)
///   is handled by ``StrokeStateMachine``, which is pure and tested separately.
@available(macOS 13, *)
public final class CGEventInjector: Injector {

    /// True if the process currently holds Accessibility trust.
    public private(set) var isTrusted: Bool

    private var stateMachine = StrokeStateMachine()
    private let stateLock = NSLock()
    private let eventSource: CGEventSource?

    public init() {
        self.isTrusted = AXIsProcessTrustedWithOptions(nil)
        // An explicit HID state source is required for synthetic mouse-button
        // events (leftMouseDown / leftMouseUp / leftMouseDragged) to register
        // in the system button state. With a nil source, mouseMoved works but
        // button transitions are swallowed.
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Re-evaluates Accessibility trust and updates ``isTrusted``.
    public func refreshTrust() {
        isTrusted = AXIsProcessTrustedWithOptions(nil)
    }

    public func inject(_ event: StylusEvent, at point: CGPoint) throws {
        isTrusted = AXIsProcessTrustedWithOptions(nil)
        guard isTrusted else {
            throw InjectorError.notTrusted
        }

        // Route the event through the state machine under a lock so concurrent
        // transport callbacks produce a consistent down/dragged/up sequence.
        let actions: [StrokeAction] = {
            stateLock.lock()
            defer { stateLock.unlock() }
            return stateMachine.process(event, at: point)
        }()

        for action in actions {
            try post(action)
        }
    }

    // MARK: - Private

    private func post(_ action: StrokeAction) throws {
        switch action {
        case let .moved(point, fields):
            try postMouseLike(type: .mouseMoved, point: point, button: .left, fields: fields)

        case let .dragged(point, button, fields):
            let type: CGEventType = (button == .left) ? .leftMouseDragged : .rightMouseDragged
            try postMouseLike(type: type, point: point, button: button, fields: fields)

        case let .mouseDown(point, button):
            let type: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
            try postMouseLike(type: type, point: point, button: button, fields: nil)

        case let .mouseUp(point, button):
            let type: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
            try postMouseLike(type: type, point: point, button: button, fields: nil)

        case let .proximity(entering):
            try postProximity(entering: entering)
        }
    }

    private func postMouseLike(
        type: CGEventType,
        point: CGPoint,
        button: CGMouseButton,
        fields: TabletFields?
    ) throws {
        // NOTE: synthetic leftMouseDown/Dragged/Up posted here are silently
        // dropped on macOS 14+ for apps without a Developer ID and proper
        // entitlements. mouseMoved works. Strokes in drawing apps will not
        // register until the app is signed for distribution. See design doc.
        guard let cgEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            throw InjectorError.eventCreationFailed
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp:
            cgEvent.setIntegerValueField(.mouseEventClickState, value: 1)
        default:
            break
        }

        if let fields = fields {
            cgEvent.setDoubleValueField(.tabletEventPointPressure, value: Double(fields.pressure) / 65535.0)
            cgEvent.setDoubleValueField(.tabletEventTiltX, value: Double(fields.tiltX) / 9000.0)
            cgEvent.setDoubleValueField(.tabletEventTiltY, value: Double(fields.tiltY) / 9000.0)
            cgEvent.setIntegerValueField(.tabletEventPointX, value: Int64(point.x))
            cgEvent.setIntegerValueField(.tabletEventPointY, value: Int64(point.y))
        }

        cgEvent.post(tap: .cgSessionEventTap)
    }

    private func postProximity(entering: Bool) throws {
        guard let cgEvent = CGEvent(source: eventSource) else {
            throw InjectorError.eventCreationFailed
        }
        cgEvent.type = .tabletProximity
        cgEvent.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        cgEvent.setIntegerValueField(.tabletProximityEventPointerType, value: 1)
        cgEvent.setIntegerValueField(.tabletProximityEventDeviceID, value: 0x0001)
        cgEvent.post(tap: .cgSessionEventTap)
    }
}
