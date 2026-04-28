# Exploration: Wi-Fi Host Discovery via mDNS / Bonjour

> Phase: `sdd-explore` | Change: `wifi-discovery` | Date: 2026-04-27

---

## Current State

The Android client requires the user to manually type the macOS server's IPv4 address
into a `WifiTabContent` `OutlinedTextField` (ConnectionScreen.kt:279–299). Validation
at line 560 is strict IPv4-only (`IPV4_REGEX`). There is no discovery mechanism on
either side — confirmed by codebase-wide grep with zero hits for NsdManager, NWBrowser,
NetServiceBrowser, or any mDNS/Bonjour API.

On macOS, `UDPListener.swift` binds `NWListener` on `0.0.0.0:4545` using
`NWParameters.udp` without a `service` parameter (line 86–92). The server wires both
UDP and TCP listeners in `InkBridgeServer.start()`. The `ServerViewModel` is the
single owner of server lifecycle and the right place to own a new `BonjourAdvertiser`.

On Android, `ConnectionViewModel` owns `ConnectionManager` and `SettingsRepository`.
`SettingsRepository` persists `KEY_LAST_HOST` for the last connected host. There is no
repository-level concept of "discovered hosts". `AndroidManifest.xml` declares only
`INTERNET` and `VIBRATE` — `CHANGE_WIFI_MULTICAST_STATE` is absent.

---

## Affected Areas

### Android
- `android/app/src/main/AndroidManifest.xml` — add `CHANGE_WIFI_MULTICAST_STATE`
- `android/app/src/main/kotlin/com/inkbridge/ui/screens/ConnectionScreen.kt` — update `WifiTabContent` to show discovery list; update `validateHost` to accept hostnames (mDNS `.local` addresses) in addition to IPv4
- `android/app/src/main/kotlin/com/inkbridge/data/connection/ConnectionManager.kt` — no change (receives resolved IP from discovery)
- `android/app/src/main/kotlin/com/inkbridge/data/transport/UdpStylusClient.kt` — no change (already calls `InetAddress.getByName` which resolves `.local` via mDNS on Android)
- `android/app/src/main/kotlin/com/inkbridge/data/settings/SettingsRepository.kt` — no change; `KEY_LAST_HOST` stores the resolved IP after successful connect, so it stays compatible
- New file: `android/app/src/main/kotlin/com/inkbridge/data/discovery/NsdDiscoveryRepository.kt` — implements `HostDiscoverer` interface; wraps `NsdManager`
- New file: `android/app/src/main/kotlin/com/inkbridge/domain/model/DiscoveredHost.kt` — value object `(name: String, host: String, port: Int)`
- New interface: `android/app/src/main/kotlin/com/inkbridge/domain/model/HostDiscoverer.kt` — `Flow<List<DiscoveredHost>>` + `startDiscovery()` / `stopDiscovery()`
- `android/app/src/main/kotlin/com/inkbridge/ui/screens/ConnectionViewModel.kt` — accept `HostDiscoverer`, expose `discoveredHosts: StateFlow<List<DiscoveredHost>>`

### macOS
- New file: `macos/Sources/InkBridgeCore/Transport/BonjourAdvertiser.swift` — wraps `NWListener` service parameter OR `NetService`; protocol-backed for testability
- New protocol: `macos/Sources/InkBridgeCore/Transport/ServiceAdvertiser.swift` — `start()`, `stop()`, `@Published state`
- `macos/Sources/InkBridge/ServerViewModel.swift` — own a `BonjourAdvertiser`; call `advertiser.start()` alongside `server.start()`, `advertiser.stop()` alongside `server.stop()`

### Tests (new)
- `android/.../data/discovery/NsdDiscoveryRepositoryTest.kt` — fake `NsdManager` source, tests `DiscoveredHost` emission and lifecycle
- `macos/Tests/InkBridgeCoreTests/BonjourAdvertiserTests.swift` — `MockServiceAdvertiser` protocol double; tests state transitions

---

## Approaches

### 1. NWListener.service parameter (macOS) — preferred
Apple Network.framework allows setting a `service` parameter on `NWListener` directly:

```swift
let params = NWParameters.udp
let listener = try NWListener(using: params, on: nwPort)
listener.service = NWListener.Service(
    name: "InkBridge",          // human-readable instance name
    type: "_inkbridge._udp",    // service type — browseable by Android NSD
    domain: "local.",
    txtRecord: NWTXTRecord(["version": "1"])
)
listener.start(queue: .global(qos: .userInteractive))
```

`NWListener.Service` is available from macOS 10.14+. The project targets macOS 13
(Package.swift line 5), so this is fully available. Setting `.service` causes the
system Bonjour daemon to register the service on behalf of the process — no separate
`NetService` object needed, no run-loop dance.

**The service parameter MUST be set BEFORE `start()` is called.** Setting it after
`start()` has no documented effect and will likely be silently ignored.

- Pros: single API surface, Network.framework is already imported in UDPListener.swift, service lifecycle tied to listener lifetime (auto-deregisters on cancel)
- Cons: requires splitting the UDPListener.start() into parameter-setup + start phases, or creating a dedicated `BonjourAdvertiser` that owns its own `NWListener` purely for advertising (cleaner separation of concerns)
- Effort: Low–Medium

### 2. NetService / NSNetService (macOS) — legacy
The Objective-C `NetService` API is available but deprecated since macOS 12 and requires
run-loop scheduling. Network.framework supersedes it.

- Pros: more documentation/examples in the wild
- Cons: deprecated, requires run-loop, adds `Foundation` boilerplate, likely removed in a future SDK
- Effort: Medium (more code for less)

### 3. Android NsdManager — the only viable option for Android (not an alternative)
`NsdManager` is Android's mDNS client. Key constraints:

**`MulticastLock` is mandatory** for receiving mDNS announcements on Wi-Fi. Without
acquiring `WifiManager.MulticastLock` before calling `discoverServices`, the Android
Wi-Fi chip silently drops multicast frames and discovery returns no results. This is
the single most-missed requirement in every mDNS Android integration.

Acquire pattern (must be in `NsdDiscoveryRepository`):
```kotlin
val wm = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
val lock = wm.createMulticastLock("inkbridge-nsd")
lock.setReferenceCounted(false)
lock.acquire()
// ... discoverServices ...
// Release when ViewModel is cleared
lock.release()
```

**API 30+ path** (`registerServiceInfoCallback`): The project's `minSdk = 26`
(build.gradle.kts line 15). `NsdManager.registerServiceInfoCallback` is API 34+, so
it is NOT safe to use as the primary path. For API 26–33, `resolveService` must be
used with a serialisation guard (only one `resolveService` call in flight at a time,
because the NsdManager's resolver is single-threaded up to API 33). The correct
approach is a coroutine-based serialisation queue (a `Mutex` or a `Channel`) in
`NsdDiscoveryRepository`.

**Discovery lifecycle**: `discoverServices` starts a continuous scan. Each
`onServiceFound` callback gives an `NsdServiceInfo` with name and type but no IP/port.
A separate `resolveService` call (or `registerServiceInfoCallback` on API 34+) is
needed to get the host address and port. The resolved IP is what gets passed to
`ConnectionManager.connect()`.

---

## Recommendation

**Approach: NWListener.service on macOS + NsdManager on Android (the only feasible path)**

On macOS, create a standalone `BonjourAdvertiser` in the Transport layer that owns
its own `NWListener` purely for service registration — separate from the data
`UDPListener`. This is cleaner than modifying `UDPListener` to accept a service
parameter, because `UDPListener` should remain focused on data transport.
`BonjourAdvertiser` implements a `ServiceAdvertiser` protocol so `ServerViewModel` tests
can use a `MockServiceAdvertiser`.

On Android, create a `NsdDiscoveryRepository` in the `data/discovery` package that
implements a `HostDiscoverer` domain interface. The repository acquires `MulticastLock`,
calls `discoverServices("_inkbridge._udp", ...)`, and serialises `resolveService` calls
through a coroutine mutex. It emits `Flow<List<DiscoveredHost>>`. The `ConnectionViewModel`
receives the `HostDiscoverer` interface via constructor injection (keeping it testable
without NsdManager). `WifiTabContent` shows the discovered list inline, above the manual
entry field — auto-scan starts when the Wi-Fi tab is selected.

Manual IP entry remains the fallback: if the list is empty, the user types an IP. The
`validateHost` function needs to be updated to accept `.local` hostnames (produced by
mDNS resolution) in addition to raw IPv4. This is because `NsdServiceInfo.host` on
Android returns an `InetAddress` whose `hostAddress` is a resolved IPv4 — but the
service instance name resolution may also produce a `.local` hostname in some API
levels. Safest: accept both IPv4 and any non-blank string that passes a DNS-name regex.

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `MulticastLock` not acquired → silent zero results | High | Acquire lock in `NsdDiscoveryRepository.startDiscovery()` before calling `discoverServices`. Release in `stopDiscovery()`. Test with a FakeNsdManager that returns events. |
| NsdManager `resolveService` concurrent calls crash on API < 30 | High | Wrap all resolve calls in a `Mutex`-guarded coroutine. Only one in-flight at a time. |
| `NWListener.service` set after `start()` → silently ignored | Medium | `BonjourAdvertiser.start()` sets service parameter in the `NWParameters` before calling `listener.start()`. Add a unit test that asserts `isAdvertising == true` after `start()`. |
| Network blocks multicast (guest Wi-Fi, corporate) | Medium | Manual IP fallback always available. Show a "No servers found" empty state with a "Enter IP manually" CTA. |
| `validateHost` rejects `.local` after discovery resolves to hostname | Medium | Update regex to accept hostnames. Or, resolve to IPv4 in `NsdDiscoveryRepository` before passing to ViewModel. Prefer resolving in repo so the transport layer never sees hostnames. |
| `CHANGE_WIFI_MULTICAST_STATE` permission missing causes SecurityException | High | Add to AndroidManifest.xml. Verify with a unit test on the repository that the permission is declared. |
| `BonjourAdvertiser` lifecycle: advertiser stops if macOS network interface changes | Low | `NWListener` state updates fire `stateUpdateHandler`. Restart on `.failed` state, similar to how `UsbTunnelMaintainer` handles errors. |

---

## Threading / Lifecycle

### Android — where NsdManager lives
`NsdDiscoveryRepository` should be a **ViewModel-scoped** object, NOT a singleton.
Discovery is only needed while the `ConnectionScreen` is active. `ConnectionViewModel`
owns the `HostDiscoverer` reference and calls `startDiscovery()` in `init` when the
last known transport was Wi-Fi, or lazily when the user selects the Wi-Fi tab.
`stopDiscovery()` is called in `onCleared()` alongside transport teardown.

`NsdManager` callbacks arrive on the thread the manager was created on (or a background
thread on newer APIs). The repository must marshal emissions to `Dispatchers.IO` and
let the StateFlow/SharedFlow handle main-thread delivery. Do NOT call `resolveService`
from the `onServiceFound` callback directly — enqueue via a Channel.

### macOS — where BonjourAdvertiser starts
`BonjourAdvertiser.start()` is called from `ServerViewModel.init()` after `server.start()`.
Both are `@MainActor`. The `NWListener` inside `BonjourAdvertiser` runs on
`.global(qos: .userInteractive)` (consistent with `UDPListener`). `BonjourAdvertiser.stop()`
is called in `ServerViewModel`'s deinit or when server stops.

---

## Test Boundaries

### Unit-testable (fakes only)
- `NsdDiscoveryRepository` — inject a fake `NsdManager` source (a function or interface) that emits `NsdServiceInfo` events. Test: discovered hosts appear in the Flow; resolve serialisation works; MulticastLock is acquired/released.
- `BonjourAdvertiser` — inject a `ServiceAdvertiser` protocol double (`MockServiceAdvertiser`). Test: `ServerViewModel` calls `start()` when trusted and `stop()` on server stop.
- `ConnectionViewModel` — inject `HostDiscoverer` fake. Test: `discoveredHosts` StateFlow updates; tapping a discovered host fills the host field.
- `WifiTabContent` — pure Composable, no discovery logic; preview-testable.

### Integration-only (requires real hardware / network)
- Actual mDNS packet exchange between Android and macOS
- `MulticastLock` effectiveness on real Wi-Fi (varies by chipset)
- mDNS TTL / re-announcement timing

---

## UI Integration Sketch

`WifiTabContent` currently renders only one `OutlinedTextField` for the host IP.
The updated layout (within the existing scrollable `Column` in `ConnectionScreen`):

```
┌─────────────────────────────────────────────┐
│ Discovered on this network                  │
│ ┌───────────────────────────────────────┐   │
│ │ ○  InkBridge (MacBook Pro)   ←tap→  │   │
│ │ ○  InkBridge (Mac Studio)           │   │
│ └───────────────────────────────────────┘   │
│                                             │
│ ── or enter manually ─────────────────────  │
│  [Host IP field]                            │
└─────────────────────────────────────────────┘
```

**Auto-scan on tab open** (no explicit Search button): Discovery starts automatically
when the user selects the Wi-Fi tab. A `CircularProgressIndicator` (small, inline)
appears next to "Discovered on this network" while scanning. If the list is empty after
5 seconds, show "No servers found on this network". The manual field is always visible
and usable regardless of discovery state.

Tapping a discovered host: fills the host field with the resolved IPv4 address and
clears any validation error. The user then presses Connect. This keeps the existing
`onConnect` callback contract intact — no protocol change needed.

---

## Fallback Compatibility

`KEY_LAST_HOST` stores a resolved IPv4 string. mDNS discovery always resolves to IPv4
before passing to the ViewModel. Therefore `KEY_LAST_HOST` is fully backward-compatible:
it continues to work for auto-reconnect, and the manual field still accepts it. No data
migration needed.

---

## Open Questions

1. Should the `BonjourAdvertiser` be part of `InkBridgeCore` (testable library) or live
   in the `InkBridge` app target? The `UsbTunnelMaintainer` lives in `InkBridgeCore` —
   the same pattern should apply so the advertiser is unit-testable from `InkBridgeCoreTests`.
2. Service instance name: use `"InkBridge"` as a fixed string, or include the Mac's
   hostname (e.g., `"InkBridge (\(Host.current().localizedName ?? "Mac"))"`)? The latter
   helps users with multiple Macs on the same network. Apple's convention uses the machine
   name — recommend following that convention.
3. Should the TXT record include a `host` field (the IPv4 of the Mac) in addition to
   `version=1`? Some Android NSD implementations fail to resolve the A record for `.local`
   hostnames; embedding the IP in the TXT record avoids a second DNS-SD resolution step.
   Trade-off: TXT record IP can get stale if the Mac's IP changes. Low risk on home
   networks (DHCP with long lease), but worth noting.
4. Discovery scope: should Android stop discovery as soon as one host is tapped (to
   release `MulticastLock` early), or keep scanning until `onCleared()`? Recommendation:
   keep scanning to handle the case where the user dismisses the selection and reconnects
   to a different host.

---

## Ready for Proposal

Yes. The approach is unambiguous, the constraints are fully catalogued, and no
clarification is needed before writing the proposal. The open questions above are design
details that the proposal phase can resolve with lightweight decisions.
