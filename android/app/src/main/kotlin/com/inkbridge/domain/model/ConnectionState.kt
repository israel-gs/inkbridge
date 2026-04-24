package com.inkbridge.domain.model

/**
 * Sealed hierarchy representing the Android-side connection lifecycle.
 *
 * Maps to the states defined in transport.md R6 and ui.md R1.
 */
sealed class ConnectionState {

    /** No active transport. Initial state on every launch. */
    data object Disconnected : ConnectionState()

    /** Transport is establishing the connection (meaningful for TCP; UDP transitions immediately). */
    data object Connecting : ConnectionState()

    /**
     * Transport is active and frames can be sent.
     *
     * @param kind the transport that is active (Wi-Fi UDP or USB TCP).
     */
    data class Connected(val kind: TransportKind) : ConnectionState()

    /**
     * Last connection attempt failed or the connection was lost mid-session.
     *
     * @param reason human-readable explanation shown directly in the UI.
     */
    data class Error(val reason: String) : ConnectionState()
}
