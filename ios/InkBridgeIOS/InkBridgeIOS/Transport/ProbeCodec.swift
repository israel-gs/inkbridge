import Foundation

// MARK: - ProbeCodec

/// Encodes UDP discovery probe packets and decodes server replies.
///
/// **Wire protocol (ASCII, matches BroadcastResponder.swift on macOS):**
/// - Probe TX: `INKB?` (5 bytes ASCII)
/// - Reply RX: `INKB!<version>|<dataPort>|<hostname>`
///   - version: integer (currently `1`)
///   - dataPort: UInt16 decimal string
///   - hostname: ASCII string, may contain spaces, no `|` characters
///
/// Example reply: `INKB!1|4545|MacBook Pro`
public enum ProbeCodec {

    /// The UDP payload to send as a broadcast probe.
    public static let probePayload = Data("INKB?".utf8)

    /// Parses a `INKB!<version>|<port>|<name>` reply into a `DiscoveredHost`.
    ///
    /// - Parameters:
    ///   - data: The raw bytes received from `recvfrom`.
    ///   - sourceIP: The IPv4 address string of the sender.
    /// - Returns: A `DiscoveredHost` on success, `nil` if the payload is malformed.
    public static func parseReply(_ data: Data, sourceIP: String) -> DiscoveredHost? {
        guard !data.isEmpty,
              let rawText = String(data: data, encoding: .utf8) else { return nil }

        // Trim trailing whitespace / newlines defensively — some platforms may
        // append \n or \r\n to the UDP payload even when the spec says none.
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with "INKB!"
        guard text.hasPrefix("INKB!") else { return nil }

        // Strip prefix, split on '|' — expect exactly 3 fields: version, port, name
        let body = String(text.dropFirst(5)) // drop "INKB!"
        let parts = body.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        // parts[0] = version (ignored for now), parts[1] = port, parts[2] = name
        let portString = String(parts[1])
        // Trim name too — handles any whitespace the server may append.
        let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let port = UInt16(portString) else { return nil }

        return DiscoveredHost(
            name: name,
            ipv4: sourceIP,
            port: port,
            lastSeen: Date()
        )
    }
}
