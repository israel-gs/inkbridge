# Proposal: Wi-Fi Host Discovery via mDNS / Bonjour

> Phase: `sdd-propose` | Change: `wifi-discovery` | Date: 2026-04-27

## Intent

Eliminate manual IPv4 entry as the only path to connect over Wi-Fi. Today users must
type the macOS server's IP into `WifiTabContent`. The macOS server advertises nothing,
the Android client browses nothing. We add mDNS/Bonjour: the Mac advertises an
`_inkbridge._udp` service on port 4545, Android browses for it, and the user taps a
discovered host instead of typing an IP. Manual entry stays as a fallback for networks
that block multicast.

## Scope

### In Scope
- macOS: `BonjourAdvertiser` in `InkBridgeCore/Transport/` wrapping `NWListener.service`, started/stopped by `InkBridgeServer`.
- Android: `CHANGE_WIFI_MULTICAST_STATE` permission, `HostDiscoverer` domain interface, `NsdDiscoveryRepository` with `MulticastLock` lifecycle and serialised `resolveService`.
- Android: `WifiTabContent` shows a discovered-hosts list above the manual IP field, with a Search button to re-trigger scan.
- Tests: Android `HostDiscoverer` fake driving ViewModel + UI tests; macOS unit test for `BonjourAdvertiser` config and start/stop transitions.

### Out of Scope
- Wire format changes (binary little-endian stays).
- Port change (4545 stays for both UDP data and mDNS service).
- Manual IP entry removal (stays as fallback).
- `KEY_LAST_HOST` persistence schema changes (stays IPv4 string).
- IPv6 advertising or multi-interface bonding.

## Capabilities

### New Capabilities
- `wifi-discovery`: mDNS-based automatic discovery of InkBridge servers on the local Wi-Fi network, covering macOS service advertising, Android service browsing, and the discovered-hosts UI.

### Modified Capabilities
- None. The `wifi-transport` capability does not exist as a spec yet, and this change does not alter wire-level UDP behavior — it adds an orthogonal discovery layer.

## Approach

**macOS** — `BonjourAdvertiser` (in `InkBridgeCore`) owns a dedicated `NWListener`
configured purely for service registration, separate from `UDPListener`'s data path.
Service config is set on `NWParameters` BEFORE `listener.start()`. Service type
`_inkbridge._udp`, instance name `InkBridge — <hostname>` (where `<hostname>` is
`Host.current().localizedName`), TXT record `version=1`, `port=4545`, `host=<IPv4>`.
Embedding the IPv4 in TXT lets Android skip A-record resolution on flaky chipsets;
trade-off is staleness if the Mac's DHCP lease rotates — acceptable on home Wi-Fi.

**Android** — `NsdDiscoveryRepository` implements the `HostDiscoverer` domain
interface, ViewModel-scoped (not singleton). On `startDiscovery()`: acquire
`MulticastLock`, call `discoverServices("_inkbridge._udp", ...)`, serialise
`resolveService` calls through a `Mutex` (NSD resolver is single-threaded pre-API-30).
Resolve to IPv4 before emitting `DiscoveredHost(name, host, port)` so the transport
layer never sees `.local` hostnames and `KEY_LAST_HOST` stays IPv4. Discovery runs
while the Wi-Fi tab is active; stops on tab leave or `onCleared()`. `MulticastLock`
re-acquired per session.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `android/app/src/main/AndroidManifest.xml` | Modified | Add `CHANGE_WIFI_MULTICAST_STATE` |
| `android/app/.../domain/model/HostDiscoverer.kt` | New | Domain interface: `Flow<List<DiscoveredHost>>`, `start/stop` |
| `android/app/.../domain/model/DiscoveredHost.kt` | New | Value object `(name, host, port)` |
| `android/app/.../data/discovery/NsdDiscoveryRepository.kt` | New | NsdManager + MulticastLock impl |
| `android/app/.../ui/screens/ConnectionViewModel.kt` | Modified | Inject `HostDiscoverer`, expose `discoveredHosts` StateFlow |
| `android/app/.../ui/screens/ConnectionScreen.kt` | Modified | `WifiTabContent` lists discovered hosts + Search button |
| `macos/Sources/InkBridgeCore/Transport/BonjourAdvertiser.swift` | New | `NWListener.service` wrapper |
| `macos/Sources/InkBridgeCore/Transport/InkBridgeServer.swift` | Modified | Start/stop advertiser around listener |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `MulticastLock` not held → silent zero results | High | Acquire before `discoverServices`, release in `stopDiscovery`; covered by repository test |
| Concurrent `resolveService` crash on API < 30 | Medium | Coroutine `Mutex` serialises all resolves; one in flight at a time |
| Network blocks multicast (corporate/guest Wi-Fi) | Medium | Manual IP fallback always visible; empty-state CTA points users to it |

## Rollback Plan

The change is additive and gated by UI. To revert:
1. Remove `CHANGE_WIFI_MULTICAST_STATE` from `AndroidManifest.xml`.
2. Revert `WifiTabContent` to the manual-only field (one-file change).
3. Stop calling `BonjourAdvertiser.start/stop` in `InkBridgeServer`; delete the
   advertiser file. The `UDPListener` data path is untouched, so reverting the
   advertiser does not affect existing connections.
4. `KEY_LAST_HOST` schema is unchanged, so users keep their last IP.

## Dependencies

- Android `minSdk = 26` already supports `NsdManager` (API 16+). No bump needed.
- macOS target is 13+; `NWListener.Service` is available from macOS 10.14+. No bump needed.

## Success Criteria

- [ ] Fresh Android install on the same Wi-Fi as a running Mac shows the Mac in the discovered-hosts list within 5 seconds without typing.
- [ ] Tapping a discovered host populates the host field with a valid IPv4 and Connect succeeds.
- [ ] Manual IP entry still works on networks with multicast disabled (verified on a guest Wi-Fi or via emulator with multicast blocked).
- [ ] `MulticastLock` is acquired exactly once per discovery session and released on tab leave (verified via repository unit test).
- [ ] macOS advertiser stops cleanly on server stop (no dangling Bonjour registration; verified via `dns-sd -B _inkbridge._udp` after server stop returns no instances).
- [ ] All existing tests still pass; new tests for `NsdDiscoveryRepository`, `ConnectionViewModel.discoveredHosts`, and `BonjourAdvertiser` are green.
