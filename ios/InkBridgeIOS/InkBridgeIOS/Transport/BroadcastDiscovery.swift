import Foundation

// MARK: - BroadcastDiscovery (protocol)

/// Discovers Mac servers on the local network by sending UDP broadcast probes
/// and collecting unicast replies.
///
/// The implementation uses raw BSD sockets (`socket(AF_INET, SOCK_DGRAM, 0)`)
/// with `setsockopt(SO_BROADCAST, 1)` because `NWConnection` rejects broadcast
/// destination addresses on iOS (NWConnection cannot broadcast — engram #220).
///
/// - Important: `hosts` is a lazy `AsyncStream`. Subscribe before calling `start()`.
public protocol BroadcastDiscovery: Sendable {
    /// The stream of discovered hosts. Each host is emitted as it is found or refreshed.
    /// Subscribers should merge updates into a `HostRegistry` for dedup + staleness.
    var hosts: AsyncStream<DiscoveredHost> { get }

    /// Begins probe transmission and reply collection.
    func start() async throws

    /// Stops probe transmission, cancels the background Task, and finishes the stream.
    func stop() async
}
