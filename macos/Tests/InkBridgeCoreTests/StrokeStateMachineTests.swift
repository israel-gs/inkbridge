import XCTest
import CoreGraphics
@testable import InkBridgeCore

final class StrokeStateMachineTests: XCTestCase {

    private let p = CGPoint(x: 100, y: 200)

    // MARK: - Move without button

    func testMoveWithoutButtonEmitsMoveOnly() {
        var sm = StrokeStateMachine()
        let actions = sm.process(.move(x: 0.5, y: 0.5, pressure: 32768, tiltX: 0, tiltY: 0), at: p)
        XCTAssertEqual(actions, [
            .moved(point: p, fields: TabletFields(pressure: 32768, tiltX: 0, tiltY: 0)),
        ])
    }

    // MARK: - Primary button down → drag → up

    func testPrimaryStrokeSequence() {
        var sm = StrokeStateMachine()

        // Button down (primary bit = 0x08).
        let down = sm.process(.button(buttons: 0x08), at: p)
        XCTAssertEqual(down, [.mouseDown(point: p, button: .left)])
        XCTAssertTrue(sm.state.primaryDown)

        // Move while down → dragged.
        let mid = CGPoint(x: 150, y: 220)
        let drag1 = sm.process(.move(x: 0.5, y: 0.5, pressure: 10000, tiltX: 0, tiltY: 0), at: mid)
        XCTAssertEqual(drag1, [
            .dragged(point: mid, button: .left, fields: TabletFields(pressure: 10000, tiltX: 0, tiltY: 0)),
        ])

        // Another move while down → dragged again.
        let end = CGPoint(x: 200, y: 240)
        let drag2 = sm.process(.move(x: 0.5, y: 0.5, pressure: 30000, tiltX: 500, tiltY: -500), at: end)
        XCTAssertEqual(drag2, [
            .dragged(point: end, button: .left, fields: TabletFields(pressure: 30000, tiltX: 500, tiltY: -500)),
        ])

        // Button up (bit cleared).
        let up = sm.process(.button(buttons: 0x00), at: end)
        XCTAssertEqual(up, [.mouseUp(point: end, button: .left)])
        XCTAssertFalse(sm.state.primaryDown)

        // After up, move goes back to plain moved.
        let after = CGPoint(x: 220, y: 260)
        let moved = sm.process(.move(x: 0.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0), at: after)
        XCTAssertEqual(moved, [.moved(point: after, fields: TabletFields(pressure: 0, tiltX: 0, tiltY: 0))])
    }

    // MARK: - Repeated button frame with same state emits nothing

    func testRepeatedButtonDownDoesNotEmitDoubleDown() {
        var sm = StrokeStateMachine()
        _ = sm.process(.button(buttons: 0x08), at: p)
        let repeated = sm.process(.button(buttons: 0x08), at: p)
        XCTAssertEqual(repeated, [])
    }

    // MARK: - Secondary button

    func testSecondaryStrokeSequence() {
        var sm = StrokeStateMachine()
        let down = sm.process(.button(buttons: 0x10), at: p)
        XCTAssertEqual(down, [.mouseDown(point: p, button: .right)])

        let drag = sm.process(.move(x: 0.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0), at: p)
        XCTAssertEqual(drag, [
            .dragged(point: p, button: .right, fields: TabletFields(pressure: 0, tiltX: 0, tiltY: 0)),
        ])

        let up = sm.process(.button(buttons: 0x00), at: p)
        XCTAssertEqual(up, [.mouseUp(point: p, button: .right)])
    }

    // MARK: - Simultaneous buttons

    func testBothButtonsDownTogether() {
        var sm = StrokeStateMachine()
        let actions = sm.process(.button(buttons: 0x18), at: p)
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains(.mouseDown(point: p, button: .left)))
        XCTAssertTrue(actions.contains(.mouseDown(point: p, button: .right)))
        XCTAssertTrue(sm.state.primaryDown)
        XCTAssertTrue(sm.state.secondaryDown)
    }

    func testBothButtonsUpTogether() {
        var sm = StrokeStateMachine(state: .init(primaryDown: true, secondaryDown: true))
        let actions = sm.process(.button(buttons: 0x00), at: p)
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains(.mouseUp(point: p, button: .left)))
        XCTAssertTrue(actions.contains(.mouseUp(point: p, button: .right)))
        XCTAssertFalse(sm.state.primaryDown)
        XCTAssertFalse(sm.state.secondaryDown)
    }

    // MARK: - Primary takes precedence over secondary for dragged routing

    func testMoveDuringBothDownRoutesLeftDragged() {
        var sm = StrokeStateMachine(state: .init(primaryDown: true, secondaryDown: true))
        let actions = sm.process(.move(x: 0.5, y: 0.5, pressure: 5000, tiltX: 0, tiltY: 0), at: p)
        XCTAssertEqual(actions, [
            .dragged(point: p, button: .left, fields: TabletFields(pressure: 5000, tiltX: 0, tiltY: 0)),
        ])
    }

    // MARK: - Proximity passthrough

    func testProximityPassthrough() {
        var sm = StrokeStateMachine()
        XCTAssertEqual(sm.process(.proximity(entering: true), at: p), [.proximity(entering: true)])
        XCTAssertEqual(sm.process(.proximity(entering: false), at: p), [.proximity(entering: false)])
    }
}
