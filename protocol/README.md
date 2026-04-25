# InkBridge Wire Protocol v1

This directory documents the binary frame format exchanged between the Android client and the macOS server, and provides concrete test vectors for both encoder and decoder implementations.

## Overview

- **Byte order**: little-endian everywhere.
- **Transport**: same frame format over UDP (Wi-Fi) and TCP (USB via `adb reverse`).
- **Version byte**: byte 0 of every frame. Currently `0x01`. Receivers MUST discard frames with an unknown version.
- **No handshake**: the first frame on any connection MUST be a real event frame. There is no HELLO/greeting preamble.

---

## Frame layout

### Fixed header (16 bytes — present in every frame)

| Offset | Size | Type | Field | Description |
|--------|------|------|-------|-------------|
| 0 | 1 | u8 | `version` | Protocol version. MUST be `0x01`. |
| 1 | 1 | u8 | `event_type` | Frame kind. See Event Types below. |
| 2 | 1 | u8 | `flags` | Bitfield. See Flags below. |
| 3 | 1 | u8 | `_reserved` | MUST be `0x00` on send; receiver MUST ignore. |
| 4 | 4 | u32 | `sequence` | LE. Monotonically increasing per session; wraps at 2^32. |
| 8 | 8 | u64 | `timestamp_ns` | LE. Monotonic nanoseconds from Android `System.nanoTime()`. |

### Event types

| Value | Name | Payload size | Total frame |
|-------|------|-------------|-------------|
| `0x01` | `STYLUS_MOVE` | 20 bytes | **36 bytes** |
| `0x02` | `STYLUS_PROXIMITY` | 4 bytes | **20 bytes** |
| `0x03` | `STYLUS_BUTTON` | 4 bytes | **20 bytes** |
| `0x04` | `STYLUS_SCROLL` | 4 bytes | **20 bytes** |
| `0x05` | `STYLUS_ZOOM` | 4 bytes | **20 bytes** |
| `0x06` | `CURSOR_DELTA` | 4 bytes | **20 bytes** |
| `0x07` | `KEY_EVENT` | 4 bytes | **20 bytes** |

All other `event_type` values are reserved. Decoders MUST discard unknown types without crashing.

### Flags byte (offset 2)

| Bit | Name | Meaning when set |
|-----|------|-----------------|
| 0 | `PRESSURE_PRESENT` | `pressure` field carries a real sensor value. |
| 1 | `TILT_PRESENT` | `tilt_x` / `tilt_y` carry real sensor values. |
| 2 | `HOVER` | Stylus hovering (not touching); tip distance > 0. |
| 3 | `BUTTON_PRIMARY` | Primary barrel button pressed. |
| 4 | `BUTTON_SECONDARY` | Secondary barrel button pressed. |
| 5–7 | (reserved) | MUST be `0` on send; receiver MUST ignore. |

---

## STYLUS_MOVE payload (20 bytes, offset 16–35)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 4 | f32 | `x` | Normalized X in [0.0, 1.0] (display width). LE IEEE 754. |
| 4 | 4 | f32 | `y` | Normalized Y in [0.0, 1.0] (display height). LE IEEE 754. |
| 8 | 2 | u16 | `pressure` | [0, 65535]. `round(sensor × 65535)`. 0 when `PRESSURE_PRESENT` clear. |
| 10 | 2 | i16 | `tilt_x` | Degrees × 100, range [−9000, 9000]. 0 when `TILT_PRESENT` clear. |
| 12 | 2 | i16 | `tilt_y` | Degrees × 100, range [−9000, 9000]. 0 when `TILT_PRESENT` clear. |
| 14 | 2 | u16 | `_pad` | MUST be `0x0000`; receiver MUST ignore. |
| 16 | 4 | — | `_reserved` | MUST be `0x00000000`; receiver MUST ignore. |

`x` and `y` MUST be clamped to [0.0, 1.0] before encoding. Values outside this range on the receiver side MUST cause the frame to be discarded.

---

## STYLUS_PROXIMITY payload (4 bytes, offset 16–19)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 1 | u8 | `entering` | `0x01` = entering proximity; `0x00` = leaving. |
| 1 | 3 | — | `_pad` | MUST be `0x000000`; receiver MUST ignore. |

When `entering = 0x01`, the `HOVER` flag (bit 2) MUST be `1`.  
When `entering = 0x00`, the `HOVER` flag MUST be `0`.

---

## STYLUS_BUTTON payload (4 bytes, offset 16–19)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 1 | u8 | `buttons` | Bitfield mirroring bits 3–4 of the header `flags` byte. |
| 1 | 3 | — | `_pad` | MUST be `0x000000`; receiver MUST ignore. |

`buttons` MUST be consistent with bits 3–4 of `flags`. Inconsistency → discard.

---

## KEY_EVENT payload (4 bytes, offset 16–19)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 1 | u8 | `key_code` | macOS virtual keycode (`kVK_*`) for shortcut keys; or `0x00` for modifier-only events. |
| 1 | 1 | u8 | `modifiers` | Bitfield: bit 0 = Cmd, bit 1 = Ctrl, bit 2 = Opt, bit 3 = Shift. Bits 4–7 reserved. |
| 2 | 1 | u8 | `action` | `0x01` = press, `0x02` = release, `0x03` = tap (atomic press+release). |
| 3 | 1 | u8 | `_pad` | MUST be `0x00`; receiver MUST ignore. |

When `key_code == 0x00`, the receiver MUST treat the event as modifier-only and emit a `flagsChanged` event rather than a virtual keycode.

---

## Test vectors

Test vectors are in `test-vectors/`. Each `.hex` file is a single line of uppercase hex pairs separated by spaces, preceded by a `#` comment line describing the frame.

Implementations MUST encode each scenario to the exact byte sequence shown. Decoders MUST round-trip each vector without loss.

| File | Frame type | Key values |
|------|-----------|-----------|
| `move-with-pressure-tilt.hex` | `STYLUS_MOVE` | x=0.5, y=0.25, pressure=49151 (~75%), tilt_x=45.00°, tilt_y=-18.00°, seq=42 |
| `proximity-enter.hex` | `STYLUS_PROXIMITY` | entering=1, HOVER flag set, seq=0 |
| `proximity-exit.hex` | `STYLUS_PROXIMITY` | entering=0, HOVER flag clear, seq=1 |
| `button-press.hex` | `STYLUS_BUTTON` | BUTTON_PRIMARY flag set, buttons=0x08, seq=2 |

See `test-vectors/` for the byte sequences.

### Vector mirrors

`macos/Tests/InkBridgeCoreTests/Vectors/` is a copy of the four `.hex` files above, embedded in
the Swift test bundle (SPM `.copy("Vectors")` resource rule). If you edit the canonical vectors
here, re-copy them there manually — Swift Package Manager embeds resources at build time.

The Android Gradle `copyProtocolVectors` task in `android/app/build.gradle.kts` copies the
canonical vectors automatically before `./gradlew test` runs — no manual step needed there.
