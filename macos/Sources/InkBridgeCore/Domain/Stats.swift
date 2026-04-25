import Foundation

/// Telemetry counters for the InkBridge macOS server.
///
/// Updated after each packet is processed. Thread safety is the caller's
/// responsibility — ``InkBridgeServer`` publishes snapshots on the main actor.
///
/// ## Change 2 — Bug 4 (Option A)
///
/// `bytesReceived` was dead (never incremented) and has been removed.
/// `packetsDropped` has been split into two distinct counters:
/// - `packetsDropped`: listener errors and decode failures (transport noise).
/// - `injectionFailures`: frames that were decoded correctly but failed to inject
///   into the OS (e.g. CGEvent creation failure, permission error that has since
///   been recovered). These two failure modes have different root causes and
///   different remediation paths, so conflating them in a single counter masked
///   real problems.
public struct Stats: Equatable {
    /// Total packets successfully decoded since server start.
    public var packetsReceived: UInt64
    /// Packets discarded due to listener errors or decode failures.
    public var packetsDropped: UInt64
    /// Frames that were decoded successfully but failed during OS injection.
    public var injectionFailures: UInt64
    /// Monotonic timestamp of the last successfully received packet, or nil if none.
    public var lastPacketAt: Date?

    public init(
        packetsReceived: UInt64 = 0,
        packetsDropped: UInt64 = 0,
        injectionFailures: UInt64 = 0,
        lastPacketAt: Date? = nil
    ) {
        self.packetsReceived = packetsReceived
        self.packetsDropped = packetsDropped
        self.injectionFailures = injectionFailures
        self.lastPacketAt = lastPacketAt
    }
}
