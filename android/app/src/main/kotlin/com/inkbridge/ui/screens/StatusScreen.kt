package com.inkbridge.ui.screens

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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind

/**
 * Status screen — shown while [ConnectionState.Connected] or [ConnectionState.Error].
 *
 * Canvas-first layout:
 * - Slim top bar with wordmark, transport chip (with pulsing dot when connected),
 *   and disconnect action.
 * - Error banner (only when errored).
 * - Full-bleed [CaptureSurface] occupies the rest of the screen.
 *
 * @param stats Kept in the signature for API stability but no longer rendered —
 *              the transport label is read from the chip via state.
 */
@Composable
fun StatusScreen(
    connectionState: ConnectionState,
    stats: ConnectionViewModel.Stats,
    onDisconnect: () -> Unit,
    onMotionEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        TopBar(
            transportLabel = stats.transportLabel,
            connectionState = connectionState,
            onDisconnect = onDisconnect,
        )

        if (connectionState is ConnectionState.Error) {
            ErrorBanner(connectionState.reason)
        }

        CaptureSurface(
            connectionState = connectionState,
            onMotionEvent = onMotionEvent,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )
    }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

@Composable
private fun TopBar(
    transportLabel: String,
    connectionState: ConnectionState,
    onDisconnect: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
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

        IconButton(
            onClick = onDisconnect,
            modifier = Modifier.size(40.dp),
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
    val icon: ImageVector? = when {
        label.equals("Wi-Fi", ignoreCase = true) -> Icons.Outlined.Wifi
        label.equals("USB", ignoreCase = true) -> Icons.Outlined.Usb
        else -> null
    }

    val dotColor: Color = when (connectionState) {
        is ConnectionState.Connected -> MaterialTheme.colorScheme.secondary
        is ConnectionState.Error -> MaterialTheme.colorScheme.error
        is ConnectionState.Connecting -> MaterialTheme.colorScheme.tertiary
        is ConnectionState.Disconnected -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val pulse = connectionState is ConnectionState.Connected

    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
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
private fun PulsingDot(color: Color, pulse: Boolean) {
    val infiniteTransition = rememberInfiniteTransition(label = "statusPulse")
    val haloAlpha by infiniteTransition.animateFloat(
        initialValue = 0.0f,
        targetValue = if (pulse) 0.45f else 0f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseAlpha",
    )
    val haloScale by infiniteTransition.animateFloat(
        initialValue = 1.0f,
        targetValue = if (pulse) 2.0f else 1.0f,
        animationSpec = infiniteRepeatable(
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
                modifier = Modifier
                    .size((7 * haloScale).dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = haloAlpha)),
            )
        }
        Box(
            modifier = Modifier
                .size(7.dp)
                .clip(CircleShape)
                .background(color),
        )
    }
}

// ── Error banner ─────────────────────────────────────────────────────────────

@Composable
private fun ErrorBanner(reason: String) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier
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

@Preview(name = "Status — Connected Wi-Fi", showBackground = true, backgroundColor = 0xFF0A0A0A, widthDp = 360, heightDp = 780)
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

@Preview(name = "Status — Connected USB", showBackground = true, backgroundColor = 0xFF0A0A0A, widthDp = 360, heightDp = 780)
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
