# Proposal: signal-quality

## Intent

Improve the *feel* of drawing on InkBridge by addressing three pain points reported during real use:

1. **Cursor jitter** in hover and at low-pressure starts — visible micro-shake from S Pen sensor noise that makes thin lines wavy.
2. **Pressure response is uniform across apps** — Krita and Photoshop interpret the same raw pressure differently; users currently can't tune one without affecting the other.
3. **Latency is opaque** — `LatencyTracker` already collects p50/p95/p99 of arrival-to-inject but the values are never surfaced. There is no way to validate that "feels laggy" complaints map to real numbers, and no way to A/B the effect of the new smoothing filter.

The change is **macOS-server-only**. No wire-protocol changes. No Android changes. All three additions are server-side transformations or UI on existing data.

## Why now

- The smoothing filter is the cheapest visible-quality win we have left in the pipeline — once added, the next quality wins require either DriverKit (native pinch) or hardware (ProMotion 240 Hz Mac). It belongs in the foundation for everything that follows.
- The latency histogram is needed *before* shipping smoothing: smoothing trades latency for stability, and we must measure the trade rather than guess.
- Per-app pressure curves unblock real production drawing workflows that currently require adjusting the brush in every app to compensate for InkBridge's flat 1:1 pressure mapping.

## Scope

### In scope
- A pure One-Euro filter implementation with a configurable cutoff/beta pair, applied to MOVE-frame coordinates server-side before coordinate mapping. Toggleable on/off. Default: ON with conservative parameters.
- A `PressureCurve` type (4-point cubic Bézier) that transforms `[0,1]` raw pressure to `[0,1]` output pressure, applied in `CGEventInjector.inject` before posting the tablet event.
- A `CurveRegistry` keyed by macOS app bundle identifier with one default curve and any number of per-app overrides. Frontmost-app detection cached at ~1 Hz to keep the inject hot path syscall-free.
- A SwiftUI `Chart`-based latency histogram in `StatusView` that visualises arrival-to-inject percentiles using the existing `LatencyTracker.Snapshot`. Refresh rate ≤10 Hz to match the publisher throttle already in `InkBridgeServer`.
- Settings UI (in the Mac status window) for: smoothing on/off + strength preset, per-app curve picker + editor, histogram show/hide.
- Persistence of all of the above via `UserDefaults` (the current settings store).

### Out of scope
- Wire-protocol changes (no new event types, no new flag bits).
- Android UI for any of the above (settings live on the Mac side because the transformations happen there).
- DriverKit, KEXT, or any path that requires Developer ID / private entitlements.
- Inter-app real-time profile switching beyond reading `NSWorkspace.frontmostApplication` once a second.
- Express keys (separate change).
- mDNS / display picker (separate change).

## Risks

| Risk | Mitigation |
|------|------------|
| Smoothing adds perceptible lag | Default parameters tuned for "stabilise jitter, don't lag fast moves". Toggle off in settings. Histogram lets the user see the cost. |
| Frontmost-app lookup on every frame | Cache `bundleIdentifier` for 1 s; refresh on `NSWorkspace.didActivateApplicationNotification`. |
| `PressureCurve` Bézier evaluation on hot path | Bézier is O(1), branch-free, ~30 ns. Negligible vs. `CGEventPost`. |
| SwiftUI `Chart` redraws at 240 Hz murder MainActor | Latency snapshot publish is already throttled to 10 Hz. Chart re-renders only when `latency` Published value changes. |
| Curve editor UX is fiddly | First release ships with three named presets (Linear, Soft, Hard) plus a manual control-point editor — presets cover 80% of needs. |

## Rollback

Each capability is independently togglable:
- Smoothing → settings toggle.
- Pressure curves → set every app to the default Linear curve.
- Histogram → settings toggle to hide.

A full rollback is `git revert` on the single SDD commit; no schema migrations, no wire changes, nothing to undo on the Android side.

## Affected modules

- `macos/Sources/InkBridgeCore/Domain/` — new `PressureCurve.swift`, new `OneEuroFilter.swift`, new `LatencyHistogram.swift`.
- `macos/Sources/InkBridgeCore/Server/InkBridgeServer.swift` — wire smoothing into `processFrame` before coordinate mapping.
- `macos/Sources/InkBridgeCore/Injection/CGEventInjector.swift` — apply curve transform to pressure before posting tablet event.
- `macos/Sources/InkBridgeCore/Server/CurveRegistry.swift` — new, keyed by bundle identifier, persisted via injected store.
- `macos/Sources/InkBridge/StatusView.swift` — histogram chart + new settings sheet.
- `macos/Sources/InkBridge/ServerViewModel.swift` — owns the toggles.
- `macos/Tests/InkBridgeCoreTests/` — pure-function tests for filter, curve, histogram.
