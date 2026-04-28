# wifi-discovery Specification

> Phase: `sdd-spec` | Change: `wifi-discovery` | Date: 2026-04-27

> **Note (2026-04-28)**: this spec captures the original mDNS/Bonjour design.
> During implementation we discovered that Samsung NSD did not reliably receive
> mDNS responses from `NWListener.service` or even `mDNSResponder` on a real
> LAN — only the initial announcement burst was caught, with worst-case
> discovery time approaching 45 s. The shipped implementation replaces mDNS
> with a custom UDP broadcast probe on port `4546` (`INKB?` →
> `INKB!<v>|<dataPort>|<hostname>`) which discovers the host in <60 ms
> deterministically. See the README's "Discovery sub-protocol" section and
> `BroadcastResponder.swift` / `BroadcastDiscoveryRepository.kt`.

## Purpose

Defines behavior for automatic InkBridge server discovery over local Wi-Fi using
mDNS/Bonjour. Covers macOS service advertisement (`bonjour-advertisement`) and Android
service browsing (`host-discovery`), including UI presentation and lifecycle management.

---

## macOS — `bonjour-advertisement`

### Requirement: Service Publication

The `BonjourAdvertiser` MUST publish a `_inkbridge._udp` service on port 4545 when
`start()` is called. The `NWListener.service` configuration MUST be set on
`NWParameters` before `listener.start()` is called — setting it after is silently
ignored.

#### Scenario: Happy path — advertiser starts

- GIVEN the macOS server is initialized and not yet advertising
- WHEN `BonjourAdvertiser.start()` is called
- THEN a `_inkbridge._udp` service is visible on the local network on port 4545

#### Scenario: Listener config order enforced

- GIVEN a `BonjourAdvertiser` instance
- WHEN `start()` is called
- THEN `NWListener.service` is configured on `NWParameters` BEFORE `listener.start()`
  is invoked — verifiable in unit test by asserting the service is set on parameters,
  not patched post-start

---

### Requirement: TXT Record Content

The published TXT record MUST contain exactly three keys: `version=1`, `port=4545`,
and `host=<IPv4>` where `<IPv4>` is the primary IPv4 address of the currently active
network interface.

#### Scenario: TXT record keys present

- GIVEN a running `BonjourAdvertiser`
- WHEN a client resolves the service
- THEN the TXT record contains `version=1`, `port=4545`, and a dotted-decimal `host`
  value matching the Mac's active interface IPv4

#### Scenario: No IPv4 available

- GIVEN the Mac has no active IPv4 interface (VPN-only or offline)
- WHEN `start()` is called
- THEN `BonjourAdvertiser` MUST NOT advertise a `host` value that is empty or `nil`;
  it SHOULD omit the `host` key or use `127.0.0.1` and log a warning

---

### Requirement: Instance Name

The service instance name MUST be `InkBridge — <hostname>` where `<hostname>` is
`Host.current().localizedName ?? ProcessInfo.processInfo.hostName`.

#### Scenario: Single Mac on network

- GIVEN one Mac running InkBridge
- WHEN Android discovers the service
- THEN the displayed name is `InkBridge — <Mac's localized hostname>`

#### Scenario: Multiple Macs on network

- GIVEN two Macs named "Studio" and "Laptop" both running InkBridge
- WHEN Android discovers services
- THEN two entries appear: `InkBridge — Studio` and `InkBridge — Laptop`, each with
  their own distinct IPv4 in the TXT record

---

### Requirement: Clean Stop

`BonjourAdvertiser.stop()` MUST cancel the `NWListener` and withdraw the Bonjour
advertisement. No stale records MUST remain after stop completes.

#### Scenario: Server stops

- GIVEN a running advertiser
- WHEN `stop()` is called
- THEN `dns-sd -B _inkbridge._udp` returns no instances within 2 seconds

---

### Requirement: Restart After Stop

Calling `start()` after a previous `stop()` MUST publish a fresh advertisement with
current TXT record values. No stale state from the previous session MAY persist.

#### Scenario: Stop then start

- GIVEN an advertiser that was previously started and then stopped
- WHEN `start()` is called again
- THEN a fresh `_inkbridge._udp` advertisement appears with an up-to-date `host` value

---

## Android — `host-discovery`

### Requirement: Domain Interface Contract

`HostDiscoverer` MUST be a domain interface returning `Flow<List<DiscoveredHost>>`,
with `startDiscovery()` and `stopDiscovery()` lifecycle methods. It MUST NOT expose
any NSD or platform types.

#### Scenario: Interface shape

- GIVEN `HostDiscoverer` is defined
- WHEN a ViewModel collects its `hosts` flow
- THEN the flow emits `List<DiscoveredHost>` containing `name: String`, `ipv4: String`,
  and `port: Int`

---

### Requirement: MulticastLock Lifecycle

`NsdDiscoveryRepository` MUST acquire a `MulticastLock` before calling
`NsdManager.discoverServices` and MUST release it in `stopDiscovery()` and
`onCleared()`. The lock MUST be re-acquired at the start of each new discovery session.

#### Scenario: Lock acquired before discovery

- GIVEN a fresh `NsdDiscoveryRepository`
- WHEN `startDiscovery()` is called
- THEN `MulticastLock.acquire()` is called before `NsdManager.discoverServices`

#### Scenario: Lock released on stop

- GIVEN an active discovery session
- WHEN `stopDiscovery()` is called
- THEN `MulticastLock.release()` is called

#### Scenario: Multicast-blocked network

- GIVEN the network blocks multicast (corporate or guest Wi-Fi)
- WHEN discovery runs for more than 2 seconds with no results
- THEN the `hosts` flow emits an empty list and the empty state CTA is shown;
  manual IP entry remains fully functional

---

### Requirement: Serialized Resolve

Only one `resolveService` call MAY be in flight at a time. Additional
`onServiceFound` callbacks MUST be queued and processed sequentially via a coroutine
`Mutex`.

#### Scenario: Single resolve in flight

- GIVEN a burst of 3 simultaneous `onServiceFound` callbacks
- WHEN `NsdDiscoveryRepository` processes them
- THEN only one `resolveService` call is active at any moment; all three are eventually
  resolved without a crash or dropped entry

---

### Requirement: IPv4 Resolution

`DiscoveredHost.ipv4` MUST be populated from `serviceInfo.host.hostAddress` (dotted-
decimal IPv4). The domain layer MUST NOT emit `.local` hostnames or IPv6 addresses to
the transport layer, and `KEY_LAST_HOST` MUST remain an IPv4 string.

#### Scenario: Host resolved to IPv4

- GIVEN a service is resolved
- WHEN `onServiceResolved` fires
- THEN `DiscoveredHost.ipv4` is a valid dotted-decimal IPv4 (e.g. `192.168.1.42`)
  and never a `.local` address

---

### Requirement: Service Type

The NSD discovery service type MUST be `_inkbridge._udp.` (with trailing dot as
required by mDNS).

#### Scenario: Correct service type

- GIVEN `NsdDiscoveryRepository.startDiscovery()` is called
- WHEN `NsdManager.discoverServices` is invoked
- THEN the service type argument is exactly `_inkbridge._udp.`

---

### Requirement: Permission Declaration

`CHANGE_WIFI_MULTICAST_STATE` MUST be declared in `AndroidManifest.xml` at the
`uses-permission` level.

#### Scenario: Manifest contains permission

- GIVEN the built APK
- WHEN the manifest is inspected
- THEN `<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>`
  is present

---

### Requirement: Discovery Lifecycle Bound to UI

Discovery MUST start when `WifiTab` gains focus and MUST stop when it loses focus
or the `ConnectionViewModel` is cleared (`onCleared()`).

#### Scenario: Tab gains focus

- GIVEN the user navigates to the Wi-Fi tab
- WHEN the composable enters composition
- THEN `HostDiscoverer.startDiscovery()` is called

#### Scenario: Tab loses focus

- GIVEN an active discovery session
- WHEN the user navigates away from the Wi-Fi tab
- THEN `HostDiscoverer.stopDiscovery()` is called and the `MulticastLock` is released

#### Scenario: ViewModel cleared

- GIVEN an active discovery session
- WHEN the Activity is destroyed or the ViewModel is cleared
- THEN `HostDiscoverer.stopDiscovery()` is called from `onCleared()`

---

### Requirement: Tap to Connect

Tapping a discovered host MUST fill the host field with the resolved IPv4 and trigger
the existing connect flow. Manual IP entry MUST remain functional and take precedence
if the user subsequently edits the field.

#### Scenario: Tap discovered host

- GIVEN the discovered-hosts list shows one entry `InkBridge — Studio (192.168.1.42)`
- WHEN the user taps it
- THEN the host field is populated with `192.168.1.42` and the connect flow is triggered

#### Scenario: Tap then manual override

- GIVEN the user tapped a discovered host (field shows `192.168.1.42`)
- WHEN the user clears the field and types `10.0.0.5` manually
- THEN `10.0.0.5` is used for connection — the manual value wins

---

### Requirement: Empty State

When discovery returns zero results after more than 2 seconds, the UI MUST display
"No servers found — enter IP manually" as a CTA. The manual entry field MUST remain
visible and editable at all times.

#### Scenario: No servers after timeout

- GIVEN discovery has been running for more than 2 seconds
- WHEN the `hosts` flow emits an empty list
- THEN the text "No servers found — enter IP manually" is visible above the manual
  field, which remains editable

---

### Requirement: Lost Service Removal

When `NsdManager.onServiceLost` fires for a previously discovered host, that host
MUST be removed from the visible list immediately.

#### Scenario: Mac goes offline mid-scan

- GIVEN one host is visible in the discovered-hosts list
- WHEN the macOS server stops or the Mac leaves the network
- THEN `onServiceLost` fires and the entry disappears from the list

---

## Cross-Side Scenarios

### Scenario: macOS server restarts during active Android scan

- GIVEN Android is actively browsing and the Mac appears in the list
- WHEN the macOS server is stopped and started again
- THEN `onServiceLost` removes the old entry; the restarted server's
  `onServiceFound`/resolve cycle adds a fresh entry with the current IPv4

### Scenario: Rapid serviceFound burst — no crash

- GIVEN 5 `onServiceFound` callbacks arrive within 100 ms
- WHEN `NsdDiscoveryRepository` processes them via the Mutex queue
- THEN no crash occurs, all 5 are eventually resolved, and the list shows up to 5 entries
