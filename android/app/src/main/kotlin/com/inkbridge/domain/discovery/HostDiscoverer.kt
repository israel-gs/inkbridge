package com.inkbridge.domain.discovery

import kotlinx.coroutines.flow.Flow

/**
 * Domain port for Wi-Fi host discovery.
 *
 * Implementations MUST NOT expose any NSD or platform types through this interface.
 * Discovery runs when [start] is called and stops when [stop] is called.
 *
 * [observe] returns a hot [Flow] that emits the current list of discovered hosts
 * whenever it changes. The initial emission is always an empty list.
 */
interface HostDiscoverer {
    /** Hot flow of the current discovered-host list. Always emits an initial empty list. */
    fun observe(): Flow<List<DiscoveredHost>>

    /** Starts mDNS service browsing. Idempotent. */
    suspend fun start()

    /** Stops mDNS service browsing and releases the MulticastLock. Idempotent. */
    suspend fun stop()
}
