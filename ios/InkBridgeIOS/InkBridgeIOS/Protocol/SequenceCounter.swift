/// A per-session monotonically increasing UInt32 counter that wraps at 2^32.
///
/// Actor isolation provides thread safety without external dependencies.
/// Semantics match the wire protocol sequence field (protocol/README.md §Fixed header):
/// "Monotonically increasing per session; wraps at 2^32."
///
/// Usage:
/// ```swift
/// let counter = SequenceCounter()
/// let seq = await counter.next()   // 0
/// let seq2 = await counter.next()  // 1
/// ```
public actor SequenceCounter {

    private var value: UInt32

    /// Creates a counter starting at `initialValue` (default 0).
    /// Pass a non-zero start only in tests that need to verify wrap behavior.
    public init(initialValue: UInt32 = 0) {
        value = initialValue
    }

    /// Returns the current counter value and increments the internal state.
    /// After `UInt32.max`, the next call returns `0` (wrapping addition).
    public func next() -> UInt32 {
        let current = value
        value = value &+ 1   // &+ = wrapping add, no overflow trap at UInt32.max
        return current
    }
}
