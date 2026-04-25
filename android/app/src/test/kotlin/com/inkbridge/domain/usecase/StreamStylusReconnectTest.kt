package com.inkbridge.domain.usecase

import com.inkbridge.domain.model.StylusSample
import com.inkbridge.domain.model.StylusTransport
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Tests for [StreamStylus.swapTransport] — the Bug 3/4 fix.
 *
 * A single [StreamStylus] instance survives reconnections. [swapTransport] replaces
 * the active transport without losing the sequence counter or accumulated stats.
 */
class StreamStylusReconnectTest {
    private class RecordingTransport : StylusTransport {
        val sentFrames = mutableListOf<ByteArray>()
        private val connectedFlow = MutableStateFlow(true)
        override val isConnected: StateFlow<Boolean> = connectedFlow
        override val errors: SharedFlow<Throwable> = MutableSharedFlow()

        override suspend fun connect() = Result.success(Unit)

        override suspend fun close() {
            connectedFlow.value = false
        }

        override suspend fun send(bytes: ByteArray): Result<Unit> {
            sentFrames.add(bytes.copyOf())
            return Result.success(Unit)
        }
    }

    private class FailingTransport : StylusTransport {
        var sendAttempts = 0
        private val connectedFlow = MutableStateFlow(true)
        override val isConnected: StateFlow<Boolean> = connectedFlow
        override val errors: SharedFlow<Throwable> = MutableSharedFlow()

        override suspend fun connect() = Result.success(Unit)

        override suspend fun close() {
            connectedFlow.value = false
        }

        override suspend fun send(bytes: ByteArray): Result<Unit> {
            sendAttempts++
            return Result.failure(Exception("transport closed"))
        }
    }

    private fun sample(i: Int = 0) =
        StylusSample(
            x = 0.5f,
            y = 0.5f,
            pressure = 32767,
            tiltX = 0,
            tiltY = 0,
            hover = false,
            timestampNs = i.toLong(),
        )

    // ── Reconnect routing ─────────────────────────────────────────────────────

    @Test
    fun `pre-swap frames reach transport1, post-swap frames reach transport2`() =
        runBlocking {
            val t1 = RecordingTransport()
            val t2 = RecordingTransport()
            val useCase = StreamStylus(transport = t1)

            repeat(5) { i -> useCase.emit(sample(i)) }
            useCase.swapTransport(t2)
            repeat(5) { i -> useCase.emit(sample(i + 10)) }

            assertEquals(5, t1.sentFrames.size, "transport1 must receive exactly 5 pre-swap frames")
            assertEquals(5, t2.sentFrames.size, "transport2 must receive exactly 5 post-swap frames")
        }

    @Test
    fun `sentCount is cumulative across transport swaps`() =
        runBlocking {
            val t1 = RecordingTransport()
            val t2 = RecordingTransport()
            val useCase = StreamStylus(transport = t1)

            repeat(5) { i -> useCase.emit(sample(i)) }
            useCase.swapTransport(t2)
            repeat(5) { i -> useCase.emit(sample(i + 10)) }

            assertEquals(10, useCase.sentCount.value, "sentCount must be 10 after two batches of 5")
        }

    @Test
    fun `swapTransport to null makes frames drop gracefully`() =
        runBlocking {
            val t1 = RecordingTransport()
            val useCase = StreamStylus(transport = t1)

            useCase.emit(sample(1))
            useCase.swapTransport(null)
            useCase.emit(sample(2))
            useCase.emit(sample(3))

            assertEquals(1, t1.sentFrames.size, "Only pre-null-swap frame must reach t1")
            assertEquals(2, useCase.droppedCount.value, "2 frames dropped when transport is null")
            assertEquals(1, useCase.sentCount.value, "sentCount counts only the 1 successful send")
        }

    @Test
    fun `swapTransport replaces failing transport and subsequent sends succeed`() =
        runBlocking {
            val failing = FailingTransport()
            val good = RecordingTransport()
            val useCase = StreamStylus(transport = failing)

            useCase.emit(sample(1))
            assertEquals(1, failing.sendAttempts, "failing transport was attempted once")
            assertEquals(1, useCase.droppedCount.value, "dropped count for the failed send")

            useCase.swapTransport(good)
            useCase.emit(sample(2))

            assertEquals(1, good.sentFrames.size, "good transport receives post-swap frame")
            assertEquals(1, useCase.droppedCount.value, "dropped count must not increase for good send")
            assertEquals(1, useCase.sentCount.value, "sentCount reflects 1 successful send")
        }

    // ── Bug 4: transport is live before frames arrive ─────────────────────────

    /**
     * Verifies that after [swapTransport] the immediately next [emit] reaches
     * the new transport — there is no window where transport is null.
     */
    @Test
    fun `first emit after swapTransport reaches new transport immediately`() =
        runBlocking {
            val t1 = RecordingTransport()
            val t2 = RecordingTransport()
            val useCase = StreamStylus(transport = t1)

            useCase.swapTransport(t2)
            useCase.emit(sample(0)) // Must hit t2, not t1.

            assertEquals(0, t1.sentFrames.size, "t1 must receive nothing after swap")
            assertEquals(1, t2.sentFrames.size, "t2 must receive the first post-swap frame immediately")
        }
}
