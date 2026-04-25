package com.inkbridge.ui.screens

import android.app.Activity
import android.view.MotionEvent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind
import kotlinx.coroutines.launch

/**
 * Status screen — shown while [ConnectionState.Connected] or [ConnectionState.Error].
 *
 * Canvas-first layout:
 * - Slim top bar with wordmark, transport chip (with pulsing dot when connected),
 *   gear icon to open settings, and disconnect action.
 * - Error banner (only when errored).
 * - Full-bleed [CaptureSurface] occupies the rest of the screen.
 * - [ModalBottomSheet] for gesture settings (natural-scroll toggle).
 *
 * @param stats Kept in the signature for API stability but no longer rendered —
 *              the transport label is read from the chip via state.
 * @param naturalScroll Current natural-scroll setting. True = fingers-direction (macOS default).
 * @param onSetNaturalScroll Callback to persist a natural-scroll change.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatusScreen(
    connectionState: ConnectionState,
    stats: ConnectionViewModel.Stats,
    onDisconnect: () -> Unit,
    onMotionEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit,
    onGestureEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int, indices: IntArray) -> Unit = { _, _, _, _ -> },
    onTrackpadEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int, indices: IntArray) -> Unit = { _, _, _, _ -> },
    naturalScroll: Boolean = true,
    onSetNaturalScroll: (Boolean) -> Unit = {},
    autoReconnect: Boolean = true,
    onSetAutoReconnect: (Boolean) -> Unit = {},
    hapticIntensity: Int = 100,
    onSetHapticIntensity: (Int) -> Unit = {},
    onPreviewHaptic: () -> Unit = {},
    clickFlashEnabled: Boolean = true,
    onSetClickFlashEnabled: (Boolean) -> Unit = {},
    clickFlashes: kotlinx.coroutines.flow.SharedFlow<androidx.compose.ui.geometry.Offset>? = null,
    isAutoReconnecting: Boolean = false,
    expressKeysEnabled: Boolean = false,
    onSetExpressKeysEnabled: (Boolean) -> Unit = {},
    expressKeysEdge: com.inkbridge.domain.model.ExpressKeysEdge =
        com.inkbridge.domain.model.ExpressKeysEdge.RIGHT,
    onSetExpressKeysEdge: (com.inkbridge.domain.model.ExpressKeysEdge) -> Unit = {},
    expressKeys: List<com.inkbridge.domain.model.ExpressKey> = emptyList(),
    onExpressKeyAction: (
        com.inkbridge.domain.model.ExpressKeyAction,
        com.inkbridge.protocol.KeyAction,
    ) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
) {
    var showSettings by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()

    // Feature 2: Fullscreen / immersive mode toggle state.
    var isFullscreen by rememberSaveable { mutableStateOf(false) }
    val view = LocalView.current
    val window = (view.context as? Activity)?.window
    val insetsController = window?.let { WindowCompat.getInsetsController(it, view) }

    Column(
        modifier =
            modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
    ) {
        TopBar(
            transportLabel = stats.transportLabel,
            connectionState = connectionState,
            onDisconnect = onDisconnect,
            onOpenSettings = { showSettings = true },
            isFullscreen = isFullscreen,
            onToggleFullscreen = {
                isFullscreen = !isFullscreen
                if (isFullscreen) {
                    window?.let { w ->
                        WindowCompat.setDecorFitsSystemWindows(w, false)
                    }
                    insetsController?.hide(WindowInsetsCompat.Type.systemBars())
                    insetsController?.systemBarsBehavior =
                        WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                } else {
                    insetsController?.show(WindowInsetsCompat.Type.systemBars())
                }
            },
        )

        if (connectionState is ConnectionState.Error) {
            ErrorBanner(connectionState.reason)
        }

        if (isAutoReconnecting) {
            AutoReconnectBanner()
        }

        // Canvas + express-key bar live side by side rather than overlayed so
        // (a) a tap on the bar never reaches the underlying CaptureSurface and
        // (b) the user keeps full reachability of every canvas pixel without
        // having to navigate around an overlay column.
        val barShouldShow = expressKeysEnabled && expressKeys.isNotEmpty()
        androidx.compose.foundation.layout.Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .weight(1f),
        ) {
            if (barShouldShow && expressKeysEdge == com.inkbridge.domain.model.ExpressKeysEdge.LEFT) {
                ExpressKeyBar(
                    keys = expressKeys,
                    edge = expressKeysEdge,
                    onKeyAction = onExpressKeyAction,
                )
            }
            CaptureSurface(
                connectionState = connectionState,
                onMotionEvent = onMotionEvent,
                onGestureEvent = onGestureEvent,
                onTrackpadEvent = onTrackpadEvent,
                clickFlashes = clickFlashes,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
            )
            if (barShouldShow && expressKeysEdge == com.inkbridge.domain.model.ExpressKeysEdge.RIGHT) {
                ExpressKeyBar(
                    keys = expressKeys,
                    edge = expressKeysEdge,
                    onKeyAction = onExpressKeyAction,
                )
            }
        }
    }

    if (showSettings) {
        ModalBottomSheet(
            onDismissRequest = { showSettings = false },
            sheetState = sheetState,
        ) {
            SettingsSheet(
                naturalScroll = naturalScroll,
                onNaturalScrollChange = onSetNaturalScroll,
                autoReconnect = autoReconnect,
                onAutoReconnectChange = onSetAutoReconnect,
                hapticIntensity = hapticIntensity,
                onHapticIntensityChange = onSetHapticIntensity,
                onPreviewHaptic = onPreviewHaptic,
                clickFlashEnabled = clickFlashEnabled,
                onClickFlashChange = onSetClickFlashEnabled,
                expressKeysEnabled = expressKeysEnabled,
                onExpressKeysEnabledChange = onSetExpressKeysEnabled,
                expressKeysEdge = expressKeysEdge,
                onExpressKeysEdgeChange = onSetExpressKeysEdge,
            )
        }
    }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

@Composable
private fun TopBar(
    transportLabel: String,
    connectionState: ConnectionState,
    onDisconnect: () -> Unit,
    onOpenSettings: () -> Unit = {},
    isFullscreen: Boolean = false,
    onToggleFullscreen: () -> Unit = {},
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier =
            Modifier
                .fillMaxWidth()
                // Feature 1: push content below the status bar (edge-to-edge).
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        // Compact wordmark.
        Row {
            Text(
                text = "Ink",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Bridge",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.secondary,
            )
        }

        Spacer(Modifier.width(12.dp))
        TransportChip(
            label = transportLabel,
            connectionState = connectionState,
        )
        Spacer(Modifier.weight(1f))

        // Feature 2: Fullscreen toggle button.
        IconButton(
            onClick = onToggleFullscreen,
            modifier = Modifier.size(48.dp),
        ) {
            Icon(
                imageVector = if (isFullscreen) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                contentDescription = if (isFullscreen) "Exit fullscreen" else "Enter fullscreen",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        IconButton(
            onClick = onOpenSettings,
            modifier = Modifier.size(48.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.Settings,
                contentDescription = "Settings",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        IconButton(
            onClick = onDisconnect,
            modifier = Modifier.size(48.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = "Disconnect",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TransportChip(
    label: String,
    connectionState: ConnectionState,
) {
    val icon: ImageVector? =
        when {
            label.equals("Wi-Fi", ignoreCase = true) -> Icons.Outlined.Wifi
            label.equals("USB", ignoreCase = true) -> Icons.Outlined.Usb
            else -> null
        }

    val dotColor: Color =
        when (connectionState) {
            is ConnectionState.Connected -> MaterialTheme.colorScheme.secondary
            is ConnectionState.Error -> MaterialTheme.colorScheme.error
            is ConnectionState.Connecting -> MaterialTheme.colorScheme.tertiary
            is ConnectionState.Disconnected -> MaterialTheme.colorScheme.onSurfaceVariant
        }
    val pulse = connectionState is ConnectionState.Connected
    val statusText =
        when (connectionState) {
            is ConnectionState.Connected -> "Connected via $label"
            is ConnectionState.Connecting -> "Connecting via $label"
            is ConnectionState.Error -> "Connection error"
            is ConnectionState.Disconnected -> "Disconnected"
        }

    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "Server status: $statusText" },
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
        ) {
            PulsingDot(color = dotColor, pulse = pulse)
            icon?.let {
                Icon(
                    imageVector = it,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(
                text = if (label.isNotBlank()) label else "—",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun PulsingDot(
    color: Color,
    pulse: Boolean,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "statusPulse")
    val haloAlpha by infiniteTransition.animateFloat(
        initialValue = 0.0f,
        targetValue = if (pulse) 0.45f else 0f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(durationMillis = 1200),
                repeatMode = RepeatMode.Reverse,
            ),
        label = "pulseAlpha",
    )
    val haloScale by infiniteTransition.animateFloat(
        initialValue = 1.0f,
        targetValue = if (pulse) 2.0f else 1.0f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(durationMillis = 1200),
                repeatMode = RepeatMode.Reverse,
            ),
        label = "pulseScale",
    )

    Box(
        modifier = Modifier.size(14.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (pulse) {
            Box(
                modifier =
                    Modifier
                        .size((7 * haloScale).dp)
                        .clip(CircleShape)
                        .background(color.copy(alpha = haloAlpha)),
            )
        }
        Box(
            modifier =
                Modifier
                    .size(7.dp)
                    .clip(CircleShape)
                    .background(color),
        )
    }
}

// ── Settings sheet ───────────────────────────────────────────────────────────

/**
 * Content of the gesture-settings bottom sheet.
 *
 * Exposes a "Natural scrolling" toggle and an "Auto-reconnect" toggle.
 * Additional settings can be added as rows below the divider.
 */
@Composable
private fun SettingsSheet(
    naturalScroll: Boolean,
    onNaturalScrollChange: (Boolean) -> Unit,
    autoReconnect: Boolean = true,
    onAutoReconnectChange: (Boolean) -> Unit = {},
    hapticIntensity: Int = 100,
    onHapticIntensityChange: (Int) -> Unit = {},
    onPreviewHaptic: () -> Unit = {},
    clickFlashEnabled: Boolean = true,
    onClickFlashChange: (Boolean) -> Unit = {},
    expressKeysEnabled: Boolean = false,
    onExpressKeysEnabledChange: (Boolean) -> Unit = {},
    expressKeysEdge: com.inkbridge.domain.model.ExpressKeysEdge =
        com.inkbridge.domain.model.ExpressKeysEdge.RIGHT,
    onExpressKeysEdgeChange: (com.inkbridge.domain.model.ExpressKeysEdge) -> Unit = {},
) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
    ) {
        Text(
            text = "Settings",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(bottom = 12.dp),
        )
        HorizontalDivider()
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Natural scrolling",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Two-finger drag scrolls in the same direction your fingers move.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(
                checked = naturalScroll,
                onCheckedChange = onNaturalScrollChange,
            )
        }
        HorizontalDivider()
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Auto-reconnect",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Automatically retry connection after a disconnect (up to 30 attempts).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(
                checked = autoReconnect,
                onCheckedChange = onAutoReconnectChange,
            )
        }
        HorizontalDivider()
        HapticSection(
            intensity = hapticIntensity,
            onIntensityChange = onHapticIntensityChange,
            onPreview = onPreviewHaptic,
        )
        HorizontalDivider()
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Click flash",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Show a ripple on the canvas at every tap and right-click.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(
                checked = clickFlashEnabled,
                onCheckedChange = onClickFlashChange,
            )
        }
        HorizontalDivider()
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Express keys",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Edge column with 6 shortcut/modifier keys (Ctrl, Undo, Redo, [, ], Pan).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(
                checked = expressKeysEnabled,
                onCheckedChange = onExpressKeysEnabledChange,
            )
        }
        if (expressKeysEnabled) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(start = 4.dp, bottom = 12.dp),
            ) {
                Text(
                    text = "Side",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                EdgeChip(
                    label = "Left",
                    selected = expressKeysEdge == com.inkbridge.domain.model.ExpressKeysEdge.LEFT,
                    onClick = {
                        onExpressKeysEdgeChange(com.inkbridge.domain.model.ExpressKeysEdge.LEFT)
                    },
                )
                EdgeChip(
                    label = "Right",
                    selected = expressKeysEdge == com.inkbridge.domain.model.ExpressKeysEdge.RIGHT,
                    onClick = {
                        onExpressKeysEdgeChange(com.inkbridge.domain.model.ExpressKeysEdge.RIGHT)
                    },
                )
            }
        }
    }
}

@Composable
private fun EdgeChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val cyan = androidx.compose.ui.graphics.Color(0xFF00C8FF)
    androidx.compose.material3.Surface(
        onClick = onClick,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp),
        color = if (selected) cyan.copy(alpha = 0.18f) else MaterialTheme.colorScheme.surfaceVariant,
        border = androidx.compose.foundation.BorderStroke(
            width = 1.dp,
            color = if (selected) cyan.copy(alpha = 0.6f) else androidx.compose.ui.graphics.Color.Transparent,
        ),
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = if (selected) cyan else MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun HapticSection(
    intensity: Int,
    onIntensityChange: (Int) -> Unit,
    onPreview: () -> Unit,
) {
    var sliderValue by remember(intensity) { mutableStateOf(intensity.toFloat()) }
    Column(modifier = Modifier.padding(vertical = 12.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Haptic feedback",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = if (sliderValue.toInt() == 0) {
                        "Disabled"
                    } else {
                        "Intensity ${sliderValue.toInt()}% — fires on tap and right-click."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.size(8.dp))
        androidx.compose.material3.Slider(
            value = sliderValue,
            onValueChange = { sliderValue = it },
            onValueChangeFinished = {
                onIntensityChange(sliderValue.toInt())
                if (sliderValue.toInt() > 0) onPreview()
            },
            valueRange = 0f..100f,
            steps = 9, // 0, 10, 20, …, 100
        )
    }
}

// ── Auto-reconnect banner ────────────────────────────────────────────────────

@Composable
private fun AutoReconnectBanner() {
    Surface(
        color = MaterialTheme.colorScheme.tertiaryContainer,
        shape = RoundedCornerShape(8.dp),
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Text(
            text = "Auto-reconnecting…",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onTertiaryContainer,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        )
    }
}

// ── Error banner ─────────────────────────────────────────────────────────────

@Composable
private fun ErrorBanner(reason: String) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(8.dp),
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Text(
            text = reason,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onErrorContainer,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        )
    }
}

// ── Previews ──────────────────────────────────────────────────────────────────

@Preview(
    name = "Status — Connected Wi-Fi",
    showBackground = true,
    backgroundColor = 0xFF0A0A0A,
    widthDp = 360,
    heightDp = 780,
)
@Composable
private fun PreviewStatusConnectedWifi() {
    InkBridgeTheme {
        StatusScreen(
            connectionState = ConnectionState.Connected(TransportKind.WIFI_UDP),
            stats = ConnectionViewModel.Stats(transportLabel = "Wi-Fi"),
            onDisconnect = {},
            onMotionEvent = { _, _, _ -> },
        )
    }
}

@Preview(
    name = "Status — Connected USB",
    showBackground = true,
    backgroundColor = 0xFF0A0A0A,
    widthDp = 360,
    heightDp = 780,
)
@Composable
private fun PreviewStatusConnectedUsb() {
    InkBridgeTheme {
        StatusScreen(
            connectionState = ConnectionState.Connected(TransportKind.USB_TCP),
            stats = ConnectionViewModel.Stats(transportLabel = "USB"),
            onDisconnect = {},
            onMotionEvent = { _, _, _ -> },
        )
    }
}

@Preview(name = "Status — Error", showBackground = true, backgroundColor = 0xFF0A0A0A, widthDp = 360, heightDp = 780)
@Composable
private fun PreviewStatusError() {
    InkBridgeTheme {
        StatusScreen(
            connectionState = ConnectionState.Error("Connection lost — retry from the previous screen."),
            stats = ConnectionViewModel.Stats(transportLabel = "Wi-Fi"),
            onDisconnect = {},
            onMotionEvent = { _, _, _ -> },
        )
    }
}
