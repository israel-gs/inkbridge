import XCTest
@testable import InkBridgeIOS

final class StylusEventTests: XCTestCase {

    // MARK: - Variant existence

    func testCursorDeltaVariantExists() {
        let event = StylusEvent.cursorDelta(dx: 10, dy: -3)
        if case .cursorDelta(let dx, let dy) = event {
            XCTAssertEqual(dx, 10)
            XCTAssertEqual(dy, -3)
        } else {
            XCTFail("Expected .cursorDelta")
        }
    }

    func testStylusButtonVariantExists() {
        let event = StylusEvent.stylusButton(buttons: 0x01, primaryDown: true)
        if case .stylusButton(let buttons, let primaryDown) = event {
            XCTAssertEqual(buttons, 0x01)
            XCTAssertTrue(primaryDown)
        } else {
            XCTFail("Expected .stylusButton")
        }
    }

    func testStylusScrollVariantExists() {
        let event = StylusEvent.stylusScroll(deltaX: 5, deltaY: -2, phase: 1)
        if case .stylusScroll(let dx, let dy, let phase) = event {
            XCTAssertEqual(dx, 5)
            XCTAssertEqual(dy, -2)
            XCTAssertEqual(phase, 1)
        } else {
            XCTFail("Expected .stylusScroll")
        }
    }

    func testStylusZoomVariantExists() {
        let event = StylusEvent.stylusZoom(magnification: 0.5, phase: 0)
        if case .stylusZoom(let mag, let phase) = event {
            XCTAssertEqual(mag, 0.5, accuracy: 0.001)
            XCTAssertEqual(phase, 0)
        } else {
            XCTFail("Expected .stylusZoom")
        }
    }

    func testKeyEventVariantExists() {
        let event = StylusEvent.keyEvent(keyCode: 6, modifiers: 0x08, action: .down)
        if case .keyEvent(let code, let mods, let action) = event {
            XCTAssertEqual(code, 6)
            XCTAssertEqual(mods, 0x08)
            XCTAssertEqual(action, .down)
        } else {
            XCTFail("Expected .keyEvent")
        }
    }

    func testCaptureRequestVariantExists() {
        let event = StylusEvent.captureRequest(slot: 2)
        if case .captureRequest(let slot) = event {
            XCTAssertEqual(slot, 2)
        } else {
            XCTFail("Expected .captureRequest")
        }
    }

    // MARK: - No forbidden variants

    /// Verifies that STYLUS_MOVE (0x01) and STYLUS_PROXIMITY (0x02) are NOT representable
    /// as StylusEvent variants. This test uses an exhaustive switch so it fails to compile
    /// if a new variant is added without handling it here.
    func testExhaustiveSwitchCompiles_noDefaultNeeded() {
        let event = StylusEvent.cursorDelta(dx: 0, dy: 0)
        // This switch must be exhaustive without a `default` case.
        // If a new variant is added, the compiler will error here — catching accidental additions.
        switch event {
        case .cursorDelta:
            break
        case .stylusButton:
            break
        case .stylusScroll:
            break
        case .stylusZoom:
            break
        case .keyEvent:
            break
        case .captureRequest:
            break
        }
    }

    // MARK: - Equatable

    func testEqualityForCursorDelta() {
        XCTAssertEqual(
            StylusEvent.cursorDelta(dx: 5, dy: -2),
            StylusEvent.cursorDelta(dx: 5, dy: -2)
        )
        XCTAssertNotEqual(
            StylusEvent.cursorDelta(dx: 5, dy: -2),
            StylusEvent.cursorDelta(dx: 5, dy: 0)
        )
    }

    func testEqualityForStylusButton() {
        XCTAssertEqual(
            StylusEvent.stylusButton(buttons: 1, primaryDown: true),
            StylusEvent.stylusButton(buttons: 1, primaryDown: true)
        )
        XCTAssertNotEqual(
            StylusEvent.stylusButton(buttons: 1, primaryDown: true),
            StylusEvent.stylusButton(buttons: 1, primaryDown: false)
        )
    }

    func testEqualityForKeyEvent() {
        XCTAssertEqual(
            StylusEvent.keyEvent(keyCode: 6, modifiers: 8, action: .down),
            StylusEvent.keyEvent(keyCode: 6, modifiers: 8, action: .down)
        )
        XCTAssertNotEqual(
            StylusEvent.keyEvent(keyCode: 6, modifiers: 8, action: .down),
            StylusEvent.keyEvent(keyCode: 6, modifiers: 8, action: .up)
        )
    }

    func testEqualityForCaptureRequest() {
        XCTAssertEqual(
            StylusEvent.captureRequest(slot: 1),
            StylusEvent.captureRequest(slot: 1)
        )
        XCTAssertNotEqual(
            StylusEvent.captureRequest(slot: 1),
            StylusEvent.captureRequest(slot: 2)
        )
    }

    func testCrossVariantInequality() {
        XCTAssertNotEqual(
            StylusEvent.cursorDelta(dx: 0, dy: 0),
            StylusEvent.captureRequest(slot: 0)
        )
    }

    // MARK: - Hashable

    func testHashableConformance() {
        var set = Set<StylusEvent>()
        set.insert(.cursorDelta(dx: 1, dy: 2))
        set.insert(.cursorDelta(dx: 1, dy: 2))
        XCTAssertEqual(set.count, 1)
        set.insert(.captureRequest(slot: 0))
        XCTAssertEqual(set.count, 2)
    }
}
