package com.inkbridge.ui.screens

import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind

/**
 * Status screen — shown when in [ConnectionState.Connected].
 *
 * Shows:
 * - Top bar with transport chip and disconnect icon.
 * - Status pill.
 * - Stats row (packets, dropped).
 * - Full-bleed [CaptureSurface].
 *
 * ui.md R1, R4, R8.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatusScreen(
    connectionState: ConnectionState,
    stats: ConnectionViewModel.Stats,
    onDisconnect: () -> Unit,
    onMotionEvent: (event: MotionEvent, viewWidth: Int, viewHeight: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                TransportChip(stats.transportLabel)
            },
            actions = {
                IconButton(
                    onClick = onDisconnect,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Disconnect",
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            },
        )

        Column(
            modifier = Modifier.padding(horizontal = 16.dp),
        ) {
            Spacer(Modifier.height(8.dp))
            StatusPill(connectionState)
            Spacer(Modifier.height(12.dp))
            StatsRow(stats)
            Spacer(Modifier.height(12.dp))
        }

        // Full-bleed capture surface
        CaptureSurface(
            connectionState = connectionState,
            onMotionEvent = onMotionEvent,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )
    }
}

@Composable
private fun TransportChip(label: String) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
    ) {
        Text(
            text = if (label.isNotBlank()) label else "—",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun StatusPill(state: ConnectionState) {
    val (dotColor, label) = when (state) {
        is ConnectionState.Connected -> Pair(
            MaterialTheme.colorScheme.primary,
            "Connected",
        )
        is ConnectionState.Error -> Pair(
            MaterialTheme.colorScheme.error,
            "Error: ${state.reason}",
        )
        is ConnectionState.Connecting -> Pair(
            MaterialTheme.colorScheme.tertiary,
            "Connecting…",
        )
        is ConnectionState.Disconnected -> Pair(
            MaterialTheme.colorScheme.outline,
            "Disconnected",
        )
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(dotColor),
        )
        Text(text = label, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun StatsRow(stats: ConnectionViewModel.Stats) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        StatItem("Packets", stats.packetsSent.toString())
        StatItem("Dropped", stats.dropped.toString())
    }
}

@Composable
private fun StatItem(label: String, value: String) {
    Column {
        Text(text = value, style = MaterialTheme.typography.titleMedium)
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ── Previews ──────────────────────────────────────────────────────────────────

@Preview(name = "StatusScreen — Connected light", showBackground = true)
@Composable
private fun PreviewStatusConnectedLight() {
    InkBridgeTheme(darkTheme = false, dynamicColor = false) {
        StatusScreen(
            connectionState = ConnectionState.Connected(TransportKind.WIFI_UDP),
            stats = ConnectionViewModel.Stats(
                transportLabel = "Wi-Fi",
                packetsSent = 1024,
                dropped = 2,
            ),
            onDisconnect = {},
            onMotionEvent = { _, _, _ -> },
        )
    }
}

@Preview(name = "StatusScreen — Connected dark", showBackground = true)
@Composable
private fun PreviewStatusConnectedDark() {
    InkBridgeTheme(darkTheme = true, dynamicColor = false) {
        StatusScreen(
            connectionState = ConnectionState.Connected(TransportKind.USB_TCP),
            stats = ConnectionViewModel.Stats(
                transportLabel = "USB",
                packetsSent = 512,
                dropped = 0,
            ),
            onDisconnect = {},
            onMotionEvent = { _, _, _ -> },
        )
    }
}

@Preview(name = "StatusScreen — Error light", showBackground = true)
@Composable
private fun PreviewStatusError() {
    InkBridgeTheme(darkTheme = false, dynamicColor = false) {
        StatusScreen(
            connectionState = ConnectionState.Error("Connection lost"),
            stats = ConnectionViewModel.Stats(),
            onDisconnect = {},
            onMotionEvent = { _, _, _ -> },
        )
    }
}
