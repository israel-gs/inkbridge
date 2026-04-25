package com.inkbridge.domain.model

import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Port: an active transport channel that can carry encoded stylus frames.
 *
 * Implementations live in [com.inkbridge.data.transport] and are the only place
 * where [java.net.*] sockets are allowed.
 *
 * Both suspend functions return [Result] so the caller can handle failures without
 * catching exceptions across coroutine boundaries.
 */
interface StylusTransport {
    /** True while the socket is open and usable for [send]. */
    val isConnected: StateFlow<Boolean>

    /**
     * Hot stream of send-time I/O errors. Emits the first [Throwable] each time
     * [send] fails due to a broken pipe / connection reset. Subscribers (e.g.
     * [com.inkbridge.data.connection.ConnectionManager]) can use this to detect
     * mid-session disconnects without polling [isConnected].
     *
     * The flow is a SharedFlow with no replay — subscribers receive only future
     * errors emitted after they start collecting.
     */
    val errors: SharedFlow<Throwable>

    /**
     * Establishes the underlying socket connection.
     * Calling [connect] when already connected is a no-op (returns [Result.success]).
     */
    suspend fun connect(): Result<Unit>

    /**
     * Sends a single encoded wire frame.
     *
     * @param bytes A complete wire frame as produced by [com.inkbridge.protocol.BinaryStylusCodec].
     * @return [Result.failure] if the socket is closed or an I/O error occurs.
     *         On I/O failure the transport also transitions [isConnected] to false
     *         and emits the cause to [errors].
     */
    suspend fun send(bytes: ByteArray): Result<Unit>

    /** Closes the socket. Idempotent. */
    suspend fun close()
}
