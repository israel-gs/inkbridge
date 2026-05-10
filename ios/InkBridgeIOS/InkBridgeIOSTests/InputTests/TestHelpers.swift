import Foundation

/// A reference-type box around a `TimeInterval` value.
///
/// Swift prohibits escaping closures from capturing `inout` parameters.
/// Wrapping the fake clock in a `ClockBox` lets the `@escaping now:` closure
/// in `TouchRouter(now:)` share the same mutable clock with the test body.
///
/// Usage:
/// ```swift
/// let clockBox = ClockBox()
/// var router = TouchRouter(now: { clockBox.value })
/// clockBox.value = 0.500  // advance fake time
/// ```
final class ClockBox {
    var value: TimeInterval

    init(_ initial: TimeInterval = 0) {
        value = initial
    }
}
