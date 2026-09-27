@testable import MCPHostCore
import Foundation
import Testing

/// The request pipeline: envelope parsing, revision selection, dispatch and HTTP status.
/// See docs/requirements.md#selecting-the-revision and #protocol-errors.
@Suite struct PipelineTests {
    static let codex = CallerIdentity("codex")!
    static let description = ServerDescription(
        name: "example", title: "Example", version: "1.0.0",
        instructions: "Synthetic server for pipeline tests.", description: "Pipeline fixture.", websiteURL: "https://example.test"
    )

    /// An echo method in both eras, so dispatch and result decoration can be observed.
    static let methods: MethodTable = {
        var table = MethodTable.standard
        table.requests["test/echo"] = .init(eras: [.legacy, .modern]) { context, params in
            .success(["revision": .string(context.selection.revision?.rawValue ?? "handshake"), "params": params ?? .null])
        }
        table.requests["test/fail"] = .init(eras: [.legacy, .modern]) { _, _ in
            .failure(.internalFailure(publicMessage: "The server failed; this is not caused by the arguments.", tool: nil, detail: "disk on fire"))
        }
        return table
    }()

    let recorder = EventRecorder()
    var server: MCPServer {
        MCPServer(description: Self.description, tools: try! ToolRegistry([]), identities: [Self.codex], events: recorder.record, methods: Self.methods)
    }

    struct Reply {
        let status: Int
        let json: JSONValue?
    }

    func http(_ body: String, headers: [(String, String)] = [], caller: CallerIdentity = codex) async throws -> Reply {
        let response = await server.handle(InboundMessage(
            body: Array(body.utf8), caller: caller,
            transport: .http(HTTPRequestHeaders(headers.map { (name: $0.0, value: $0.1) }))
        ))
        return Reply(status: response.httpStatus, json: try response.body.map { try JSONValue.parse(Data($0)) })
    }

    func stream(_ body: String, session: StreamSession) async throws -> Reply {
        let response = await server.handle(InboundMessage(body: Array(body.utf8), caller: Self.codex, transport: .stream(session)))
        return Reply(status: response.httpStatus, json: try response.body.map { try JSONValue.parse(Data($0)) })
    }

    static func modern(_ method: String, id: Int = 1, version: String = "2026-07-28", capabilities: String = "{}") -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"\#(version)","io.modelcontextprotocol/clientCapabilities":\#(capabilities)}}}"#
    }

    static func legacy(_ method: String, id: Int = 1) -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)"}"#
    }

    func code(_ reply: Reply) -> JSONValue? { reply.json?["error"]?["code"] }

    // MARK: Envelope

    @Test(arguments: ["", "{", "not json"])
    func unparseableBodyIsParseError(_ body: String) async throws {
        let reply = try await http(body)
        #expect(reply.status == 400)
        #expect(code(reply) == -32700)
        #expect(reply.json?["id"] == nil, "an error for an unparsed message carries no id")
    }

    @Test(arguments: [#"[]"#, #"{"id":1,"method":"x"}"#, #"{"jsonrpc":"2.0","id":1}"#, #"{"jsonrpc":"2.0","id":null,"method":"x"}"#, #"{"jsonrpc":"2.0","id":1.5,"method":"x"}"#, #"{"jsonrpc":"2.0","id":1,"result":{}}"#, #"{"jsonrpc":"2.0","id":1,"method":"x","params":[1]}"#])
    func malformedMessageIsInvalidRequest(_ body: String) async throws {
        let reply = try await http(body)
        #expect(reply.status == 400)
        #expect(code(reply) == -32600)
    }

    @Test func batchIsRejectedUntil2025_03_26BatchSupportLands() async throws {
        let reply = try await http("[\(Self.legacy("ping"))]", headers: [("MCP-Protocol-Version", "2025-06-18")])
        #expect(reply.status == 400)
        #expect(code(reply) == -32600)
    }

    // MARK: Caller identity

    @Test func unknownCallerIs404WithoutID() async throws {
        let reply = try await http(Self.modern("test/echo"), headers: [("MCP-Protocol-Version", "2026-07-28")], caller: CallerIdentity("muse")!)
        #expect(reply.status == 404)
        #expect(code(reply) == -32600)
        #expect(reply.json?["id"] == nil)
        #expect(recorder.events.contains { if case .rejected(_, _, 404) = $0 { true } else { false } })
    }

    // MARK: Modern selection

    @Test func modernRequestIsServedAndDecorated() async throws {
        let reply = try await http(Self.modern("test/echo"), headers: [("mcp-protocol-version", "2026-07-28")])
        #expect(reply.status == 200)
        let result = reply.json?["result"]
        #expect(result?["revision"] == "2026-07-28")
        #expect(result?["resultType"] == "complete")
        #expect(result?["_meta"]?["io.modelcontextprotocol/serverInfo"] == [
            "name": "example", "title": "Example", "version": "1.0.0", "description": "Pipeline fixture.", "websiteUrl": "https://example.test",
        ])
    }

    @Test func modernRequestOverStreamNeedsNoHandshake() async throws {
        let reply = try await stream(Self.modern("test/echo"), session: StreamSession())
        #expect(reply.json?["result"]?["revision"] == "2026-07-28")
    }

    @Test(arguments: ["2025-11-25", "2024-11-05", "2027-01-01"])
    func unsupportedModernVersionListsSupported(_ version: String) async throws {
        let reply = try await http(Self.modern("test/echo", version: version), headers: [("MCP-Protocol-Version", version)])
        #expect(reply.status == 400)
        #expect(code(reply) == -32022)
        #expect(reply.json?["error"]?["data"]?["supported"] == ["2026-07-28"])
    }

    @Test(arguments: [nil, "2025-11-25"] as [String?])
    func modernHeaderMustMatchMeta(_ header: String?) async throws {
        let reply = try await http(Self.modern("test/echo"), headers: header.map { [("MCP-Protocol-Version", $0)] } ?? [])
        #expect(reply.status == 400)
        #expect(code(reply) == -32020)
    }

    @Test(arguments: [nil, "[]", "\"none\""] as [String?])
    func modernRequestNeedsCapabilitiesObject(_ capabilities: String?) async throws {
        let body = capabilities.map { Self.modern("test/echo", capabilities: $0) }
            ?? #"{"jsonrpc":"2.0","id":1,"method":"test/echo","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#
        let reply = try await http(body, headers: [("MCP-Protocol-Version", "2026-07-28")])
        #expect(reply.status == 400)
        #expect(code(reply) == -32602)
    }

    @Test func modernUnknownMethodIs404() async throws {
        let reply = try await http(Self.modern("nope"), headers: [("MCP-Protocol-Version", "2026-07-28")])
        #expect(reply.status == 404)
        #expect(code(reply) == -32601)
        #expect(reply.json?["id"] == 1)
    }

    @Test func pingDoesNotExistInTheModernEra() async throws {
        let reply = try await http(Self.modern("ping"), headers: [("MCP-Protocol-Version", "2026-07-28")])
        #expect(reply.status == 404)
        #expect(code(reply) == -32601)
    }

    // MARK: Legacy selection over HTTP

    @Test(arguments: ["2025-06-18", "2025-11-25"])
    func legacyHeaderSelectsThatRevision(_ version: String) async throws {
        let reply = try await http(Self.legacy("test/echo"), headers: [("MCP-Protocol-Version", version)])
        #expect(reply.status == 200)
        #expect(reply.json?["result"]?["revision"] == .string(version))
        #expect(reply.json?["result"]?["resultType"] == nil, "legacy results are not decorated")
    }

    @Test func missingHeaderMeans2025_03_26() async throws {
        let reply = try await http(Self.legacy("test/echo"))
        #expect(reply.json?["result"]?["revision"] == "2025-03-26")
    }

    @Test func unknownLegacyHeaderIsRejected() async throws {
        let reply = try await http(Self.legacy("test/echo"), headers: [("MCP-Protocol-Version", "2024-11-05")])
        #expect(reply.status == 400)
        #expect(code(reply) == -32600)
    }

    @Test func modernHeaderWithoutMetaIsInvalidParams() async throws {
        let reply = try await http(Self.legacy("test/echo"), headers: [("MCP-Protocol-Version", "2026-07-28")])
        #expect(reply.status == 400)
        #expect(code(reply) == -32602)
    }

    @Test func legacyErrorsAre200AndPingWorks() async throws {
        let unknown = try await http(Self.legacy("nope"), headers: [("MCP-Protocol-Version", "2025-11-25")])
        #expect(unknown.status == 200)
        #expect(code(unknown) == -32601)
        let ping = try await http(Self.legacy("ping"), headers: [("MCP-Protocol-Version", "2025-11-25")])
        #expect(ping.json?["result"] == [:])
    }

    @Test func initializeWithoutHeaderIsAHandshake() async throws {
        let reply = try await http(Self.legacy("test/echo").replacingOccurrences(of: "test/echo", with: "initialize"))
        // `initialize` is not registered yet; reaching dispatch in the legacy era proves selection.
        #expect(reply.status == 200)
        #expect(code(reply) == -32601)
    }

    // MARK: Legacy selection over a stream

    @Test func streamRequestBeforeInitializeIsRejected() async throws {
        let reply = try await stream(Self.legacy("test/echo"), session: StreamSession())
        #expect(code(reply) == -32602)
    }

    @Test func streamUsesTheNegotiatedRevision() async throws {
        let session = StreamSession()
        #expect(await session.negotiate(.v2025_06_18))
        #expect(await !session.negotiate(.v2025_11_25), "negotiation happens once per stream")
        let reply = try await stream(Self.legacy("test/echo"), session: session)
        #expect(reply.json?["result"]?["revision"] == "2025-06-18")
    }

    // MARK: Notifications and failures

    @Test func notificationsAreAccepted() async throws {
        let reply = try await http(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, headers: [("MCP-Protocol-Version", "2025-11-25")])
        #expect(reply.status == 202)
        #expect(reply.json == nil)
        let invalid = try await http(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, headers: [("MCP-Protocol-Version", "1999-01-01")])
        #expect(invalid.status == 202, "a notification gets no error response")
    }

    @Test func internalFailureWithholdsDetailFromTheClient() async throws {
        let reply = try await http(Self.modern("test/fail"), headers: [("MCP-Protocol-Version", "2026-07-28")])
        #expect(reply.status == 500)
        #expect(code(reply) == -32603)
        #expect(try !(reply.json?.serialized() ?? "").contains("disk on fire"))
        #expect(recorder.events.contains { if case .internalFailure(_, "test/fail", nil, "disk on fire") = $0 { true } else { false } })
    }
}

final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ServerEvent] = []

    var events: [ServerEvent] { lock.withLock { recorded } }

    @Sendable func record(_ event: ServerEvent) {
        lock.withLock { recorded.append(event) }
    }
}
