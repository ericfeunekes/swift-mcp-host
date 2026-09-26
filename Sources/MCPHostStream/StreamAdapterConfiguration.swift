import MCPHostCore

/// How the newline-delimited stream adapter frames messages and whom it serves.
/// See docs/requirements.md#newline-delimited-stream.
public struct StreamAdapterConfiguration: Sendable {
    /// The single identity this process serves, fixed at launch.
    public var identity: CallerIdentity
    /// Lines above this size are rejected without being parsed.
    public var maxMessageBytes: Int

    public init(identity: CallerIdentity, maxMessageBytes: Int = 1 << 20) {
        self.identity = identity
        self.maxMessageBytes = maxMessageBytes
    }
}
