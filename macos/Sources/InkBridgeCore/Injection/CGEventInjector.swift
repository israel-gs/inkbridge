import CoreGraphics
import ApplicationServices
import Foundation
#if canImport(AppKit)
import AppKit
#endif

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

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

    /// Tracks click state for double/triple-click recognition.
    /// macOS counts consecutive clicks within ~500ms as multi-clicks; the
    /// CGEvent's mouseEventClickState field carries the count (1, 2, 3...).
    private var lastLeftClickUpNs: UInt64 = 0
    private var lastLeftClickState: Int64 = 0
    private var lastRightClickUpNs: UInt64 = 0
    private var lastRightClickState: Int64 = 0
    private static let doubleClickWindowNs: UInt64 = 500_000_000  // 500ms

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

    // MARK: - Gesture injection (scroll + zoom)

    /// Controls whether `injectZoom` attempts kCGEventTypeGesture (raw value 29)
    /// before falling back to Cmd+scroll. Empirically the gesture-event path is
    /// silently dropped on macOS 14+ for unentitled apps even with Hardened
    /// Runtime + Apple Development cert, so the default is `false` (use the
    /// Cmd+scroll fallback which works universally).
    public var preferGestureEvent: Bool = false

    /// Tracks the in-flight momentum simulation task so a fresh gesture can cancel it.
    private var momentumTask: Task<Void, Never>?

    public func injectScroll(deltaX: Int16, deltaY: Int16, phaseFlags: UInt8) throws {
        // Decode phase flags from the wire.
        // 0x40 = SCROLL_BEGIN, 0x80 = SCROLL_END, 0x00 = changed (default).
        let scrollPhase: Int64
        let isEnd: Bool
        switch phaseFlags {
        case 0x40: scrollPhase = 1   // kCGScrollPhaseBegan
                  ; isEnd = false
        case 0x80: scrollPhase = 4   // kCGScrollPhaseEnded
                  ; isEnd = true
        default:   scrollPhase = 2   // kCGScrollPhaseChanged
                  ; isEnd = false
        }

        // A new gesture start cancels any in-flight momentum from a previous one.
        if scrollPhase == 1 {
            momentumTask?.cancel()
            momentumTask = nil
        }

        try postScrollEvent(deltaX: deltaX, deltaY: deltaY, phase: scrollPhase, momentumPhase: 0)

        // After an END phase, kick off momentum decay if the last delta has
        // any meaningful magnitude. Real Magic Trackpad hardware emits these.
        if isEnd {
            startMomentumDecay(initialDeltaX: deltaX, initialDeltaY: deltaY)
        }
    }

    private func postScrollEvent(deltaX: Int16, deltaY: Int16, phase: Int64, momentumPhase: Int64) throws {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else {
            throw InjectorError.eventCreationFailed
        }
        // Field 99 = kCGScrollWheelEventScrollPhase (1=began, 2=changed, 4=ended).
        if let phaseField = CGEventField(rawValue: 99) {
            scrollEvent.setIntegerValueField(phaseField, value: phase)
        }
        // Field 123 = kCGScrollWheelEventMomentumPhase (1=began, 2=changed, 4=ended).
        if momentumPhase != 0, let momField = CGEventField(rawValue: 123) {
            scrollEvent.setIntegerValueField(momField, value: momentumPhase)
        }
        // Field 88 = kCGScrollWheelEventIsContinuous → marks as touch-device.
        if let contField = CGEventField(rawValue: 88) {
            scrollEvent.setIntegerValueField(contField, value: 1)
        }
        scrollEvent.post(tap: .cgSessionEventTap)
    }

    /// Simulates Magic Trackpad inertia by emitting decaying scroll events tagged
    /// with kCGScrollWheelEventMomentumPhase. Decays exponentially until below
    /// 0.5px/frame or 1.2s elapsed.
    private func startMomentumDecay(initialDeltaX: Int16, initialDeltaY: Int16) {
        let absMag = abs(Int(initialDeltaX)) + abs(Int(initialDeltaY))
        // Threshold: only kick off momentum when the lift-off velocity was
        // meaningful. Below ~10px combined the user clearly stopped scrolling
        // already and inertia would feel uncanny.
        guard absMag >= 10 else { return }

        var dx = Float(initialDeltaX)
        var dy = Float(initialDeltaY)
        let decayPerFrame: Float = 0.93     // ~7% drop per frame
        let frameNs: UInt64 = 16_000_000    // ~60Hz
        let maxFrames = 80                  // ~1.3s of momentum

        momentumTask = Task { [weak self] in
            // Began phase.
            do {
                try self?.postScrollEvent(deltaX: Int16(dx), deltaY: Int16(dy), phase: 0, momentumPhase: 1)
            } catch { return }

            for _ in 0..<maxFrames {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: frameNs)
                dx *= decayPerFrame
                dy *= decayPerFrame
                if abs(dx) < 0.5 && abs(dy) < 0.5 { break }
                let cappedX = Int16(dx.rounded().clamped(to: Float(Int16.min)...Float(Int16.max)))
                let cappedY = Int16(dy.rounded().clamped(to: Float(Int16.min)...Float(Int16.max)))
                do {
                    try self?.postScrollEvent(deltaX: cappedX, deltaY: cappedY, phase: 0, momentumPhase: 2)
                } catch { return }
            }

            // Ended phase — zero delta, momentumPhase=ended.
            try? self?.postScrollEvent(deltaX: 0, deltaY: 0, phase: 0, momentumPhase: 4)
        }
    }

    /// Acceleration multiplier for trackpad-mode cursor movement. Tunable —
    /// higher = faster cursor, lower = more precise but laggier feel.
    public var cursorAcceleration: Float = 1.6

    public func injectCursorDelta(deltaX: Int16, deltaY: Int16) throws {
        // Read current cursor position, add scaled delta, post mouseMoved.
        guard let probe = CGEvent(source: nil) else {
            throw InjectorError.eventCreationFailed
        }
        let current = probe.location
        let scaledDx = CGFloat(Float(deltaX) * cursorAcceleration)
        let scaledDy = CGFloat(Float(deltaY) * cursorAcceleration)
        let target = CGPoint(x: current.x + scaledDx, y: current.y + scaledDy)

        guard let moveEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        ) else {
            throw InjectorError.eventCreationFailed
        }
        moveEvent.post(tap: .cgSessionEventTap)
    }

    public func injectZoom(scaleDelta: Float) throws {
        if preferGestureEvent {
            // kCGEventTypeGesture is undocumented; historically raw value 29.
            // Field 113 = gestureType (6 = magnify), field 114 = magnification amount.
            if let gestureEvent = CGEvent(source: eventSource),
               let gestureType = CGEventType(rawValue: 29),
               let gestureTypeField = CGEventField(rawValue: 113),
               let magnificationField = CGEventField(rawValue: 114) {
                gestureEvent.type = gestureType
                gestureEvent.setIntegerValueField(gestureTypeField, value: 6) // magnify
                gestureEvent.setDoubleValueField(magnificationField, value: Double(scaleDelta - 1.0))
                gestureEvent.post(tap: .cgSessionEventTap)
                return
            }
        }

        // Fallback: synthesise Cmd+scroll which apps interpret as zoom.
        // Post flagsChanged (cmd down), a vertical scroll proportional to scaleDelta,
        // then flagsChanged (cmd up) to release the modifier.
        guard let flagsDown = CGEvent(source: eventSource) else {
            throw InjectorError.eventCreationFailed
        }
        flagsDown.type = .flagsChanged
        flagsDown.flags = .maskCommand
        flagsDown.post(tap: .cgSessionEventTap)

        // Per-frame scaleDelta is small (~1.005..1.05). Multiply generously so
        // the resulting Cmd+scroll has perceptible zoom magnitude in apps that
        // use scroll ticks for zoom (Krita, Preview, Affinity, browsers).
        let zoomAmount = Int32((scaleDelta - 1.0) * 80)
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: zoomAmount,
            wheel2: 0,
            wheel3: 0
        ) {
            scrollEvent.post(tap: .cgSessionEventTap)
        }

        guard let flagsUp = CGEvent(source: eventSource) else { return }
        flagsUp.type = .flagsChanged
        flagsUp.flags = []
        flagsUp.post(tap: .cgSessionEventTap)
    }

    // MARK: - Stylus injection

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

        // Track click state for double-click recognition. A leftMouseDown that
        // arrives within 500ms of the previous leftMouseUp should carry
        // clickState=2 (or 3, etc) so macOS treats it as a multi-click.
        let now = DispatchTime.now().uptimeNanoseconds
        switch type {
        case .leftMouseDown:
            let withinWindow = (now - lastLeftClickUpNs) <= Self.doubleClickWindowNs
            lastLeftClickState = withinWindow && lastLeftClickState > 0 ? lastLeftClickState + 1 : 1
            cgEvent.setIntegerValueField(.mouseEventClickState, value: lastLeftClickState)
        case .leftMouseUp:
            cgEvent.setIntegerValueField(.mouseEventClickState, value: lastLeftClickState)
            lastLeftClickUpNs = now
        case .rightMouseDown:
            let withinWindow = (now - lastRightClickUpNs) <= Self.doubleClickWindowNs
            lastRightClickState = withinWindow && lastRightClickState > 0 ? lastRightClickState + 1 : 1
            cgEvent.setIntegerValueField(.mouseEventClickState, value: lastRightClickState)
        case .rightMouseUp:
            cgEvent.setIntegerValueField(.mouseEventClickState, value: lastRightClickState)
            lastRightClickUpNs = now
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
