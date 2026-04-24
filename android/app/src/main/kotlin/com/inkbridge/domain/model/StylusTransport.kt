package com.inkbridge.domain.model

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
     * Establishes the underlying socket connection.
     * Calling [connect] when already connected is a no-op (returns [Result.success]).
     */
    suspend fun connect(): Result<Unit>

    /**
     * Sends a single encoded wire frame.
     *
     * @param bytes A complete wire frame as produced by [com.inkbridge.protocol.BinaryStylusCodec].
     * @return [Result.failure] if the socket is closed or an I/O error occurs.
     */
    suspend fun send(bytes: ByteArray): Result<Unit>

    /** Closes the socket. Idempotent. */
    suspend fun close()
}
