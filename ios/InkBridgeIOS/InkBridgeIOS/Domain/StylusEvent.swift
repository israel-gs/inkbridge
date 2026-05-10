/// StylusEvent — the sum type of events the iOS client can emit to the Mac server.
///
/// Only the 6 event types valid for a phone client are represented here.
/// STYLUS_MOVE (0x01) and STYLUS_PROXIMITY (0x02) are intentionally absent:
/// the iPhone has no stylus, pen digitizer, or pressure sensor. Emitting those
/// event codes would violate the wire protocol contract (server ignores them, but
/// it would be misleading). See `protocol/README.md` for the full type table.
public enum StylusEvent: Equatable, Hashable {
    /// CURSOR_DELTA (0x06) — moves the macOS cursor by (dx, dy) in points.
    /// Values are Int16 and clamped to ±32767 before encoding.
    case cursorDelta(dx: Int16, dy: Int16)

    /// STYLUS_BUTTON (0x03) — mouse button event.
    /// `buttons` is a bitmask (bit 0 = left, bit 1 = right).
    /// `primaryDown` is true when the primary (left) button transitions to pressed.
    case stylusButton(buttons: UInt8, primaryDown: Bool)

    /// STYLUS_SCROLL (0x04) — 2-finger scroll gesture delta.
    /// `deltaX`/`deltaY` in points. `phase` mirrors CGScrollPhase raw values.
    case stylusScroll(deltaX: Float, deltaY: Float, phase: UInt8)

    /// STYLUS_ZOOM (0x05) — 2-finger pinch/spread gesture.
    /// `magnification` is a signed scale delta (positive = zoom in).
    /// `phase` mirrors CGGesturePhase raw values.
    case stylusZoom(magnification: Float, phase: UInt8)

    /// KEY_EVENT (0x07) — keyboard shortcut event.
    /// `keyCode` is a macOS virtual key code (see `MacKeyCodes`).
    /// `modifiers` is a bitmask per protocol: SHIFT=1, CTRL=2, ALT=4, CMD=8.
    /// `action` is `.down` or `.up`.
    case keyEvent(keyCode: UInt8, modifiers: UInt8, action: KeyAction)

    /// CAPTURE_REQUEST (0x08) — requests the server to capture the next key combo
    /// and assign it to the given Express Key slot index.
    case captureRequest(slot: UInt8)
}

/// The direction of a key event.
///
/// Raw values match the wire protocol (protocol/README.md §KEY_EVENT):
///   0x01 = press, 0x02 = release, 0x03 = tap (atomic press+release).
/// Note: 0x00 is not a valid action. Encoders must never emit 0x00 here.
public enum KeyAction: UInt8, Equatable, Hashable {
    case down = 1
    case up   = 2
    /// Atomic press+release in a single frame. Used for shortcut keys.
    case tap  = 3
}
