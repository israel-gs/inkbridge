package com.inkbridge.domain.usecase

import com.inkbridge.domain.model.StylusSample
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.protocol.BinaryStylusCodec
import com.inkbridge.protocol.EventType
import com.inkbridge.protocol.Flags
import com.inkbridge.protocol.StylusEvent
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertInstanceOf
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
        override val errors: SharedFlow<Throwable> = MutableSharedFlow()
        override val incomingFrames: SharedFlow<com.inkbridge.protocol.DecodedFrame> =
            MutableSharedFlow()

        override suspend fun connect(): Result<Unit> = Result.success(Unit)

        override suspend fun close() {
            _isConnected.value = false
        }

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
    fun `first frame has sequence 0`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emit(sample())
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            assertEquals(0u, frame.header.sequence)
        }

    @Test
    fun `sequence increments for each frame`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            repeat(3) { useCase.emit(sample(timestampNs = it * 1_000_000L.toLong())) }
            val sequences = transport.sentFrames.map { BinaryStylusCodec.decode(it).header.sequence }
            assertEquals(listOf(0u, 1u, 2u), sequences)
        }

    @Test
    fun `sequence increments across event types`() =
        runBlocking {
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
    fun `emit with pressure sets PRESSURE_PRESENT flag`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emit(sample(pressure = 32767))
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            val flags = frame.header.flags
            assertTrue((flags and Flags.PRESSURE_PRESENT) != 0u.toUByte(), "PRESSURE_PRESENT must be set")
        }

    @Test
    fun `emit with zero pressure clears PRESSURE_PRESENT flag`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emit(sample(pressure = 0))
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            val flags = frame.header.flags
            assertTrue((flags and Flags.PRESSURE_PRESENT) == 0u.toUByte(), "PRESSURE_PRESENT must be clear")
        }

    @Test
    fun `emit with tilt sets TILT_PRESENT flag`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emit(sample(tiltX = 100, tiltY = 0))
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            assertTrue((frame.header.flags and Flags.TILT_PRESENT) != 0u.toUByte(), "TILT_PRESENT must be set")
        }

    @Test
    fun `emit hover sample sets HOVER flag`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emit(sample(hover = true, pressure = 0))
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            assertTrue((frame.header.flags and Flags.HOVER) != 0u.toUByte(), "HOVER must be set")
        }

    @Test
    fun `emitProximity entering sets HOVER flag`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitProximity(entering = true, timestampNs = 1_000_000L)
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            assertTrue((frame.header.flags and Flags.HOVER) != 0u.toUByte())
            val event = frame.event as StylusEvent.Proximity
            assertTrue(event.entering)
        }

    @Test
    fun `emitProximity leaving clears HOVER flag`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitProximity(entering = false, timestampNs = 1_000_000L)
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            assertTrue((frame.header.flags and Flags.HOVER) == 0u.toUByte())
            val event = frame.event as StylusEvent.Proximity
            assertFalse(event.entering)
        }

    @Test
    fun `emitButton primary sets BUTTON_PRIMARY flag and buttons payload`() =
        runBlocking {
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
    fun `drop counter increments when transport is null`() =
        runBlocking {
            val useCase = StreamStylus(transport = null)
            useCase.emit(sample())
            useCase.emit(sample())
            assertEquals(2, useCase.droppedCount.value)
        }

    @Test
    fun `drop counter increments when send fails`() =
        runBlocking {
            val transport = FakeTransport(sendResult = { Result.failure(Exception("socket closed")) })
            val useCase = StreamStylus(transport)
            useCase.emit(sample())
            assertEquals(1, useCase.droppedCount.value)
        }

    @Test
    fun `drop counter stays at 0 when all sends succeed`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            repeat(5) { useCase.emit(sample(timestampNs = it.toLong())) }
            assertEquals(0, useCase.droppedCount.value)
        }

    @Test
    fun `sent count reflects successful sends`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            repeat(3) { useCase.emit(sample(timestampNs = it.toLong())) }
            assertEquals(3, useCase.sentCount.value)
        }

    // A10 — emitScroll phaseFlags persistence

    @Test
    fun `emitScroll phaseFlags 0x40 is preserved in wire frame`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitScroll(deltaX = 10, deltaY = 20, phaseFlags = 0x40u, timestampNs = 0L)
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            // phaseFlags is stored in header.flags masked to 0xC0.
            val maskedFlags = frame.header.flags and 0xC0u.toUByte()
            assertEquals(
                0x40u.toUByte(),
                maskedFlags,
                "phaseFlags=0x40 must appear in wire header.flags bits 7-6",
            )
        }

    @Test
    fun `emitScroll phaseFlags 0x80 is preserved in wire frame`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitScroll(deltaX = 0, deltaY = 5, phaseFlags = 0x80u, timestampNs = 0L)
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            val maskedFlags = frame.header.flags and 0xC0u.toUByte()
            assertEquals(
                0x80u.toUByte(),
                maskedFlags,
                "phaseFlags=0x80 must appear in wire header.flags bits 7-6",
            )
        }

    @Test
    fun `emitScroll phaseFlags 0x00 produces zero phase bits in wire frame`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitScroll(deltaX = 3, deltaY = -1, phaseFlags = 0x00u, timestampNs = 0L)
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            val maskedFlags = frame.header.flags and 0xC0u.toUByte()
            assertEquals(
                0x00u.toUByte(),
                maskedFlags,
                "phaseFlags=0x00 must produce zero phase bits in wire frame",
            )
        }

    @Test
    fun `emitScroll payload deltas match wire layout`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitScroll(deltaX = 10, deltaY = 20, phaseFlags = 0x40u, timestampNs = 0L)
            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            val scroll = assertInstanceOf(StylusEvent.Scroll::class.java, frame.event)
            assertEquals(10.toShort(), scroll.deltaX, "deltaX must match")
            assertEquals(20.toShort(), scroll.deltaY, "deltaY must match")
        }

    // A11 — emitCursorDelta wire layout

    @Test
    fun `emitCursorDelta produces CURSOR_DELTA frame with correct wire layout`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emitCursorDelta(deltaX = 3, deltaY = -7, timestampNs = 12_345_678L)
            assertEquals(1, transport.sentFrames.size, "emitCursorDelta must send exactly one frame")

            val frame = BinaryStylusCodec.decode(transport.sentFrames.first())
            // Event type must be CURSOR_DELTA (0x06)
            assertEquals(
                EventType.CURSOR_DELTA,
                frame.header.eventType,
                "Frame event_type must be CURSOR_DELTA (0x06)",
            )
            // flags must be 0x00 (cursor delta carries no flag bits)
            assertEquals(
                0x00u.toUByte(),
                frame.header.flags,
                "CURSOR_DELTA flags must be 0x00",
            )
            // timestamp must be propagated
            assertEquals(
                12_345_678uL,
                frame.header.timestampNs,
                "timestampNs must match the emitted value",
            )

            val cursorDelta = assertInstanceOf(StylusEvent.CursorDelta::class.java, frame.event)
            assertEquals(3.toShort(), cursorDelta.deltaX, "deltaX must match")
            assertEquals((-7).toShort(), cursorDelta.deltaY, "deltaY must match")
        }

    @Test
    fun `emitCursorDelta increments sequence counter`() =
        runBlocking {
            val transport = FakeTransport()
            val useCase = StreamStylus(transport)
            useCase.emit(sample())
            useCase.emitCursorDelta(deltaX = 1, deltaY = 2, timestampNs = 0L)
            val sequences = transport.sentFrames.map { BinaryStylusCodec.decode(it).header.sequence }
            assertEquals(listOf(0u, 1u), sequences, "emitCursorDelta must increment sequence like any other event")
        }
}
