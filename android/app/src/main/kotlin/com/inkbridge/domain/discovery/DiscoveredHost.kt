package com.inkbridge.domain.discovery

/**
 * Represents a discovered InkBridge server on the local network.
 *
 * [ipv4] MUST be a dotted-decimal IPv4 address (never a .local hostname or IPv6).
 * This is enforced by [NsdDiscoveryRepository] which reads from
 * NsdServiceInfo.host.hostAddress after resolution.
 *
 * [version] is the value of the TXT record key "version" (e.g. "1").
 */
data class DiscoveredHost(
    val name: String,
    val ipv4: String,
    val port: Int,
    val version: String,
)
