import CoreGraphics
import ApplicationServices
import Foundation
#if canImport(AppKit)
import AppKit
#endif

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
    private var proximityEntered = false

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

        // Ensure AppKit has a tablet-proximity context before ANY tablet-tagged
        // mouse event arrives. Drawing apps (Krita, Photoshop, Affinity) gate
        // pressure/tilt recognition on a prior proximity-enter with valid
        // vendor + capability metadata. We synthesise one lazily on the first
        // event if Android did not send a STYLUS_PROXIMITY enter frame.
        stateLock.lock()
        let needsImplicitProximity = !proximityEntered && !isProximityEvent(event)
        stateLock.unlock()
        if needsImplicitProximity {
            try postProximity(entering: true)
            stateLock.lock()
            proximityEntered = true
            stateLock.unlock()
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

        if case let .proximity(entering) = event {
            stateLock.lock()
            proximityEntered = entering
            stateLock.unlock()
        }
    }

    private func isProximityEvent(_ event: StylusEvent) -> Bool {
        if case .proximity = event { return true }
        return false
    }

    // MARK: - Private

    private func post(_ action: StrokeAction) throws {
        switch action {
        case let .moved(point, fields):
            try postMouseLike(type: .mouseMoved, point: point, button: .left, fields: fields)

        case let .dragged(point, button, fields):
            let type: CGEventType = (button == .left) ? .leftMouseDragged : .rightMouseDragged
            try postMouseLike(type: type, point: point, button: button, fields: fields)

        case let .mouseDown(point, button, fields):
            let type: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
            try postMouseLike(type: type, point: point, button: button, fields: fields)

        case let .mouseUp(point, button, fields):
            let type: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
            try postMouseLike(type: type, point: point, button: button, fields: fields)

        case let .proximity(entering):
            try postProximity(entering: entering)
        }
    }

    private static let tabletDeviceID: Int64 = 1

    private func postMouseLike(
        type: CGEventType,
        point: CGPoint,
        button: CGMouseButton,
        fields: TabletFields?
    ) throws {
        // Emit the event as a tablet-subtyped mouse event so (a) macOS treats
        // it as originating from a tablet rather than a "raw" synthetic click
        // (which is aggressively filtered on macOS 14+ for unentitled apps),
        // and (b) AppKit propagates tabletPoint fields to drawing apps, which
        // only read pressure/tilt from subtype=tabletPoint events.
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

        // Tag every mouse-like stroke event as a tablet event. Even moveOnly
        // events benefit from the subtype because the tablet proximity state
        // is tied to consistent device id + subtype across the event stream.
        cgEvent.setIntegerValueField(.mouseEventSubtype, value: Self.tabletPointSubtypeRawValue)
        cgEvent.setIntegerValueField(.tabletEventDeviceID, value: Self.tabletDeviceID)

        if let fields = fields {
            // Pressure: u16 [0, 65535] → normalized double [0.0, 1.0].
            let normalizedPressure = Double(fields.pressure) / 65535.0
            cgEvent.setDoubleValueField(.tabletEventPointPressure, value: normalizedPressure)
            // Some AppKit consumers also read the integer pressure field on the
            // mouse event itself. Scale to 0..255 (NSEvent pressure is typically
            // 0..1 but the CG field is integer-scaled internally).
            cgEvent.setIntegerValueField(.mouseEventPressure, value: Int64(normalizedPressure * 255.0))

            cgEvent.setDoubleValueField(.tabletEventTiltX, value: Double(fields.tiltX) / 9000.0)
            cgEvent.setDoubleValueField(.tabletEventTiltY, value: Double(fields.tiltY) / 9000.0)
            cgEvent.setIntegerValueField(.tabletEventPointX, value: Int64(point.x))
            cgEvent.setIntegerValueField(.tabletEventPointY, value: Int64(point.y))
            cgEvent.setDoubleValueField(.tabletEventRotation, value: 0)
        }

        cgEvent.post(tap: .cgSessionEventTap)
    }

    /// NSEvent.EventSubtype.tabletPoint.rawValue = 1. Hard-coded to avoid a
    /// build-time AppKit dependency in tests that don't need the UI layer.
    #if canImport(AppKit)
    private static let tabletPointSubtypeRawValue: Int64 = Int64(NSEvent.EventSubtype.tabletPoint.rawValue)
    #else
    private static let tabletPointSubtypeRawValue: Int64 = 1
    #endif

    // Simulated Wacom-compatible tablet identity. Capability mask advertises
    // support for the fields we actually set (pressure + tilt + absolute x/y).
    // Drawing apps check this bitmask before reading the corresponding fields.
    private static let simulatedVendorID: Int64 = 0x056A                // Wacom
    private static let simulatedTabletID: Int64 = 0x0001
    private static let simulatedPointerID: Int64 = 0x0001
    private static let simulatedSystemTabletID: Int64 = 0x0001
    private static let simulatedVendorPointerType: Int64 = 0x0802       // Pro Pen
    private static let simulatedPointerSerial: Int64 = 0x0001
    private static let simulatedUniqueID: Int64 = 0x0000_0001_0001
    /// kCGTabletEventPointButtons bit0 (tip) + bit1 (button) = 0x3, plus
    /// bits reserved for pressure (4), tilt-x (5), tilt-y (6), abs-x (13),
    /// abs-y (14), abs-z (15). See IOHIDEventTypes CapabilityMask constants.
    private static let simulatedCapabilityMask: Int64 = 0x0000_E063

    private func postProximity(entering: Bool) throws {
        guard let cgEvent = CGEvent(source: eventSource) else {
            throw InjectorError.eventCreationFailed
        }
        cgEvent.type = .tabletProximity
        cgEvent.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        cgEvent.setIntegerValueField(.tabletProximityEventPointerType, value: 1)  // pen tip
        cgEvent.setIntegerValueField(.tabletProximityEventDeviceID, value: Self.tabletDeviceID)
        cgEvent.setIntegerValueField(.tabletProximityEventVendorID, value: Self.simulatedVendorID)
        cgEvent.setIntegerValueField(.tabletProximityEventTabletID, value: Self.simulatedTabletID)
        cgEvent.setIntegerValueField(.tabletProximityEventPointerID, value: Self.simulatedPointerID)
        cgEvent.setIntegerValueField(.tabletProximityEventSystemTabletID, value: Self.simulatedSystemTabletID)
        cgEvent.setIntegerValueField(.tabletProximityEventVendorPointerType, value: Self.simulatedVendorPointerType)
        cgEvent.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: Self.simulatedPointerSerial)
        cgEvent.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: Self.simulatedUniqueID)
        cgEvent.setIntegerValueField(.tabletProximityEventCapabilityMask, value: Self.simulatedCapabilityMask)
        cgEvent.post(tap: .cgSessionEventTap)
    }
}
