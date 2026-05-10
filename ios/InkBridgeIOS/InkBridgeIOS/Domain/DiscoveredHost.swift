import Foundation

/// A Mac server discovered via UDP broadcast probe.
///
/// Equality is defined on `(ipv4, port)` only — the network identity.
/// `name` and `lastSeen` are mutable metadata and do not affect identity.
public struct DiscoveredHost: Equatable {
    public let ipv4: String
    public let port: UInt16
    public var name: String
    public var lastSeen: Date

    public init(name: String, ipv4: String, port: UInt16, lastSeen: Date) {
        self.name = name
        self.ipv4 = ipv4
        self.port = port
        self.lastSeen = lastSeen
    }

    /// Returns true if the host has not responded within `threshold` seconds of `now`.
    /// Boundary is strict: exactly at the threshold is NOT considered stale.
    public func isStale(now: Date, threshold: TimeInterval) -> Bool {
        now.timeIntervalSince(lastSeen) > threshold
    }

    // MARK: Equatable — identity on (ipv4, port) only

    public static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.ipv4 == rhs.ipv4 && lhs.port == rhs.port
    }
}
