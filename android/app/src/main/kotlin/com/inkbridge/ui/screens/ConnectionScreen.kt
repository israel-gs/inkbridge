package com.inkbridge.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind

private const val DEFAULT_PORT = "4545"
private const val TAB_WIFI = 0
private const val TAB_USB = 1

// Simple IPv4 regex (format check only — no DNS validation)
private val IPV4_REGEX = Regex("""^(\d{1,3}\.){3}\d{1,3}$""")

/**
 * Connection screen — transport selector, host/port fields, connect/disconnect controls.
 *
 * Implements ui.md R1–R3, R8, R10 (no persisted state).
 *
 * @param state           Current connection state.
 * @param onConnect       Called with (host, port, kind) when the user taps Connect.
 * @param onDisconnect    Called when the user taps Disconnect.
 */
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

    val isConnecting = state is ConnectionState.Connecting
    val isConnected = state is ConnectionState.Connected
    val controlsEnabled = !isConnecting && !isConnected

    val portError = validatePort(portText)
    val hostError = if (selectedTab == TAB_WIFI) validateHost(host) else null
    val canConnect = controlsEnabled && portError == null && hostError == null &&
        (selectedTab == TAB_USB || host.isNotBlank())

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 24.dp),
    ) {
        // Header
        Text(
            text = "InkBridge",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        Text(
            text = "Connect your stylus to a macOS host.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(24.dp))

        // Transport selector (ui.md R2)
        TabRow(selectedTabIndex = selectedTab) {
            Tab(
                selected = selectedTab == TAB_WIFI,
                onClick = { if (controlsEnabled) selectedTab = TAB_WIFI },
                text = { Text("Wi-Fi (UDP)") },
            )
            Tab(
                selected = selectedTab == TAB_USB,
                onClick = { if (controlsEnabled) selectedTab = TAB_USB },
                text = { Text("USB (TCP)") },
            )
        }

        Spacer(Modifier.height(16.dp))

        when (selectedTab) {
            TAB_WIFI -> WifiTabContent(
                host = host,
                onHostChange = { host = it },
                hostError = hostError,
                portText = portText,
                onPortChange = { portText = it },
                portError = portError,
                enabled = controlsEnabled,
            )
            TAB_USB -> UsbTabContent(
                portText = portText,
                onPortChange = { portText = it },
                portError = portError,
                enabled = controlsEnabled,
            )
        }

        Spacer(Modifier.height(16.dp))

        // Error state display (ui.md R1)
        if (state is ConnectionState.Error) {
            Text(
                text = state.reason,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        // Connecting indicator (ui.md R1)
        if (isConnecting) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            Spacer(Modifier.height(8.dp))
        }

        // Action buttons (ui.md R1, R8)
        when {
            isConnected -> {
                Button(
                    onClick = onDisconnect,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                ) {
                    Text("Disconnect")
                }
            }
            isConnecting -> {
                OutlinedButton(
                    onClick = onDisconnect,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                ) {
                    Text("Cancel")
                }
            }
            else -> {
                Button(
                    onClick = {
                        val port = portText.toIntOrNull() ?: return@Button
                        val kind = if (selectedTab == TAB_USB) TransportKind.USB_TCP else TransportKind.WIFI_UDP
                        val effectiveHost = if (selectedTab == TAB_USB) "127.0.0.1" else host
                        onConnect(effectiveHost, port, kind)
                    },
                    enabled = canConnect,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                ) {
                    Text("Connect")
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        Text(
            text = "macOS Accessibility permission required on the host.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun WifiTabContent(
    host: String,
    onHostChange: (String) -> Unit,
    hostError: String?,
    portText: String,
    onPortChange: (String) -> Unit,
    portError: String?,
    enabled: Boolean,
) {
    OutlinedTextField(
        value = host,
        onValueChange = onHostChange,
        label = { Text("Host IP address") },
        placeholder = { Text("e.g. 192.168.1.100") },
        isError = hostError != null,
        supportingText = hostError?.let { { Text(it) } },
        enabled = enabled,
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Number,
            imeAction = ImeAction.Next,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(8.dp))
    PortField(portText, onPortChange, portError, enabled)
}

@Composable
private fun UsbTabContent(
    portText: String,
    onPortChange: (String) -> Unit,
    portError: String?,
    enabled: Boolean,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "USB via adb reverse",
                style = MaterialTheme.typography.titleSmall,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "Run on your Mac before connecting:",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "adb reverse tcp:4545 tcp:4545",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "Host: 127.0.0.1 (via adb reverse)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    Spacer(Modifier.height(8.dp))
    PortField(portText, onPortChange, portError, enabled)
}

@Composable
private fun PortField(
    portText: String,
    onPortChange: (String) -> Unit,
    portError: String?,
    enabled: Boolean,
) {
    OutlinedTextField(
        value = portText,
        onValueChange = onPortChange,
        label = { Text("Port") },
        isError = portError != null,
        supportingText = portError?.let { { Text(it) } },
        enabled = enabled,
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Number,
            imeAction = ImeAction.Done,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
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
    return if (!IPV4_REGEX.matches(host)) "Enter a valid IPv4 address (e.g. 192.168.1.100)" else null
}

// ── Previews ──────────────────────────────────────────────────────────────────

@Preview(name = "Connection — Disconnected light", showBackground = true)
@Composable
private fun PreviewConnectionLight() {
    InkBridgeTheme(darkTheme = false) {
        ConnectionScreen(
            state = ConnectionState.Disconnected,
            onConnect = { _, _, _ -> },
            onDisconnect = {},
        )
    }
}

@Preview(name = "Connection — Disconnected dark", showBackground = true)
@Composable
private fun PreviewConnectionDark() {
    InkBridgeTheme(darkTheme = false, dynamicColor = false) {
        // Force dark via the theme wrapper
        InkBridgeTheme(darkTheme = true, dynamicColor = false) {
            ConnectionScreen(
                state = ConnectionState.Disconnected,
                onConnect = { _, _, _ -> },
                onDisconnect = {},
            )
        }
    }
}

@Preview(name = "Connection — Error light", showBackground = true)
@Composable
private fun PreviewConnectionError() {
    InkBridgeTheme(darkTheme = false, dynamicColor = false) {
        ConnectionScreen(
            state = ConnectionState.Error("Connection refused — run: adb reverse tcp:4545 tcp:4545"),
            onConnect = { _, _, _ -> },
            onDisconnect = {},
        )
    }
}
