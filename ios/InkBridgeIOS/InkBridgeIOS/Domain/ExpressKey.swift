import Foundation

/// Modifier bitmask constants matching the InkBridge wire protocol.
/// Bit 0 = SHIFT, bit 1 = CTRL, bit 2 = ALT/Option, bit 3 = CMD.
/// Source: `protocol/README.md` modifier field definition.
public enum ExpressKeyModifiers {
    public static let shift: UInt8 = 0b0001  // 1
    public static let ctrl:  UInt8 = 0b0010  // 2
    public static let alt:   UInt8 = 0b0100  // 4
    public static let cmd:   UInt8 = 0b1000  // 8
}

/// Whether the Express Key fires a one-shot key combo or holds a modifier for the
/// duration of the button press.
public enum HoldMode: String, Codable, Equatable, Hashable {
    /// Emit KEY_DOWN immediately followed by KEY_UP on tap.
    case oneShot
    /// Emit KEY_DOWN on press; emit KEY_UP on release.
    case modifierHold
}

/// A single Express Key button assignment.
///
/// - `keyCode`: macOS virtual key code (see `MacKeyCodes`).
/// - `modifiers`: bitmask of modifier keys (SHIFT=1, CTRL=2, ALT=4, CMD=8).
/// - `holdMode`: whether the key fires as one-shot or as a held modifier.
public struct ExpressKey: Codable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var label: String
    public var keyCode: UInt8
    public var modifiers: UInt8
    public var holdMode: HoldMode

    public init(id: UUID = UUID(), label: String, keyCode: UInt8, modifiers: UInt8, holdMode: HoldMode) {
        self.id = id
        self.label = label
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.holdMode = holdMode
    }
}
