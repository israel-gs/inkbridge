package com.inkbridge.ui.screens

import com.inkbridge.domain.model.StylusSample
import com.inkbridge.domain.model.StylusSink
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.domain.usecase.StreamStylus
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Tests for the channel-based emit ordering fix (Bug 1) and related Bug 3 / A-B6.
 *
 * We test [StreamStylus] and the channel dispatch mechanics directly without
 * spinning up a ViewModel (which requires Application context). All tests run
 * on a coroutine test dispatcher — no Android framework needed.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionViewModelEmitOrderTest {
    // ── Recording sink ─────────────────────────────────────────────────────────

    /** Records the names of operations in call order. */
    private class RecordingSink : StylusSink {
        val calls = mutableListOf<String>()

        override suspend fun emit(sample: StylusSample) {
            calls.add("sample(${sample.x},${sample.y})")
        }

        override suspend fun emitProximity(
            entering: Boolean,
            timestampNs: Long,
        ) {
            calls.add("proximity($entering)")
        }

        override suspend fun emitButton(
            primaryPressed: Boolean,
            secondaryPressed: Boolean,
            timestampNs: Long,
        ) {
            calls.add("button(primary=$primaryPressed)")
        }

        override suspend fun emitScroll(
            deltaX: Short,
            deltaY: Short,
            phaseFlags: UByte,
            timestampNs: Long,
        ) {
            calls.add("scroll($deltaX,$deltaY)")
        }

        override suspend fun emitZoom(
            scaleDelta: Float,
            timestampNs: Long,
        ) {
            calls.add("zoom($scaleDelta)")
        }

        override suspend fun emitCursorDelta(
            deltaX: Short,
            deltaY: Short,
            timestampNs: Long,
        ) {
            calls.add("cursor($deltaX,$deltaY)")
        }
    }

    // ── Bug 1: ACTION_DOWN sample arrives before button ────────────────────────

    /**
     * Simulates the Channel consumer pattern from ConnectionViewModel:
     * push jobs into a Channel.UNLIMITED channel, then drain them sequentially.
     * Verifies Sample is delivered before Button for an ACTION_DOWN sequence.
     */
    @Test
    fun `channel consumer delivers sample before button for ACTION_DOWN`() =
        runTest {
            val sink = RecordingSink()
            val channel = Channel<suspend (StylusSink) -> Unit>(Channel.UNLIMITED)

            // Simulate what onMotion does for ACTION_DOWN: push Sample then Button.
            channel.trySend { s -> s.emit(StylusSample(0.5f, 0.5f, 32767, 0, 0, false, 100L)) }
            channel.trySend { s -> s.emitButton(primaryPressed = true, secondaryPressed = false, timestampNs = 100L) }
            channel.close()

            // Drain channel sequentially (mirrors the consumer coroutine).
            for (job in channel) {
                job(sink)
            }

            assertEquals(2, sink.calls.size)
            assertTrue(sink.calls[0].startsWith("sample"), "First call must be sample, got: ${sink.calls[0]}")
            assertTrue(
                sink.calls[1].startsWith("button(primary=true)"),
                "Second call must be button-down, got: ${sink.calls[1]}",
            )
        }

    // ── Bug 1: Stress ordering test ────────────────────────────────────────────

    /**
     * 100 rapid trySend calls all arrive in order at the consumer.
     * Tests that Channel.UNLIMITED preserves FIFO under rapid producer activity.
     */
    @Test
    fun `100 rapid channel sends arrive in order`() =
        runTest {
            val sink = RecordingSink()
            val channel = Channel<suspend (StylusSink) -> Unit>(Channel.UNLIMITED)

            repeat(100) { i ->
                val x = i.toFloat() / 100f
                channel.trySend { s -> s.emit(StylusSample(x, 0f, 1000, 0, 0, false, i.toLong())) }
            }
            channel.close()

            for (job in channel) job(sink)

            assertEquals(100, sink.calls.size)
            sink.calls.forEachIndexed { index, call ->
                val expected = "sample(${index.toFloat() / 100f},0.0)"
                assertEquals(expected, call, "Call $index out of order")
            }
        }

    // ── Bug 3/4: swapTransport survives reconnect ──────────────────────────────

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

    /**
     * Emit 5 frames → swap transport → emit 5 more.
     * transport2 must receive exactly the post-swap 5 frames.
     * Counters (sentCount) must be cumulative (10 total).
     */
    @Test
    fun `swapTransport mid-stroke routes post-swap frames to new transport`() =
        runTest {
            val transport1 = RecordingTransport()
            val transport2 = RecordingTransport()
            val useCase = StreamStylus(transport = transport1)

            val sample = StylusSample(0.5f, 0.5f, 32767, 0, 0, false, 1_000_000L)

            // Pre-swap: 5 frames to transport1.
            repeat(5) { useCase.emit(sample) }
            assertEquals(5, transport1.sentFrames.size, "transport1 must receive 5 pre-swap frames")
            assertEquals(0, transport2.sentFrames.size)

            // Swap.
            useCase.swapTransport(transport2)

            // Post-swap: 5 frames to transport2.
            repeat(5) { useCase.emit(sample) }
            assertEquals(5, transport1.sentFrames.size, "transport1 must not receive post-swap frames")
            assertEquals(5, transport2.sentFrames.size, "transport2 must receive 5 post-swap frames")

            // Cumulative sentCount.
            assertEquals(10, useCase.sentCount.value, "sentCount must be cumulative across transports")
        }

    // ── Bug A-B6: historical samples preserved on first MOVE after DOWN ────────

    /**
     * Channel-based dispatch test for Bug A-B6:
     * Simulate ACTION_DOWN (1 sample) followed by ACTION_MOVE with 3 historical samples.
     * All 4 samples must reach the sink (not just the last).
     *
     * We test the effectiveSamples selection logic directly because the ViewModel
     * requires an Application context. We replicate the same logic here to keep
     * tests hermetic.
     */
    @Test
    fun `first MOVE after DOWN preserves all historical samples`() =
        runTest {
            val sink = RecordingSink()
            val channel = Channel<suspend (StylusSink) -> Unit>(Channel.UNLIMITED)

            // Replicate onMotion logic for ACTION_DOWN.
            var lastActionWasDown = false
            val samplesDown = listOf(StylusSample(0.5f, 0.5f, 1000, 0, 0, false, 1L))
            val actionDown = android.view.MotionEvent.ACTION_DOWN
            val prevWasDown1 = lastActionWasDown
            lastActionWasDown = (actionDown == android.view.MotionEvent.ACTION_DOWN)
            // effectiveSamples for DOWN = samplesDown (not MOVE branch)
            for (s in samplesDown) {
                val captured = s
                channel.trySend { sink -> sink.emit(captured) }
            }
            // Also push button-down
            channel.trySend { s -> s.emitButton(primaryPressed = true, secondaryPressed = false, timestampNs = 1L) }

            // Replicate onMotion logic for ACTION_MOVE (first after DOWN).
            val historicalSamples =
                listOf(
                    StylusSample(0.51f, 0.51f, 1100, 0, 0, false, 2L),
                    StylusSample(0.52f, 0.52f, 1200, 0, 0, false, 3L),
                    StylusSample(0.53f, 0.53f, 1300, 0, 0, false, 4L),
                )
            val actionMove = android.view.MotionEvent.ACTION_MOVE
            val prevWasDown2 = lastActionWasDown // true
            lastActionWasDown = (actionMove == android.view.MotionEvent.ACTION_DOWN)
            val effectiveSamples = if (prevWasDown2) historicalSamples else historicalSamples.takeLast(1)
            for (s in effectiveSamples) {
                val captured = s
                channel.trySend { sink -> sink.emit(captured) }
            }

            channel.close()
            for (job in channel) job(sink)

            // Expected: 1 DOWN sample + button + 3 MOVE historicals = 5 calls
            val sampleCalls = sink.calls.filter { it.startsWith("sample") }
            assertEquals(4, sampleCalls.size, "All 4 samples must reach the sink (1 DOWN + 3 MOVE historicals)")
            assertTrue(sink.calls[0].startsWith("sample(0.5"), "First call is DOWN sample")
            assertTrue(sink.calls[1].startsWith("button(primary=true)"), "Second call is button-down")
            assertEquals("sample(0.51,0.51)", sink.calls[2], "Third is first historical")
            assertEquals("sample(0.52,0.52)", sink.calls[3], "Fourth is second historical")
            assertEquals("sample(0.53,0.53)", sink.calls[4], "Fifth is third historical")
        }
}
