# Architecture

The library separates what every MCP server must get right (the protocol contract and agent-facing defaults) from what each utility owns (its tools and its process). It is a library, not a host application: it does not own permissions, lifetime, supervision or deployment.

## Targets

| Target | Owns | Depends on |
|---|---|---|
| `MCPHostCore` | Protocol value types, JSON-RPC handling, version negotiation, the request pipeline, tool registry, validation, error rendering, caller identity | swift-json-schema |
| `MCPHostMacrosPlugin` | The `@MCPTool`, `@MCPSchema` and `@MCPEnum` macros and their compile-time checks; declared in `MCPHostCore` | swift-syntax |
| `MCPHostHTTP` | Streamable HTTP on loopback or a Unix socket: origin, host, header and body-size checks, cancellation on disconnect | `MCPHostCore`, Hummingbird |
| `MCPHostStream` | Newline-delimited streams over stdio or file handles | `MCPHostCore` |
| `MCPHostTesting` | Validation against the official MCP schemas today; a synthetic example server and a test client later | `MCPHostCore`, swift-json-schema |
| `MCPHostExample` (planned) | An executable example server with the conformance suite's fixture tools, used by conformance and interoperability runs | `MCPHostCore`, both adapters |

A consumer depends on `MCPHostCore` plus the adapters it uses. `MCPHostCore` has no transport or web-framework dependency.

## Request pipeline

Adapters own transport; the core owns everything a message means. The boundary between them is one call:

```swift
let server = MCPServer(description: ..., tools: try ToolRegistry([...]), identities: [...], events: { event in ... })
let response: OutboundResponse = await server.handle(InboundMessage(body: bytes, caller: identity, transport: .http(headers)))
```

| Type | Role |
|---|---|
| `InboundMessage` | The raw body, the caller identity the adapter resolved, and the transport: `.http(HTTPRequestHeaders)` or `.stream(StreamSession)` |
| `HTTPRequestHeaders` | Request headers with case-insensitive lookup |
| `StreamSession` | Per-stream state: the revision `initialize` negotiated and the requests still running, so `notifications/cancelled` can stop one. One per stream; HTTP has none |
| `OutboundResponse` | A body to write (or `nil` for nothing: `202` over HTTP, no line on a stream) and the HTTP status |
| `ServerEvent` | Tool calls, internal failures and rejections, for the host to log |

Inside `handle`, every message passes through the same stages in order:

1. **Identity.** An identity the server does not accept is `404` with `-32600`.
2. **Envelope.** Parse JSON-RPC (`JSONRPC.parse`). Each batch item is parsed on its own so a batch can be answered item by item; batches are rejected until 2025-03-26 batch support lands. Malformed messages are rejected.
3. **Revision.** `RevisionSelection.select` applies the table in [requirements](requirements.md#selecting-the-revision), including the modern `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` checks. The result is `.modern(revision, clientCapabilities:)`, `.legacy(revision)` or `.handshake` (for `initialize`, and for `ping` before `initialize` on a stream). Notifications use `notificationSelection` and never fail.
4. **Dispatch.** `MethodTable` maps a method name to a handler and the eras the method exists in. A method missing from the table or from the era is `-32601`. Notifications run their handler if one is registered and always get `202`. On a stream, each request is tracked in its `StreamSession` while it runs, and the standard `notifications/cancelled` handler cancels it by id.
5. **Handle.** A handler receives a `RequestContext` (server, caller, selection, transport) and the params, and returns a result or a `MethodFailure`: a protocol error, or an internal failure whose detail goes only to the event handler.
6. **Encode.** `reply(to:from:)` produces a `Reply` (a JSON value or none, and a status) for one message, so batch support can combine replies. Modern results get `resultType: "complete"` and `io.modelcontextprotocol/serverInfo` in `_meta`. `HTTPStatus.for(code, era:)` is the only mapping from error code to status; the unknown-identity `404` is the one exception.

The standard method table holds `ping` and `notifications/cancelled` today. The lifecycle methods (`initialize`, `notifications/initialized`, `server/discover`) and the tool methods (`tools/list`, `tools/call`) are added to it by their own changes. Rendering that differs by revision (fields added in later revisions, 2025-03-26 omissions) happens in the handler for that method, using the selection's revision; `initialize` has no revision in its selection and must pass the negotiated revision to `serverInfo(for:)`.

The stream adapter must hand each line to `handle` concurrently, so a `notifications/cancelled` line can arrive while the request it names is running.

Tool handlers never see revision differences.

## Protocol types

The library owns a small set of Codable protocol types rather than using the official Swift SDK's. They decode leniently: unknown fields and extension objects anywhere in a client message are preserved as JSON values and never fail decoding. They encode strictly: every outgoing message is checked against the official schema in tests. See [decisions](decisions.md#accepted).

## Typed tools

A tool is a struct. Its stored properties are the arguments, its `///` comment is the tool description, and each property's `///` comment is that argument's description:

```swift
import MCPHostCore

/// Read recent messages from one conversation, newest first. Use after find_chats and
/// pass its chatID; do not pass a person's name.
@Schemable
@MCPTool(title: "Read messages", readOnly: true, destructive: false, idempotent: true, openWorld: false)
struct ReadMessages {
    /// The chat to read, from find_chats.
    let chatID: String
    /// How many messages to return.
    @NumberOptions(.minimum(1), .maximum(100))
    var limit: Int = 25
    /// Reading order.
    @SchemaOptions(.default("newest"))
    var order: Order = .newest

    func call(context: ToolContext) async throws(ReadError) -> MessagePage { ... }
}

@Schemable @MCPEnum
enum Order: String {
    /// Most recent message first.
    case newest
    /// Earliest message first.
    case oldest
}

/// One page of messages.
@Schemable @MCPSchema
struct MessagePage: Encodable { ... }

enum ReadError: ToolError {
    case chatNotFound(String)
    var code: String { "chat_not_found" }
    var message: String { ... }
    var nextStep: String { "Call find_chats and pass one of its chatID values." }
}
```

| Declaration | Needs | Checked |
|---|---|---|
| `@MCPTool` struct | `@Schemable`; a doc comment; a doc comment on every stored property; all four annotations; a title | Compile time (macro diagnostics; the annotation arguments have no defaults) |
| Tool name | Defaults to the struct name in snake_case; `name:` overrides; `^[A-Za-z0-9_-]{1,64}$`; unique | Compile time for the pattern, registration for uniqueness |
| `call` | `throws(E)` with `E: ToolError`, or no `throws` | Compile time: an untyped `throws` cannot satisfy the protocol |
| Nested and output structs | `@Schemable @MCPSchema`, `Encodable` for outputs, doc comments on every property | Compile time for docs; registration for a nested type missing `@MCPSchema` |
| Enums | `@Schemable @MCPEnum`, plain-value cases, a doc comment on every case | Compile time for docs; registration for an enum missing `@MCPEnum` |
| Non-primitive defaults | `@SchemaOptions(.default(...))` with the same value, because swift-json-schema only writes defaults for primitive types | Compile time |
| Description length | At least `ToolRules.minimumDescriptionLength` (40) characters | Registration |
| Key renaming | Not supported: `@Schemable(keyStrategy:)` and `.key(...)` are rejected so property names are field names | Compile time |

`ToolRegistry` prepares each tool once at startup. It takes the generated schema and:

- sets `additionalProperties: false` on every object;
- removes properties that have defaults from `required`;
- appends each enum's case descriptions to the field description;
- rejects keywords outside the portable profile.

It reports every problem in one error. A call is then validated against that prepared schema. So what the agent sees is exactly what is enforced. Every failure is mapped to the argument error shape, defaults are filled in, the arguments are parsed into the struct, and the handler runs. Output is encoded with sorted keys and ISO 8601 dates and checked against the output schema. A mismatch is a server fault, not an agent error.

## Caller identity

Adapters resolve the identity; the core enforces that it is one the server accepts. The identity is a label, not authentication; see [requirements](requirements.md#caller-identity). The stream adapter takes it from its configuration at launch. The HTTP adapter takes it from the path segment in `<base>/c/<identity>/mcp`. The core receives an already-resolved value and never reads it from the message body.

## Extension points

Each is defined as a protocol and exercised by a test-only implementation; none ships an implementation. Seams are internal to the package until an accepted extension needs one to be public ([decisions](decisions.md#accepted)). The "needs" column is work the extension brings with it; the seam alone does not provide it.

| Point | Future uses | Seam: inputs and outputs | Needs |
|---|---|---|---|
| Capability | resources, prompts, completion | Registers method handlers; contributes a capability object merged into `initialize` and `server/discover` results | Nothing beyond the seam for request-response methods |
| Protocol extension | tasks (`io.modelcontextprotocol/tasks`), MCP Apps | Contributes an entry to `capabilities.extensions` (SEP-2133), may register methods and add fields to tool definitions and results | Tasks need durable handle storage owned by the consumer |
| Content block | new result content types | Encodes a block for the negotiated revision, or omits it for revisions that lack it | Nothing |
| Request stage | per-caller policy, bearer-token validation | Runs after identity and before dispatch with the request, identity and transport metadata; returns continue or a typed rejection | OAuth also needs HTTP adapter hooks for `401`, `WWW-Authenticate` and well-known metadata routes |
| Response mode | `subscriptions/listen`, progress | The core response type is a single value today; it is designed so a stream variant can be added | SSE responses in the HTTP adapter and interleaved writes in the stream adapter |
| Result type | `input_required` multi-round-trip results (SEP-2322) | A handler returns a non-complete result with `inputRequests` and opaque `requestState` | The pipeline must accept `inputResponses` and `requestState` on the retried request and protect `requestState` from tampering |

## Boundaries not owned here

- Process lifetime, launchd supervision, macOS permissions and app UI belong to the consumer.
- Tailscale Serve configuration belongs to the consumer's deployment documentation. The library only guarantees it can listen on loopback or a Unix socket and enforce host and origin rules.
- Authorization servers and token issuance are out of scope; a request stage can validate tokens when an accepted requirement needs it.
