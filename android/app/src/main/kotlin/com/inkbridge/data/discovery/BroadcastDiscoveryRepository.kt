package com.inkbridge.data.discovery

import android.util.Log
import com.inkbridge.domain.discovery.DiscoveredHost
import com.inkbridge.domain.discovery.HostDiscoverer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import kotlin.coroutines.CoroutineContext

private const val TAG = "InkBridge.Discovery"
private const val PROBE_PAYLOAD = "INKB?"
private const val RESPONSE_PREFIX = "INKB!"
private const val PROBE_INTERVAL_MS = 2_000L
private const val STALE_THRESHOLD_MS = 6_000L

/**
 * Custom UDP-broadcast discovery — replacement for NSD/Bonjour.
 *
 * Periodically broadcasts a small probe (`INKB?`) on `probePort`. Any
 * InkBridge server on the LAN replies unicast with `INKB!<v>|<dataPort>|<name>`
 * and we extract the source IPv4 from the UDP header. The host is added to
 * [observe] within ~1 RTT of opening the screen — typically <500 ms.
 *
 * Why not mDNS: in real-world Samsung+macOS networks, NSD's queries don't
 * reliably elicit responses from `NWListener.service` or even the system
 * `mDNSResponder`. Custom broadcast bypasses all of that.
 *
 * **MulticastLock**: even though this uses *broadcast* (not multicast) frames,
 * many Wi-Fi drivers (Samsung S Pen tablets included) gate broadcast packets
 * behind the same lock to save battery. Acquired here for safety.
 */
class BroadcastDiscoveryRepository(
    private val lockHolder: MulticastLockHolder,
    private val probePort: Int = 4546,
    backgroundDispatcher: CoroutineContext = Dispatchers.IO,
) : HostDiscoverer {

    private val _hosts = MutableStateFlow<List<DiscoveredHost>>(emptyList())
    private val scope = CoroutineScope(SupervisorJob() + backgroundDispatcher)
    private var job: Job? = null

    override fun observe(): Flow<List<DiscoveredHost>> = _hosts.asStateFlow()

    override suspend fun start() {
        if (job != null) return
        Log.i(TAG, "start: acquire lock + open broadcast socket")
        lockHolder.acquire()
        job = scope.launch { runLoop() }
    }

    override suspend fun stop() {
        Log.i(TAG, "stop")
        job?.cancelAndJoin()
        job = null
        lockHolder.release()
        _hosts.value = emptyList()
    }

    private suspend fun runLoop() {
        val socket = DatagramSocket(null).apply {
            broadcast = true
            reuseAddress = true
            bind(InetSocketAddress(0)) // ephemeral local port
            soTimeout = 1_000
        }
        try {
            val probe = PROBE_PAYLOAD.toByteArray(Charsets.US_ASCII)
            val limitedBroadcast = InetAddress.getByName("255.255.255.255")
            val recvBuf = ByteArray(512)
            var lastProbeAt = 0L
            val seenAt = HashMap<String, Long>()

            while (currentCoroutineContext().isActive) {
                val now = System.currentTimeMillis()

                if (now - lastProbeAt >= PROBE_INTERVAL_MS) {
                    sendProbeAll(socket, probe, limitedBroadcast)
                    lastProbeAt = now
                }

                try {
                    val packet = DatagramPacket(recvBuf, recvBuf.size)
                    socket.receive(packet)
                    handleResponse(packet, seenAt, now)
                } catch (_: SocketTimeoutException) {
                    // expected once per second when no responses are arriving
                }

                pruneStale(seenAt, now)
            }
        } finally {
            socket.close()
        }
    }

    /**
     * Send the probe to:
     *   1. The limited broadcast `255.255.255.255` (some APs honor this).
     *   2. Every active interface's directed broadcast (e.g. `192.168.100.255`).
     *
     * Many home routers drop `255.255.255.255` and only forward the subnet
     * directed broadcast within the LAN; others do the opposite. Sending to
     * both maximizes the chance that the server receives the probe.
     */
    private fun sendProbeAll(
        socket: DatagramSocket,
        probe: ByteArray,
        limitedBroadcast: InetAddress,
    ) {
        runCatching {
            socket.send(DatagramPacket(probe, probe.size, limitedBroadcast, probePort))
        }.onFailure { Log.w(TAG, "send limited-broadcast failed: ${it.message}") }

        for (target in directedBroadcastAddresses()) {
            runCatching {
                socket.send(DatagramPacket(probe, probe.size, target, probePort))
            }.onFailure { Log.w(TAG, "send directed-broadcast to $target failed: ${it.message}") }
        }
    }

    private fun directedBroadcastAddresses(): List<InetAddress> {
        return runCatching {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { iface -> iface.interfaceAddresses }
                .mapNotNull { it.broadcast }
                .filterIsInstance<Inet4Address>()
                .distinct()
        }.getOrDefault(emptyList())
    }

    private fun handleResponse(
        packet: DatagramPacket,
        seenAt: HashMap<String, Long>,
        now: Long,
    ) {
        val text = String(packet.data, 0, packet.length, Charsets.US_ASCII)
        if (!text.startsWith(RESPONSE_PREFIX)) return
        val parts = text.removePrefix(RESPONSE_PREFIX).split("|")
        val version = parts.getOrNull(0)?.takeIf { it.isNotBlank() } ?: return
        val dataPort = parts.getOrNull(1)?.toIntOrNull() ?: return
        val rawName = parts.getOrNull(2)?.takeIf { it.isNotBlank() } ?: "InkBridge"
        val ipv4 = packet.address.hostAddress ?: return
        if (ipv4.contains(':')) return // skip IPv6 noise

        val previousSeen = seenAt[ipv4]
        seenAt[ipv4] = now

        val current = _hosts.value
        val existing = current.firstOrNull { it.ipv4 == ipv4 }
        if (existing == null) {
            Log.i(TAG, "discovered ipv4=$ipv4 port=$dataPort name=$rawName")
            _hosts.value = current + DiscoveredHost(
                name = rawName,
                ipv4 = ipv4,
                port = dataPort,
                version = version,
            )
        } else if (existing.name != rawName || existing.port != dataPort) {
            _hosts.value = current.map {
                if (it.ipv4 == ipv4) it.copy(name = rawName, port = dataPort, version = version) else it
            }
        }
        // Quiet refresh path: previousSeen exists; nothing to log.
        @Suppress("UNUSED_VARIABLE") val _quiet = previousSeen
    }

    private fun pruneStale(seenAt: HashMap<String, Long>, now: Long) {
        val cutoff = now - STALE_THRESHOLD_MS
        val toRemove = seenAt.filterValues { it < cutoff }.keys
        if (toRemove.isEmpty()) return
        toRemove.forEach { seenAt.remove(it) }
        val before = _hosts.value
        val after = before.filter { it.ipv4 !in toRemove }
        if (after.size != before.size) {
            Log.i(TAG, "pruned stale hosts: $toRemove")
            _hosts.value = after
        }
    }
}
