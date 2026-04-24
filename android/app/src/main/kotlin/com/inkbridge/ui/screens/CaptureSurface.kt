package com.inkbridge.ui.screens

import android.view.MotionEvent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind

/**
 * Full-bleed capture surface that intercepts stylus MotionEvents.
 *
 * Active only when [connectionState] is [ConnectionState.Connected] (ui.md R4).
 *
 * No ink rendering — this is a transparent forwarding surface. Visual feedback:
 * - Subtle border distinguishing the capture area.
 * - Pressure-opacity feedback circle at the last stylus contact point.
 *
 * @param connectionState Current connection state. Events are ignored unless Connected.
 * @param onMotionEvent   Callback with the raw MotionEvent and actual view dimensions (px).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun CaptureSurface(
    connectionState: ConnectionState,
    onMotionEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val isActive = connectionState is ConnectionState.Connected

    var viewWidth by remember { mutableIntStateOf(1) }
    var viewHeight by remember { mutableIntStateOf(1) }

    val borderColor = MaterialTheme.colorScheme.primary.copy(alpha = if (isActive) 0.3f else 0.08f)
    val feedbackColor = MaterialTheme.colorScheme.primary

    var feedbackOffset by remember { mutableStateOf(Offset.Zero) }
    var feedbackPressure by remember { mutableFloatStateOf(0f) }
    var showFeedback by remember { mutableStateOf(false) }

    Box(
        modifier = modifier
            .fillMaxSize()
            .onSizeChanged { size ->
                viewWidth = size.width.coerceAtLeast(1)
                viewHeight = size.height.coerceAtLeast(1)
            }
            .border(width = 1.dp, color = borderColor)
            .pointerInteropFilter { event ->
                if (!isActive) return@pointerInteropFilter false
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
                true
            },
    ) {
        if (showFeedback && isActive) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawFeedbackCircle(feedbackOffset, feedbackPressure, feedbackColor)
            }
        }
    }
}

private fun DrawScope.drawFeedbackCircle(
    offset: Offset,
    pressure: Float,
    color: Color,
) {
    val radius = 12.dp.toPx() + pressure * 4.dp.toPx()
    drawCircle(
        color = color.copy(alpha = (pressure * 0.4f).coerceIn(0.05f, 0.4f)),
        radius = radius,
        center = offset,
    )
}

// ── Previews ──────────────────────────────────────────────────────────────────

@Preview(name = "CaptureSurface — active light", showBackground = true)
@Composable
private fun PreviewCaptureSurfaceActive() {
    InkBridgeTheme(darkTheme = false, dynamicColor = false) {
        CaptureSurface(
            connectionState = ConnectionState.Connected(TransportKind.WIFI_UDP),
            onMotionEvent = { _, _, _ -> },
        )
    }
}

@Preview(name = "CaptureSurface — inactive light", showBackground = true)
@Composable
private fun PreviewCaptureSurfaceInactive() {
    InkBridgeTheme(darkTheme = false, dynamicColor = false) {
        CaptureSurface(
            connectionState = ConnectionState.Disconnected,
            onMotionEvent = { _, _, _ -> },
        )
    }
}
