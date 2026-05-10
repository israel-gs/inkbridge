import XCTest
@testable import InkBridgeIOS

// MARK: - HostRegistryTests (D.3 + D.5)

final class HostRegistryTests: XCTestCase {

    // MARK: D.3 — Stale host pruning

    func test_hostRegistry_stalenessAtExactThreshold_isNotStale() async {
        // Boundary: exactly at 10 s threshold → NOT stale (strictly > threshold = prune)
        let now = Date()
        let host = DiscoveredHost(
            name: "Mac",
            ipv4: "192.168.1.10",
            port: 4545,
            lastSeen: now.addingTimeInterval(-10.0)
        )
        var fakeClock = now
        let registry = HostRegistry(clock: { fakeClock })

        await registry.ingest(host)
        let snapshot1 = await registry.snapshot()
        XCTAssertEqual(snapshot1.count, 1, "Host at exactly 10 s should not be pruned yet")

        // Advance past threshold by 1 ms
        fakeClock = now.addingTimeInterval(0.001)
        // Force a prune sweep
        await registry.pruneSweep()
        let snapshot2 = await registry.snapshot()
        XCTAssertEqual(snapshot2.count, 0, "Host older than 10 s must be pruned")
    }

    func test_hostRegistry_stalenessStrictlyGreaterThan10s_isPruned() async {
        let now = Date()
        let host = DiscoveredHost(
            name: "Mac",
            ipv4: "192.168.1.10",
            port: 4545,
            lastSeen: now.addingTimeInterval(-11.0)
        )
        var fakeClock = now
        let registry = HostRegistry(clock: { fakeClock })
        await registry.ingest(host)

        // Even at "now", the host is 11 s stale — prune immediately
        await registry.pruneSweep()
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 0)
        _ = fakeClock // suppress unused warning
    }

    func test_hostRegistry_freshHost_isKept() async {
        let now = Date()
        let host = DiscoveredHost(
            name: "Mac",
            ipv4: "192.168.1.10",
            port: 4545,
            lastSeen: now.addingTimeInterval(-5.0)
        )
        let fakeClock = now
        let registry = HostRegistry(clock: { fakeClock })
        await registry.ingest(host)
        await registry.pruneSweep()
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 1)
    }

    // MARK: D.3 — Dedup by (ipv4, port)

    func test_hostRegistry_dedupSameIPPort_newerWins() async {
        let now = Date()
        let older = DiscoveredHost(
            name: "Old Name",
            ipv4: "192.168.1.10",
            port: 4545,
            lastSeen: now.addingTimeInterval(-3.0)
        )
        let newer = DiscoveredHost(
            name: "New Name",
            ipv4: "192.168.1.10",
            port: 4545,
            lastSeen: now.addingTimeInterval(-1.0)
        )
        let registry = HostRegistry(clock: { now })
        await registry.ingest(older)
        await registry.ingest(newer)
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 1, "Dedup must produce exactly one entry")
        XCTAssertEqual(snapshot.first?.name, "New Name", "Newer lastSeen must win")
    }

    func test_hostRegistry_differentIPs_bothKept() async {
        let now = Date()
        let h1 = DiscoveredHost(name: "Mac 1", ipv4: "192.168.1.10", port: 4545, lastSeen: now)
        let h2 = DiscoveredHost(name: "Mac 2", ipv4: "192.168.1.11", port: 4545, lastSeen: now)
        let registry = HostRegistry(clock: { now })
        await registry.ingest(h1)
        await registry.ingest(h2)
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 2)
    }

    func test_hostRegistry_sameIPDifferentPort_bothKept() async {
        let now = Date()
        let h1 = DiscoveredHost(name: "Mac A", ipv4: "192.168.1.10", port: 4545, lastSeen: now)
        let h2 = DiscoveredHost(name: "Mac B", ipv4: "192.168.1.10", port: 4546, lastSeen: now)
        let registry = HostRegistry(clock: { now })
        await registry.ingest(h1)
        await registry.ingest(h2)
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 2)
    }

    // MARK: D.5 — Probe interval seam (indirect: verify ingest + snapshot roundtrip)

    func test_hostRegistry_emptyInitially() async {
        let registry = HostRegistry(clock: { Date() })
        let snapshot = await registry.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
    }
}
