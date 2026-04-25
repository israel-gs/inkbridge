package com.inkbridge.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.inkbridge.domain.model.ExpressKey
import com.inkbridge.domain.model.ExpressKeyAction
import com.inkbridge.domain.model.ExpressKeysEdge
import com.inkbridge.protocol.KeyAction

/**
 * Floating column of express-key buttons aligned to the chosen edge of the canvas.
 *
 * Stylus events with [PointerType.Stylus] pass through this overlay to the
 * underlying [CaptureSurface] — only finger taps register as keys (palm
 * rejection by design — no extra gating needed).
 *
 * Each [ExpressKey]:
 * - [ExpressKeyAction.Shortcut] → emits a single [KeyAction.TAP] on press.
 * - [ExpressKeyAction.ModifierHold] → emits [KeyAction.PRESS] on touch down,
 *   [KeyAction.RELEASE] on lift / cancel / out-of-bounds.
 */
@Composable
fun ExpressKeyBar(
    keys: List<ExpressKey>,
    edge: ExpressKeysEdge,
    onKeyAction: (ExpressKeyAction, KeyAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.fillMaxHeight(),
        contentAlignment = when (edge) {
            ExpressKeysEdge.LEFT  -> Alignment.CenterStart
            ExpressKeysEdge.RIGHT -> Alignment.CenterEnd
        },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(horizontal = 16.dp),
        ) {
            keys.forEach { key ->
                ExpressKeyButton(
                    key = key,
                    onAction = { wireAction -> onKeyAction(key.action, wireAction) },
                )
            }
        }
    }
}

@Composable
private fun ExpressKeyButton(
    key: ExpressKey,
    onAction: (KeyAction) -> Unit,
) {
    var pressed by remember(key.id) { mutableStateOf(false) }
    val pressScale by animateFloatAsState(
        targetValue = if (pressed) 0.95f else 1.0f,
        animationSpec = tween(durationMillis = 120),
        label = "expressKeyPressScale-${key.id}",
    )

    val cyan = Color(0xFF00C8FF)
    val idleBg = Color.White.copy(alpha = 0.06f)
    val idleBorder = Color.White.copy(alpha = 0.12f)
    val pressedBg = cyan.copy(
        alpha = if (key.action is ExpressKeyAction.ModifierHold) 0.28f else 0.18f,
    )
    val pressedBorder = cyan.copy(alpha = 0.6f)

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(64.dp)
            .scale(pressScale)
            .background(
                color = if (pressed) pressedBg else idleBg,
                shape = RoundedCornerShape(12.dp),
            )
            .border(
                width = 1.dp,
                color = if (pressed) pressedBorder else idleBorder,
                shape = RoundedCornerShape(12.dp),
            )
            .pointerInput(key.id, key.action) {
                awaitEachGesture {
                    val firstDown = awaitFirstDown(requireUnconsumed = false)
                    // Stylus passes through — only fingers trigger express keys.
                    if (firstDown.type == PointerType.Stylus) return@awaitEachGesture
                    firstDown.consume()
                    pressed = true
                    when (key.action) {
                        is ExpressKeyAction.Shortcut     -> onAction(KeyAction.TAP)
                        is ExpressKeyAction.ModifierHold -> onAction(KeyAction.PRESS)
                    }

                    // Wait for the finger to lift OR the gesture to be cancelled.
                    var sawAllUp = false
                    while (!sawAllUp) {
                        val event = awaitPointerEvent()
                        if (event.changes.all { !it.pressed }) {
                            sawAllUp = true
                        }
                    }
                    pressed = false
                    if (key.action is ExpressKeyAction.ModifierHold) {
                        onAction(KeyAction.RELEASE)
                    }
                }
            },
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = key.label,
                color = if (pressed) cyan else Color.White.copy(alpha = 0.85f),
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                fontFamily = FontFamily.SansSerif,
            )
            if (key.action is ExpressKeyAction.ModifierHold && pressed) {
                Text(
                    text = "HELD",
                    color = cyan,
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    }
}
