package com.inkbridge.domain.usecase

import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusSample
import com.inkbridge.domain.model.StylusSink
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.protocol.BinaryStylusCodec
import com.inkbridge.protocol.Flags
import com.inkbridge.protocol.StylusEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicInteger

/**
 * Use case: encodes stylus events and streams them over the active transport.
 *
 * Implements [StylusSink] so the capture layer can call [emit], [emitProximity],
 * and [emitButton] without knowing anything about the transport or codec.
 *
 * Sequence counter: [AtomicInteger] wrapping u32 per wire-protocol.md R9.
 * Start at 0; increment for every frame successfully encoded.
 *
 * Dropped frames (when [transport] is null or send fails) are counted in [droppedCount].
 */
class StreamStylus(
    private val transport: StylusTransport?,
) : StylusSink {

    private val sequence = AtomicInteger(0)

    private val _droppedCount = MutableStateFlow(0)
    val droppedCount: StateFlow<Int> = _droppedCount.asStateFlow()

    /** Total frames sent successfully (observable). */
    private val _sentCount = MutableStateFlow(0)
    val sentCount: StateFlow<Int> = _sentCount.asStateFlow()

    override suspend fun emit(sample: StylusSample) {
        val pressurePresent = sample.pressure > 0
        val tiltPresent = sample.tiltX != 0 || sample.tiltY != 0

        var flags: UInt = 0u
        if (pressurePresent) flags = flags or Flags.PRESSURE_PRESENT.toUInt()
        if (tiltPresent) flags = flags or Flags.TILT_PRESENT.toUInt()
        if (sample.hover) flags = flags or Flags.HOVER.toUInt()

        val event = StylusEvent.Move(
            x = sample.x,
            y = sample.y,
            pressure = sample.pressure.toUShort(),
            tiltX = sample.tiltX.toShort(),
            tiltY = sample.tiltY.toShort(),
        )

        val seq = nextSequence()
        val bytes = BinaryStylusCodec.encode(
            event = event,
            flags = flags.toUByte(),
            sequence = seq,
            timestampNs = sample.timestampNs.toULong(),
        )
        sendOrDrop(bytes)
    }

    override suspend fun emitProximity(entering: Boolean, timestampNs: Long) {
        val flags: UByte = if (entering) Flags.HOVER else 0x00u
        val event = StylusEvent.Proximity(entering = entering)
        val seq = nextSequence()
        val bytes = BinaryStylusCodec.encode(
            event = event,
            flags = flags,
            sequence = seq,
            timestampNs = timestampNs.toULong(),
        )
        sendOrDrop(bytes)
    }

    override suspend fun emitButton(
        primaryPressed: Boolean,
        secondaryPressed: Boolean,
        timestampNs: Long,
    ) {
        var flags: UInt = 0u
        if (primaryPressed) flags = flags or Flags.BUTTON_PRIMARY.toUInt()
        if (secondaryPressed) flags = flags or Flags.BUTTON_SECONDARY.toUInt()

        // buttons payload mirrors bits 3–4 of header flags (wire-protocol.md R8)
        val buttonsByte = flags.toUByte()
        val event = StylusEvent.Button(buttons = buttonsByte)

        val seq = nextSequence()
        val bytes = BinaryStylusCodec.encode(
            event = event,
            flags = flags.toUByte(),
            sequence = seq,
            timestampNs = timestampNs.toULong(),
        )
        sendOrDrop(bytes)
    }

    override suspend fun emitScroll(deltaX: Short, deltaY: Short, phaseFlags: UByte, timestampNs: Long) {
        val event = StylusEvent.Scroll(deltaX = deltaX, deltaY = deltaY)
        val seq = nextSequence()
        val bytes = BinaryStylusCodec.encode(
            event = event,
            flags = phaseFlags,
            sequence = seq,
            timestampNs = timestampNs.toULong(),
        )
        sendOrDrop(bytes)
    }

    override suspend fun emitZoom(scaleDelta: Float, timestampNs: Long) {
        val event = StylusEvent.Zoom(scaleDelta = scaleDelta)
        val seq = nextSequence()
        val bytes = BinaryStylusCodec.encode(
            event = event,
            flags = 0x00u,
            sequence = seq,
            timestampNs = timestampNs.toULong(),
        )
        sendOrDrop(bytes)
    }

    override suspend fun emitCursorDelta(deltaX: Short, deltaY: Short, timestampNs: Long) {
        val event = StylusEvent.CursorDelta(deltaX = deltaX, deltaY = deltaY)
        val seq = nextSequence()
        val bytes = BinaryStylusCodec.encode(
            event = event,
            flags = 0x00u,
            sequence = seq,
            timestampNs = timestampNs.toULong(),
        )
        sendOrDrop(bytes)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────────────────────────────────────

    /** Returns the next sequence number, wrapping from Int.MAX_VALUE to 0 (u32 semantics). */
    private fun nextSequence(): UInt {
        // getAndIncrement is atomic; the Int wraps at MAX_VALUE → MIN_VALUE but
        // we convert to UInt so the wire sees values 0..4294967295 cycling correctly.
        return sequence.getAndIncrement().toUInt()
    }

    private suspend fun sendOrDrop(bytes: ByteArray) {
        val t = transport
        if (t == null) {
            _droppedCount.value++
            return
        }
        val result = t.send(bytes)
        if (result.isSuccess) {
            _sentCount.value++
        } else {
            _droppedCount.value++
        }
    }
}
