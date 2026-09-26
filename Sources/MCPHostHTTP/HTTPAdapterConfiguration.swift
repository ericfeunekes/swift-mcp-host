import MCPHostCore

/// How the Streamable HTTP adapter listens and which requests it accepts.
/// See docs/requirements.md#streamable-http.
public struct HTTPAdapterConfiguration: Sendable {
    public enum Listener: Sendable {
        /// A TCP port on 127.0.0.1. Non-loopback interfaces are not offered.
        case loopback(port: Int)
        /// A Unix domain socket at an absolute path.
        case unixSocket(path: String)
    }

    public var listener: Listener
    /// Prefix before `/c/<identity>/mcp`, for example `/messages` behind `tailscale serve --set-path /messages`.
    public var basePath: String
    /// The identities served, one MCP path each. There is no default identity.
    public var identities: Set<CallerIdentity>
    /// `Host` header values accepted, to prevent DNS rebinding.
    public var allowedHosts: Set<String>
    /// `Origin` header values accepted when the header is present.
    public var allowedOrigins: Set<String>
    /// Request bodies above this size are rejected with `413` before parsing.
    public var maxBodyBytes: Int

    public init(
        listener: Listener,
        basePath: String,
        identities: Set<CallerIdentity>,
        allowedHosts: Set<String>,
        allowedOrigins: Set<String> = [],
        maxBodyBytes: Int = 1 << 20
    ) {
        self.listener = listener
        self.basePath = basePath
        self.identities = identities
        self.allowedHosts = allowedHosts
        self.allowedOrigins = allowedOrigins
        self.maxBodyBytes = maxBodyBytes
    }
}
