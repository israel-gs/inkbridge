import Foundation

// MARK: - HostRegistry

/// Actor-isolated registry of discovered Mac hosts.
///
/// Responsibilities:
/// - **Dedup**: keyed by `(ipv4, port)` — newer `lastSeen` wins on collision.
/// - **Staleness sweep**: entries with `now - lastSeenAt > DISCOVERY_STALE_PRUNE_S` are removed.
///
/// The sweep is driven externally — either by `BSDBroadcastDiscovery`'s
/// periodic Task, or directly in tests via `pruneSweep()`.
///
/// The `clock` dependency is injected so tests can control time deterministically.
///
/// Constants (spec §Discovery):
/// - `DISCOVERY_STALE_PRUNE_S = 10 s` — staleness threshold (strictly greater-than).
public actor HostRegistry {

    // MARK: - Constants

    public static let stalenessThreshold: TimeInterval = 10.0

    // MARK: - State

    /// Key: (ipv4, port) as a composite string for simple dictionary keying.
    private var entries: [String: DiscoveredHost] = [:]

    /// Injected clock — returns `Date()` by default; overridden in tests.
    private let clock: @Sendable () -> Date

    // MARK: - Initializer

    /// - Parameter clock: Returns the current time. Default is `Date.init`.
    public init(clock: @escaping @Sendable () -> Date = Date.init) {
        self.clock = clock
    }

    // MARK: - Public API

    /// Ingests a discovered host.
    ///
    /// If an entry with the same `(ipv4, port)` already exists, the one with the
    /// newer `lastSeen` date wins (dedup semantics).
    public func ingest(_ host: DiscoveredHost) {
        let key = registryKey(host)
        if let existing = entries[key] {
            if host.lastSeen > existing.lastSeen {
                entries[key] = host
            }
        } else {
            entries[key] = host
        }
    }

    /// Returns a snapshot of all non-stale hosts at the current clock time.
    public func snapshot() -> [DiscoveredHost] {
        Array(entries.values)
    }

    /// Removes hosts whose `lastSeen` is more than `stalenessThreshold` seconds
    /// before the current clock time. Boundary: strictly greater than — exactly at
    /// threshold is NOT pruned.
    public func pruneSweep() {
        let now = clock()
        entries = entries.filter { _, host in
            !host.isStale(now: now, threshold: Self.stalenessThreshold)
        }
    }

    // MARK: - Private

    private func registryKey(_ host: DiscoveredHost) -> String {
        "\(host.ipv4):\(host.port)"
    }
}
