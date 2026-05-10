/// The connection lifecycle state of the iOS client.
///
/// Drives UI routing: `idle` and `connecting` show the connection screen;
/// `connected` shows the capture canvas; `failed` shows the connection screen
/// with an error banner.
public enum ConnectionState: Equatable {
    /// No connection attempt in progress.
    case idle
    /// A connection attempt is underway.
    case connecting
    /// Connected and ready to send events to the given host.
    case connected(host: DiscoveredHost)
    /// The last connection attempt failed with the given human-readable reason.
    case failed(reason: String)
}
