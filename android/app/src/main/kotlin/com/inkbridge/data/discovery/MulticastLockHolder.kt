package com.inkbridge.data.discovery

/**
 * Abstraction over [android.net.wifi.WifiManager.MulticastLock] for testability.
 *
 * The real MulticastLock requires a WifiManager instance (Android context), which
 * is not available in JVM unit tests. Implementations inject this interface so
 * tests can use a hand-rolled fake.
 */
interface MulticastLockHolder {
    /** Acquires the multicast lock. Must be called before [NsdManager.discoverServices]. */
    fun acquire()

    /** Releases the multicast lock. Must be called when discovery stops. */
    fun release()
}
