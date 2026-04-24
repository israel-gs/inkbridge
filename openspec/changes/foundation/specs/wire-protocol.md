# Spec: Wire Protocol

## Purpose

Defines the binary frame format used to transmit stylus events from the Android client to the macOS server. All frames share a fixed-length header followed by a payload whose size is determined by the event type. The format is version-stamped, little-endian, and transport-agnostic: the identical byte sequence travels over UDP (Wi-Fi) and TCP (USB). The wire format is the contract between `android/data/` (codec) and `macos/transport/` (decoder); changes to this spec constitute a breaking change and MUST increment the version byte.

---

## Requirements

### R1. Byte Order

All multi-byte integer fields MUST be encoded in little-endian byte order.

#### Scenario: multi-byte field encoding
- **Given** a 64-bit timestamp value of `0x0000_0001_DCD6_5000` (8,000,000,000 ns)
- **When** the field is serialized to wire bytes
- **Then** the 8 bytes on the wire MUST be `00 50 D6 DC 01 00 00 00` (LSB first)

---

### R2. Version Byte Position

The first byte of every frame MUST be the protocol version byte. No other data MAY precede it.

#### Scenario: version byte is byte zero
- **Given** any valid inkbridge frame
- **When** the macOS decoder reads offset 0
- **Then** the value MUST be the protocol version in use (currently `0x01`)

#### Scenario: version mismatch detection
- **Given** a frame arrives with version byte `0x02` and the server only knows version `0x01`
- **When** the server reads byte 0
- **Then** the server MUST discard the frame and MUST NOT attempt to inject an event from it

---

### R3. Fixed Header Layout

Every frame MUST begin with a 16-byte fixed header laid out as follows:

| Offset | Size (bytes) | Type   | Field          | Description                                                                      |
|--------|-------------|--------|----------------|----------------------------------------------------------------------------------|
| 0      | 1           | u8     | `version`      | Protocol version. Currently `0x01`.                                              |
| 1      | 1           | u8     | `event_type`   | Identifies payload kind. See Event Type Enum (R4).                               |
| 2      | 1           | u8     | `flags`        | Bitfield. See Flags (R5).                                                        |
| 3      | 1           | u8     | `_reserved`    | MUST be `0x00` on send; receivers MUST ignore this byte.                        |
| 4      | 4           | u32    | `sequence`     | Monotonically increasing per-session counter, wraps at 2^32. Little-endian.     |
| 8      | 8           | u64    | `timestamp_ns` | Monotonic nanosecond timestamp from the Android device. Little-endian.           |

Total header size: **16 bytes**.

#### Scenario: header fields are contiguous with no padding
- **Given** a serialized frame
- **When** the encoder writes the fixed header
- **Then** bytes 0–15 MUST be exactly the 16 fields above with no inserted padding bytes

---

### R4. Event Type Enum

The `event_type` byte at offset 1 MUST be one of the following values. All other values are reserved and MUST be treated as an unknown frame (discarded).

| Value | Name              | Description                                               |
|-------|-------------------|-----------------------------------------------------------|
| `0x01`| `STYLUS_MOVE`     | Stylus tip touching or hovering with position data.       |
| `0x02`| `STYLUS_PROXIMITY`| Stylus entered or left the proximity zone.                |
| `0x03`| `STYLUS_BUTTON`   | Button state changed without movement.                    |

#### Scenario: unknown event_type is discarded
- **Given** a frame arrives with `event_type = 0xFF`
- **When** the decoder processes it
- **Then** the decoder MUST discard the frame without injecting any event and MUST NOT crash

---

### R5. Flags Bitfield

The `flags` byte at offset 2 is a bitfield. Bits are numbered 0 (LSB) to 7 (MSB).

| Bit | Name              | Meaning when set                                                    |
|-----|-------------------|---------------------------------------------------------------------|
| 0   | `PRESSURE_PRESENT`| The `pressure` payload field carries a real sensor value (not 0).  |
| 1   | `TILT_PRESENT`    | The `tilt_x` / `tilt_y` payload fields carry real sensor values.   |
| 2   | `HOVER`           | Stylus is hovering (not touching); tip distance > 0.               |
| 3   | `BUTTON_PRIMARY`  | Primary barrel button is pressed.                                   |
| 4   | `BUTTON_SECONDARY`| Secondary barrel button is pressed.                                 |
| 5–7 | (reserved)        | MUST be `0` on send; receivers MUST ignore these bits.             |

#### Scenario: device without pressure sensor
- **Given** an Android device where `MotionEvent.AXIS_PRESSURE` always returns `0.0`
- **When** the encoder builds the flags byte
- **Then** bit 0 (`PRESSURE_PRESENT`) MUST be `0` and the `pressure` field MUST be `0x0000`

#### Scenario: hover flag
- **Given** the stylus is detected in the proximity zone but not touching the screen
- **When** the encoder emits a `STYLUS_MOVE` frame
- **Then** bit 2 (`HOVER`) MUST be `1` in the flags byte

---

### R6. STYLUS_MOVE Payload

When `event_type == 0x01`, the payload immediately following the 16-byte header MUST be 20 bytes:

| Offset (from payload start) | Size | Type  | Field      | Description                                                       |
|-----------------------------|------|-------|------------|-------------------------------------------------------------------|
| 0                           | 4    | f32   | `x`        | Normalized X position in [0.0, 1.0] relative to display width.   |
| 4                           | 4    | f32   | `y`        | Normalized Y position in [0.0, 1.0] relative to display height.  |
| 8                           | 2    | u16   | `pressure` | Pressure in range [0, 65535]. 0 when `PRESSURE_PRESENT` is clear.|
| 10                          | 2    | i16   | `tilt_x`   | Tilt around X axis, degrees × 100, range [−9000, 9000]. 0 when `TILT_PRESENT` is clear. |
| 12                          | 2    | i16   | `tilt_y`   | Tilt around Y axis, degrees × 100, range [−9000, 9000]. 0 when `TILT_PRESENT` is clear. |
| 14                          | 2    | u16   | `_pad`     | MUST be `0x0000`; receiver MUST ignore.                           |
| 16                          | 4    | (none)| `_reserved`| MUST be `0x00000000`; receiver MUST ignore.                       |

Total frame size for `STYLUS_MOVE`: **16 (header) + 20 (payload) = 36 bytes**.

`x` and `y` MUST be clamped to [0.0, 1.0] before encoding. Values outside this range on the receiving side MUST be treated as malformed and the frame discarded.

#### Scenario: normalized coordinates
- **Given** a touch at pixel (540, 1200) on a 1080×2400 screen
- **When** the Android encoder serializes the position
- **Then** `x = 0.5` (encoded as IEEE 754 little-endian f32 `00 00 00 3F`) and `y = 0.5` (same encoding)

#### Scenario: pressure encoding
- **Given** the sensor reports pressure `0.75` (MotionEvent normalized 0–1)
- **When** the encoder converts pressure to u16
- **Then** the encoded value MUST be `round(0.75 × 65535) = 49151 = 0xBFFF`, little-endian bytes `FF BF`

---

### R7. STYLUS_PROXIMITY Payload

When `event_type == 0x02`, the payload immediately following the 16-byte header MUST be 4 bytes:

| Offset (from payload start) | Size | Type | Field      | Description                              |
|-----------------------------|------|------|------------|------------------------------------------|
| 0                           | 1    | u8   | `entering` | `0x01` = entering proximity; `0x00` = leaving proximity. |
| 1                           | 3    | —    | `_pad`     | MUST be `0x000000`; receiver MUST ignore.|

Total frame size for `STYLUS_PROXIMITY`: **16 (header) + 4 (payload) = 20 bytes**.

#### Scenario: proximity enter
- **Given** the stylus moves close enough to the screen to trigger MotionEvent ACTION_HOVER_ENTER
- **When** the encoder builds the frame
- **Then** `event_type = 0x02`, `entering = 0x01`, `HOVER` flag (bit 2) MUST be `1`

#### Scenario: proximity exit
- **Given** the stylus is lifted beyond the sensor range (ACTION_HOVER_EXIT)
- **When** the encoder builds the frame
- **Then** `event_type = 0x02`, `entering = 0x00`, `HOVER` flag MUST be `0`

---

### R8. STYLUS_BUTTON Payload

When `event_type == 0x03`, the payload immediately following the 16-byte header MUST be 4 bytes:

| Offset (from payload start) | Size | Type | Field      | Description                                        |
|-----------------------------|------|------|------------|----------------------------------------------------|
| 0                           | 1    | u8   | `buttons`  | Bitfield mirroring bits 3–4 of the header `flags`. |
| 1                           | 3    | —    | `_pad`     | MUST be `0x000000`; receiver MUST ignore.          |

Total frame size for `STYLUS_BUTTON`: **16 (header) + 4 (payload) = 20 bytes**.

The `buttons` field in the payload MUST be consistent with bits 3–4 of the `flags` byte in the same frame's header. If they differ, the receiver MUST discard the frame.

---

### R9. Sequence Number

The `sequence` field (offset 4, u32) MUST be:
- Set to `0` for the first frame of a session.
- Incremented by 1 for every subsequent frame sent in the same session.
- Reset to `0` when a new transport connection is established.

The receiver MUST use the sequence number to detect out-of-order delivery. When a frame arrives with a sequence number strictly less than the last accepted sequence number, the receiver MUST discard it.

#### Scenario: out-of-order discard on UDP
- **Given** frames with sequence numbers 10, 12, 11 arrive in that order
- **When** the decoder processes frame with sequence 11 (after already accepting 12)
- **Then** the decoder MUST discard frame 11 and MUST NOT inject its event

#### Scenario: sequence wrap
- **Given** the sequence counter is at `0xFFFFFFFF`
- **When** the next frame is sent
- **Then** the sequence field MUST be `0x00000000` and the receiver MUST treat it as the successor to `0xFFFFFFFF`

---

### R10. Worked Example — STYLUS_MOVE Frame (Hex Dump)

Concrete values:
- Version: `1`
- Event type: `STYLUS_MOVE` (`0x01`)
- Flags: `PRESSURE_PRESENT` + `TILT_PRESENT` = bits 0 and 1 set = `0x03`
- Reserved: `0x00`
- Sequence: `42` = `0x0000002A`
- Timestamp: `8,000,000,000 ns` = `0x00000001DCD65000`
- x: `0.5` (IEEE 754 f32 LE = `00 00 00 3F`)
- y: `0.25` (IEEE 754 f32 LE = `00 00 80 3E`)
- pressure: `49151` = `0xBFFF`
- tilt_x: `4500` (45.00°) = `0x1194`
- tilt_y: `-1800` (-18.00°) = `0xF8F8`
- pad: `0x0000`
- reserved: `0x00000000`

```
Offset  Hex                                          Field
------  -------------------------------------------  -----
00      01                                           version = 1
01      01                                           event_type = STYLUS_MOVE
02      03                                           flags = PRESSURE_PRESENT | TILT_PRESENT
03      00                                           _reserved
04      2A 00 00 00                                  sequence = 42
08      00 50 D6 DC 01 00 00 00                      timestamp_ns = 8,000,000,000
--- payload (20 bytes) ---
10      00 00 00 3F                                  x = 0.5
14      00 00 80 3E                                  y = 0.25
18      FF BF                                        pressure = 49151
1A      94 11                                        tilt_x = 4500 (45.00°)
1C      F8 F8                                        tilt_y = -1800 (-18.00°)
1E      00 00                                        _pad
20      00 00 00 00                                  _reserved
```

Total: 36 bytes.

---

### R11. Optional-Extension Region

Version 1 frames do not include an optional-extension region. The design MUST reserve the mechanism: a future version MAY append additional bytes after the fixed payload. Receivers that implement version N MUST ignore trailing bytes beyond the known payload size for that version.

#### Scenario: forward-compatible extension
- **Given** a v2 frame that appends 8 bytes of extension data after the v1 payload
- **When** a v1-only receiver parses the frame
- **Then** the v1 receiver MUST read only the first 36 bytes (for STYLUS_MOVE) and MUST discard or ignore the remainder without error
