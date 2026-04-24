import Foundation

/// A single decoded stylus sample with normalized coordinates and sensor data.
///
/// All floating-point fields are normalized to [0.0, 1.0] or degree × 100 for tilt.
/// Throws ``StylusSampleError`` when field values are out of spec range.
public struct StylusSample: Equatable {
    /// Normalized X position in [0.0, 1.0] relative to display width.
    public let x: Float
    /// Normalized Y position in [0.0, 1.0] relative to display height.
    public let y: Float
    /// Normalized pressure in [0.0, 1.0].
    public let pressure: Float
    /// Tilt around X axis × 100, range [−9000, 9000].
    public let tiltX: Int16
    /// Tilt around Y axis × 100, range [−9000, 9000].
    public let tiltY: Int16
    /// True when stylus is hovering (not touching).
    public let hover: Bool
    /// Monotonic nanosecond timestamp from Android device.
    public let timestampNs: UInt64

    public init(
        x: Float,
        y: Float,
        pressure: Float,
        tiltX: Int16,
        tiltY: Int16,
        hover: Bool,
        timestampNs: UInt64
    ) throws {
        guard (0.0...1.0).contains(x) else {
            throw StylusSampleError.xOutOfRange(x)
        }
        guard (0.0...1.0).contains(y) else {
            throw StylusSampleError.yOutOfRange(y)
        }
        guard (0.0...1.0).contains(pressure) else {
            throw StylusSampleError.pressureOutOfRange(pressure)
        }
        guard (-9000...9000).contains(tiltX) else {
            throw StylusSampleError.tiltXOutOfRange(tiltX)
        }
        guard (-9000...9000).contains(tiltY) else {
            throw StylusSampleError.tiltYOutOfRange(tiltY)
        }
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.hover = hover
        self.timestampNs = timestampNs
    }
}

/// Errors thrown when ``StylusSample`` field values violate spec ranges.
public enum StylusSampleError: Error, Equatable {
    case xOutOfRange(Float)
    case yOutOfRange(Float)
    case pressureOutOfRange(Float)
    case tiltXOutOfRange(Int16)
    case tiltYOutOfRange(Int16)
}
