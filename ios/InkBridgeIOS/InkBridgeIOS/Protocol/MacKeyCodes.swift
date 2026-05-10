/// macOS Carbon-era virtual keycodes (kVK_* from HIToolbox/Events.h).
///
/// Ported from `android/app/src/main/kotlin/com/inkbridge/protocol/MacKeyCodes.kt`.
/// The mapping is position-based (not character-based): macOS apps register shortcuts
/// by virtual keycode regardless of the active keyboard layout for letter/number keys.
///
/// On iOS these codes appear in ``StylusEvent.keyEvent`` payloads emitted by Express Keys.
/// The wire format carries the `kVK_*` value in byte 16 of the KEY_EVENT frame.
///
/// No tests required for this file (pure static data). See tasks.md B.7.
public enum MacKeyCodes {

    // MARK: - Name → Code

    /// Maps a human-readable key name to its macOS virtual keycode.
    /// Keys include letters (uppercase), digits, punctuation names, and special keys.
    public static let nameToCode: [String: UInt8] = [
        // Letters (kVK_ANSI_*)
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04,
        "G": 0x05, "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09,
        "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F,
        "Y": 0x10, "T": 0x11, "O": 0x1F, "U": 0x20, "I": 0x22,
        "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28, "N": 0x2D,
        "M": 0x2E,

        // Digits row (kVK_ANSI_*)
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16,
        "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B,
        "8": 0x1C, "0": 0x1D,

        // Punctuation
        "]": 0x1E, "[": 0x21, "'": 0x27, ";": 0x29, "\\": 0x2A,
        ",": 0x2B, "/": 0x2C, ".": 0x2F, "`": 0x32,

        // Whitespace / editing
        "Return":    0x24,
        "Tab":       0x30,
        "Space":     0x31,
        "Backspace": 0x33, // kVK_Delete
        "Delete":    0x75, // kVK_ForwardDelete
        "Escape":    0x35,

        // Arrow keys
        "Left":  0x7B,
        "Right": 0x7C,
        "Down":  0x7D,
        "Up":    0x7E,

        // Function keys
        "F1":  0x7A, "F2":  0x78, "F3":  0x63, "F4":  0x76,
        "F5":  0x60, "F6":  0x61, "F7":  0x62, "F8":  0x64,
        "F9":  0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
    ]

    // MARK: - Code → Name (for debugging / label generation)

    /// Inverse map: macOS virtual keycode → printable key name.
    /// Used to auto-generate Express Key labels and for debug descriptions.
    public static let codeToName: [UInt8: String] = {
        var inverse = [UInt8: String]()
        for (name, code) in nameToCode {
            inverse[code] = name
        }
        return inverse
    }()

    // MARK: - Lookup helpers

    /// Returns the macOS virtual keycode for a named key, or `nil` if unsupported.
    public static func code(for name: String) -> UInt8? {
        nameToCode[name]
    }

    /// Returns a printable name for a macOS virtual keycode, or a hex fallback.
    public static func name(for code: UInt8) -> String {
        codeToName[code] ?? String(format: "0x%02X", code)
    }
}

// MARK: - Wire-format modifier bitmask constants

/// Modifier key bitmask values as used in the KEY_EVENT wire payload (byte 17).
/// Bit layout: bit 0 = Cmd, bit 1 = Ctrl, bit 2 = Opt, bit 3 = Shift.
///
/// Protocol reference: `protocol/README.md §KEY_EVENT payload`.
public enum KeyModifier {
    public static let cmd:   UInt8 = 0x01
    public static let ctrl:  UInt8 = 0x02
    public static let opt:   UInt8 = 0x04
    public static let shift: UInt8 = 0x08
}
