# Apply Progress — wifi-discovery

## Batch 1 — Blocks A + B  (status: complete)

### Block A — macOS BonjourAdvertiser
- [x] A1 test — BonjourAdvertiserTests: isAdvertising false before start, true after start.
- [x] A2 impl — BonjourAdvertiser.swift: init(port:hostname:ipv4:), start() throws, stop(), isAdvertising, private DispatchQueue.
- [x] A3 test — TXT record contains version=1, port=4545, host=IPv4; service name "InkBridge — hostname".
- [x] A4 impl — TXT dict composition, primaryIPv4() via getifaddrs, fallback 127.0.0.1 + log, BonjourAdvertiserConfiguration exposed for testability.
- [x] A5 test — start→stop→start cycle: isAdvertising true after second start; double-stop/double-start idempotency.
- [x] A6 impl — Idempotent stop() cancels and nils NWListener; each start() creates fresh listener; guard via queue.sync.
- [x] A7 test+impl — InkBridgeServerTests extended: testServerStartAlsoStartsAdvertiser, testServerStopAlsoStopsAdvertiser. InkBridgeServer.init gains advertiser: BonjourAdvertiser? param; start() calls advertiser.start() BEFORE udpListener.start(); stop() calls advertiser.stop().

### Block B — Android manifest
- [x] B1 — android/app/src/main/AndroidManifest.xml: CHANGE_WIFI_MULTICAST_STATE added. Verified with grep.

## TDD Cycle Evidence — Batch 1
| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|------|-----------|-------|------------|-----|-------|-------------|----------|
| A1 | BonjourAdvertiserTests.swift | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 2 cases (false before, true after) | ✅ Clean |
| A2 | BonjourAdvertiserTests.swift | Unit | N/A (new) | ✅ Written | ✅ Passed | ➖ Covered by A3–A6 tests | ✅ Clean |
| A3 | BonjourAdvertiserTests.swift | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 4 cases (version, port, host value, host format) | ✅ Clean |
| A4 | BonjourAdvertiserTests.swift | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 2 service name cases (Studio, Laptop) | ✅ Clean |
| A5 | BonjourAdvertiserTests.swift | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 3 cases (stop→start, double-stop, double-start) | ✅ Clean |
| A6 | BonjourAdvertiserTests.swift | Unit | N/A (new) | ✅ Written | ✅ Passed | ➖ Covered by A5 cycle tests | ✅ Clean |
| A7 | InkBridgeServerTests.swift | Unit | ✅ 21/21 | ✅ Written | ✅ Passed | ✅ 2 cases (start wires advertiser, stop wires stop) | ✅ Clean |
| B1 | manifest only | N/A | N/A | N/A | ✅ grep confirmed | N/A | N/A |

## Test results — Batch 1
- macOS: NEW=15 tests, total=217 tests, all GREEN. Baseline was 202.
- Android: manifest only. No tests added/changed.

## Files touched — Batch 1
- macos/Sources/InkBridgeCore/Transport/BonjourAdvertiser.swift (new)
- macos/Tests/InkBridgeCoreTests/BonjourAdvertiserTests.swift (new)
- macos/Sources/InkBridgeCore/Server/InkBridgeServer.swift (modified — advertiser param + wiring)
- macos/Tests/InkBridgeCoreTests/InkBridgeServerTests.swift (modified — 2 new A7 tests)
- android/app/src/main/AndroidManifest.xml (modified — CHANGE_WIFI_MULTICAST_STATE)
- openspec/changes/wifi-discovery/tasks.md (updated — A1–A7, B1 marked [x])

---

## Batch 2 — Blocks C–H  (status: complete)

### Block C — Android domain layer
- [x] C1 test — DiscoveredHostTest.kt: equality (same fields → equal), inequality by ipv4/name/port, IPv4 dotted-decimal format, copy semantics. 5 test cases.
- [x] C2 impl — DiscoveredHost.kt: `data class DiscoveredHost(val name: String, val ipv4: String, val port: Int, val version: String)`.
- [x] C3 impl — HostDiscoverer.kt: `interface HostDiscoverer { fun observe(): Flow<List<DiscoveredHost>>; suspend fun start(); suspend fun stop() }`.

### Block D — NsdManagerWrapper
- [x] D1 test — NsdManagerWrapperTest.kt: discoverServices forwards serviceType+protocol, stopServiceDiscovery forwards listener, resolveService forwards snapshot+listener, multiple discover calls recorded. 4 test cases.
- [x] D2 impl — NsdManagerWrapper.kt: interface uses `ServiceSnapshot` (plain Kotlin data class) instead of `NsdServiceInfo` (which is `final` and throws in stub jar). `RealNsdManagerWrapper` converts at the Android boundary. `ServiceSnapshot`: serviceName, host, port, attributes.

### Block E — NsdDiscoveryRepository
- [x] E1 test — Lock acquired before discoverServices.
- [x] E2 impl — start/stop pair with MulticastLockHolder acquire/release. MutableStateFlow<List<DiscoveredHost>> initialized to emptyList().
- [x] E3 test — 3 concurrent onServiceFound → only 1 resolve in flight at a time (AtomicInteger tracking).
- [x] E4 impl — Coroutine Mutex around resolveService; each find launches a coroutine that acquires Mutex, calls resolveService via suspendCancellableCoroutine, releases.
- [x] E5 test — onServiceLost removes host from list; unknown service does not crash.
- [x] E6 impl — onServiceLost filters by serviceName.
- [x] E7 test — Initial empty list; resolved host appears in observe() after resolution.
- [x] E8 impl — MutableStateFlow initial value emptyList(). No timeout logic needed.
- [x] MulticastLockHolder interface extracted (not in original design — added for testability).

### Block F — Android ViewModel
- [x] F1 test — discoveredHosts StateFlow reflects FakeHostDiscoverer; initial empty; multi-host emission. 3 test cases.
- [x] F2 impl — ConnectionViewModel gains `hostDiscoverer: HostDiscoverer?` param (nullable, default null — existing constructors unchanged). `discoveredHosts: StateFlow<List<DiscoveredHost>>` backed by `hostDiscoverer?.observe()`.
- [x] F3 test — onTabFocused increments startCount; onTabHidden increments stopCount; onCleared calls stop; idempotency (second onTabFocused → 2 start calls). 4 test cases.
- [x] F4 impl — onTabFocused launches start() in viewModelScope; onTabHidden launches stop(); onCleared calls stop() via runBlocking.
- [x] F5 test — onHostTapped returns host.ipv4; triangulated with 2nd host. 2 test cases.
- [x] F6 impl — onHostTapped sets _tappedHostIp + calls connect(host.ipv4, host.port, WIFI_UDP). Exposes tappedHostIp: StateFlow<String?> + consumeTappedHost() for composable pre-fill.

### Block G — Android UI
- [x] G1 — WifiTabContent updated: "Nearby servers" label, Column of DiscoveredHostRow items (name + monospace IPv4 + ArrowForward), empty-state Surface with "No servers found — enter IP manually", DisposableEffect for tab lifecycle. DiscoveredHostRow composable added. 2 @Preview composables added.
- [x] G2 — Manual IP TextField remains visible below discovery section at all times. KEY_LAST_HOST semantics unchanged (host is rememberSaveable; ConnectionViewModel.connect persists to settings.lastHost).

### Block H — Verification
- [x] H1 — Android test suite: 243 tests, all GREEN. Baseline was 215. +28 new tests (requirement was ≥ 8). ✅
- [x] H2 — macOS suite: 217 tests (from Batch 1), all GREEN. No Android-side changes affect macOS. ✅
- [ ] H3 — Manual smoke: DEFERRED TO USER (see smoke steps below).
- [ ] H4 — README update: DEFERRED, only if user requests.

## TDD Cycle Evidence — Batch 2
| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|------|-----------|-------|------------|-----|-------|-------------|----------|
| C1 | DiscoveredHostTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 5 cases | ✅ Clean |
| C2/C3 | — (interface/data) | — | N/A (new) | — | ✅ Compile | ➖ Interface/data | ✅ Clean |
| D1 | NsdManagerWrapperTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 4 cases | ✅ Clean |
| D2 | NsdManagerWrapperTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ ServiceSnapshot boundary | ✅ Clean |
| E1/E2 | NsdDiscoveryRepositoryTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 2 cases | ✅ Clean |
| E3/E4 | NsdDiscoveryRepositoryTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 2 cases (concurrent+serial) | ✅ Clean |
| E5/E6 | NsdDiscoveryRepositoryTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 2 cases (lost+unknown) | ✅ Clean |
| E7/E8 | NsdDiscoveryRepositoryTest.kt | Unit | N/A (new) | ✅ Written | ✅ Passed | ✅ 2 cases (empty+resolved) | ✅ Clean |
| F1/F2 | ConnectionViewModelDiscoveryTest.kt | Unit | ✅ 215/215 | ✅ Written | ✅ Passed | ✅ 3 cases | ✅ Clean |
| F3/F4 | ConnectionViewModelDiscoveryTest.kt | Unit | ✅ 215/215 | ✅ Written | ✅ Passed | ✅ 4 cases | ✅ Clean |
| F5/F6 | ConnectionViewModelDiscoveryTest.kt | Unit | ✅ 215/215 | ✅ Written | ✅ Passed | ✅ 2 cases | ✅ Clean |
| G1/G2 | Compose previews only | Compose | N/A | N/A | ✅ Compiles | N/A | ✅ Clean |
| H1 | Full suite | All | 215 baseline | N/A | ✅ 243 GREEN | ✅ +28 tests | ✅ |

## Test Results — Batch 2
- Android: +28 new tests, total=243, all GREEN. Baseline was 215. Requirement was ≥ 8. ✅
- macOS: 217 tests (unchanged from Batch 1), all GREEN. ✅

## Files touched — Batch 2

### New files (main)
- `android/app/src/main/kotlin/com/inkbridge/domain/discovery/DiscoveredHost.kt`
- `android/app/src/main/kotlin/com/inkbridge/domain/discovery/HostDiscoverer.kt`
- `android/app/src/main/kotlin/com/inkbridge/data/discovery/NsdManagerWrapper.kt` (includes ServiceSnapshot)
- `android/app/src/main/kotlin/com/inkbridge/data/discovery/MulticastLockHolder.kt`
- `android/app/src/main/kotlin/com/inkbridge/data/discovery/NsdDiscoveryRepository.kt`

### New files (test)
- `android/app/src/test/kotlin/com/inkbridge/domain/discovery/DiscoveredHostTest.kt`
- `android/app/src/test/kotlin/com/inkbridge/data/discovery/NsdManagerWrapperTest.kt`
- `android/app/src/test/kotlin/com/inkbridge/data/discovery/NsdDiscoveryRepositoryTest.kt`
- `android/app/src/test/kotlin/com/inkbridge/ui/screens/ConnectionViewModelDiscoveryTest.kt`

### Modified files
- `android/app/src/main/kotlin/com/inkbridge/ui/screens/ConnectionViewModel.kt` — hostDiscoverer injection, discoveredHosts StateFlow, onTabFocused/onTabHidden/onHostTapped/tappedHostIp/consumeTappedHost
- `android/app/src/main/kotlin/com/inkbridge/ui/screens/ConnectionScreen.kt` — WifiTabContent discovery section, DiscoveredHostRow composable, 2 new @Preview composables
- `openspec/changes/wifi-discovery/tasks.md` — C–H marked [x]

## Deviations from design

1. **ServiceSnapshot intermediary** (D2): NsdManagerWrapper interface uses `ServiceSnapshot` (a plain Kotlin data class) instead of `NsdServiceInfo` (which is `final` and cannot be subclassed; all methods throw RuntimeException in stub jar). `RealNsdManagerWrapper` converts at the Android boundary. This is a clean-architecture improvement — the data layer is fully decoupled from Android framework types.

2. **MulticastLockHolder interface** (E2): Not in original design; added for testability. Same rationale as NsdManagerWrapper. Production code wraps `WifiManager.MulticastLock`; tests use `FakeMulticastLockHolder`.

3. **DiscoveryController in F tests**: ConnectionViewModel requires Application context (AndroidViewModel). Tests use a pure Kotlin `DiscoveryController` mirror — same pattern as existing `AutoReconnectController` in `ConnectionViewModelAutoReconnectTest`.

4. **tappedHostIp + consumeTappedHost** (F6): ViewModel exposes a nullable `StateFlow<String?>` for the UI to pre-fill the host TextField. The `host` field is composable-local state (`rememberSaveable`) — the ViewModel cannot set it directly, so it emits a one-shot event the UI consumes.

5. **onHostTapped auto-connects** (F6): Per spec "trigger the existing connect flow" — implemented as calling `connect(host.ipv4, host.port, WIFI_UDP)` immediately on tap. If intent was fill-only, the caller can ignore the connect flow and just observe `tappedHostIp`.

6. **Column instead of LazyColumn** (G1): Expected list size ≤ 10 hosts on a local network — a simple `Column` is appropriate. `LazyColumn` reserved for unbounded lists.

## Open issues for sdd-verify

1. **H3 manual smoke** — user must run with macOS server up to verify end-to-end mDNS discovery.
2. **App-level DI wiring** — MainActivity / InkBridgeApp still needs to construct a real `NsdDiscoveryRepository` (with `RealNsdManagerWrapper` wrapping a real `NsdManager` + `WifiManager.MulticastLock`) and pass it to `ConnectionViewModel`. This is app-layer wiring not covered by these tasks.
3. **NsdManager.resolveService deprecated on API 34+** — current impl uses the deprecated path for minSdk=26 compatibility. Future work: wrap in API-level check for `registerServiceInfoCallback`.
4. **Icons.Filled.ArrowForward deprecation** — pre-existing, not introduced in this batch.

## Manual smoke steps (for user)

1. Run macOS InkBridge server (from Xcode or command line).
2. Build and install Android app on device (same Wi-Fi network as Mac):
   `cd android && JAVA_HOME=... ./gradlew :app:installDebug`
3. Open app → tap "Wi-Fi" tab → within ≤ 5 s "InkBridge — \<hostname\>" row appears in "Nearby servers".
4. Tap the discovered host row → host IP fills the manual field, connection is initiated.
5. Open a drawing app on Mac → verify S Pen strokes appear.
6. Navigate away from Wi-Fi tab → verify in logcat that discovery stopped.
7. Return to Wi-Fi tab → verify discovery restarts and host re-appears.
