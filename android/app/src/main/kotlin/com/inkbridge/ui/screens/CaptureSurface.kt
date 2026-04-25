package com.inkbridge.ui.screens

import android.view.MotionEvent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
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
import com.inkbridge.ui.theme.FingerIndicatorColor
import com.inkbridge.ui.theme.InkOutline

/**
 * Per-finger visual indicator state.
 *
 * @param id      Android pointer ID — stable across the lifetime of the touch.
 * @param position Last known screen-space position of this finger.
 * @param alpha   Animatable alpha (180ms fade-in, 120ms fade-out).
 */
private data class FingerPointer(
    val id: Int,
    val position: Offset,
    val alpha: Animatable<Float, *>,
)

/**
 * Full-bleed capture surface that intercepts stylus and two-finger gesture MotionEvents.
 *
 * Visual design:
 * - Pure OLED-black background.
 * - Subtle dot grid pattern (32dp pitch) — brighter when Connected.
 * - Rounded corners, hairline border that animates on active/inactive.
 * - Cyan radial-glow feedback at current stylus position with pressure scaling.
 * - Gray-300 hollow ring at each finger position (Feature 4).
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
    onGestureEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int, indices: IntArray) -> Unit = { _, _, _, _ -> },
    onTrackpadEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int, indices: IntArray) -> Unit = { _, _, _, _ -> },
    clickFlashes: kotlinx.coroutines.flow.SharedFlow<Offset>? = null,
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

    // Feature 4: per-finger visual indicators (up to 2 fingers).
    // Key = pointer ID, value = mutable position + alpha state.
    var fingerPointers by remember { mutableStateOf(mapOf<Int, FingerPointer>()) }

    // Click flash: a short ripple at the click point, driven by the upstream
    // clickFlashes flow. We hold a single active flash; rapid clicks restart
    // the animation rather than overlapping.
    val flashRadius = remember { Animatable(0f) }
    val flashAlpha = remember { Animatable(0f) }
    var flashCenter by remember { mutableStateOf(Offset.Zero) }
    if (clickFlashes != null) {
        androidx.compose.runtime.LaunchedEffect(clickFlashes) {
            clickFlashes.collect { norm ->
                flashCenter = Offset(norm.x * viewWidth, norm.y * viewHeight)
                // Cancel previous animation if running.
                flashRadius.snapTo(0f)
                flashAlpha.snapTo(0.85f)
                coroutineScope {
                    launch {
                        flashRadius.animateTo(
                            targetValue = 1f,
                            animationSpec = tween(durationMillis = 320),
                        )
                    }
                    launch {
                        flashAlpha.animateTo(
                            targetValue = 0f,
                            animationSpec = tween(durationMillis = 320),
                        )
                    }
                }
            }
        }
    }

    Box(
        modifier =
            modifier
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

                    // pointerInteropFilter is a legacy-View bridge: when ANY
                    // pointer hits the canvas region, it receives the FULL
                    // MotionEvent including pointers whose down location was
                    // on a sibling view (e.g. the express-key bar). Those
                    // pointers' X coordinates are translated to canvas-local
                    // space and may be > viewWidth (right-edge bar) or < 0
                    // (left-edge bar). We must filter them out before
                    // counting fingers, otherwise holding a modifier key on
                    // the bar inflates pointerCount and breaks the routing.
                    var stylusCount = 0
                    val fingerIndices = mutableListOf<Int>()
                    val w = viewWidth.toFloat()
                    val h = viewHeight.toFloat()
                    for (i in 0 until event.pointerCount) {
                        val x = event.getX(i)
                        val y = event.getY(i)
                        val inBounds = x >= 0f && x < w && y >= 0f && y < h
                        if (!inBounds) continue
                        val t = event.getToolType(i)
                        if (t == MotionEvent.TOOL_TYPE_STYLUS || t == MotionEvent.TOOL_TYPE_ERASER) {
                            stylusCount++
                        } else {
                            fingerIndices.add(i)
                        }
                    }
                    val fingerCount = fingerIndices.size

                    // If the action that triggered this dispatch corresponds to
                    // an out-of-bounds pointer (POINTER_DOWN/UP on the bar), do
                    // not consume — let the gesture system continue routing.
                    val actionIdx = when (event.actionMasked) {
                        MotionEvent.ACTION_POINTER_DOWN,
                        MotionEvent.ACTION_POINTER_UP,
                        -> event.actionIndex
                        else -> -1
                    }
                    if (actionIdx >= 0 && actionIdx !in fingerIndices && stylusCount == 0) {
                        // Bar finger transition — ignore.
                        return@pointerInteropFilter false
                    }

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
                            // Stylus engaged — clear any stale finger indicators.
                            if (fingerPointers.isNotEmpty()) {
                                fingerPointers = emptyMap()
                            }
                        }
                        fingerCount in 1..2 && stylusCount == 0 -> {
                            // Update finger indicator positions.
                            val updated = fingerPointers.toMutableMap()

                            when (event.actionMasked) {
                                MotionEvent.ACTION_DOWN,
                                MotionEvent.ACTION_POINTER_DOWN,
                                MotionEvent.ACTION_MOVE,
                                -> {
                                    // Upsert each active finger pointer.
                                    for (i in 0 until event.pointerCount) {
                                        val t = event.getToolType(i)
                                        if (t == MotionEvent.TOOL_TYPE_STYLUS || t == MotionEvent.TOOL_TYPE_ERASER) continue
                                        val pid = event.getPointerId(i)
                                        val pos = Offset(event.getX(i), event.getY(i))
                                        if (pid in updated) {
                                            // Update position in-place (Animatable stays).
                                            updated[pid] = updated[pid]!!.copy(position = pos)
                                        } else {
                                            updated[pid] = FingerPointer(
                                                id = pid,
                                                position = pos,
                                                alpha = Animatable(0f),
                                            )
                                        }
                                    }
                                }
                                MotionEvent.ACTION_UP,
                                MotionEvent.ACTION_CANCEL,
                                -> {
                                    // All fingers lifted.
                                    updated.clear()
                                }
                                MotionEvent.ACTION_POINTER_UP -> {
                                    // One finger lifted — remove it.
                                    val idx = event.actionIndex
                                    val pid = event.getPointerId(idx)
                                    updated.remove(pid)
                                }
                            }

                            fingerPointers = updated

                            val indicesArray = fingerIndices.toIntArray()
                            if (fingerCount == 2) {
                                onGestureEvent(event, viewWidth, viewHeight, indicesArray)
                            } else {
                                onTrackpadEvent(event, viewWidth, viewHeight, indicesArray)
                            }
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

        // Feature 4: finger indicators — animated alpha rings, one per finger.
        // Z-order: above dot grid, below stylus glow.
        for ((_, fp) in fingerPointers) {
            val alphaAnimatable = fp.alpha
            val pos = fp.position

            // Drive fade-in on appearance, fade-out on removal via LaunchedEffect.
            LaunchedEffect(fp.id) {
                alphaAnimatable.animateTo(
                    targetValue = 0.5f,
                    animationSpec = tween(durationMillis = 180),
                )
            }

            val currentAlpha = alphaAnimatable.value
            if (currentAlpha > 0f) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    drawFingerIndicator(pos, currentAlpha)
                }
            }
        }

        // Cyan glow feedback — only while a stylus is in contact.
        if (showFeedback && isActive) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawFeedbackGlow(feedbackOffset, feedbackPressure)
            }
        }

        // Click ripple flash — accent ring that fades while expanding.
        val currentFlashAlpha = flashAlpha.value
        val currentFlashProgress = flashRadius.value
        if (currentFlashAlpha > 0.01f) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawClickFlash(
                    center = flashCenter,
                    progress = currentFlashProgress,
                    alpha = currentFlashAlpha,
                )
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
 * Draws a single finger indicator: hollow ring (32dp outer diameter, 2dp stroke)
 * with a 4dp filled dot at the centre.
 *
 * Color: [FingerIndicatorColor] at [alpha] opacity (0.4–0.6 range during contact).
 */
private fun DrawScope.drawFingerIndicator(
    center: Offset,
    alpha: Float,
) {
    val outerRadius = 16.dp.toPx() // 32dp outer diameter → 16dp radius
    val strokeWidth = 2.dp.toPx()
    val dotRadius = 2.dp.toPx() // 4dp filled dot → 2dp radius
    val color = FingerIndicatorColor.copy(alpha = alpha)

    // Hollow ring.
    drawCircle(
        color = color,
        radius = outerRadius - strokeWidth / 2f,
        center = center,
        style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
    )

    // Filled centre dot.
    drawCircle(
        color = color,
        radius = dotRadius,
        center = center,
    )
}

/**
 * Radial glow under the stylus tip. Larger + more intense with pressure.
 * Not a stroke — purely UX confirmation that input is captured.
 */
private fun DrawScope.drawFeedbackGlow(
    offset: Offset,
    pressure: Float,
) {
    val baseRadius = 16.dp.toPx()
    val pressureRadius = baseRadius + pressure * 24.dp.toPx()
    val intensity = (0.15f + pressure * 0.55f).coerceIn(0.15f, 0.7f)

    // Soft outer halo.
    drawCircle(
        brush =
            Brush.radialGradient(
                colors =
                    listOf(
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

/**
 * Click ripple — accent-coloured ring that expands and fades.
 * Distinct from stylus glow (cyan radial filled circle) and finger indicators
 * (gray hollow rings tracking touch). Used to confirm a discrete click event.
 */
private fun DrawScope.drawClickFlash(
    center: Offset,
    progress: Float, // 0..1 — animation progress
    alpha: Float,
) {
    if (center == Offset.Zero) return
    val minR = 12.dp.toPx()
    val maxR = 64.dp.toPx()
    val radius = minR + progress * (maxR - minR)
    val strokeW = 3.dp.toPx() * (1f - progress * 0.3f).coerceAtLeast(0.4f)

    // Outer ring stroke.
    drawCircle(
        color = androidx.compose.ui.graphics.Color(0xFFFFFFFF).copy(alpha = alpha),
        radius = radius,
        center = center,
        style = androidx.compose.ui.graphics.drawscope.Stroke(width = strokeW),
    )
    // Inner faint fill for the first half of the animation.
    if (progress < 0.5f) {
        drawCircle(
            color = androidx.compose.ui.graphics.Color(0xFFFFFFFF)
                .copy(alpha = alpha * 0.18f),
            radius = radius * 0.6f,
            center = center,
        )
    }
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
