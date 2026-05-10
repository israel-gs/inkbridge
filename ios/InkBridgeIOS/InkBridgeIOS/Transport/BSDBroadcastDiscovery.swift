import Foundation
import Darwin

// MARK: - BSDBroadcastDiscovery

/// `BroadcastDiscovery` implementation using raw BSD sockets.
///
/// **Why BSD sockets?**
/// `NWConnection` with `NWParameters.udp` cannot send to broadcast addresses
/// on iOS — the connection transitions to `.failed` immediately (engram #220).
/// BSD `socket(AF_INET, SOCK_DGRAM)` + `setsockopt(SO_BROADCAST, 1)` works
/// in the iOS simulator and on device within the app sandbox without requiring
/// special entitlements.
///
/// **Probe sequence:**
/// 1. Open TX socket (ephemeral local port), enable SO_BROADCAST.
/// 2. Open RX socket bound to the same ephemeral port as TX (SO_REUSEADDR).
///    Note: On iOS simulator, binding RX to the same port as TX or a separate
///    ephemeral port both work — the server replies unicast to the source
///    `sockaddr_in` captured by the macOS server's `recvfrom`.
/// 3. Every `DISCOVERY_PROBE_INTERVAL_S = 2 s`, `sendto(255.255.255.255:4546)` the probe.
/// 4. `recvfrom` loop on a background `Task` parses replies via `ProbeCodec`.
/// 5. Each parsed `DiscoveredHost` is yielded into the `AsyncStream` continuation.
/// 6. `HostRegistry` (owned by caller) handles dedup + staleness sweep.
///
/// **Simulator note:**
/// Broadcasting to 255.255.255.255 from the iOS Simulator may not reach a
/// macOS server on the same machine because the simulator runs inside a network
/// namespace that does not deliver limited broadcast back to the host. If the
/// macOS `BroadcastResponder` is not running (as in unit tests), no replies are
/// expected — the `recvfrom` Task blocks until `stop()` closes the socket.
/// Real BSD broadcast tests are marked device-only via `XCTSkipIf` in the test suite.
public final class BSDBroadcastDiscovery: BroadcastDiscovery, @unchecked Sendable {

    // MARK: - Constants

    public static let probePort: UInt16 = 4546
    public static let probeInterval: TimeInterval = 2.0

    // MARK: - State

    private let lock = NSLock()
    /// Single socket used for both TX (sendto probe) and RX (recvfrom reply).
    /// The Mac server replies unicast to the source address of the probe — i.e.
    /// to *this socket's* ephemeral port. A separate RX socket bound to a
    /// different port would never see replies.
    private var probeSocket: Int32 = -1
    private var probeTask: Task<Void, Never>?
    private var recvTask: Task<Void, Never>?
    private var continuation: AsyncStream<DiscoveredHost>.Continuation?
    private var _started = false

    // MARK: - BroadcastDiscovery

    /// The `AsyncStream` is created lazily. The continuation is stored before
    /// `start()` is called — callers must access `hosts` before awaiting `start()`
    /// (or simultaneously, since `start()` spawns detached tasks that only write
    /// to the continuation after at least one probe interval). The lock ensures
    /// the continuation is visible to the recv loop regardless of scheduling order.
    public lazy var hosts: AsyncStream<DiscoveredHost> = {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.continuation = continuation
            print("[BSDBroadcastDiscovery] AsyncStream continuation installed")
            self?.lock.unlock()
        }
    }()

    public init() {}

    public func start() async throws {
        lock.lock()
        defer { lock.unlock() }
        guard !_started else { return }
        _started = true

        // Single socket used for both sending probes and receiving unicast replies.
        // The Mac server replies to the probe's source address; that is THIS
        // socket's ephemeral port. Using two sockets would route the reply to
        // a port nobody reads from.
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { throw POSIXError(.EBADF) }

        var enable: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))

        // 1 s receive timeout so the recv loop can poll cancellation.
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Bind to INADDR_ANY:0 (ephemeral) so we have a stable source port that
        // recvfrom can read from. Without an explicit bind, sendto auto-binds
        // and then recvfrom will read on the same fd — but explicit bind makes
        // the port reservation deterministic for diagnostics.
        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_addr.s_addr = in_addr_t(0)
        bindAddr.sin_port = 0
        withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                _ = Darwin.bind(s, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Bind to en0 so the kernel routes broadcast through Wi-Fi on device.
        // IP_BOUND_IF is the Darwin equivalent of Linux SO_BINDTODEVICE.
        Self.bindToWifi(socket: s)

        // Log the bound port for diagnostics.
        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                _ = getsockname(s, saPtr, &boundLen)
            }
        }
        let boundPort = UInt16(bigEndian: boundAddr.sin_port)
        print("[BSDBroadcastDiscovery] single-socket fd=\(s) bound to ephemeral port \(boundPort)")

        probeSocket = s

        let sock = s

        // Probe loop: sendto broadcast every probeInterval seconds.
        probeTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.sendProbe(socket: sock)
                try? await Task.sleep(nanoseconds: UInt64(Self.probeInterval * 1_000_000_000))
            }
        }

        // Receive loop on the SAME socket — replies arrive on the probe's source port.
        recvTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.runRecvLoop(socket: sock)
        }
    }

    public func stop() async {
        lock.lock()
        _started = false
        probeTask?.cancel()
        recvTask?.cancel()
        let s = probeSocket
        probeSocket = -1
        continuation?.finish()
        continuation = nil
        lock.unlock()

        if s >= 0 {
            shutdown(s, SHUT_RDWR)
            Darwin.close(s)
        }
        await probeTask?.value
        await recvTask?.value
    }

    // MARK: - Private

    // MARK: - Wi-Fi interface enumeration

    /// Enumerates `getifaddrs(3)` to find `en0` (Wi-Fi on iPhone) IPv4 address and
    /// compute the directed subnet broadcast address.
    ///
    /// Returns `(localIP, broadcastIP, ifindex)` or `nil` if `en0` is not present
    /// or has no IPv4 address (e.g. no Wi-Fi connection).
    private static func wifiInterface() -> (localIP: String, broadcastIP: String, ifindex: UInt32)? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstIfaddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstIfaddr
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name == "en0" else { continue }
            guard let addrPtr = ifa.pointee.ifa_addr else { continue }
            guard addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let netmaskPtr = ifa.pointee.ifa_netmask else { continue }

            let addr = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let netmask = netmaskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }

            // directed broadcast = (ip & netmask) | (~netmask)
            let ipBits = addr.sin_addr.s_addr
            let maskBits = netmask.sin_addr.s_addr
            let bcastBits = (ipBits & maskBits) | (~maskBits)

            var localBuf  = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var bcastBuf  = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

            var localAddr  = addr.sin_addr;  inet_ntop(AF_INET, &localAddr,  &localBuf,  socklen_t(INET_ADDRSTRLEN))
            var bcastInAddr = in_addr(s_addr: bcastBits)
            inet_ntop(AF_INET, &bcastInAddr, &bcastBuf, socklen_t(INET_ADDRSTRLEN))

            let localIP  = String(cString: localBuf)
            let bcastIP  = String(cString: bcastBuf)
            let ifindex  = if_nametoindex(ifa.pointee.ifa_name)

            return (localIP, bcastIP, ifindex)
        }
        return nil
    }

    /// Applies `IP_BOUND_IF` to `fd` so the kernel routes outgoing datagrams
    /// through the `en0` Wi-Fi interface instead of the default route.
    ///
    /// Without this, `sendto(255.255.255.255)` fails with `errno=65 (ENETUNREACH)` on
    /// device because iOS does not auto-route global broadcast through any interface.
    private static func bindToWifi(socket fd: Int32) {
        guard let wifi = wifiInterface() else {
            print("[BSDBroadcastDiscovery] en0 not found — skipping IP_BOUND_IF")
            return
        }
        var ifindex = wifi.ifindex
        let rc = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifindex, socklen_t(MemoryLayout<UInt32>.size))
        if rc != 0 {
            print("[BSDBroadcastDiscovery] setsockopt(IP_BOUND_IF) failed errno=\(errno)")
        } else {
            print("[BSDBroadcastDiscovery] bound to en0 ifindex=\(ifindex) local=\(wifi.localIP) directedBcast=\(wifi.broadcastIP)")
        }
    }

    private func sendProbe(socket fd: Int32) {
        let probe = Array(ProbeCodec.probePayload)

        // Resolve Wi-Fi interface info for directed broadcast.
        // Falls back gracefully if no Wi-Fi (simulator ethernet, etc.).
        let wifiInfo = Self.wifiInterface()

        // Send to global limited broadcast (255.255.255.255).
        // Some access points relay this; others drop it — we send both for resilience.
        sendTo(socket: fd, probe: probe, destination: "255.255.255.255")

        // Send to directed subnet broadcast (e.g. 192.168.1.255).
        // More reliably delivered within the local subnet than limited broadcast.
        if let wifi = wifiInfo, wifi.broadcastIP != "255.255.255.255" {
            sendTo(socket: fd, probe: probe, destination: wifi.broadcastIP)
        }
    }

    private func sendTo(socket fd: Int32, probe: [UInt8], destination: String) {
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_addr.s_addr = inet_addr(destination)
        dest.sin_port = Self.probePort.bigEndian

        let sent = probe.withUnsafeBufferPointer { bp -> Int in
            withUnsafePointer(to: &dest) { destPtr in
                destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    sendto(fd, bp.baseAddress, bp.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            print("[BSDBroadcastDiscovery] sendto \(destination) failed errno=\(errno)")
        } else {
            print("[BSDBroadcastDiscovery] probe sent \(sent) bytes to \(destination):\(Self.probePort)")
        }
    }

    private func runRecvLoop(socket fd: Int32) {
        print("[BSDBroadcastDiscovery] recvLoop started fd=\(fd)")
        var buf = [UInt8](repeating: 0, count: 1024)
        while !Task.isCancelled {
            var srcAddr = sockaddr_in()
            var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafeMutablePointer(to: &srcAddr) { saPtr in
                    saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { genericPtr in
                        recvfrom(fd, bp.baseAddress, bp.count, 0, genericPtr, &srcLen)
                    }
                }
            }

            guard n > 0 else {
                // Timeout (SO_RCVTIMEO = 1 s) or error — loop again to check isCancelled.
                continue
            }

            let data = Data(buf[0..<n])
            let rawText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[BSDBroadcastDiscovery] recvfrom \(n) bytes: \(rawText.debugDescription)")

            // Extract source IP string from sockaddr_in.
            let ip = withUnsafePointer(to: &srcAddr.sin_addr) { ptr -> String in
                var addrBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, ptr, &addrBuf, socklen_t(INET_ADDRSTRLEN))
                return String(cString: addrBuf)
            }

            if let host = ProbeCodec.parseReply(data, sourceIP: ip) {
                print("[BSDBroadcastDiscovery] parsed host name=\(host.name) ip=\(host.ipv4) port=\(host.port)")
                lock.lock()
                let cont = continuation
                lock.unlock()
                if cont == nil {
                    print("[BSDBroadcastDiscovery] WARNING: continuation is nil — host dropped. Ensure 'hosts' stream is subscribed before start().")
                }
                cont?.yield(host)
            } else {
                print("[BSDBroadcastDiscovery] parseReply failed for: \(rawText.debugDescription)")
            }
        }
        print("[BSDBroadcastDiscovery] recvLoop exiting")
    }
}
