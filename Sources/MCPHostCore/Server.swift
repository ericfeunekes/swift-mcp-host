import OrderedCollections

/// What the server tells clients about itself. See docs/requirements.md#server-description.
public struct ServerDescription: Sendable {
    public var name: String
    public var title: String
    public var version: String
    /// How the tools fit together and when to use which. Do not repeat tool descriptions.
    public var instructions: String
    public var description: String?
    public var websiteURL: String?
    /// How long clients may cache `tools/list` and `server/discover` results under 2026-07-28.
    public var listTTLMilliseconds: Int

    public init(
        name: String, title: String, version: String, instructions: String,
        description: String? = nil, websiteURL: String? = nil, listTTLMilliseconds: Int = 300_000
    ) {
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
        self.description = description
        self.websiteURL = websiteURL
        self.listTTLMilliseconds = listTTLMilliseconds
    }
}

/// HTTP request headers as the adapter received them. Names match case-insensitively.
public struct HTTPRequestHeaders: Sendable {
    private let fields: [(name: String, value: String)]

    public init(_ fields: [(name: String, value: String)]) {
        self.fields = fields
    }

    public subscript(name: String) -> String? {
        let wanted = name.lowercased()
        return fields.first { $0.name.lowercased() == wanted }?.value
    }
}

/// The state a stream keeps: the revision `initialize` negotiated, for the life of the stream.
/// See docs/requirements.md#selecting-the-revision.
public actor StreamSession {
    public private(set) var negotiated: ProtocolRevision?

    public init() {}

    func negotiate(_ revision: ProtocolRevision) -> Bool {
        guard negotiated == nil else { return false }
        negotiated = revision
        return true
    }
}

/// One message from a client, with what the adapter knows about how it arrived.
public struct InboundMessage: Sendable {
    public enum Transport: Sendable {
        case http(HTTPRequestHeaders)
        case stream(StreamSession)
    }

    public let body: [UInt8]
    /// Resolved by the adapter from configuration. See docs/requirements.md#caller-identity.
    public let caller: CallerIdentity
    public let transport: Transport

    public init(body: [UInt8], caller: CallerIdentity, transport: Transport) {
        self.body = body
        self.caller = caller
        self.transport = transport
    }
}

/// What the adapter sends back. A `nil` body means nothing is written: `202 Accepted` over
/// HTTP, no line on a stream. `httpStatus` is ignored by stream adapters.
public struct OutboundResponse: Sendable, Equatable {
    public let body: [UInt8]?
    public let httpStatus: Int

    static let accepted = OutboundResponse(body: nil, httpStatus: 202)
}

/// Facts the host may log. Events never carry argument values or results.
/// See docs/requirements.md#server-events.
public enum ServerEvent: Sendable {
    case toolCall(caller: CallerIdentity, tool: String, outcome: String, duration: Duration)
    case internalFailure(caller: CallerIdentity, method: String, tool: String?, detail: String)
    case rejected(caller: CallerIdentity, reason: String, httpStatus: Int)
}

/// A tools-only MCP server. Adapters pass each inbound message to ``handle(_:)``.
public struct MCPServer: Sendable {
    public let description: ServerDescription
    public let tools: ToolRegistry
    public let identities: Set<CallerIdentity>
    let events: @Sendable (ServerEvent) -> Void
    let methods: MethodTable

    public init(
        description: ServerDescription,
        tools: ToolRegistry,
        identities: Set<CallerIdentity>,
        events: @escaping @Sendable (ServerEvent) -> Void = { _ in }
    ) {
        self.init(description: description, tools: tools, identities: identities, events: events, methods: .standard)
    }

    /// The seam capabilities and extensions use to add methods. See docs/architecture.md#extension-points.
    init(
        description: ServerDescription, tools: ToolRegistry, identities: Set<CallerIdentity>,
        events: @escaping @Sendable (ServerEvent) -> Void, methods: MethodTable
    ) {
        self.description = description
        self.tools = tools
        self.identities = identities
        self.events = events
        self.methods = methods
    }

    public func accepts(_ caller: CallerIdentity) -> Bool {
        identities.contains(caller)
    }

    public func handle(_ message: InboundMessage) async -> OutboundResponse {
        guard accepts(message.caller) else {
            return reject(message, era: nil, error: .invalidRequest(
                "The caller identity `\(message.caller)` is not configured for this server. Use a client URL or launch argument with an identity this server accepts."
            ), status: 404, id: nil)
        }
        let body: ClientBody
        switch JSONRPC.parse(message.body) {
        case .success(let parsed): body = parsed
        case .failure(let error): return reject(message, era: nil, error: error, status: 400, id: nil)
        }
        switch body {
        case .batch:
            // Batches are part of 2025-03-26 only; see docs/requirements.md#legacy-requests.
            return reject(message, era: nil, error: .invalidRequest(
                "JSON-RPC batches are not supported. Send one message per request."
            ), status: 400, id: nil)
        case .single(let clientMessage):
            return await handle(clientMessage, from: message)
        }
    }

    private func handle(_ clientMessage: ClientMessage, from message: InboundMessage) async -> OutboundResponse {
        let id: RequestID?
        let method: String
        let params: JSONValue?
        switch clientMessage {
        case .request(let requestID, let name, let parameters): (id, method, params) = (requestID, name, parameters)
        case .notification(let name, let parameters): (id, method, params) = (nil, name, parameters)
        }

        let selection: RevisionSelection
        switch await RevisionSelection.select(method: method, params: params, transport: message.transport) {
        case .success(let selected): selection = selected
        case .failure(let failure):
            guard id != nil else { return .accepted }
            return reject(message, era: failure.era, error: failure.error, status: failure.httpStatus, id: id)
        }

        let context = RequestContext(server: self, caller: message.caller, selection: selection, transport: message.transport)
        guard let id else {
            if let notification = methods.notifications[method] { await notification(context, params) }
            return .accepted
        }
        guard let entry = methods.requests[method], entry.eras.contains(selection.era) else {
            return respond(error: .methodNotFound(method), id: id, era: selection.era)
        }
        switch await entry.handler(context, params) {
        case .success(let result):
            return respond(result: result, id: id, selection: selection)
        case .failure(.protocolError(let error)):
            return respond(error: error, id: id, era: selection.era)
        case .failure(.internalFailure(let publicMessage, let tool, let detail)):
            events(.internalFailure(caller: message.caller, method: method, tool: tool, detail: detail))
            return respond(error: .internalError(publicMessage), id: id, era: selection.era)
        }
    }

    private func respond(result: JSONValue, id: RequestID, selection: RevisionSelection) -> OutboundResponse {
        var result = result
        if selection.era == .modern, case .object(var object) = result {
            object["resultType"] = "complete"
            var meta: OrderedDictionary<String, JSONValue> = [:]
            if case .object(let existing)? = object["_meta"] { meta = existing }
            meta["io.modelcontextprotocol/serverInfo"] = serverInfo(for: selection.revision)
            object["_meta"] = .object(meta)
            result = .object(object)
        }
        return encode(JSONRPC.response(id: id, result: result), status: 200)
    }

    private func respond(error: ProtocolError, id: RequestID?, era: ProtocolRevision.Era?) -> OutboundResponse {
        encode(JSONRPC.response(id: id, error: error), status: HTTPStatus.for(error.code, era: era))
    }

    private func reject(
        _ message: InboundMessage, era: ProtocolRevision.Era?, error: ProtocolError, status: Int, id: RequestID?
    ) -> OutboundResponse {
        events(.rejected(caller: message.caller, reason: error.message, httpStatus: status))
        return encode(JSONRPC.response(id: id, error: error), status: status)
    }

    private func encode(_ value: JSONValue, status: Int) -> OutboundResponse {
        // Serializing a value built from parsed JSON and literals cannot fail.
        OutboundResponse(body: Array(try! value.serializedData()), httpStatus: status)
    }

    /// `Implementation` for the given revision; fields added in 2025-11-25 are omitted before it.
    func serverInfo(for revision: ProtocolRevision?) -> JSONValue {
        var info: OrderedDictionary<String, JSONValue> = ["name": .string(description.name)]
        if revision.map({ $0 >= .v2025_06_18 }) ?? true { info["title"] = .string(description.title) }
        info["version"] = .string(description.version)
        if revision.map({ $0 >= .v2025_11_25 }) ?? true {
            if let text = description.description { info["description"] = .string(text) }
            if let url = description.websiteURL { info["websiteUrl"] = .string(url) }
        }
        return .object(info)
    }
}

/// What a method handler knows about the request.
struct RequestContext: Sendable {
    let server: MCPServer
    let caller: CallerIdentity
    let selection: RevisionSelection
    let transport: InboundMessage.Transport
}

enum MethodFailure: Error, Sendable {
    case protocolError(ProtocolError)
    /// `publicMessage` goes to the client; `detail` only to the host's event handler.
    case internalFailure(publicMessage: String, tool: String?, detail: String)
}

/// The methods the server answers, by name. Each method lists the eras it exists in.
struct MethodTable: Sendable {
    struct Entry: Sendable {
        let eras: Set<ProtocolRevision.Era>
        let handler: @Sendable (RequestContext, JSONValue?) async -> Result<JSONValue, MethodFailure>
    }

    var requests: [String: Entry] = [:]
    var notifications: [String: @Sendable (RequestContext, JSONValue?) async -> Void] = [:]

    /// The standard tools-only server. Lifecycle and tool methods are added here as they land.
    static let standard = MethodTable(requests: [
        // `ping` exists before 2026-07-28 only (*2026-07-28 changelog*, SEP-2575).
        "ping": Entry(eras: [.legacy]) { _, _ in .success([:]) },
    ])
}

enum HTTPStatus {
    /// Status for a JSON-RPC error on Streamable HTTP. See docs/requirements.md#protocol-errors.
    static func `for`(_ code: Int, era: ProtocolRevision.Era?) -> Int {
        switch (code, era) {
        case (ProtocolError.internalErrorCode, _): 500
        case (ProtocolError.parseErrorCode, _), (ProtocolError.invalidRequestCode, _): 400
        case (_, .legacy?): 200
        case (ProtocolError.methodNotFoundCode, _): 404
        default: 400
        }
    }
}
