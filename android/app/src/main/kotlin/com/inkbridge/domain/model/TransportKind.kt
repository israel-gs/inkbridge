package com.inkbridge.domain.model

/**
 * Identifies the active transport path chosen by the user.
 *
 * WIFI_UDP — unicast UDP datagrams over Wi-Fi (transport.md R3).
 * USB_TCP  — TCP stream over loopback via `adb reverse tcp:4545 tcp:4545` (transport.md R4).
 */
enum class TransportKind {
    WIFI_UDP,
    USB_TCP,
}
