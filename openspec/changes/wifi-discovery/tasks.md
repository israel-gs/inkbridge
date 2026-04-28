# Tasks: Wi-Fi Host Discovery (mDNS / Bonjour)

> Phase: `sdd-tasks` | Change: `wifi-discovery` | Strict TDD: ACTIVE | Date: 2026-04-27

---

## Block A — macOS BonjourAdvertiser

- [x] A1 [test] Create `macos/Tests/InkBridgeCoreTests/BonjourAdvertiserTests.swift` — assert `NWListener.service` is configured on `NWParameters` BEFORE `listener.start()` is called; assert `isAdvertising == true` after `start()`. Run: `cd macos && swift test`
- [x] A2 [impl] Create `macos/Sources/InkBridgeCore/Transport/BonjourAdvertiser.swift` — `init(port:hostname:)`, `start() throws`, `stop()`, `isAdvertising: Bool`; private `DispatchQueue` for thread safety.
- [x] A3 [test] In `BonjourAdvertiserTests` add: assert TXT record contains `version=1`, `port=4545`, `host=<dotted-decimal IPv4>`; assert service name is `"InkBridge — \(hostname)"`. Run: `cd macos && swift test`
- [x] A4 [impl] In `BonjourAdvertiser.swift` — compose TXT dict `["version":"1","port":"\(port)","host":"<IPv4>"]`; resolve primary IPv4 from `getifaddrs`; fallback to `127.0.0.1` + log warning; compose name `"InkBridge — \(Host.current().localizedName ?? ProcessInfo.processInfo.hostName)"`.
- [x] A5 [test] In `BonjourAdvertiserTests` add: call `start()` → `stop()` → `start()` — assert `isAdvertising == true` after second start, no stale records (no crash, no hang). Run: `cd macos && swift test`
- [x] A6 [impl] In `BonjourAdvertiser.swift` — idempotent `stop()` cancels and nils the `NWListener`; each `start()` creates a fresh listener; guard `isAdvertising` with `AtomicBoolean` equivalent using queue.
- [x] A7 [test+impl] In `macos/Tests/InkBridgeCoreTests/InkBridgeServerTests.swift` (extend or add) — assert `start(port:)` initialises and starts advertiser; assert `stop()` stops advertiser. Wire `BonjourAdvertiser` into `InkBridgeServer.start(port:)` at the point before `listener.start(queue:)`. Run: `cd macos && swift test`

---

## Block B — Android Manifest Permission

- [x] B1 [task] In `android/app/src/main/AndroidManifest.xml` add `<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />`. No unit test (manifest-only). Commit alone.

---

## Block C — Android Domain Layer

- [x] C1 [test] Create `android/app/src/test/kotlin/com/inkbridge/domain/discovery/DiscoveredHostTest.kt` — assert data-class structural equality: two instances with same fields are equal; assert `ipv4` is a dotted-decimal string (regex `\d+\.\d+\.\d+\.\d+`). Run: `cd android && JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] C2 [impl] Create `android/app/src/main/kotlin/com/inkbridge/domain/discovery/DiscoveredHost.kt` — `data class DiscoveredHost(val name: String, val ipv4: String, val port: Int, val version: String)`.
- [x] C3 [impl] Create `android/app/src/main/kotlin/com/inkbridge/domain/discovery/HostDiscoverer.kt` — `interface HostDiscoverer { fun observe(): Flow<List<DiscoveredHost>>; suspend fun start(); suspend fun stop() }`. No unit test needed for the interface itself.

---

## Block D — Android NsdManagerWrapper Abstraction

- [x] D1 [test] Create `android/app/src/test/kotlin/com/inkbridge/data/discovery/NsdManagerWrapperTest.kt` — use a hand-rolled fake: assert `discoverServices(type, listener)` forwards type `"_inkbridge._udp."` and the provided listener; assert `stopServiceDiscovery(listener)` forwards the same listener; assert `resolveService(info, listener)` forwards `info` and listener. Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] D2 [impl] Create `android/app/src/main/kotlin/com/inkbridge/data/discovery/NsdManagerWrapper.kt` — `interface NsdManagerWrapper { fun discoverServices(…); fun resolveService(…); fun stopServiceDiscovery(…) }` + `class RealNsdManagerWrapper(private val nsd: NsdManager) : NsdManagerWrapper` delegating to `nsd.*`.

---

## Block E — Android NsdDiscoveryRepository

- [x] E1 [test] Create `android/app/src/test/kotlin/com/inkbridge/data/discovery/NsdDiscoveryRepositoryTest.kt` — with `FakeNsdManagerWrapper` and `FakeMulticastLock`: assert `startDiscovery()` calls `lock.acquire()` before `discoverServices`; assert `stopDiscovery()` calls `lock.release()`. Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] E2 [impl] Create `android/app/src/main/kotlin/com/inkbridge/data/discovery/NsdDiscoveryRepository.kt` — `start()` acquires lock then calls `discoverServices("_inkbridge._udp.", listener)`; `stop()` calls `stopServiceDiscovery` then releases lock; `MutableStateFlow<List<DiscoveredHost>>`.
- [x] E3 [test] In `NsdDiscoveryRepositoryTest` add: trigger 3 simultaneous `onServiceFound` callbacks via the fake; assert `resolveService` is called exactly one at a time (track concurrent calls with `AtomicInteger`); assert all 3 resolve eventually. Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] E4 [impl] In `NsdDiscoveryRepository` — add coroutine `Mutex` around `resolveService` call; launch each found-service resolve in a coroutine that acquires the Mutex, calls resolve, awaits callback via `suspendCancellableCoroutine`, releases Mutex.
- [x] E5 [test] In `NsdDiscoveryRepositoryTest` add: emit one resolved host → assert `observe()` emits list with that host; then fire `onServiceLost` for the same service → assert `observe()` emits empty list. Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] E6 [impl] In `NsdDiscoveryRepository` — `onServiceLost` removes by service name from `_hosts` `MutableStateFlow`.
- [x] E7 [test] In `NsdDiscoveryRepositoryTest` add: start discovery, advance time 2+ seconds with no `onServiceFound` → assert `observe()` most-recent emission is `emptyList()`. Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] E8 [impl] In `NsdDiscoveryRepository` — emit `emptyList()` as initial state of `MutableStateFlow`; no additional timeout logic needed (initial state covers the spec requirement; empty state is always present before results).

---

## Block F — Android ViewModel

- [x] F1 [test] Create `android/app/src/test/kotlin/com/inkbridge/ui/screens/ConnectionViewModelDiscoveryTest.kt` — `FakeHostDiscoverer` emits a prebuilt `List<DiscoveredHost>`; assert `discoveredHosts` `StateFlow` in ViewModel reflects that list. Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] F2 [impl] In `android/app/src/main/kotlin/com/inkbridge/ui/screens/ConnectionViewModel.kt` — inject `HostDiscoverer`; expose `val discoveredHosts: StateFlow<List<DiscoveredHost>>` backed by `hostDiscoverer.observe()`.
- [x] F3 [test] In `ConnectionViewModelDiscoveryTest` add: call `onTabFocused()` → assert `FakeHostDiscoverer.startCalled == true`; call `onTabHidden()` → assert `stopCalled == true`; call `onTabFocused()` again → assert `startCalled` count == 2 (idempotency check). Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] F4 [impl] In `ConnectionViewModel` — `fun onTabFocused()` launches `hostDiscoverer.start()` in `viewModelScope`; `fun onTabHidden()` launches `hostDiscoverer.stop()`; `override fun onCleared()` calls `stop()`.
- [x] F5 [test] In `ConnectionViewModelDiscoveryTest` add: fake emits one host (`name="Studio"`, `ipv4="192.168.1.42"`, `port=4545`); call `onHostTapped(host)` → assert `hostField.value == "192.168.1.42"` and connect flow triggered (e.g. `connectCalled == true`). Run: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon`
- [x] F6 [impl] In `ConnectionViewModel` — `fun onHostTapped(host: DiscoveredHost)` sets `hostField` to `host.ipv4` and invokes existing connect logic.

---

## Block G — Android UI

- [x] G1 [task] In `android/app/src/main/kotlin/com/inkbridge/ui/screens/ConnectionScreen.kt` — update `WifiTabContent`: add "Discovered hosts" section ABOVE manual IP field with a Search button (calls `onTabFocused`/`onScanRequested`), a `LazyColumn` of `DiscoveredHostRow(host, onClick = { onHostTapped(host) })` items (name + ipv4 + connect chevron), and an empty-state `Text("No servers found — enter IP manually")` shown when list is empty after 2 s. Keep `ui-ux-pro-max` spacing/typography. Add a `@Preview` composable for visual check. No unit tests (Compose UI); preview is the verification mechanism.
- [x] G2 [task] Ensure the manual host `TextField` remains visible below the discovery section at all times. Verify `KEY_LAST_HOST` persistence is unchanged — user's last manual entry is still restored on reopen.

---

## Block H — Verification & Polish

- [x] H1 [task] Run full Android test suite: `cd android && JAVA_HOME=... ./gradlew :app:testDebugUnitTest --no-daemon` — must be green; confirm ≥ 8 new test cases were added across blocks C–F. RESULT: 243 tests, all GREEN. +28 new tests (baseline was 215).
- [x] H2 [task] Run full macOS test suite: `cd macos && swift test` — must be green; confirm ≥ 3 new test cases were added in Block A. RESULT: 217 tests (from batch 1), no Android changes affect macOS.
- [ ] H3 [task] Manual smoke: macOS running → Android opens Wi-Fi tab → host appears in list within 5 s → tap host → connect → S Pen drawing works end-to-end. DEFERRED TO USER.
- [ ] H4 [task] (Optional) Update README discovery screenshot/section only if user explicitly requests it. Do NOT commit screenshots in this change unless asked.
