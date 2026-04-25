package com.inkbridge.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind

private const val DEFAULT_PORT = "4545"
private const val TAB_WIFI = 0
private const val TAB_USB = 1

private val IPV4_REGEX = Regex("""^(\d{1,3}\.){3}\d{1,3}$""")

/**
 * Connection screen — transport selector, host/port fields, connect/disconnect controls.
 *
 * Redesigned for dark theme with:
 * - Headline wordmark + tagline.
 * - Segmented transport selector with icons.
 * - USB card with copy-to-clipboard command.
 * - Collapsible Advanced section for non-default port.
 * - Sticky footer tip for Accessibility permission.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionScreen(
    state: ConnectionState,
    onConnect: (host: String, port: Int, kind: TransportKind) -> Unit,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(TAB_WIFI) }
    var host by rememberSaveable { mutableStateOf("") }
    var portText by rememberSaveable { mutableStateOf(DEFAULT_PORT) }
    var showAdvanced by rememberSaveable { mutableStateOf(false) }

    val isConnecting = state is ConnectionState.Connecting
    val isConnected = state is ConnectionState.Connected
    val controlsEnabled = !isConnecting && !isConnected

    val portError = validatePort(portText)
    val hostError = if (selectedTab == TAB_WIFI) validateHost(host) else null
    val canConnect =
        controlsEnabled && portError == null && hostError == null &&
            (selectedTab == TAB_USB || host.isNotBlank())

    Column(
        modifier =
            modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                // Feature 1: push content above the gesture navigation bar.
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = 20.dp, vertical = 24.dp),
    ) {
        // ── Wordmark header ──
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Ink",
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Bridge",
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = "Stream your S Pen to a macOS host.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(32.dp))

        // ── Transport selector ──
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            SegmentedButton(
                selected = selectedTab == TAB_WIFI,
                onClick = { if (controlsEnabled) selectedTab = TAB_WIFI },
                shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                enabled = controlsEnabled,
                icon = { Icon(Icons.Outlined.Wifi, contentDescription = null, modifier = Modifier.size(18.dp)) },
                label = { Text("Wi-Fi") },
            )
            SegmentedButton(
                selected = selectedTab == TAB_USB,
                onClick = { if (controlsEnabled) selectedTab = TAB_USB },
                shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                enabled = controlsEnabled,
                icon = { Icon(Icons.Outlined.Usb, contentDescription = null, modifier = Modifier.size(18.dp)) },
                label = { Text("USB") },
            )
        }

        Spacer(Modifier.height(20.dp))

        // ── Tab content ──
        when (selectedTab) {
            TAB_WIFI ->
                WifiTabContent(
                    host = host,
                    onHostChange = { host = it },
                    hostError = hostError,
                    enabled = controlsEnabled,
                )
            TAB_USB -> UsbTabContent()
        }

        Spacer(Modifier.height(16.dp))

        // ── Advanced (port) collapsible ──
        AdvancedSection(
            expanded = showAdvanced,
            onToggle = { showAdvanced = !showAdvanced },
            portText = portText,
            onPortChange = { portText = it },
            portError = portError,
            enabled = controlsEnabled,
        )

        Spacer(Modifier.height(16.dp))

        // ── Error state ──
        if (state is ConnectionState.Error) {
            ErrorBanner(state.reason)
            Spacer(Modifier.height(12.dp))
        }

        // ── Connecting spinner ──
        if (isConnecting) {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.size(28.dp),
                    strokeWidth = 3.dp,
                )
            }
            Spacer(Modifier.height(12.dp))
        }

        // ── Fill the middle space so the button sits close to the bottom. ──
        Box(modifier = Modifier.weight(1f))

        // ── Primary action ──
        ConnectButton(
            isConnected = isConnected,
            isConnecting = isConnecting,
            canConnect = canConnect,
            onConnect = {
                val port = portText.toIntOrNull() ?: return@ConnectButton
                val kind = if (selectedTab == TAB_USB) TransportKind.USB_TCP else TransportKind.WIFI_UDP
                val effectiveHost = if (selectedTab == TAB_USB) "127.0.0.1" else host
                onConnect(effectiveHost, port, kind)
            },
            onDisconnect = onDisconnect,
        )

        Spacer(Modifier.height(12.dp))

        // ── Footer hint ──
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.Info,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = "macOS Accessibility permission required on the host.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── Tab contents ──────────────────────────────────────────────────────────────

@Composable
private fun WifiTabContent(
    host: String,
    onHostChange: (String) -> Unit,
    hostError: String?,
    enabled: Boolean,
) {
    OutlinedTextField(
        value = host,
        onValueChange = onHostChange,
        label = { Text("Host IP") },
        placeholder = { Text("192.168.1.100") },
        isError = hostError != null,
        supportingText = hostError?.let { { Text(it) } },
        enabled = enabled,
        singleLine = true,
        keyboardOptions =
            KeyboardOptions(
                keyboardType = KeyboardType.Number,
                imeAction = ImeAction.Done,
            ),
        colors =
            OutlinedTextFieldDefaults.colors(
                focusedBorderColor = MaterialTheme.colorScheme.secondary,
                cursorColor = MaterialTheme.colorScheme.secondary,
            ),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun UsbTabContent() {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    val command = "adb reverse tcp:4545 tcp:4545"

    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "USB via adb reverse",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "Run on your Mac before connecting.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
            ) {
                Text(
                    text = command,
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("adb reverse", command))
                        copied = true
                    },
                    contentPadding =
                        androidx.compose.foundation.layout.PaddingValues(
                            horizontal = 8.dp,
                            vertical = 4.dp,
                        ),
                ) {
                    Icon(
                        imageVector = if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                        contentDescription = if (copied) "Copied" else "Copy command",
                        tint =
                            if (copied) {
                                MaterialTheme.colorScheme.secondary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.size(4.dp))
                    Text(
                        text = if (copied) "Copied" else "Copy",
                        style = MaterialTheme.typography.labelSmall,
                        fontSize = 12.sp,
                        color =
                            if (copied) {
                                MaterialTheme.colorScheme.secondary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                    )
                }
            }

            Spacer(Modifier.height(10.dp))
            Text(
                text = "Host is fixed to 127.0.0.1 over the adb tunnel.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── Advanced (port) ──────────────────────────────────────────────────────────

@Composable
private fun AdvancedSection(
    expanded: Boolean,
    onToggle: () -> Unit,
    portText: String,
    onPortChange: (String) -> Unit,
    portError: String?,
    enabled: Boolean,
) {
    Column {
        TextButton(
            onClick = onToggle,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp, vertical = 4.dp),
        ) {
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.size(4.dp))
            Text(
                text = if (expanded) "Hide advanced" else "Advanced (port)",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        AnimatedVisibility(
            visible = expanded,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            Column(modifier = Modifier.padding(top = 8.dp)) {
                OutlinedTextField(
                    value = portText,
                    onValueChange = onPortChange,
                    label = { Text("Port") },
                    isError = portError != null,
                    supportingText = portError?.let { { Text(it) } },
                    enabled = enabled,
                    singleLine = true,
                    keyboardOptions =
                        KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done,
                        ),
                    colors =
                        OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.colorScheme.secondary,
                            cursorColor = MaterialTheme.colorScheme.secondary,
                        ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

// ── Error banner ──────────────────────────────────────────────────────────────

@Composable
private fun ErrorBanner(reason: String) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
        ) {
            Box(
                modifier =
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.error),
            )
            Text(
                text = reason,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

// ── Primary action button ────────────────────────────────────────────────────

@Composable
private fun ConnectButton(
    isConnected: Boolean,
    isConnecting: Boolean,
    canConnect: Boolean,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
) {
    when {
        isConnected -> {
            OutlinedButton(
                onClick = onDisconnect,
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .height(52.dp),
            ) {
                Text("Disconnect")
            }
        }
        isConnecting -> {
            OutlinedButton(
                onClick = onDisconnect,
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .height(52.dp),
            ) {
                Text("Cancel")
            }
        }
        else -> {
            Button(
                onClick = onConnect,
                enabled = canConnect,
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.secondary,
                        contentColor = MaterialTheme.colorScheme.onSecondary,
                        disabledContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .height(52.dp),
            ) {
                Text(
                    text = "Connect",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.size(8.dp))
                Icon(
                    imageVector = Icons.Default.ArrowForward,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

// ── Validation helpers ────────────────────────────────────────────────────────

private fun validatePort(portText: String): String? {
    val port = portText.toIntOrNull()
    return when {
        port == null -> "Port must be a number"
        port !in 1024..65535 -> "Port must be between 1024 and 65535"
        else -> null
    }
}

private fun validateHost(host: String): String? {
    if (host.isBlank()) return "Host is required"
    return if (!IPV4_REGEX.matches(host)) "Enter a valid IPv4 address" else null
}

// ── Previews ──────────────────────────────────────────────────────────────────

@Preview(
    name = "Connection — Wi-Fi",
    showBackground = true,
    backgroundColor = 0xFF0A0A0A,
    widthDp = 360,
    heightDp = 780,
)
@Composable
private fun PreviewConnectionWifi() {
    InkBridgeTheme {
        ConnectionScreen(
            state = ConnectionState.Disconnected,
            onConnect = { _, _, _ -> },
            onDisconnect = {},
        )
    }
}

@Preview(
    name = "Connection — Error",
    showBackground = true,
    backgroundColor = 0xFF0A0A0A,
    widthDp = 360,
    heightDp = 780,
)
@Composable
private fun PreviewConnectionError() {
    InkBridgeTheme {
        ConnectionScreen(
            state = ConnectionState.Error("Connection refused — run: adb reverse tcp:4545 tcp:4545"),
            onConnect = { _, _, _ -> },
            onDisconnect = {},
        )
    }
}

@Suppress("unused")
private val PreviewPlaceholderColor = Color.Transparent
