package com.inkbridge.data.discovery

import android.net.wifi.WifiManager

/**
 * Production [MulticastLockHolder] backed by [WifiManager.MulticastLock].
 *
 * [acquire] is idempotent: a second call while a lock is already held is a no-op.
 * [release] is idempotent: calling it when no lock is held is a no-op.
 *
 * Reference-counting is disabled ([setReferenceCounted(false)]) because the
 * repository pairs exactly one acquire with one release per discovery session.
 */
class RealMulticastLockHolder(private val wifiManager: WifiManager) : MulticastLockHolder {

    private var lock: WifiManager.MulticastLock? = null

    override fun acquire() {
        if (lock != null) return
        lock = wifiManager.createMulticastLock("InkBridgeDiscovery").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun release() {
        lock?.release()
        lock = null
    }
}
