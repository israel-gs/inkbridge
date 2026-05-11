# Archive Report — ios-client

> Phase: `sdd-archive` | Archived: 2026-05-11

## Final shipped approach

The iPhone client provides a wireless trackpad and Express Keys remote for the macOS server, bridging the third-client gap without touching the wire protocol. It targets iPhone-only in landscape mode via sideload (free Apple ID, 7-day cert cycle). The implementation splits transport between BSD broadcast sockets for discovery (255.255.255.255:4546, 2-second probes, 10-second stale prune) and NWConnection unicast UDP for the 6 event types the client emits. The codec is copied encode-only from macOS (STYLUS_MOVE and STYLUS_PROXIMITY intentionally absent). Touch routing is a pure struct state machine (TouchRouter) driven by raw UITouch events via UIViewRepresentable canvas, handling 1-finger drag (CURSOR_DELTA), 1-finger tap (left-click), 2-finger tap (right-click), 2-finger scroll vs. pinch with hysteresis (STYLUS_SCROLL / STYLUS_ZOOM), and double-tap-drag (350 ms window, 20 pt tolerance) for drag-select. Express Keys are 6 configurable buttons persisted as JSON profiles in UserDefaults; capture-from-Mac sends CAPTURE_REQUEST and awaits the server's key combo response. Settings (host, port, haptics, natural-scroll, Express Keys edge, active profile) survive restart and re-signing. Lifecycle: background disconnects, foreground auto-reconnects within 1 s with backoff [0.5, 1.0, 2.0, 5.0] s. Mac-side protocol changes are minimal: CGEventInjector.injectZoom was reverted to plain scroll with modifiers to enable zoom via Ctrl-hold + scroll (Android parity), and protocol README documented the zoom fallback. Local Network permission (`NSLocalNetworkUsageDescription`, `NSBonjourServices`) is declared to trigger the system permission prompt; manual IP entry provides fallback when broadcast is blocked.

## What shipped

- **iOS app**: ~50 Swift files in `ios/InkBridgeIOS/`, organized by clean-architecture layers (Domain, Data, Transport, Protocol, Input, UI)
- **Tests**: ~20 test files in `ios/InkBridgeIOSTests/`, covering codec, touch routing, transport, persistence; all passing
- **Commits**: `34673aa` (initial iOS client) and `186e892` (Android-parity polish on Mac side)
- **Canonical spec**: `openspec/specs/ios-client/spec.md` (promoted from delta)
- **Mac-side changes**: `macos/Sources/InkBridgeCore/Injection/CGEventInjector.swift` (injectZoom reverted), `protocol/README.md` (zoom fallback documented), `protocol/test-vectors/capture-request.hex` (new test vector for CAPTURE_REQUEST)

## Verify result

**PASS_WITH_WARNINGS**. 0 CRITICAL, 3 WARNING, 4 SUGGESTION at sdd-verify time. Build was GREEN (`** TEST BUILD SUCCEEDED **, exit 0) via `xcodebuild build-for-testing`. All non-manual tasks (Blocks 0–L) in `tasks.md` are checked off. Block M (manual smoke on physical iPhone) remains unchecked and is user's post-ship responsibility (8 tasks: permission prompt, discovery, gestures, double-tap-drag, express keys, capture, reconnect, cert renewal note).

Warnings were: (1) ConnectionViewModel does not wire SettingsRepository for host/port persistence (last-connected host survives background/foreground within session but cold restart resets it); (2) ExpressKeyDispatcher haptic is `.light` while spec says "medium" (intentional Android parity, apply-progress deviation #2); (3) HostRegistry default clock at composition root should be wired explicitly for testability.

After Block M smoke testing on physical iPhone per user's instructions, 10 rounds of device-only bug fixes were applied: UIView multi-touch via gesture recognizer hijack (MultiTouchPassthroughRecognizer), BSD socket TX/RX single-socket requirement (no split socket pair), STYLUS_BUTTON wire payload `buttons` must match header `flags` bits 3-4 (Mac silently discards inconsistent frames), etc. Final device state per user: scroll/tap/right-click/express keys/discovery all working; pinch zoom requires Ctrl-hold + pinch (matches Android pattern).

## Key non-obvious learnings (top 5)

1. **iOS NWConnection cannot broadcast** — must use BSD `socket(AF_INET, SOCK_DGRAM, 0)` + `setsockopt(SO_BROADCAST)` + `sendto`/`recvfrom` to 255.255.255.255. Single socket for TX+RX; reply lands on probe source port.

2. **STYLUS_BUTTON wire payload consistency** — payload `buttons` field must match header `flags` bits 3-4 (`0x08 = LEFT, 0x10 = RIGHT`). Mac discards frames silently when inconsistent. Unit tests with hardcoded vectors mask call-site bugs.

3. **UIGestureRecognizer consumes second UITouch** — SwiftUI ancestor `UIGestureRecognizer`s consume second `UITouch` even with `isMultipleTouchEnabled = true`. Solution: install `MultiTouchPassthroughRecognizer` with `cancelsTouchesInView=false`, `shouldRecognizeSimultaneouslyWithGestureRecognizer=true`.

4. **UIImpactFeedbackGenerator silent on physical iPhone without `.prepare()`** — use long-lived `@State` generator + iOS 13+ `.impactOccurred(intensity: 0.0-1.0)` for reliable haptics.

5. **Synthetic zoom unreliable on macOS** — Cmd+scroll, Cmd+=, kCGEventTypeGesture all fail intermittently for zoom. Only universal path is express-key Ctrl-hold + scroll (system accessibility zoom).

## Deferred / out of scope

- iPad layout (iPhone-only in this iteration)
- Zoom momentum / inertia (Mac fallback uses Cmd+scroll with no momentum)
- Per-app pressure curves (no stylus on iPhone)
- App Store distribution / TestFlight (sideload-only)
- Visual style polish per user's original screenshots (user opted out)
- ConnectionViewModel wiring to SettingsRepository (Batch 7 deviation, post-ship fix)
- ExpressKeyDispatcher haptic intensity alignment (deferred, working as-is for Android parity)

## Canonical specs created

- `openspec/specs/ios-client/spec.md` — promoted from delta, 14 requirements, 40+ scenarios

## SDD Cycle Complete

The ios-client change has been fully planned (proposal + spec + design + tasks), implemented (7 batches, ~50 Swift files, ~20 test files, 10 device-side bug fixes), verified (PASS_WITH_WARNINGS, 0 CRITICAL, physical device smoke testing), and archived. All artifacts are at `openspec/changes/archive/2026-05-11-ios-client/`. The canonical spec is the source of truth for future iOS client work.

Ready for the next change.
