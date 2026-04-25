# Proposal: express-keys

## Intent

Promote InkBridge from "fancy trackpad" to "real graphics tablet" by adding configurable hardware-button-style keys along the edge of the Android canvas. Each key fires a configurable shortcut (`Cmd+Z`, `[`, `]`) or holds a modifier (`Ctrl`, `Cmd`, `Opt`, `Shift`, `Space`) for as long as the finger stays down. The bar can be hidden with one tap so the canvas stays edge-to-edge for clean drawing.

This is what Wacom Express Keys, Astropad shortcut bars, and the Apple Pencil's lost-and-found double-tap *should* be. None of them ship out of the box on a Samsung tablet running our app, so we add it.

## Why now

Pack A (signal-quality) addressed how the stroke *feels*. Pack C addresses how a drawing *workflow* feels: undo/redo/brush-size/Ctrl-pick are reached without dropping the stylus to mash a keyboard. For users who switch between apps (Krita, Photoshop, Affinity), the keys also become app-aware via the same per-app pattern as pressure curves — but per-app overrides are out of scope for this change to keep the cross-platform delta small.

## Scope

### In scope
- New wire-protocol event `KEY_EVENT 0x07` — 20 B total, 4 B payload (key code, modifier bitfield, action). Strict version-1 receiver behavior preserved (unknown event types still discarded).
- Android: an overlay row of 6 keys on the chosen edge (default right) of the capture canvas. Keys are 64×64 dp, 12 dp gap, palm-rejection-free because the stylus passes through (only finger taps register).
- Android: a settings sheet (existing `SettingsSheet`) with a "Express keys" subsection that toggles visibility, picks edge (left/right), and lists each slot for editing.
- Android: each slot configurable via a small editor that picks an action type (Shortcut / ModifierHold / Toggle) and a key combo. Default preset assigns Slot 1 to Ctrl-hold, Slot 2 to Cmd+Z (Undo), Slot 3 to Cmd+Shift+Z (Redo), Slot 4 to `[` (Brush −), Slot 5 to `]` (Brush +), Slot 6 to Space-hold (Pan).
- Android: persist the configuration in `SettingsRepository`.
- macOS: decode `KEY_EVENT` frames in `BinaryStylusCodec`, add the new variant to `StylusEvent`, add `injectKey(action:key:modifiers:)` to the `Injector` protocol, implement it via `CGEvent(keyboardEventSource:virtualKey:keyDown:)` in `CGEventInjector`, post to `cgSessionEventTap`.
- Both sides: encode/decode round-trip tests for the new frame; one new canonical hex test vector under `protocol/test-vectors/key-event.hex`.

### Out of scope
- Per-app key profiles (defer to a follow-up that mirrors the per-app pressure curve pattern).
- Recording macros (multi-key sequences with timing).
- Drag-to-reorder slots (slots are fixed order in this release).
- Custom icons (we use SF Symbols on Mac status display only — Android uses Material icons resolved from action type).
- Custom labels (label is auto-derived from the action; user can replace via the editor in a follow-up).
- Haptic feedback on key press — already configurable via the existing haptic intensity slider; reuse that path rather than adding a separate setting.

## Why a new wire-protocol event

The existing `STYLUS_BUTTON 0x03` carries only `BUTTON_PRIMARY`/`BUTTON_SECONDARY` flags — the entire wire schema for "buttons" assumes stylus barrel buttons, two states max. Reusing it would require: (a) overloading what those flags mean, (b) new flag bits for modifiers, (c) breaking the existing button → mouse-button mapping on the Mac. It is cleaner to add a parallel event type that carries the full keyboard semantics and leave the stylus button path untouched. The protocol's existing rule — "unknown event_type MUST be discarded by older receivers" — is precisely the affordance designed for this case.

## Risks

| Risk | Mitigation |
|------|------------|
| User taps express keys while drawing with the stylus → palm rejection issues | Keys only respond to `MotionEvent.TOOL_TYPE_FINGER`. Stylus events with `TOOL_TYPE_STYLUS` pass through to the canvas. No code change to that distinction — it is already enforced by the existing finger-vs-stylus routing. |
| Modifier-hold gets stuck if user lifts finger off-screen (e.g. drags off the bar) | Track key state per pointer ID. Auto-release on `MotionEvent.ACTION_CANCEL` and on `View.onDetachedFromWindow`. Send a release event regardless of where the finger went. |
| Wire-format compat: Android sends 0x07 frames, older Mac builds don't decode them | The Mac already ignores unknown `event_type` bytes (`BinaryStylusCodec` discards them, increments dropped counter). The Android side adds 0x07 only when the user has the bar enabled; default-off would prevent any wire change for users who don't opt in. We default ON only for new installs; users on the current build won't see frames for keys they didn't press. |
| `injectKey` keyboard codes differ across keyboard layouts | Use the macOS *virtual* keycodes (kVK_ANSI_*), not Unicode — these correspond to physical-key positions and `CGEvent` will translate them to the user's active layout for character keys. For modifier keys we use `event.flags` which is layout-independent. |
| Modifier-hold conflicts with stylus drawing under that modifier (e.g. Shift held = constrain stroke) | This is the *intent*, not a bug — the user should be able to hold Slot 1 (Ctrl) and stroke to get Krita's eyedropper. The Mac side posts the modifier-down before the next stylus event, modifier-up after the finger lifts. |

## Rollback

- Bar is independently togglable in Android settings. Off → no `KEY_EVENT` frames sent → behaviour identical to today.
- Wire change is purely additive — disabling the bar reverts to a strict v1 protocol stream.
- macOS side: if `injectKey` fails (no Accessibility), the failure is counted as `injectionFailures` and does not change server state.
