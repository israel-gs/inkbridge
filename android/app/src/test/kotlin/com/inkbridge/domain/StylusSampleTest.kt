package com.inkbridge.domain

import com.inkbridge.domain.model.StylusSample
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * Validates the boundary enforcement in [StylusSample].
 *
 * The mapper guarantees values are in range before constructing StylusSample,
 * so these tests serve as contract / programming-error guards.
 */
class StylusSampleTest {

    // ── Valid construction ────────────────────────────────────────────────────

    @Test
    fun `valid sample at center constructs without exception`() {
        val sample = StylusSample(
            x = 0.5f,
            y = 0.5f,
            pressure = 32767,
            tiltX = 0,
            tiltY = 0,
            hover = false,
            timestampNs = 1_000_000_000L,
        )
        assertEquals(0.5f, sample.x)
        assertEquals(0.5f, sample.y)
    }

    @Test
    fun `valid sample at boundary x=0 y=0 constructs`() {
        val sample = StylusSample(
            x = 0f,
            y = 0f,
            pressure = 0,
            tiltX = -9000,
            tiltY = -9000,
            hover = false,
            timestampNs = 0L,
        )
        assertEquals(0f, sample.x)
        assertEquals(-9000, sample.tiltX)
    }

    @Test
    fun `valid sample at boundary x=1 y=1 constructs`() {
        val sample = StylusSample(
            x = 1f,
            y = 1f,
            pressure = 65535,
            tiltX = 9000,
            tiltY = 9000,
            hover = true,
            timestampNs = Long.MAX_VALUE,
        )
        assertEquals(1f, sample.x)
        assertEquals(65535, sample.pressure)
    }

    // ── x boundary violations ─────────────────────────────────────────────────

    @Test
    fun `x below 0 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = -0.001f, y = 0.5f, pressure = 0, tiltX = 0, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    @Test
    fun `x above 1 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 1.001f, y = 0.5f, pressure = 0, tiltX = 0, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    // ── y boundary violations ─────────────────────────────────────────────────

    @Test
    fun `y below 0 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = -0.001f, pressure = 0, tiltX = 0, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    @Test
    fun `y above 1 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 1.001f, pressure = 0, tiltX = 0, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    // ── pressure boundary violations ──────────────────────────────────────────

    @Test
    fun `pressure below 0 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 0.5f, pressure = -1, tiltX = 0, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    @Test
    fun `pressure above 65535 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 0.5f, pressure = 65536, tiltX = 0, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    // ── tiltX boundary violations ─────────────────────────────────────────────

    @Test
    fun `tiltX below -9000 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 0.5f, pressure = 0, tiltX = -9001, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    @Test
    fun `tiltX above 9000 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 0.5f, pressure = 0, tiltX = 9001, tiltY = 0, hover = false, timestampNs = 0)
        }
    }

    // ── tiltY boundary violations ─────────────────────────────────────────────

    @Test
    fun `tiltY below -9000 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 0.5f, pressure = 0, tiltX = 0, tiltY = -9001, hover = false, timestampNs = 0)
        }
    }

    @Test
    fun `tiltY above 9000 throws IllegalArgumentException`() {
        assertThrows<IllegalArgumentException> {
            StylusSample(x = 0.5f, y = 0.5f, pressure = 0, tiltX = 0, tiltY = 9001, hover = false, timestampNs = 0)
        }
    }
}
