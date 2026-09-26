# Architecture

The library separates what every MCP server must get right (the protocol contract and agent-facing defaults) from what each utility owns (its tools and its process). It is a library, not a host application: it does not own permissions, lifetime, supervision or deployment.

## Targets

| Target | Owns | Depends on |
|---|---|---|
| `MCPHostCore` | Protocol value types, JSON-RPC handling, version negotiation, the request pipeline, tool registry, validation, error rendering, caller identity | swift-json-schema |
| `MCPHostMacros` (not yet added) | Compile-time checks that tool types and errors carry descriptions and annotations; added with the [authoring API decision](decisions.md#owner-decisions) | swift-syntax |
| `MCPHostHTTP` | Streamable HTTP on loopback or a Unix socket: origin, host, header and body-size checks, cancellation on disconnect | `MCPHostCore`, Hummingbird |
| `MCPHostStream` | Newline-delimited streams over stdio or file handles | `MCPHostCore` |
| `MCPHostTesting` | Validation against the official MCP schemas today; a synthetic example server and a test client later | `MCPHostCore`, swift-json-schema |

A consumer depends on `MCPHostCore` plus the adapters it uses. `MCPHostCore` has no transport or web-framework dependency.

## Request pipeline

Every request, whatever the transport, passes through the same stages in order:

1. **Frame.** The adapter produces one JSON-RPC message plus transport metadata (headers, the resolved caller identity, a cancellation signal).
2. **Identity.** Reject a missing or unknown caller identity.
3. **Envelope.** Parse JSON-RPC. Reject batches and malformed messages.
4. **Version.** Select the revision using the table in [requirements](requirements.md#selecting-the-revision). Reject unsupported revisions and header disagreements.
5. **Dispatch.** Route by method to a capability. Core ships the lifecycle methods and `tools`.
6. **Tool call.** Look up the tool, validate arguments against its type, invoke the handler with a context, and render the result or error.
7. **Encode.** Produce the result in the shape of the negotiated revision, including `_meta` and `resultType` where that revision requires them.

Protocol types are revision-aware at the encode stage only. Handlers never see revision differences.

## Protocol types

The library owns a small set of Codable protocol types rather than using the official Swift SDK's. They decode leniently: unknown fields and extension objects anywhere in a client message are preserved as JSON values and never fail decoding. They encode strictly: every outgoing message is checked against the official schema in tests. See [decisions](decisions.md#accepted).

## Typed tools

A tool is defined by:

- an input type whose schema, decoding and validation come from one declaration, using swift-json-schema's schema builder and `@Schemable` macro, with doc comments as descriptions;
- an output type declared the same way;
- an error type, thrown with Swift typed throws, conforming to a library protocol that requires a code, a message and a next step for each case;
- annotations and descriptions supplied through a library macro that fails compilation when any are missing.

Validation runs the parser, which accumulates every problem with its JSON Pointer, then maps the problems to the agent error shape in the [requirements](requirements.md#argument-errors). The Swift handler receives only a fully valid value.

The exact authoring API is an [open decision](decisions.md#owner-decisions) and will be shown as a worked example before it is built.

## Caller identity

Adapters resolve the identity; the core enforces that it is one the server accepts. The identity is a label, not authentication; see [requirements](requirements.md#caller-identity). The stream adapter takes it from its configuration at launch. The HTTP adapter takes it from the path segment in `<base>/c/<identity>/mcp`. The core receives an already-resolved value and never reads it from the message body.

## Extension points

Each is defined as a protocol and exercised by a test-only implementation; none ships an implementation. The "needs" column is work the extension brings with it; the seam alone does not provide it.

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
