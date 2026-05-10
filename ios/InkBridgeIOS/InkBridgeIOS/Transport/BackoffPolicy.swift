import Foundation

/// Exponential backoff sequence for reconnect attempts.
///
/// Sequence (per spec §Reconnection): 0.5 / 1.0 / 2.0 / 5.0 s, capped at 5.0 s.
///
/// Usage:
/// ```swift
/// var policy = BackoffPolicy()
/// let t1 = policy.next()  // 0.5
/// let t2 = policy.next()  // 1.0
/// let t3 = policy.next()  // 2.0
/// let t4 = policy.next()  // 5.0
/// let t5 = policy.next()  // 5.0  (capped)
/// policy.reset()
/// let t6 = policy.next()  // 0.5  (back to start)
/// ```
public struct BackoffPolicy: Sendable {

    // MARK: - Constants

    public static let sequence: [TimeInterval] = [0.5, 1.0, 2.0, 5.0]
    public static let cap: TimeInterval = 5.0

    // MARK: - State

    private var index: Int = 0

    public init() {}

    /// Returns the next backoff duration. Subsequent calls beyond the sequence
    /// return the last (capped) value indefinitely until `reset()` is called.
    public mutating func next() -> TimeInterval {
        let value = Self.sequence[min(index, Self.sequence.count - 1)]
        if index < Self.sequence.count - 1 {
            index += 1
        }
        return value
    }

    /// Resets the backoff to the beginning of the sequence.
    public mutating func reset() {
        index = 0
    }
}
