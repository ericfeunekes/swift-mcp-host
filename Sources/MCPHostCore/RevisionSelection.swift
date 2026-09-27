/// How a request's protocol revision was chosen. See docs/requirements.md#selecting-the-revision.
enum RevisionSelection: Sendable, Equatable {
    /// A 2026-07-28 request carrying its revision and client capabilities in `_meta`.
    case modern(ProtocolRevision, clientCapabilities: JSONValue)
    /// A request served under a legacy revision, from the stream's negotiation or the HTTP header.
    case legacy(ProtocolRevision)
    /// An `initialize` request: the handshake chooses the legacy revision.
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
        let era: ProtocolRevision.Era?
        let httpStatus: Int
    }

    static let versionKey = "io.modelcontextprotocol/protocolVersion"
    static let capabilitiesKey = "io.modelcontextprotocol/clientCapabilities"

    static func select(
        method: String, params: JSONValue?, transport: InboundMessage.Transport
    ) async -> Result<RevisionSelection, Failure> {
        let meta = params?["_meta"]
        if let version = meta?[versionKey] {
            return modern(version: version, capabilities: meta?[capabilitiesKey], transport: transport)
        }
        if method == "initialize" { return .success(.handshake) }

        switch transport {
        case .stream(let session):
            guard let negotiated = await session.negotiated else {
                return .failure(Failure(error: .invalidParams(
                    "This request needs either 2026-07-28 `_meta` (protocolVersion and clientCapabilities) or a prior `initialize` on this stream."
                ), era: nil, httpStatus: 400))
            }
            return .success(.legacy(negotiated))
        case .http(let headers):
            guard let header = headers["MCP-Protocol-Version"] else {
                // 2025-03-26 did not define the header (*2026-07-28 basic/transports/streamable-http*).
                return .success(.legacy(.v2025_03_26))
            }
            guard let revision = ProtocolRevision(rawValue: header) else {
                return .failure(Failure(error: .invalidRequest(
                    "MCP-Protocol-Version `\(header)` is not supported. Supported revisions: \(supportedList)."
                ), era: .legacy, httpStatus: 400))
            }
            guard revision.era == .legacy else {
                return .failure(Failure(error: .invalidParams(
                    "A \(revision.rawValue) request must carry `\(versionKey)` and `\(capabilitiesKey)` in params._meta."
                ), era: .modern, httpStatus: 400))
            }
            return .success(.legacy(revision))
        }
    }

    private static func modern(
        version: JSONValue, capabilities: JSONValue?, transport: InboundMessage.Transport
    ) -> Result<RevisionSelection, Failure> {
        guard case .string(let name) = version else {
            return .failure(Failure(error: .invalidParams("`\(versionKey)` must be a string."), era: .modern, httpStatus: 400))
        }
        guard let revision = ProtocolRevision(rawValue: name), revision.era == .modern else {
            let supported: JSONValue = .array(ProtocolRevision.allCases.filter { $0.era == .modern }.map { .string($0.rawValue) })
            return .failure(Failure(error: ProtocolError(
                code: ProtocolError.unsupportedProtocolVersionCode,
                message: "Protocol revision `\(name)` is not supported in per-request metadata. Supported: \(modernList); older revisions use `initialize`.",
                data: ["supported": supported, "requested": .string(name)]
            ), era: .modern, httpStatus: 400))
        }
        if case .http(let headers) = transport, headers["MCP-Protocol-Version"] != name {
            return .failure(Failure(error: .headerMismatch(
                "The MCP-Protocol-Version header must equal `\(versionKey)` (`\(name)`)."
            ), era: .modern, httpStatus: 400))
        }
        guard let capabilities, case .object = capabilities else {
            return .failure(Failure(error: .invalidParams(
                "A \(name) request must carry `\(capabilitiesKey)` as an object in params._meta; send {} for none."
            ), era: .modern, httpStatus: 400))
        }
        return .success(.modern(revision, clientCapabilities: capabilities))
    }

    private static var supportedList: String {
        ProtocolRevision.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private static var modernList: String {
        ProtocolRevision.allCases.filter { $0.era == .modern }.map(\.rawValue).joined(separator: ", ")
    }
}
