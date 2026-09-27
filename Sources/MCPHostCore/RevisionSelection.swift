import Foundation

/// How a request's protocol revision was chosen. See docs/requirements.md#selecting-the-revision.
enum RevisionSelection: Sendable, Equatable {
    /// A 2026-07-28 request carrying its revision and client capabilities in `_meta`.
    case modern(ProtocolRevision, clientCapabilities: JSONValue)
    /// A request served under a legacy revision, from the stream's negotiation or the HTTP header.
    case legacy(ProtocolRevision)
    /// `initialize`, or `ping` on a stream before `initialize`: no revision is negotiated yet.
    case handshake

    var era: ProtocolRevision.Era {
        switch self {
        case .modern: .modern
        case .legacy, .handshake: .legacy
        }
    }

    var revision: ProtocolRevision? {
        switch self {
        case .modern(let revision, _), .legacy(let revision): revision
        case .handshake: nil
        }
    }

    struct Failure: Error {
        let error: ProtocolError
        /// The era the status is chosen for; `nil` when no era could be determined.
        let era: ProtocolRevision.Era?
    }

    static let versionKey = "io.modelcontextprotocol/protocolVersion"
    static let capabilitiesKey = "io.modelcontextprotocol/clientCapabilities"

    static func select(
        method: String, params: JSONValue?, transport: InboundMessage.Transport
    ) async -> Result<RevisionSelection, Failure> {
        let meta = params?["_meta"]
        if let version = meta?[versionKey] {
            return modern(method: method, params: params, version: version, capabilities: meta?[capabilitiesKey], transport: transport)
        }
        if method == "initialize" { return .success(.handshake) }

        switch transport {
        case .stream(let session):
            if let negotiated = await session.negotiated { return .success(.legacy(negotiated)) }
            // Legacy clients may ping before initialize (*2025-11-25 basic/lifecycle*).
            if method == "ping" { return .success(.handshake) }
            return .failure(Failure(error: .invalidParams(
                "This request needs either 2026-07-28 `_meta` (protocolVersion and clientCapabilities) or a prior `initialize` on this stream."
            ), era: nil))
        case .http(let headers):
            guard let header = headers["MCP-Protocol-Version"] else {
                // 2025-03-26 did not define the header (*2026-07-28 basic/transports/streamable-http*).
                return .success(.legacy(.v2025_03_26))
            }
            guard let revision = ProtocolRevision(rawValue: header) else {
                return .failure(Failure(error: unsupported(header, supported: ProtocolRevision.allCases), era: .modern))
            }
            guard revision.era == .legacy else {
                return .failure(Failure(error: .invalidParams(
                    "A \(revision.rawValue) request must carry `\(versionKey)` and `\(capabilitiesKey)` in params._meta."
                ), era: .modern))
            }
            return .success(.legacy(revision))
        }
    }

    /// Notifications are never answered, and 2026-07-28 notifications carry no revision, so they
    /// are routed in the era the transport indicates without failing.
    static func notificationSelection(transport: InboundMessage.Transport) async -> RevisionSelection {
        switch transport {
        case .stream(let session):
            if let negotiated = await session.negotiated { return .legacy(negotiated) }
            return .handshake
        case .http(let headers):
            return .legacy(headers["MCP-Protocol-Version"].flatMap(ProtocolRevision.init(rawValue:)) ?? .v2025_03_26)
        }
    }

    private static func modern(
        method: String, params: JSONValue?, version: JSONValue, capabilities: JSONValue?, transport: InboundMessage.Transport
    ) -> Result<RevisionSelection, Failure> {
        guard case .string(let name) = version else {
            return .failure(Failure(error: .invalidParams("`\(versionKey)` must be a string."), era: .modern))
        }
        guard let revision = ProtocolRevision(rawValue: name), revision.era == .modern else {
            // Only modern revisions are listed: a client cannot use a legacy one in `_meta`.
            return .failure(Failure(error: unsupported(name, supported: ProtocolRevision.allCases.filter { $0.era == .modern }), era: .modern))
        }
        if case .http(let headers) = transport {
            if let mismatch = headerMismatch(method: method, params: params, version: name, headers: headers) {
                return .failure(Failure(error: .headerMismatch(mismatch), era: .modern))
            }
        }
        guard let capabilities, case .object = capabilities else {
            return .failure(Failure(error: .invalidParams(
                "A \(name) request must carry `\(capabilitiesKey)` as an object in params._meta; send {} for none."
            ), era: .modern))
        }
        return .success(.modern(revision, clientCapabilities: capabilities))
    }

    /// The 2026-07-28 request headers that mirror the body (SEP-2243). Returns what is wrong, if anything.
    private static func headerMismatch(method: String, params: JSONValue?, version: String, headers: HTTPRequestHeaders) -> String? {
        guard headers["MCP-Protocol-Version"] == version else {
            return "The MCP-Protocol-Version header must equal `\(versionKey)` (`\(version)`)."
        }
        guard let methodHeader = headers["Mcp-Method"].map(decodeHeader), methodHeader == method else {
            return "The Mcp-Method header must equal the JSON-RPC method (`\(method)`)."
        }
        if method == "tools/call", case .string(let name)? = params?["name"] {
            guard let nameHeader = headers["Mcp-Name"].map(decodeHeader), nameHeader == name else {
                return "The Mcp-Name header must equal the tool name (`\(name)`)."
            }
        }
        return nil
    }

    /// Header values that are not plain ASCII are sent as `=?base64?<value>?=`.
    static func decodeHeader(_ value: String) -> String? {
        guard value.hasPrefix("=?base64?"), value.hasSuffix("?="), value.count >= 11 else { return value }
        let encoded = value.dropFirst("=?base64?".count).dropLast(2)
        return Data(base64Encoded: String(encoded)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func unsupported(_ requested: String, supported: [ProtocolRevision]) -> ProtocolError {
        let names = supported.map(\.rawValue)
        return ProtocolError(
            code: ProtocolError.unsupportedProtocolVersionCode,
            message: "Protocol revision `\(requested)` is not supported. Supported: \(names.joined(separator: ", "))."
                + (supported.contains { $0.era == .legacy } ? "" : " Older revisions use `initialize`."),
            data: ["supported": .array(names.map { .string($0) }), "requested": .string(requested)]
        )
    }
}
