# Spec: KEY_EVENT wire frame

## R1. Frame layout

A `KEY_EVENT` frame is **20 bytes** total: the standard 16-byte header plus a 4-byte payload.

### Header

`event_type` (offset 1) MUST be `0x07`. Other header fields follow the existing rules.

### Payload (4 bytes, offset 16–19)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 1 | u8 | `key_code` | macOS virtual keycode (kVK_*) for shortcut keys; or one of the `MODIFIER_*` reserved values for modifier-hold (see R3). |
| 1 | 1 | u8 | `modifiers` | Bitfield: bit 0 = Cmd, bit 1 = Ctrl, bit 2 = Opt, bit 3 = Shift. Bits 4–7 reserved (MUST be 0). |
| 2 | 1 | u8 | `action` | `0x01` = press, `0x02` = release, `0x03` = tap (atomic press+release). |
| 3 | 1 | u8 | `_pad` | MUST be `0x00`; receiver MUST ignore. |

## R2. Action semantics

- `0x01` press: receiver MUST emit `keyDown=true` (and apply the modifier flags). The key remains "down" until a matching release arrives or the source disconnects.
- `0x02` release: receiver MUST emit `keyDown=false`. Idempotent — releasing an already-released key is a no-op.
- `0x03` tap: receiver MUST emit press immediately followed by release as a single logical action.

## R3. Modifier-only events

Senders that want to hold a modifier (`Ctrl` for color picker etc.) without an associated key MUST use `key_code = 0x00` with the modifier bit set in `modifiers`. Receivers MUST treat `key_code == 0x00` as "modifier-only" and MUST emit a `flagsChanged` event with the modifier flags asserted (press) or cleared (release) rather than a virtual keycode.

## R4. Unknown reception

Receivers running an older protocol version MUST discard `KEY_EVENT 0x07` frames silently per the existing rule for unknown `event_type`. A discard counter MAY be incremented for diagnostics.

## R5. Modifier bitfield consistency

The `modifiers` byte MUST be applied to the keyDown event posted for the press (or to both press and release for non-modifier keys, so the OS sees the modifier as "held during the keystroke"). For modifier-only events (R3), the bitfield IS the payload meaning — `key_code` is `0x00` and the receiver MUST translate the bitfield into a `flagsChanged` event.

## Scenarios

### Tap of `Cmd+Z` (Undo)

**Given** the user taps Slot 2 configured as Shortcut(Cmd+Z)  
**When** the Android app emits a `KEY_EVENT` frame with `key_code = kVK_ANSI_Z (0x06)`, `modifiers = 0x01`, `action = 0x03`  
**Then** the Mac MUST post a `kCGEventKeyDown` for vKZ with `flags = .maskCommand`, immediately followed by a `kCGEventKeyUp` for vKZ.

### Hold of Ctrl

**Given** the user touches Slot 1 configured as ModifierHold(Ctrl)  
**When** the Android app emits a `KEY_EVENT` frame with `key_code = 0x00`, `modifiers = 0x02`, `action = 0x01`  
**Then** the Mac MUST post a `kCGEventFlagsChanged` event with `flags = .maskControl`.

**When** the finger leaves the slot the Android app emits a `KEY_EVENT` frame with `key_code = 0x00`, `modifiers = 0x02`, `action = 0x02`  
**Then** the Mac MUST post a `kCGEventFlagsChanged` event with `flags = []`.

### Round-trip via test vector

**Given** the canonical vector `key-event.hex` containing a Cmd+Z tap  
**When** an encoder produces the same byte sequence  
**Then** the bytes MUST be byte-identical.

**When** a decoder consumes the byte sequence  
**Then** it MUST produce a `KeyEvent(keyCode: 0x06, modifiers: 0x01, action: .tap)`.
