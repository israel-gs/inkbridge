import Foundation

/// Port for transport-layer frame listeners.
///
/// Both UDP and TCP listeners implement this protocol so ``InkBridgeServer``
/// can treat them uniformly. Frames arrive pre-decoded via ``DecodedFrame``;
/// transport errors arrive on the separate `errors` stream.
public protocol PacketListener: AnyObject {
    /// Bind and begin accepting packets. Throws if the port is unavailable.
    func start() throws
    /// Stop accepting packets and release the port.
    func stop()
    /// Stream of successfully decoded frames from incoming packets.
    var frames: AsyncStream<DecodedFrame> { get }
    /// Stream of errors (decode failures, transport errors).
    var errors: AsyncStream<Error> { get }
    /// Sends a wire-format frame back to the connected client. Bidirectional
    /// transports (TCP) wire this to the active connection; one-shot
    /// transports (UDP without a tracked remote) treat it as a no-op.
    func send(_ data: Data)
}

public extension PacketListener {
    /// Default implementation: no-op. UDPListener relies on this; TCPListener overrides.
    func send(_ data: Data) {}
}
