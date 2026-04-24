package com.inkbridge.domain.usecase

import com.inkbridge.domain.model.StylusSample
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.protocol.BinaryStylusCodec
import com.inkbridge.protocol.EventType
import com.inkbridge.protocol.Flags
import com.inkbridge.protocol.StylusEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Unit tests for [StreamStylus].
 *
 * Uses [FakeTransport] to capture sent bytes. All assertions verify wire-protocol.md
 * compliance (sequence ordering, flags correctness, drop counter).
 */
class StreamStylusTest {

    // ── Fake transport ────────────────────────────────────────────────────────

    private class FakeTransport(
        private val sendResult: () -> Result<Unit> = { Result.success(Unit) },
    ) : StylusTransport {
        val sentFrames = mutableListOf<ByteArray>()

        private val _isConnected = MutableStateFlow(true)
        override val isConnected: StateFlow<Boolean> = _isConnected

        override suspend fun connect(): Result<Unit> = Result.success(Unit)
        override suspend fun close() { _isConnected.value = false }
        override suspend fun send(bytes: ByteArray): Result<Unit> {
            val result = sendResult()
            if (result.isSuccess) sentFrames.add(bytes)
            return result
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun sample(
        x: Float = 0.5f,
        y: Float = 0.5f,
        pressure: Int = 32767,
        tiltX: Int = 0,
        tiltY: Int = 0,
        hover: Boolean = false,
        timestampNs: Long = 1_000_000_000L,
    ) = StylusSample(x, y, pressure, tiltX, tiltY, hover, timestampNs)

    // ── Sequence ordering ─────────────────────────────────────────────────────

    @Test
    fun `first frame has sequence 0`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emit(sample())
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        assertEquals(0u, frame.header.sequence)
    }

    @Test
    fun `sequence increments for each frame`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        repeat(3) { useCase.emit(sample(timestampNs = it * 1_000_000L.toLong())) }
        val sequences = transport.sentFrames.map { BinaryStylusCodec.decode(it).header.sequence }
        assertEquals(listOf(0u, 1u, 2u), sequences)
    }

    @Test
    fun `sequence increments across event types`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emit(sample())
        useCase.emitProximity(entering = true, timestampNs = 1_000_000L)
        useCase.emitButton(primaryPressed = true, secondaryPressed = false, timestampNs = 2_000_000L)
        val sequences = transport.sentFrames.map { BinaryStylusCodec.decode(it).header.sequence }
        assertEquals(listOf(0u, 1u, 2u), sequences)
    }

    // ── Flags correctness ─────────────────────────────────────────────────────

    @Test
    fun `emit with pressure sets PRESSURE_PRESENT flag`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emit(sample(pressure = 32767))
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        val flags = frame.header.flags
        assertTrue((flags and Flags.PRESSURE_PRESENT) != 0u.toUByte(), "PRESSURE_PRESENT must be set")
    }

    @Test
    fun `emit with zero pressure clears PRESSURE_PRESENT flag`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emit(sample(pressure = 0))
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        val flags = frame.header.flags
        assertTrue((flags and Flags.PRESSURE_PRESENT) == 0u.toUByte(), "PRESSURE_PRESENT must be clear")
    }

    @Test
    fun `emit with tilt sets TILT_PRESENT flag`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emit(sample(tiltX = 100, tiltY = 0))
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        assertTrue((frame.header.flags and Flags.TILT_PRESENT) != 0u.toUByte(), "TILT_PRESENT must be set")
    }

    @Test
    fun `emit hover sample sets HOVER flag`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emit(sample(hover = true, pressure = 0))
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        assertTrue((frame.header.flags and Flags.HOVER) != 0u.toUByte(), "HOVER must be set")
    }

    @Test
    fun `emitProximity entering sets HOVER flag`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emitProximity(entering = true, timestampNs = 1_000_000L)
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        assertTrue((frame.header.flags and Flags.HOVER) != 0u.toUByte())
        val event = frame.event as StylusEvent.Proximity
        assertTrue(event.entering)
    }

    @Test
    fun `emitProximity leaving clears HOVER flag`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emitProximity(entering = false, timestampNs = 1_000_000L)
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        assertTrue((frame.header.flags and Flags.HOVER) == 0u.toUByte())
        val event = frame.event as StylusEvent.Proximity
        assertFalse(event.entering)
    }

    @Test
    fun `emitButton primary sets BUTTON_PRIMARY flag and buttons payload`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        useCase.emitButton(primaryPressed = true, secondaryPressed = false, timestampNs = 1_000_000L)
        val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
        assertTrue((frame.header.flags and Flags.BUTTON_PRIMARY) != 0u.toUByte())
        val event = frame.event as StylusEvent.Button
        assertEquals(Flags.BUTTON_PRIMARY, event.buttons)
    }

    // ── Drop counter ──────────────────────────────────────────────────────────

    @Test
    fun `drop counter increments when transport is null`() = runBlocking {
        val useCase = StreamStylus(transport = null)
        useCase.emit(sample())
        useCase.emit(sample())
        assertEquals(2, useCase.droppedCount.value)
    }

    @Test
    fun `drop counter increments when send fails`() = runBlocking {
        val transport = FakeTransport(sendResult = { Result.failure(Exception("socket closed")) })
        val useCase = StreamStylus(transport)
        useCase.emit(sample())
        assertEquals(1, useCase.droppedCount.value)
    }

    @Test
    fun `drop counter stays at 0 when all sends succeed`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        repeat(5) { useCase.emit(sample(timestampNs = it.toLong())) }
        assertEquals(0, useCase.droppedCount.value)
    }

    @Test
    fun `sent count reflects successful sends`() = runBlocking {
        val transport = FakeTransport()
        val useCase = StreamStylus(transport)
        repeat(3) { useCase.emit(sample(timestampNs = it.toLong())) }
        assertEquals(3, useCase.sentCount.value)
    }
}
