# Wire Protocol v1 — Conformance Checklist

Each row maps to a requirement in `openspec/changes/foundation/specs/wire-protocol.md`.
Check a box (`[x]`) once the corresponding implementation passes its test suite.

| Req | Description | Kotlin (`BinaryStylusCodec.kt`) | Swift (`BinaryStylusCodec.swift`) |
|-----|-------------|:-------------------------------:|:---------------------------------:|
| R1 | All multi-byte fields are little-endian | [x] | [x] |
| R2 | Version byte is at offset 0; unknown version → discard | [x] | [x] |
| R3 | Fixed 16-byte header layout (version, event_type, flags, _reserved, sequence, timestamp_ns) | [x] | [x] |
| R4 | Only event_types 0x01, 0x02, 0x03 accepted; unknown → discard | [x] | [x] |
| R5 | Flags byte: PRESSURE_PRESENT, TILT_PRESENT, HOVER, BUTTON_PRIMARY, BUTTON_SECONDARY; bits 5-7 reserved | [x] | [x] |
| R6 | STYLUS_MOVE payload: 20 bytes (x f32, y f32, pressure u16, tilt_x i16, tilt_y i16, _pad u16, _reserved u32); total frame = 36 bytes | [x] | [x] |
| R7 | STYLUS_PROXIMITY payload: 4 bytes (entering u8, _pad 3 bytes); total frame = 20 bytes | [x] | [x] |
| R8 | STYLUS_BUTTON payload: 4 bytes (buttons u8, _pad 3 bytes); buttons consistent with flags bits 3-4; inconsistency → discard | [x] | [x] |
| R9 | Sequence counter: starts at 0, increments per frame, resets on new connection; receiver discards seq < last_accepted | [x] (codec decodes seq field; ordering policy belongs to transport layer) | [x] (same) |
| R10 | Worked example (move-with-pressure-tilt.hex) encodes byte-for-byte correctly | [x] | [x] |
| R11 | Forward compatibility: trailing bytes beyond known payload size are ignored without error | [x] | [x] |

---

## Cross-language interop contract

- Both codecs MUST produce byte-identical output given the same constructed event + header fields.
- The four `.hex` files in `protocol/test-vectors/` are the **single source of truth** for interop:
  - `move-with-pressure-tilt.hex` — STYLUS_MOVE, all sensor fields populated
  - `proximity-enter.hex` — STYLUS_PROXIMITY entering=1, HOVER flag set
  - `proximity-exit.hex` — STYLUS_PROXIMITY entering=0, HOVER flag clear
  - `button-press.hex` — STYLUS_BUTTON BUTTON_PRIMARY flag + buttons byte both = 0x08
- If the canonical vectors change, re-copy them to:
  - `macos/Tests/InkBridgeCoreTests/Vectors/` (Swift test bundle — manual copy)
  - The Gradle `copyProtocolVectors` task handles the Android side automatically.

---

## Integration milestones

| Test | Status |
|------|--------|
| 4.1 — USB smoke test (TCP, adb reverse) | [ ] |
| 4.2 — Wi-Fi smoke test (UDP) | [ ] |
| 4.3 — Pressure + tilt validated in ≥ 2 drawing apps | [ ] |
| 4.4 — Latency P50 ≤ 15 ms (USB), P50 ≤ 30 ms (Wi-Fi) | [ ] |
