import XCTest
@testable import InkBridgeIOS

final class ExpressKeyTests: XCTestCase {

    // MARK: - Modifier bitmask constants

    func testModifierBitmaskShift() {
        XCTAssertEqual(ExpressKeyModifiers.shift, UInt8(1))
    }

    func testModifierBitmaskCtrl() {
        XCTAssertEqual(ExpressKeyModifiers.ctrl, UInt8(2))
    }

    func testModifierBitmaskAlt() {
        XCTAssertEqual(ExpressKeyModifiers.alt, UInt8(4))
    }

    func testModifierBitmaskCmd() {
        XCTAssertEqual(ExpressKeyModifiers.cmd, UInt8(8))
    }

    func testCmdPlusShiftBitmask() {
        let combined = ExpressKeyModifiers.cmd | ExpressKeyModifiers.shift
        XCTAssertEqual(combined, UInt8(9))
    }

    // MARK: - HoldMode raw values

    func testHoldModeOneShotRawValue() {
        XCTAssertEqual(HoldMode.oneShot.rawValue, "oneShot")
    }

    func testHoldModeModifierHoldRawValue() {
        XCTAssertEqual(HoldMode.modifierHold.rawValue, "modifierHold")
    }

    // MARK: - ExpressKey equality

    func testExpressKeyEqualityOnAllFields() {
        let id = UUID()
        let a = ExpressKey(id: id, label: "Undo", keyCode: 6, modifiers: 8, holdMode: .oneShot)
        let b = ExpressKey(id: id, label: "Undo", keyCode: 6, modifiers: 8, holdMode: .oneShot)
        XCTAssertEqual(a, b)
    }

    func testExpressKeyInequalityOnKeyCode() {
        let id = UUID()
        let a = ExpressKey(id: id, label: "Undo", keyCode: 6, modifiers: 8, holdMode: .oneShot)
        let b = ExpressKey(id: id, label: "Undo", keyCode: 7, modifiers: 8, holdMode: .oneShot)
        XCTAssertNotEqual(a, b)
    }

    func testExpressKeyInequalityOnModifiers() {
        let id = UUID()
        let a = ExpressKey(id: id, label: "Copy", keyCode: 8, modifiers: 8, holdMode: .oneShot)
        let b = ExpressKey(id: id, label: "Copy", keyCode: 8, modifiers: 0, holdMode: .oneShot)
        XCTAssertNotEqual(a, b)
    }

    func testExpressKeyInequalityOnHoldMode() {
        let id = UUID()
        let a = ExpressKey(id: id, label: "Shift", keyCode: 0, modifiers: 1, holdMode: .oneShot)
        let b = ExpressKey(id: id, label: "Shift", keyCode: 0, modifiers: 1, holdMode: .modifierHold)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ExpressKey Codable round-trip

    func testExpressKeyCodableRoundTrip() throws {
        let original = ExpressKey(id: UUID(), label: "Undo", keyCode: 6, modifiers: 8, holdMode: .oneShot)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExpressKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - ExpressKeyProfile

    func testProfileHasExactlySixSlots() {
        let profile = ExpressKeyProfile.makeDefault()
        XCTAssertEqual(profile.keys.count, 6)
    }

    func testProfileCodableRoundTrip() throws {
        let profile = ExpressKeyProfile(id: UUID(), name: "Test", keys: [
            ExpressKey(id: UUID(), label: "Undo", keyCode: 6, modifiers: 8, holdMode: .oneShot),
            ExpressKey(id: UUID(), label: "Copy", keyCode: 8, modifiers: 8, holdMode: .oneShot),
            ExpressKey(id: UUID(), label: "Paste", keyCode: 9, modifiers: 8, holdMode: .oneShot),
            ExpressKey(id: UUID(), label: "Save", keyCode: 1, modifiers: 8, holdMode: .oneShot),
            ExpressKey(id: UUID(), label: "Shift", keyCode: 0, modifiers: 1, holdMode: .modifierHold),
            ExpressKey(id: UUID(), label: "Cmd", keyCode: 0, modifiers: 8, holdMode: .modifierHold),
        ])
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ExpressKeyProfile.self, from: data)
        XCTAssertEqual(profile, decoded)
        XCTAssertEqual(decoded.keys.count, 6)
    }

    func testProfileEqualityOnIdAndName() {
        let id = UUID()
        let a = ExpressKeyProfile(id: id, name: "A", keys: [])
        let b = ExpressKeyProfile(id: id, name: "A", keys: [])
        XCTAssertEqual(a, b)
    }

    func testProfileInequalityOnName() {
        let id = UUID()
        let a = ExpressKeyProfile(id: id, name: "A", keys: [])
        let b = ExpressKeyProfile(id: id, name: "B", keys: [])
        XCTAssertNotEqual(a, b)
    }
}
