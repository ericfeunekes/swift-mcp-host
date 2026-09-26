# Architecture

The library separates what every MCP server must get right (the protocol contract and agent-facing defaults) from what each utility owns (its tools and its process). It is a library, not a host application: it does not own permissions, lifetime, supervision or deployment.

## Targets

| Target | Owns | Depends on |
|---|---|---|
| `MCPHostCore` | Protocol value types, JSON-RPC handling, version negotiation, the request pipeline, tool registry, validation, error rendering, caller identity | swift-json-schema |
| `MCPHostMacros` | Compile-time checks that tool types and errors carry descriptions and annotations | swift-syntax |
| `MCPHostHTTP` | Streamable HTTP on loopback or a Unix socket: origin, host, header and body-size checks, cancellation on disconnect | `MCPHostCore`, Hummingbird |
| `MCPHostStream` | Newline-delimited streams over stdio or file handles | `MCPHostCore` |
| `MCPHostTesting` | A synthetic example server, a client for tests, schema-validation helpers and fixtures | `MCPHostCore` |

A consumer depends on `MCPHostCore` plus the adapters it uses. `MCPHostCore` has no transport or web-framework dependency.

## Request pipeline

Every request, whatever the transport, passes through the same stages in order:

1. **Frame.** The adapter produces one JSON-RPC message plus transport metadata (headers, the resolved caller identity, a cancellation signal).
2. **Identity.** Reject a missing or unknown caller identity.
3. **Envelope.** Parse JSON-RPC. Reject batches and malformed messages.
4. **Version.** Determine the revision from `initialize` negotiation or from request `_meta`. Reject unsupported revisions and header disagreements.
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
- an error type conforming to a library protocol that requires a code, a message and a next step for each case;
- annotations and descriptions supplied through a library macro that fails compilation when any are missing.

Validation runs the parser, which accumulates every problem with its JSON Pointer, then maps the problems to the agent error shape in the [requirements](requirements.md#argument-errors). The Swift handler receives only a fully valid value.

The exact authoring API is an [open decision](decisions.md#owner-decisions) and will be shown as a worked example before it is built.

## Caller identity

Adapters resolve the identity; the core enforces it. The stream adapter takes it from its configuration at launch. The HTTP adapter takes it from a configured path segment such as `/c/<identity>/mcp`, or from a configured header. The core receives an already-resolved value and never reads it from the message body.

## Extension points

Each is defined as a protocol and exercised by a test-only implementation; none ships an implementation.

| Point | Future uses | Seam |
|---|---|---|
| Capability | resources, prompts, completion, `subscriptions/listen` | Registers methods and contributes to the advertised capabilities |
| Protocol extension | tasks (`io.modelcontextprotocol/tasks`), MCP Apps | Contributes to `capabilities.extensions` and may add methods and result fields (SEP-2133) |
| Content block | new result content types | Encodes a block for the negotiated revision |
| Request stage | OAuth bearer validation, per-caller policy | Runs between identity and dispatch and may reject with a typed error |
| Result type | `input_required` multi-round-trip results (SEP-2322) | Lets a handler return a non-complete result type |

## Boundaries not owned here

- Process lifetime, launchd supervision, macOS permissions and app UI belong to the consumer.
- Tailscale Serve configuration belongs to the consumer's deployment documentation. The library only guarantees it can listen on loopback or a Unix socket and enforce host and origin rules.
- Authorization servers and token issuance are out of scope; a request stage can validate tokens when an accepted requirement needs it.
