package com.inkbridge.ui.screens

import android.view.MotionEvent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind
import com.inkbridge.ui.theme.CanvasBackground
import com.inkbridge.ui.theme.CanvasDot
import com.inkbridge.ui.theme.CanvasDotActive
import com.inkbridge.ui.theme.CanvasFeedbackGlow
import com.inkbridge.ui.theme.InkOutline

/**
 * Full-bleed capture surface that intercepts stylus and two-finger gesture MotionEvents.
 *
 * Visual design:
 * - Pure OLED-black background.
 * - Subtle dot grid pattern (32dp pitch) — brighter when Connected.
 * - Rounded corners, hairline border that animates on active/inactive.
 * - Cyan radial-glow feedback at current stylus position with pressure scaling.
 *
 * Active only when [connectionState] is [ConnectionState.Connected] (ui.md R4).
 * No ink rendering — this is a transparent forwarding surface.
 *
 * Routing logic:
 * - 1 pointer with TOOL_TYPE_STYLUS → [onMotionEvent] (existing stylus path).
 * - Exactly 2 finger pointers (no stylus in contact) → [onGestureEvent].
 * - Anything else (mixed, 3+ fingers) → ignored.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun CaptureSurface(
    connectionState: ConnectionState,
    onMotionEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit,
    onGestureEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit = { _, _, _ -> },
    onTrackpadEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit = { _, _, _ -> },
    modifier: Modifier = Modifier,
) {
    val isActive = connectionState is ConnectionState.Connected

    var viewWidth by remember { mutableIntStateOf(1) }
    var viewHeight by remember { mutableIntStateOf(1) }

    val borderAlpha by animateFloatAsState(
        targetValue = if (isActive) 0.6f else 0.2f,
        animationSpec = tween(durationMillis = 240),
        label = "captureBorderAlpha",
    )

    var feedbackOffset by remember { mutableStateOf(Offset.Zero) }
    var feedbackPressure by remember { mutableFloatStateOf(0f) }
    var showFeedback by remember { mutableStateOf(false) }

    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 12.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(CanvasBackground)
            .border(
                width = 1.dp,
                color = InkOutline.copy(alpha = borderAlpha),
                shape = RoundedCornerShape(16.dp),
            )
            .onSizeChanged { size ->
                viewWidth = size.width.coerceAtLeast(1)
                viewHeight = size.height.coerceAtLeast(1)
            }
            .pointerInteropFilter { event ->
                if (!isActive) return@pointerInteropFilter false

                // Count pointers by category. STYLUS + ERASER → stylus side.
                // Everything else (FINGER, UNKNOWN, MOUSE) → finger side.
                var stylusCount = 0
                for (i in 0 until event.pointerCount) {
                    val t = event.getToolType(i)
                    if (t == MotionEvent.TOOL_TYPE_STYLUS || t == MotionEvent.TOOL_TYPE_ERASER) {
                        stylusCount++
                    }
                }
                val fingerCount = event.pointerCount - stylusCount

                // Routing:
                // - 1 stylus alone → existing stylus path (preserves S Pen fidelity).
                // - 2 fingers alone → gesture path.
                // - 1 finger alone → CLAIM (return true) but don't dispatch. This keeps the
                //   input stream alive so the upcoming 2nd-finger ACTION_POINTER_DOWN actually
                //   reaches us. If we returned false here, Android would route subsequent
                //   pointer events elsewhere and the gesture would never start.
                // - Anything else (mixed, 3+ fingers) → ignore (return false).
                when {
                    stylusCount == 1 && fingerCount == 0 -> {
                        onMotionEvent(event, viewWidth, viewHeight)
                        when (event.actionMasked) {
                            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                                feedbackOffset = Offset(event.getX(0), event.getY(0))
                                feedbackPressure = event.pressure.coerceIn(0f, 1f)
                                showFeedback = true
                            }
                            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                                showFeedback = false
                            }
                        }
                    }
                    fingerCount == 2 && stylusCount == 0 -> {
                        onGestureEvent(event, viewWidth, viewHeight)
                        showFeedback = false
                    }
                    fingerCount == 1 && stylusCount == 0 -> {
                        // Trackpad mode: drag → cursor delta, quick tap → primary click.
                        onTrackpadEvent(event, viewWidth, viewHeight)
                        showFeedback = false
                    }
                    else -> return@pointerInteropFilter false
                }
                true
            },
    ) {
        // Dot grid — drawn once per layout, scales with view size.
        Canvas(modifier = Modifier.fillMaxSize()) {
            drawDotGrid(isActive = isActive)
        }

        // Cyan glow feedback — only while a stylus is in contact.
        if (showFeedback && isActive) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawFeedbackGlow(feedbackOffset, feedbackPressure)
            }
        }
    }
}

// ── Drawing helpers ──────────────────────────────────────────────────────────

/**
 * Draws a dot grid with 32dp pitch covering the canvas.
 * Dots brighten slightly when the surface is Connected (active state).
 */
private fun DrawScope.drawDotGrid(isActive: Boolean) {
    val pitch = 32.dp.toPx()
    val radius = 1.dp.toPx()
    val color = if (isActive) CanvasDotActive else CanvasDot

    // Offset by half-pitch so the grid visually centers within the rounded rect.
    val offsetX = pitch / 2f
    val offsetY = pitch / 2f

    var y = offsetY
    while (y < size.height) {
        var x = offsetX
        while (x < size.width) {
            drawCircle(color = color, radius = radius, center = Offset(x, y))
            x += pitch
        }
        y += pitch
    }
}

/**
 * Radial glow under the stylus tip. Larger + more intense with pressure.
 * Not a stroke — purely UX confirmation that input is captured.
 */
private fun DrawScope.drawFeedbackGlow(offset: Offset, pressure: Float) {
    val baseRadius = 16.dp.toPx()
    val pressureRadius = baseRadius + pressure * 24.dp.toPx()
    val intensity = (0.15f + pressure * 0.55f).coerceIn(0.15f, 0.7f)

    // Soft outer halo.
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                CanvasFeedbackGlow.copy(alpha = intensity),
                CanvasFeedbackGlow.copy(alpha = 0f),
            ),
            center = offset,
            radius = pressureRadius * 2f,
        ),
        radius = pressureRadius * 2f,
        center = offset,
    )

    // Bright core.
    drawCircle(
        color = CanvasFeedbackGlow.copy(alpha = (intensity + 0.2f).coerceAtMost(0.95f)),
        radius = pressureRadius * 0.45f,
        center = offset,
    )
}

// ── Previews ──────────────────────────────────────────────────────────────────

@Preview(name = "CaptureSurface — active", showBackground = true, backgroundColor = 0xFF0A0A0A)
@Composable
private fun PreviewCaptureSurfaceActive() {
    InkBridgeTheme {
        CaptureSurface(
            connectionState = ConnectionState.Connected(TransportKind.WIFI_UDP),
            onMotionEvent = { _, _, _ -> },
        )
    }
}

@Preview(name = "CaptureSurface — inactive", showBackground = true, backgroundColor = 0xFF0A0A0A)
@Composable
private fun PreviewCaptureSurfaceInactive() {
    InkBridgeTheme {
        CaptureSurface(
            connectionState = ConnectionState.Disconnected,
            onMotionEvent = { _, _, _ -> },
        )
    }
}
