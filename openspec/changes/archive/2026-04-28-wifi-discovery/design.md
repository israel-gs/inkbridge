# Design: Wi-Fi Host Discovery (mDNS / Bonjour)

> Phase: `sdd-design` | Change: `wifi-discovery` | Date: 2026-04-27

## Technical Approach

Add an orthogonal discovery layer over the existing UDP transport. macOS publishes
`_inkbridge._udp` via `NWListener.service` from a dedicated `BonjourAdvertiser` in
`InkBridgeCore/Transport/`. Android browses with `NsdManager`, exposes results
through a `HostDiscoverer` domain port implemented by `NsdDiscoveryRepository`
(holds `MulticastLock`, serialises `resolveService` via coroutine `Mutex`).
Wire format, port (4545) and `KEY_LAST_HOST` schema are unchanged. Manual IP
entry remains as the multicast-blocked fallback. Latency budget: user-perceptible
only (target < 5 s first hit).

## Architecture Decisions

| # | Decision | Alternatives | Rationale |
|---|----------|-------------|-----------|
| 1 | Dedicated `NWListener` for advertisement, separate from `UDPListener` | Reuse data `NWListener` and attach `.service` | Data listener already runs hot; mutating its parameters risks regressions. Cost is ~1 idle listener. |
| 2 | TXT carries `host=<IPv4>` | Rely on A-record resolution | Some Android chipsets stall on `.local` resolution; pre-resolved IPv4 keeps `KEY_LAST_HOST` schema (IPv4 string). Trade-off: stale on DHCP rotation — acceptable home-LAN. |
| 3 | `HostDiscoverer` as domain port; `NsdDiscoveryRepository` as data adapter | Concrete `NsdManager` use directly in ViewModel | Clean architecture: ViewModel test uses a fake; framework types stay in `data/`. |
| 4 | Coroutine `Mutex` around `resolveService` | Use `ConcurrentLinkedQueue` of pending resolves | API < 30 NSD resolver is single-threaded; `Mutex` is the minimal correct primitive. |
| 5 | `MulticastLock` lifecycle bound to `start()`/`stop()` of repository | Acquire per-resolve | Lock per session is one acquire/release pair, simpler to reason about. |
| 6 | Discovery is ViewModel-scoped, not singleton | Application-wide singleton | Lifecycle ties cleanly to Wi-Fi tab focus; `onCleared()` releases. |
| 7 | Advertiser failure is non-fatal (log + retry once) | Surface error to UI | Server primary job is data path; users still have manual entry. |

## Data Flow

### Component diagram

```
macOS:
  InkBridgeServer ──owns──> BonjourAdvertiser ──> NWListener.service (_inkbridge._udp:4545)
  InkBridgeServer ──owns──> UDPListener ─────────> NWListener (data, :4545)

Android (clean layers):
  WifiTabContent ──> ConnectionViewModel ──> HostDiscoverer (domain)
                                                  ▲
                                                  │ impl
                                          NsdDiscoveryRepository (data)
                                                  │
                                          NsdManager + WifiManager.MulticastLock
```

### Sequence: happy path

```
Mac.start() ─► BonjourAdvertiser.start ─► service registered
Android.WifiTab focus ─► ViewModel.onTabFocused ─► HostDiscoverer.start
  ─► acquire MulticastLock ─► NsdManager.discoverServices
  ◄── onServiceFound(svc)  (Mutex acquire) ─► resolveService(svc)
  ◄── onServiceResolved   (parse TXT.host/port/version) ─► emit list
User taps host ─► ViewModel.onHostTapped ─► host field filled ─► Connect
```

### Sequence: empty / error

```
ViewModel.onTabFocused ─► HostDiscoverer.start
  ─► no onServiceFound within 2 s ─► UI shows empty-state CTA pointing to manual IP
  (or) onStartDiscoveryFailed ─► repository emits empty list, logs error
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `macos/Sources/InkBridgeCore/Transport/BonjourAdvertiser.swift` | Create | `NWListener.service` wrapper, dedicated dispatch queue |
| `macos/Sources/InkBridgeCore/Server/InkBridgeServer.swift` | Modify | Instantiate advertiser in `start(port:)`, stop in `stop()` |
| `macos/Tests/InkBridgeCoreTests/BonjourAdvertiserTests.swift` | Create | start/stop transitions, TXT serialisation, port config |
| `android/app/src/main/AndroidManifest.xml` | Modify | Add `CHANGE_WIFI_MULTICAST_STATE` |
| `android/.../domain/discovery/DiscoveredHost.kt` | Create | `data class (name, ipv4, port, version)` |
| `android/.../domain/discovery/HostDiscoverer.kt` | Create | Port: `observe(): Flow<List<DiscoveredHost>>`, `start()`, `stop()` |
| `android/.../data/discovery/NsdManagerWrapper.kt` | Create | Thin interface around `NsdManager` for fake-driven tests |
| `android/.../data/discovery/NsdDiscoveryRepository.kt` | Create | Impl: lock, listeners, `Mutex`, `MutableStateFlow<List>` |
| `android/.../ui/screens/ConnectionViewModel.kt` | Modify | Inject `HostDiscoverer`; `discoveredHosts: StateFlow`; `onTabFocused`/`onScanRequested`/`onHostTapped` |
| `android/.../ui/screens/ConnectionScreen.kt` | Modify | `WifiTabContent` adds discovery section + Search button above manual field |
| `android/.../test/.../NsdDiscoveryRepositoryTest.kt` | Create | Lock pairing, resolve serialisation |
| `android/.../test/.../ConnectionViewModelDiscoveryTest.kt` | Create | Tap fills host + triggers connect |

## Interfaces

```swift
// macOS — InkBridgeCore/Transport/BonjourAdvertiser.swift
public final class BonjourAdvertiser {
    public init(port: UInt16, hostname: String)
    public func start() throws
    public func stop()
    public var isAdvertising: Bool { get }
    // service: name "InkBridge — \(hostname)", type "_inkbridge._udp",
    // txt: ["version":"1","port":"\(port)","host":"<IPv4>"]
}
```

`InkBridgeServer.start(port:)` diff sketch — between listener creation and
`listener.start()`:

```swift
self.advertiser = BonjourAdvertiser(port: port, hostname: Host.current().localizedName ?? "Mac")
do { try advertiser?.start() } catch { log("advertiser failed; retrying"); /* retry once after 1s */ }
listener.start(queue: queue)
```

```kotlin
// Android — domain/discovery
data class DiscoveredHost(val name: String, val ipv4: String, val port: Int, val version: String)

interface HostDiscoverer {
    fun observe(): Flow<List<DiscoveredHost>>
    suspend fun start()
    suspend fun stop()
}

// data/discovery
interface NsdManagerWrapper {
    fun discoverServices(type: String, listener: NsdManager.DiscoveryListener)
    fun resolveService(info: NsdServiceInfo, listener: NsdManager.ResolveListener)
    fun stopServiceDiscovery(listener: NsdManager.DiscoveryListener)
}

class NsdDiscoveryRepository(
    private val nsd: NsdManagerWrapper,
    private val multicastLock: WifiManager.MulticastLock,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : HostDiscoverer { /* MutableStateFlow, Mutex, idempotent start/stop */ }
```

## Threading & Lifecycle

- macOS: `BonjourAdvertiser` owns a private `DispatchQueue(label: "inkbridge.bonjour")`.
  `start`/`stop` are idempotent, thread-safe (internal state guarded by the queue).
- Android: `NsdDiscoveryRepository` runs all NSD callbacks on `Dispatchers.IO`.
  ViewModel uses `viewModelScope`. `MulticastLock.acquire()` paired with `release()`
  in `stop()` via `try { ... } finally { release() }` semantics. Idempotent
  start/stop guarded by an `AtomicBoolean`.

## Error Handling

| Surface | Failure | Behavior |
|---------|---------|----------|
| macOS advertiser | `NWError` on start | Log; retry once after 1 s; if still failing, log and continue (server keeps running) |
| Android discovery | `onStartDiscoveryFailed` | Emit empty list; log with error code |
| Android resolve | `onResolveFailed` | Drop the candidate; do not block other resolves |
| Lock | acquire failure | Log; emit empty list; do not crash |
| Wi-Fi off / SSID switch | (out of scope v1) | User taps Search again; documented limitation |

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| macOS unit | `BonjourAdvertiserTests` | Verify TXT contents, name format, port; verify `isAdvertising` transitions on start/stop. Integration-style test binds to ephemeral port. |
| macOS integration | `InkBridgeServerTests` (extend) | Verify `start` instantiates advertiser; `stop` tears it down |
| Android repo unit | `NsdDiscoveryRepositoryTest` | Fake `NsdManagerWrapper`; verify lock acquire/release pairing and concurrent-find resolve serialisation |
| Android VM unit | `ConnectionViewModelDiscoveryTest` | Fake `HostDiscoverer` emits prebuilt list; verify tap fills host + triggers connect |
| Android UI | composable preview tests (preferred) | Empty-state copy, list rendering with 1+ host |

Strict TDD: all listed test files are written first in `sdd-tasks`; production
files appear only after a red test exists.

## Migration & Compatibility

- No wire format changes. No persistence schema changes.
- New `CHANGE_WIFI_MULTICAST_STATE` permission requires app re-install or
  emulator runtime accept (note for QA).
- Existing manual-host code paths untouched.

## Out of Scope (v1)

- IPv6 (TXT carries IPv4 only).
- Cross-subnet discovery.
- Persistent host favorites / friendly names.
- Auto-connect on first discovery (user must tap).
- Connectivity observation (Wi-Fi off/SSID switch).

## Open Questions

- [ ] Confirm `Host.current().localizedName` is acceptable for instance name
      across macOS 13/14 (sandbox may return generic name).
- [ ] Decide whether `NsdManagerWrapper` should also wrap API-30+
      `registerServiceInfoCallback` to prepare a future cleanup.
