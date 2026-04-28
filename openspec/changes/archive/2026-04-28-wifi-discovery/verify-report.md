# Verification Report — wifi-discovery

**Change**: wifi-discovery
**Date**: 2026-04-27
**Mode**: Strict TDD (15 macOS + 28 Android new tests, 217/243 total GREEN — trusted from orchestrator)
**Artifact store**: hybrid

---

## Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 27 |
| Tasks complete | 25 |
| Tasks incomplete | 2 |

Incomplete tasks (both deferred by design):
- **H3** — Manual smoke test. DEFERRED TO USER. Not a blocker for archive; blocked on physical device.
- **H4** — README screenshot update. Explicitly optional, deferred pending user request.

---

## Build & Tests Execution

**Build**: ✅ Trusted (217 macOS / 243 Android — all GREEN per orchestrator)
**Tests**: ✅ 217 macOS passed / 243 Android passed / 0 failed
**New tests this change**: +15 macOS (Block A), +28 Android (Blocks C–F) = +43 total
**Coverage**: Not instrumented — N/A

---

## Spec Compliance Matrix

### macOS — bonjour-advertisement (5 requirements, 9 scenarios)

| Requirement | Scenario | Test | Result |
|-------------|----------|------|--------|
| R1: Service Publication | Happy path — advertiser starts | `BonjourAdvertiserTests > testIsAdvertisingTrueAfterStart` | ✅ COMPLIANT |
| R1: Service Publication | Listener config order enforced | `BonjourAdvertiserTests > testIsAdvertisingTrueAfterStart` + impl comment: `NWListener.init(service:using:on:)` structurally enforces pre-start ordering | ✅ COMPLIANT |
| R2: TXT Record Content | TXT record keys present | `BonjourAdvertiserTests > testTXTRecordContainsVersion1`, `testTXTRecordContainsPort`, `testTXTRecordContainsIPv4Host`, `testTXTRecordHostIsIPv4Format` | ✅ COMPLIANT |
| R2: TXT Record Content | No IPv4 available | `BonjourAdvertiser.init` fallback to `127.0.0.1` + NSLog warning (code: line 97–100) | ⚠️ PARTIAL (no dedicated test for nil-IPv4 fallback path) |
| R3: Instance Name | Single Mac on network | `BonjourAdvertiserTests > testServiceNameContainsHostname` | ✅ COMPLIANT |
| R3: Instance Name | Multiple Macs on network | `BonjourAdvertiserTests > testServiceNameWithDifferentHostname` | ✅ COMPLIANT |
| R4: Clean Stop | Server stops | `BonjourAdvertiserTests > testStopSetsIsAdvertisingFalse` | ✅ COMPLIANT |
| R5: Restart After Stop | Stop then start | `BonjourAdvertiserTests > testStartAfterStopSetsIsAdvertisingTrue` | ✅ COMPLIANT |
| macOS wiring (R6 from spec note) | Server start wires advertiser | `InkBridgeServerTests > testServerStartAlsoStartsAdvertiser` | ✅ COMPLIANT |

**macOS compliance: 5/5 requirements, 8/9 scenarios compliant (1 partial — no-IPv4 fallback untested)**

---

### Android — host-discovery (10 requirements, 14 scenarios)

| Requirement | Scenario | Test | Result |
|-------------|----------|------|--------|
| R1: Domain Interface Contract | Interface shape (`Flow<List<DiscoveredHost>>`, start/stop) | `DiscoveredHostTest` + `NsdDiscoveryRepositoryTest > resolved host appears in observe` | ✅ COMPLIANT |
| R2: MulticastLock Lifecycle | Lock acquired before discovery | `NsdDiscoveryRepositoryTest > start acquires MulticastLock before calling discoverServices` | ✅ COMPLIANT |
| R2: MulticastLock Lifecycle | Lock released on stop | `NsdDiscoveryRepositoryTest > stop releases MulticastLock and calls stopServiceDiscovery` | ✅ COMPLIANT |
| R2: MulticastLock Lifecycle | Multicast-blocked network (2s timeout → empty state) | `NsdDiscoveryRepositoryTest > observe emits empty list before any service is found` (initial empty list is always present) | ⚠️ PARTIAL (no time-based test; spec says "after 2s" — impl emits empty immediately which is strictly stronger) |
| R3: Serialized Resolve | Single resolve in flight | `NsdDiscoveryRepositoryTest > only one resolve is in flight at a time` | ✅ COMPLIANT |
| R3: Serialized Resolve | Three concurrent found — all resolved | `NsdDiscoveryRepositoryTest > three concurrent onServiceFound events are all eventually resolved` | ✅ COMPLIANT |
| R4: IPv4 Resolution | Host resolved to IPv4 (not .local or IPv6) | `NsdDiscoveryRepositoryTest > resolved host appears in observe after resolution` + impl filter: line 123–124 of NsdDiscoveryRepository.kt | ✅ COMPLIANT |
| R5: Service Type | Correct service type `_inkbridge._udp.` | `NsdDiscoveryRepository.kt:19` `private const val SERVICE_TYPE = "_inkbridge._udp."` + `NsdManagerWrapperTest > discoverServices forwards correct serviceType` | ✅ COMPLIANT |
| R6: Permission Declaration | Manifest contains `CHANGE_WIFI_MULTICAST_STATE` | `AndroidManifest.xml:6` `<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />` | ✅ COMPLIANT |
| R7: Discovery Lifecycle Bound to UI | Tab gains focus → startDiscovery | `ConnectionViewModelDiscoveryTest > onTabFocused calls discoverer start` + `ConnectionScreen.kt:292–294` DisposableEffect | ✅ COMPLIANT (unit layer) / ❌ NOT WIRED in production (see CRITICAL-1) |
| R7: Discovery Lifecycle Bound to UI | Tab loses focus → stopDiscovery | `ConnectionViewModelDiscoveryTest > onTabHidden calls discoverer stop` | ✅ COMPLIANT (unit layer) / ❌ NOT WIRED in production (see CRITICAL-1) |
| R7: Discovery Lifecycle Bound to UI | ViewModel cleared → stopDiscovery | `ConnectionViewModelDiscoveryTest > onCleared calls discoverer stop` + `ConnectionViewModel.kt:1051–1053` | ✅ COMPLIANT |
| R8: Tap to Connect | Tap fills host + triggers connect | `ConnectionViewModelDiscoveryTest > onHostTapped returns host ipv4` + `ConnectionViewModel.kt:166–169` | ✅ COMPLIANT (unit layer) / ❌ NOT WIRED in production (see CRITICAL-1) |
| R8: Tap then manual override | Manual value wins after tap | No dedicated test; spec says "manual value wins" — field is local composable state, user edit always overwrites. Structurally correct but untested. | ⚠️ PARTIAL |
| R9: Empty State | "No servers found" shown after 2s | `ConnectionScreen.kt:306–319` shows empty-state copy when `discoveredHosts.isEmpty()` | ❌ NOT WIRED (CRITICAL-1 blocks delivery to UI) |
| R10: Lost Service Removal | Mac goes offline → entry disappears | `NsdDiscoveryRepositoryTest > onServiceLost removes host from discovered list` | ✅ COMPLIANT |

**Android compliance: 7/10 requirements fully compliant, 2 partial, 1 blocked by CRITICAL-1**

---

## Correctness — Static Structural Evidence

### macOS

| Requirement | Status | Evidence |
|-------------|--------|----------|
| `NWListener.service` set BEFORE `start()` | ✅ Implemented | `BonjourAdvertiser.swift:127–137`: `NWListener.init(service:using:on:)` is the only way to set service; ordering is structural, not runtime-checked. Spec note confirmed. |
| TXT record: `version=1`, `port=4545`, `host=<IPv4>` | ✅ Implemented | `BonjourAdvertiser.swift:106–110` |
| Fallback to `127.0.0.1` when no IPv4 | ✅ Implemented | `BonjourAdvertiser.swift:97–100` |
| Instance name `InkBridge — <hostname>` (em dash U+2014) | ✅ Implemented | `BonjourAdvertiser.swift:103–105`, uses `\u{2014}` |
| `ServerViewModel.swift` builds real `BonjourAdvertiser` | ✅ Implemented | `ServerViewModel.swift:74–80` |
| `InkBridgeServer.start()` calls `advertiser.start()` BEFORE listener start | ✅ Implemented | `InkBridgeServer.swift:126–133`: advertiser started first, udpListener/tcpListener after |

### Android

| Requirement | Status | Evidence |
|-------------|--------|----------|
| `HostDiscoverer` interface — no NSD/platform types | ✅ Implemented | `HostDiscoverer.kt` imports only `kotlinx.coroutines.flow.Flow` and own domain types |
| MulticastLock acquired before `discoverServices` | ✅ Implemented | `NsdDiscoveryRepository.kt:55–79`: `lockHolder.acquire()` at line 57, `discoverServices` at line 79 |
| `MulticastLock` released in `stop()` | ✅ Implemented | `NsdDiscoveryRepository.kt:82–93`: `finally { lockHolder.release() }` |
| Coroutine `Mutex` serializes `resolveService` | ✅ Implemented | `NsdDiscoveryRepository.kt:97–101`: `resolveMutex.withLock { runCatching { resolveOnce(snapshot) } }` |
| IPv4 filter — rejects `.local` and IPv6 (`:`) | ✅ Implemented | `NsdDiscoveryRepository.kt:123–124` |
| Service type `_inkbridge._udp.` (trailing dot) | ✅ Implemented | `NsdDiscoveryRepository.kt:19` |
| `CHANGE_WIFI_MULTICAST_STATE` in manifest | ✅ Implemented | `AndroidManifest.xml:6` |
| `ConnectionViewModelFactory` builds real DI chain | ✅ Implemented | `ConnectionViewModelFactory.kt:38–53`: `RealNsdManagerWrapper` → `RealMulticastLockHolder` → `NsdDiscoveryRepository` → `ConnectionViewModel` |
| `discoveredHosts` StateFlow exposed by ViewModel | ✅ Implemented | `ConnectionViewModel.kt:126–131` |
| `onTabFocused`/`onTabHidden`/`onCleared` stop discovery | ✅ Implemented | `ConnectionViewModel.kt:137–148, 1051–1053` |
| **discoveredHosts/callbacks wired in InkBridgeApp** | ❌ NOT WIRED | `InkBridgeApp.kt:141–152`: `ConnectionScreen` called with only `state`, `onConnect`, `onDisconnect`. `ConnectionScreen` signature (line 100–105) has no discovery params. Discovery state never reaches the UI. |
| Empty state composable present | ✅ Implemented | `ConnectionScreen.kt:306–319` — correct copy, always present when list empty |
| `DisposableEffect` for tab lifecycle | ✅ Implemented | `ConnectionScreen.kt:292–295` — calls `onTabFocused()`/`onTabHidden()` but receives no-op lambdas from caller |

---

## Coherence — Design Decisions

| Decision | Followed? | Notes |
|----------|-----------|-------|
| `NWListener(service:using:on:)` for ordering invariant | ✅ Yes | Confirmed in `BonjourAdvertiser.swift` |
| `ServiceSnapshot` instead of `NsdServiceInfo` (testability) | ✅ Yes | Deviation from original design — correct clean-architecture improvement |
| `MulticastLockHolder` interface (testability) | ✅ Yes | Not in original design; added correctly |
| `DiscoveryController` mirror for ViewModel tests | ✅ Yes | Same pattern as `AutoReconnectController` in existing codebase |
| `tappedHostIp`/`consumeTappedHost` one-shot event | ✅ Yes | Correct pattern: ViewModel cannot set composable-local `rememberSaveable` state directly |
| `Column` instead of `LazyColumn` for host list | ✅ Yes | Acceptable — local network host count ≤ 10 |
| `onHostTapped` auto-connects immediately | ✅ Yes | Deviation from spec "fill field" only — see WARNING-1 |

---

## Issues Found

### CRITICAL (must fix before archive)

**CRITICAL-1 — Discovery state never delivered to UI**

`InkBridgeApp.kt` calls `ConnectionScreen(state, onConnect, onDisconnect)` — the three-param overload. `ConnectionScreen`'s signature does not accept `discoveredHosts`, `onHostTapped`, `onTabFocused`, or `onTabHidden`. Inside `ConnectionScreen`, `WifiTabContent` is called at line 192–201 with `discoveredHosts = emptyList()` and all no-op lambdas hardcoded. Consequence:
- The host list is ALWAYS empty regardless of what the ViewModel discovers.
- The tab lifecycle callbacks never fire from the real UI (only from unit tests via `DiscoveryController`).
- Tapping a discovered host is impossible (the list never populates).
- The empty-state CTA is ALWAYS shown.
- The MulticastLock is never acquired from the real app.

All 28 Android unit tests pass because they test `DiscoveryController` (a pure Kotlin mirror) and `WifiTabContent` via `@Preview`, both of which bypass this wiring gap entirely.

**Fix required:**
1. Add discovery params to `ConnectionScreen`: `discoveredHosts: List<DiscoveredHost>`, `onHostTapped: (DiscoveredHost) -> Unit`, `onTabFocused: () -> Unit`, `onTabHidden: () -> Unit`.
2. Thread them through to the `WifiTabContent(...)` call at line 192.
3. In `InkBridgeApp.kt`, collect `viewModel.discoveredHosts` and wire `viewModel::onTabFocused`, `viewModel::onTabHidden`, `viewModel::onHostTapped`.
4. Collect `viewModel.tappedHostIp` and call `viewModel.consumeTappedHost()` after pre-filling the `host` `rememberSaveable` state, so tap auto-fills the field.

---

### WARNING (should fix)

**WARNING-1 — Tap-to-connect auto-connects immediately; spec says "fill host field + trigger connect"**

`ConnectionViewModel.onHostTapped()` calls `connect(host.ipv4, host.port, WIFI_UDP)` immediately on tap. The spec R8 says "fill the host field with the resolved IPv4 AND trigger the existing connect flow" — so triggering connect is spec-compliant. However, the spec also says "Manual IP entry MUST remain functional and take precedence if the user subsequently edits the field." Because the connect fires immediately, there is no pause for the user to review or cancel before the connection attempt begins. This matches the spec's literal wording but may surprise users who tapped accidentally. Acceptable per spec, but worth a product decision.

**WARNING-2 — No-IPv4 fallback path has no dedicated test**

`BonjourAdvertiser.init(port:hostname:ipv4:nil)` falls back to `127.0.0.1` and logs a warning when `primaryIPv4()` returns `nil`. The spec R2 scenario "No IPv4 available" explicitly calls this out. The fallback code is correct (lines 97–100) but no test exercises the `ipv4: nil` + no-network path. The injectable `ipv4` parameter makes it trivially testable; the test just wasn't added.

**WARNING-3 — `NsdManager.resolveService` deprecated on API 34+**

`RealNsdManagerWrapper.resolveService()` uses the deprecated `NsdManager.resolveService(NsdServiceInfo, ResolveListener)` path. On API 34+ the preferred API is `registerServiceInfoCallback`. The current implementation works on minSdk=26 through API 33 correctly, but on API 34+ emits a deprecation warning and will eventually be removed. Flagged in apply-progress as known; no fix required in this change but should be scheduled.

**WARNING-4 — "Tap then manual override" scenario untested**

Spec R8 scenario 2: user taps a host (field fills), then manually edits — manual value must win. The composable local `host` state (`rememberSaveable`) means user edits always overwrite the tapped value structurally, but there is no test asserting this behavior. Since CRITICAL-1 means the tap path doesn't reach the UI at all right now, this is moot until CRITICAL-1 is fixed — but should be tested once wiring is complete.

---

### SUGGESTION (nice to have)

**SUGGESTION-1 — `Icons.Filled.ArrowForward` deprecation**

`ConnectionScreen.kt:403` uses `Icons.Default.ArrowForward` which is deprecated in favor of `Icons.AutoMirrored.Filled.ArrowForward`. Pre-existing issue, not introduced in this change.

**SUGGESTION-2 — `tappedHostIp` consumption in `ConnectionScreen`**

Even after CRITICAL-1 is fixed, the `tappedHostIp` one-shot event pattern requires the composable to `LaunchedEffect(tappedHostIp)` to update the `host` `rememberSaveable` and call `consumeTappedHost()`. If not implemented carefully, a recomposition after the initial collection could clear the user's manually typed host. Document this clearly in the fix PR.

**SUGGESTION-3 — 2s empty-state delay not implemented (E8 spec wording)**

The spec says "when discovery returns zero results after more than 2 seconds, the UI MUST display…". The implementation shows the empty state immediately (the `MutableStateFlow` initial value is `emptyList()`). This is strictly stronger — the user always sees the empty state, including during the first 2s. If a polished UX is desired (show a spinner for 2s before showing "No servers found"), a `delay(2000)` or `combine` with a timer would be needed. Not a functional regression, but does not match the spec's stated intent of a 2s grace period.

---

## Verdict

**FAIL — 1 CRITICAL blocking production delivery**

All 460 unit tests pass (217 macOS + 243 Android). The implementation architecture is sound. However, CRITICAL-1 means the feature does not work end-to-end: discovery runs in the ViewModel but its output never reaches the composable tree. The app ships with a permanently empty host list.

---

## Manual Smoke-Test Checklist (for user — run AFTER CRITICAL-1 is fixed)

**Build commands:**

1. **macOS build + install:**
   ```
   cd macos && swift build -c release && pkill -9 InkBridge 2>/dev/null; \
   cp .build/release/InkBridge build/InkBridge.app/Contents/MacOS/InkBridge && \
   codesign --force --deep --options runtime --entitlements InkBridge.entitlements \
     --sign "Apple Development: Israel Gutierrez (H2CC89A3C5)" build/InkBridge.app && \
   open build/InkBridge.app
   ```

2. **Android build + install:**
   ```
   cd android && JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
   ./gradlew :app:installDebug
   ```

**Pre-flight checklist:**
- Both devices on the same Wi-Fi SSID (not a guest network, not a hotspot with client isolation).
- macOS Accessibility permission granted to InkBridge (System Settings → Privacy & Security → Accessibility).
- macOS firewall not blocking UDP 4545 (or add an exception for InkBridge.app).

**Smoke steps:**

3. Open app on Android → tap the **Wi-Fi** tab → within ≤ 5 seconds a row labeled `InkBridge — <macname>` should appear in the "Nearby servers" section. If it does not appear after 10s, check that both devices are on the same subnet.

4. Tap the discovered host row → the "Host IP" field should pre-fill with the Mac's IPv4 (e.g. `192.168.1.42`) and a connection should initiate immediately. Verify the status screen appears showing "Wi-Fi" transport.

5. While connected, open a drawing app on the Mac (e.g. Procreate on iPad mirrored, or Vectornator) and verify S Pen strokes appear correctly.

6. Stop the macOS InkBridge server (quit the app or run `pkill InkBridge`) → the discovered host row should disappear from the Android list within a few seconds (mDNS goodbye packet).

7. Restart the macOS server (run the build command again) → the host row should reappear within ≤ 5s.

8. Navigate away from the Wi-Fi tab (tap USB) → verify in Android logcat (`adb logcat -s InkBridge`) that no discovery-related errors appear and the MulticastLock is released.

9. Return to Wi-Fi tab → verify discovery restarts and the host reappears (may take up to 5s after tab re-focus).

10. On a multicast-blocked network (e.g. corporate Wi-Fi, airplane-mode hotspot) → "No servers found — enter IP manually" CTA should be visible. Type the Mac's IP manually and verify connection still works.

---

## Return Contract

```
status: fail
executive_summary: >
  All 460 unit tests pass (217 macOS + 243 Android). Architecture and domain/data layers
  are fully correct and well-tested. One CRITICAL gap: ConnectionScreen's public signature
  does not accept discovery parameters, so InkBridgeApp.kt passes emptyList() and no-op
  callbacks — the host list is always empty in the real app. All other requirements pass
  static and unit-test verification. Two warnings (auto-connect on tap, no-IPv4 fallback
  untested) and three suggestions (icon deprecation, tappedHostIp consumption, 2s grace
  period). Fix CRITICAL-1, re-run full suite, then re-verify.
requirement_pass_count:
  macos: "5/5"
  android: "7/10 (2 partial, 1 blocked by CRITICAL-1)"
criticals:
  - "CRITICAL-1: discoveredHosts/onHostTapped/onTabFocused/onTabHidden never wired from
    InkBridgeApp → ConnectionScreen → WifiTabContent. Production UI permanently shows
    empty host list."
warnings:
  - "WARNING-1: onHostTapped auto-connects immediately — acceptable per spec literal wording
    but no user pause/cancel window"
  - "WARNING-2: No-IPv4 fallback path (127.0.0.1) has no unit test despite injectable param"
  - "WARNING-3: NsdManager.resolveService deprecated on API 34+ (known, deferred)"
  - "WARNING-4: Tap-then-manual-override scenario (R8 scenario 2) has no test"
suggestions:
  - "SUGGESTION-1: Icons.Default.ArrowForward deprecated (pre-existing)"
  - "SUGGESTION-2: tappedHostIp LaunchedEffect consumption needs care on recomposition"
  - "SUGGESTION-3: Empty state shown immediately instead of after 2s grace period"
next_recommended: fix_then_re-verify
skill_resolution: injected
```
