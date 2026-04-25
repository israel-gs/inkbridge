import CoreGraphics
import Foundation

/// Pure state machine that converts a stream of ``StylusEvent`` into the
/// concrete ``StrokeAction`` values the injector needs to post.
///
/// Rationale: CoreGraphics distinguishes `.mouseMoved`, `.leftMouseDown`,
/// `.leftMouseDragged`, `.leftMouseUp` (and right-button equivalents) as
/// separate event types. Drawing apps (Photoshop, Krita, Affinity, Procreate)
/// only register a stroke when a `Down → Dragged (N times) → Up` sequence
/// arrives — a bare `.mouseMoved` with pressure set is ignored.
///
/// The wire protocol only tells us the current button state per ``StylusEvent/button``,
/// so this state machine infers transitions from consecutive frames and routes
/// ``StylusEvent/move`` appropriately.
public struct StrokeStateMachine {

    public struct ButtonState: Equatable, Sendable {
        public var primaryDown: Bool = false
        public var secondaryDown: Bool = false
        public init(primaryDown: Bool = false, secondaryDown: Bool = false) {
            self.primaryDown = primaryDown
            self.secondaryDown = secondaryDown
        }
    }

    public private(set) var state: ButtonState

    /// Last observed tablet fields, updated on every move event. Attached to
    /// subsequent mouseDown/mouseUp so the initial click of a stroke carries
    /// the real touch pressure — otherwise drawing apps paint a max-pressure
    /// blob at the stroke start.
    public private(set) var lastFields: TabletFields?

    public init(state: ButtonState = ButtonState(), lastFields: TabletFields? = nil) {
        self.state = state
        self.lastFields = lastFields
    }

    /// Processes a single ``StylusEvent`` and returns the ordered list of
    /// ``StrokeAction`` the caller should post to CoreGraphics.
    ///
    /// Pure with respect to the returned value; mutates internal state
    /// so subsequent calls produce transition-aware actions.
    public mutating func process(
        _ event: StylusEvent,
        at point: CGPoint
    ) -> [StrokeAction] {
        switch event {
        case let .move(_, _, pressure, tiltX, tiltY):
            let fields = TabletFields(pressure: pressure, tiltX: tiltX, tiltY: tiltY)
            lastFields = fields
            if state.primaryDown {
                return [.dragged(point: point, button: .left, fields: fields)]
            }
            if state.secondaryDown {
                return [.dragged(point: point, button: .right, fields: fields)]
            }
            return [.moved(point: point, fields: fields)]

        case let .button(buttons):
            let newPrimary = (buttons & 0x08) != 0
            let newSecondary = (buttons & 0x10) != 0

            var actions: [StrokeAction] = []
            if newPrimary != state.primaryDown {
                actions.append(
                    newPrimary
                        ? .mouseDown(point: point, button: .left, fields: lastFields)
                        : .mouseUp(point: point, button: .left, fields: lastFields)
                )
            }
            if newSecondary != state.secondaryDown {
                actions.append(
                    newSecondary
                        ? .mouseDown(point: point, button: .right, fields: lastFields)
                        : .mouseUp(point: point, button: .right, fields: lastFields)
                )
            }
            state.primaryDown = newPrimary
            state.secondaryDown = newSecondary
            return actions

        case let .proximity(entering):
            return [.proximity(entering: entering)]

        case .scroll, .zoom, .cursorDelta:
            // Gesture / trackpad events are handled upstream in InkBridgeServer
            // and do not flow through the stylus state machine. Guard exhaustiveness.
            return []
        }
    }
}

/// One concrete action the injector must execute.
public enum StrokeAction: Equatable, Sendable {
    case moved(point: CGPoint, fields: TabletFields)
    case dragged(point: CGPoint, button: CGMouseButton, fields: TabletFields)
    case mouseDown(point: CGPoint, button: CGMouseButton, fields: TabletFields?)
    case mouseUp(point: CGPoint, button: CGMouseButton, fields: TabletFields?)
    case proximity(entering: Bool)
}

/// Tablet-specific fields carried by move/dragged actions.
public struct TabletFields: Equatable, Sendable {
    public let pressure: UInt16
    public let tiltX: Int16
    public let tiltY: Int16

    public init(pressure: UInt16, tiltX: Int16, tiltY: Int16) {
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
    }
}

extension CGMouseButton: @retroactive @unchecked Sendable {}
