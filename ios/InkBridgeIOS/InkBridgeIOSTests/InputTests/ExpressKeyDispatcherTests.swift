import XCTest
@testable import InkBridgeIOS

final class ExpressKeyDispatcherTests: XCTestCase {

    // MARK: - One-shot (HoldMode.oneShot)

    /// Tapping a one-shot key emits KEY_DOWN followed by KEY_UP atomically.
    func test_oneShot_press_emitsDownThenUp() {
        let key = ExpressKey(label: "Undo", keyCode: 0x06, modifiers: ExpressKeyModifiers.cmd, holdMode: .oneShot)
        let events = ExpressKeyDispatcher.events(for: key, phase: .pressed)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], .keyEvent(keyCode: 0x06, modifiers: ExpressKeyModifiers.cmd, action: .down))
        XCTAssertEqual(events[1], .keyEvent(keyCode: 0x06, modifiers: ExpressKeyModifiers.cmd, action: .up))
    }

    /// One-shot keys do nothing on release (the event is self-contained on press).
    func test_oneShot_release_emitsNothing() {
        let key = ExpressKey(label: "Undo", keyCode: 0x06, modifiers: ExpressKeyModifiers.cmd, holdMode: .oneShot)
        let events = ExpressKeyDispatcher.events(for: key, phase: .released)

        XCTAssertTrue(events.isEmpty, "One-shot key should emit nothing on release")
    }

    // MARK: - Modifier-hold (HoldMode.modifierHold)

    /// Pressing a modifier-hold key sends KEY_DOWN only.
    func test_modifierHold_press_emitsKeyDown() {
        let key = ExpressKey(label: "Ctrl", keyCode: 0x00, modifiers: ExpressKeyModifiers.ctrl, holdMode: .modifierHold)
        let events = ExpressKeyDispatcher.events(for: key, phase: .pressed)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .keyEvent(keyCode: 0x00, modifiers: ExpressKeyModifiers.ctrl, action: .down))
    }

    /// Releasing a modifier-hold key sends KEY_UP only.
    func test_modifierHold_release_emitsKeyUp() {
        let key = ExpressKey(label: "Ctrl", keyCode: 0x00, modifiers: ExpressKeyModifiers.ctrl, holdMode: .modifierHold)
        let events = ExpressKeyDispatcher.events(for: key, phase: .released)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .keyEvent(keyCode: 0x00, modifiers: ExpressKeyModifiers.ctrl, action: .up))
    }

    /// Modifier-hold with non-zero keyCode also emits DOWN/UP on the keyCode.
    func test_modifierHold_withKeyCode_press_emitsKeyDown() {
        // Space-hold (Pan) — keyCode 0x31, no modifier
        let key = ExpressKey(label: "Pan", keyCode: 0x31, modifiers: 0, holdMode: .modifierHold)
        let events = ExpressKeyDispatcher.events(for: key, phase: .pressed)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .keyEvent(keyCode: 0x31, modifiers: 0x00, action: .down))
    }

    func test_modifierHold_withKeyCode_release_emitsKeyUp() {
        let key = ExpressKey(label: "Pan", keyCode: 0x31, modifiers: 0, holdMode: .modifierHold)
        let events = ExpressKeyDispatcher.events(for: key, phase: .released)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .keyEvent(keyCode: 0x31, modifiers: 0x00, action: .up))
    }

    // MARK: - Nil slot (unassigned)

    func test_nilSlot_press_emitsNothing() {
        let events = ExpressKeyDispatcher.events(for: nil, phase: .pressed)
        XCTAssertTrue(events.isEmpty, "Unassigned slot should emit no events on press")
    }

    func test_nilSlot_release_emitsNothing() {
        let events = ExpressKeyDispatcher.events(for: nil, phase: .released)
        XCTAssertTrue(events.isEmpty, "Unassigned slot should emit no events on release")
    }

    // MARK: - Zero-assignment slot (keyCode 0, modifiers 0, oneShot)

    /// A slot assigned as "empty" (keyCode=0, mods=0) should still emit events —
    /// it is a valid (if no-op on the Mac) key assignment, NOT equivalent to nil.
    func test_zeroAssignment_oneShot_press_emitsDownUp() {
        let key = ExpressKey(label: "", keyCode: 0, modifiers: 0, holdMode: .oneShot)
        let events = ExpressKeyDispatcher.events(for: key, phase: .pressed)
        XCTAssertEqual(events.count, 2)
    }
}
