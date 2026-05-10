import Foundation
import Observation

// MARK: - CaptureFromMacViewModel

/// View model that orchestrates the "Capture from Mac" round-trip:
///   1. Send a `CAPTURE_REQUEST` for the given slot index.
///   2. Wait up to 10 seconds for the Mac server's 4-byte response.
///   3. Expose the result so `CaptureFromMacModal` can update the profile slot.
///
/// # State machine
/// ```
/// idle → requesting → captured(...) / cancelled / timeout / error
/// ```
@Observable
@MainActor
public final class CaptureFromMacViewModel {

    // MARK: - State

    public enum State: Equatable {
        /// Initial state. No capture in progress.
        case idle
        /// Waiting for the Mac server's response.
        case requesting
        /// Mac responded with a captured key combo.
        case captured(keyCode: UInt8, modifiers: UInt8)
        /// User cancelled the capture on the Mac side.
        case cancelled
        /// No response within 10 seconds.
        case timeout
        /// Transport or protocol error.
        case error(String)
    }

    // MARK: - Observed Properties

    public private(set) var state: State = .idle

    // MARK: - Dependencies

    private let udpClient: any UDPClient
    private let codec: BinaryStylusCodec
    private let sequenceCounter: SequenceCounter

    // MARK: - Init

    public init(
        udpClient: any UDPClient,
        sequenceCounter: SequenceCounter = SequenceCounter()
    ) {
        self.udpClient = udpClient
        self.codec = BinaryStylusCodec()
        self.sequenceCounter = sequenceCounter
    }

    // MARK: - Public API

    /// Initiates a capture round-trip for the given Express Key slot.
    ///
    /// - Parameter slotId: The 0-based slot index to assign the captured key to.
    public func startCapture(slotId: UInt8) async {
        state = .requesting

        // 1. Build and send the CAPTURE_REQUEST event.
        let seq = await sequenceCounter.next()
        let timestampNs = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        let encoded = BinaryStylusCodec.encode(
            .captureRequest(slot: slotId),
            flags: 0x00,
            sequence: seq,
            timestampNs: timestampNs
        )

        do {
            try await udpClient.send(encoded)
        } catch {
            state = .error("Send failed: \(error.localizedDescription)")
            return
        }

        // 2. Await the Mac server's response via CaptureResponseListener.
        let listener = CaptureResponseListener(client: udpClient)
        do {
            let result = try await listener.awaitResponse(timeoutSeconds: 10)
            switch result {
            case .captured(_, let keyCode, let modifiers):
                state = .captured(keyCode: keyCode, modifiers: modifiers)
            case .cancelled:
                state = .cancelled
            case .malformed:
                state = .error("Malformed response from Mac")
            }
        } catch let err as CaptureResponseError {
            switch err {
            case .timeout:
                state = .timeout
            case .connectionClosed:
                state = .error("Connection closed while waiting for response")
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Cancels any in-progress capture (e.g. user tapped Cancel in the modal).
    /// Resets state to `.idle` — the actual network operation completes in the
    /// background but its result will be ignored by the modal since it dismissed.
    public func cancel() {
        state = .idle
    }
}
