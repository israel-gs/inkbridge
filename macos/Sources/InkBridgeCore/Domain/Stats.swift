import Foundation

/// Telemetry counters for the InkBridge macOS server.
///
/// Updated after each packet is processed. Thread safety is the caller's
/// responsibility — ``InkBridgeServer`` publishes snapshots on the main actor.
public struct Stats: Equatable {
    /// Total packets successfully decoded since server start.
    public var packetsReceived: UInt64
    /// Total bytes received across all transports since server start.
    public var bytesReceived: UInt64
    /// Packets discarded (bad version, unknown type, out-of-order, decode error).
    public var packetsDropped: UInt64
    /// Monotonic timestamp of the last successfully received packet, or nil if none.
    public var lastPacketAt: Date?

    public init(
        packetsReceived: UInt64 = 0,
        bytesReceived: UInt64 = 0,
        packetsDropped: UInt64 = 0,
        lastPacketAt: Date? = nil
    ) {
        self.packetsReceived = packetsReceived
        self.bytesReceived = bytesReceived
        self.packetsDropped = packetsDropped
        self.lastPacketAt = lastPacketAt
    }
}
