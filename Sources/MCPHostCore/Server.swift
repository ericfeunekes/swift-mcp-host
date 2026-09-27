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

/// The state a stream keeps: the revision `initialize` negotiated, for the life of the stream,
/// and the requests still running, so `notifications/cancelled` can stop one.
/// See docs/requirements.md#selecting-the-revision and #newline-delimited-stream.
public actor StreamSession {
    public private(set) var negotiated: ProtocolRevision?
    private var running: [RequestID: @Sendable () -> Void] = [:]

    public init() {}

    func negotiate(_ revision: ProtocolRevision) -> Bool {
        guard negotiated == nil else { return false }
        negotiated = revision
        return true
    }

    func track(_ id: RequestID, cancel: @escaping @Sendable () -> Void) {
        running[id] = cancel
    }

    func finish(_ id: RequestID) {
        running[id] = nil
    }

    /// Cancels a running request. Unknown or finished ids are ignored, as the spec allows.
    func cancel(_ id: RequestID) {
        running.removeValue(forKey: id)?()
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
            let error = ProtocolError.invalidRequest(
                "The caller identity `\(message.caller)` is not configured for this server. Use a client URL or launch argument with an identity this server accepts."
            )
            events(.rejected(caller: message.caller, reason: error.message, httpStatus: 404))
            return encode(JSONRPC.response(id: nil, error: error), status: 404)
        }
        switch JSONRPC.parse(message.body) {
        case .failure(let error):
            return encode(reject(message, Reply.error(error, id: nil, era: nil)))
        case .success(.single(.failure(let error))):
            return encode(reject(message, Reply.error(error, id: nil, era: nil)))
        case .success(.single(.success(let clientMessage))):
            return encode(await reply(to: clientMessage, from: message))
        case .success(.batch):
            // Batches are part of 2025-03-26 only; see docs/requirements.md#legacy-requests.
            // Each item is parsed separately so a batch can be answered item by item.
            return encode(reject(message, Reply.error(.invalidRequest(
                "JSON-RPC batches are not supported. Send one message per request."
            ), id: nil, era: nil)))
        }
    }

    /// The answer to one message: a JSON-RPC response, or none for a notification.
    struct Reply {
        let json: JSONValue?
        let httpStatus: Int
        let rejection: String?

        static let accepted = Reply(json: nil, httpStatus: 202, rejection: nil)

        static func error(_ error: ProtocolError, id: RequestID?, era: ProtocolRevision.Era?) -> Reply {
            Reply(json: JSONRPC.response(id: id, error: error), httpStatus: HTTPStatus.for(error.code, era: era), rejection: error.message)
        }
    }

    func reply(to clientMessage: ClientMessage, from message: InboundMessage) async -> Reply {
        switch clientMessage {
        case .notification(let method, let params):
            // Notifications are never answered; they are routed in whatever era the stream or
            // header indicates (2026-07-28 notifications carry no protocol version).
            let selection = await RevisionSelection.notificationSelection(transport: message.transport)
            let context = RequestContext(server: self, caller: message.caller, selection: selection, transport: message.transport)
            if let notification = methods.notifications[method] { await notification(context, params) }
            return .accepted
        case .request(let id, let method, let params):
            let selection: RevisionSelection
            switch await RevisionSelection.select(method: method, params: params, transport: message.transport) {
            case .success(let selected): selection = selected
            case .failure(let failure): return reject(message, .error(failure.error, id: id, era: failure.era))
            }
            let context = RequestContext(server: self, caller: message.caller, selection: selection, transport: message.transport)
            guard let entry = methods.requests[method], entry.eras.contains(selection.era) else {
                return .error(.methodNotFound(method), id: id, era: selection.era)
            }
            switch await run(entry, context: context, params: params, id: id) {
            case .success(let result):
                return Reply(json: JSONRPC.response(id: id, result: decorate(result, selection: selection)), httpStatus: 200, rejection: nil)
            case .failure(.protocolError(let error)):
                return .error(error, id: id, era: selection.era)
            case .failure(.internalFailure(let publicMessage, let tool, let detail)):
                events(.internalFailure(caller: message.caller, method: method, tool: tool, detail: detail))
                return .error(.internalError(publicMessage), id: id, era: selection.era)
            }
        }
    }

    /// Runs a handler. On a stream the request is tracked so `notifications/cancelled` can stop it;
    /// over HTTP the adapter cancels the calling task when the client disconnects.
    private func run(
        _ entry: MethodTable.Entry, context: RequestContext, params: JSONValue?, id: RequestID
    ) async -> Result<JSONValue, MethodFailure> {
        guard case .stream(let session) = context.transport else { return await entry.handler(context, params) }
        let task = Task { await entry.handler(context, params) }
        await session.track(id, cancel: { task.cancel() })
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        await session.finish(id)
        return result
    }

    private func decorate(_ result: JSONValue, selection: RevisionSelection) -> JSONValue {
        guard case .modern(let revision, _) = selection, case .object(var object) = result else { return result }
        object["resultType"] = "complete"
        var meta: OrderedDictionary<String, JSONValue> = [:]
        if case .object(let existing)? = object["_meta"] { meta = existing }
        meta["io.modelcontextprotocol/serverInfo"] = serverInfo(for: revision)
        object["_meta"] = .object(meta)
        return .object(object)
    }

    private func reject(_ message: InboundMessage, _ reply: Reply) -> Reply {
        if let reason = reply.rejection {
            events(.rejected(caller: message.caller, reason: reason, httpStatus: reply.httpStatus))
        }
        return reply
    }

    private func encode(_ reply: Reply) -> OutboundResponse {
        guard let json = reply.json else { return .accepted }
        return encode(json, status: reply.httpStatus)
    }

    private func encode(_ value: JSONValue, status: Int) -> OutboundResponse {
        // Serializing a value built from parsed JSON and literals cannot fail.
        OutboundResponse(body: Array(try! value.serializedData()), httpStatus: status)
    }

    /// `Implementation` for a revision: `title` from 2025-06-18, `description` and `websiteUrl` from 2025-11-25.
    func serverInfo(for revision: ProtocolRevision) -> JSONValue {
        var info: OrderedDictionary<String, JSONValue> = ["name": .string(description.name)]
        if revision >= .v2025_06_18 { info["title"] = .string(description.title) }
        info["version"] = .string(description.version)
        if revision >= .v2025_11_25 {
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
    static let standard = MethodTable(
        requests: [
            // `ping` exists before 2026-07-28 only (*2026-07-28 changelog*, SEP-2575).
            "ping": Entry(eras: [.legacy]) { _, _ in .success([:]) },
        ],
        notifications: [
            // Only streams can cancel: over HTTP a request id is ambiguous without sessions,
            // and closing the connection is the signal (*2026-07-28 basic/patterns/cancellation*).
            "notifications/cancelled": { context, params in
                guard case .stream(let session) = context.transport, let id = params?["requestId"].flatMap(RequestID.init) else { return }
                await session.cancel(id)
            },
        ]
    )
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
