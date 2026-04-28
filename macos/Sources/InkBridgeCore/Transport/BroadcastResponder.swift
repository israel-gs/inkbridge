import Foundation
import Darwin

/// Listens for InkBridge discovery probes on a UDP port and replies unicast to
/// the sender so an Android client can locate this Mac on the LAN without
/// relying on mDNS/Bonjour (which is unreliable between Samsung NSD and the
/// macOS NWListener service in practice).
///
/// **Protocol (text, ASCII)**
/// - Probe payload: `INKB?` — sent to broadcast address on `probePort`.
/// - Response payload: `INKB!<version>|<dataPort>|<hostname>` — sent unicast
///   back to the probe sender. `hostname` may contain spaces but no `|`.
///
/// **Threading**: a single dedicated POSIX thread reads from a blocking socket
/// and dispatches replies inline. `start()` and `stop()` are thread-safe and
/// idempotent. The reader thread exits cleanly when `stop()` closes the socket.
public final class BroadcastResponder {

    public let probePort: UInt16
    public let dataPort: UInt16
    public let hostname: String

    private let queue = DispatchQueue(label: "inkbridge.broadcast", qos: .utility)
    private var fd: Int32 = -1
    private var thread: Thread?
    private var _running = false

    public var isRunning: Bool { queue.sync { _running } }

    public init(probePort: UInt16 = 4546, dataPort: UInt16 = 4545, hostname: String) {
        self.probePort = probePort
        self.dataPort = dataPort
        // Hostname is used in the response so the Android UI can show a
        // human-readable name. Strip the `|` separator to keep parsing trivial
        // and clamp to ASCII for compatibility with restrictive parsers.
        self.hostname = BroadcastResponder.sanitize(hostname)
    }

    public func start() throws {
        try queue.sync {
            guard !_running else { return }

            let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard s >= 0 else { throw POSIXError(.EBADF) }

            // Allow other listeners to share the same port (helpful when the
            // app is restarted and an old socket is still in TIME_WAIT) and
            // permit reading broadcast frames.
            var enable: Int32 = 1
            _ = setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))
            _ = setsockopt(s, SOL_SOCKET, SO_REUSEPORT, &enable, socklen_t(MemoryLayout<Int32>.size))
            _ = setsockopt(s, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_addr.s_addr = in_addr_t(0).bigEndian // INADDR_ANY
            addr.sin_port = probePort.bigEndian

            let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.bind(s, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult < 0 {
                let err = errno
                close(s)
                NSLog("[BroadcastResponder] bind(:\(probePort)) failed errno=\(err)")
                throw POSIXError(POSIXError.Code(rawValue: err) ?? .EADDRINUSE)
            }

            self.fd = s
            self._running = true
            let t = Thread { [weak self] in self?.runLoop() }
            t.name = "inkbridge.broadcast.reader"
            t.qualityOfService = .utility
            t.start()
            self.thread = t
            NSLog("[BroadcastResponder] listening on UDP :\(probePort) dataPort=\(dataPort) hostname=\(hostname)")
        }
    }

    public func stop() {
        queue.sync {
            guard _running else { return }
            _running = false
            if fd >= 0 {
                shutdown(fd, SHUT_RDWR)
                close(fd)
                fd = -1
            }
            thread = nil
        }
    }

    // MARK: - Reader loop

    private func runLoop() {
        var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let s = queue.sync { fd }
            if !queue.sync(execute: { _running }) || s < 0 { break }

            var srcAddr = sockaddr_in()
            var srcLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)

            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafeMutablePointer(to: &srcAddr) { saPtr -> Int in
                    saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { genericPtr -> Int in
                        recvfrom(s, bp.baseAddress, bp.count, 0, genericPtr, &srcLen)
                    }
                }
            }
            if n <= 0 {
                if !queue.sync(execute: { _running }) { break }
                // Spurious wakeup or transient error; tiny sleep to avoid spin.
                usleep(50_000)
                continue
            }

            let payload = Data(buf[0..<n])
            guard payload == Data("INKB?".utf8) else { continue }

            let response = "INKB!1|\(dataPort)|\(hostname)"
            let respBytes = Array(response.utf8)
            _ = respBytes.withUnsafeBufferPointer { bp -> Int in
                withUnsafePointer(to: &srcAddr) { saPtr -> Int in
                    saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { genericPtr -> Int in
                        sendto(s, bp.baseAddress, bp.count, 0, genericPtr, srcLen)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let safe = String(
            trimmed.unicodeScalars.map { scalar -> Character in
                if scalar.isASCII && scalar.value >= 0x20 && scalar != "|" {
                    return Character(scalar)
                }
                return Character("-")
            }
        )
        return safe.isEmpty ? "Mac" : safe
    }
}
