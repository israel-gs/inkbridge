import Foundation

/// A ``PacketListener`` that never emits any frames or errors.
///
/// Used in previews and tests where no real port should be bound.
public final class NoOpListener: PacketListener {

    public let frames: AsyncStream<DecodedFrame>
    public let errors: AsyncStream<Error>

    private let frameContinuation: AsyncStream<DecodedFrame>.Continuation
    private let errorContinuation: AsyncStream<Error>.Continuation

    public init() {
        var fc: AsyncStream<DecodedFrame>.Continuation!
        var ec: AsyncStream<Error>.Continuation!
        self.frames = AsyncStream { fc = $0 }
        self.errors = AsyncStream { ec = $0 }
        self.frameContinuation = fc
        self.errorContinuation = ec
    }

    public func start() throws {}

    public func stop() {
        frameContinuation.finish()
        errorContinuation.finish()
    }

    /// Injects a frame directly — used in tests to feed the server.
    public func emit(_ frame: DecodedFrame) {
        frameContinuation.yield(frame)
    }

    /// Injects an error directly — used in tests.
    public func emitError(_ error: Error) {
        errorContinuation.yield(error)
    }
}
