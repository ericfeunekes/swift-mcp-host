# Requirements

## Purpose

Make it easy, obvious and the default for a Swift utility to expose tools that agents use correctly the first time and recover from quickly when they do not. The library owns the MCP contract so that each utility owns only its tools.

Spec citations use the revision date and page, for example *2026-07-28 server/tools*. Guidance citations are listed in [references](references.md). Where a requirement goes beyond the spec, it says so.

## Scope

- Tools-only servers: tool listing, tool calls and the protocol lifecycle needed to reach them.
- Supported protocol revisions: 2025-06-18, 2025-11-25 and 2026-07-28. Older revisions are rejected with the supported list. Whether real clients still send earlier revisions is an [open question](decisions.md#engineering-questions).
- Transports: Streamable HTTP and newline-delimited streams. The legacy HTTP+SSE transport is not supported (deprecated since 2025-03-26, formally *2026-07-28 deprecated*).
- Out of scope until accepted through the [consumer process](consumers.md): resources, prompts, completion, tasks, MCP Apps, subscriptions, sampling, elicitation, roots, logging and OAuth. The [architecture](architecture.md#extension-points) reserves a place for each.

## Protocol lifecycle

- For 2025-06-18 and 2025-11-25, answer `initialize` with the negotiated version, server information, `tools` capability and instructions, and accept `notifications/initialized`. The server does not issue `Mcp-Session-Id`; the header is optional in those revisions (*2025-11-25 basic/transports*).
- For 2026-07-28, implement `server/discover` returning `supportedVersions`, capabilities, instructions, `ttlMs` and `cacheScope` (*2026-07-28 server/discover*, SEP-2575, SEP-2549). Read `io.modelcontextprotocol/protocolVersion` and `io.modelcontextprotocol/clientCapabilities` from every request's `_meta`; reject a request missing either with `-32602` (*2026-07-28 basic*). Return `io.modelcontextprotocol/serverInfo` in result `_meta` and `resultType: "complete"` on every result (SEP-2322).
- Reject an unsupported revision with `-32022` and the supported list under 2026-07-28, or the negotiated fallback under `initialize` (*2026-07-28 basic/versioning*).
- Answer `ping` for revisions that define it. `ping` is removed in 2026-07-28.
- No state spans requests. Any state a tool needs across calls is an explicit handle argument bound to the caller identity (*2026-07-28 security best practices*, state handle hijacking).
- JSON-RPC batches are rejected (removed in 2025-06-18).

## Server description

- A server declares a name, title, version and instructions. Instructions explain how the tools fit together and when to use which; they do not repeat tool descriptions (*2026-07-28 server/discover*).
- Description, icons and website are carried for 2025-11-25 and later (SEP-973).

## Tools

### Definition

- A tool is registered from a Swift input type, an output type, a handler and a declared error type. Registration fails at compile time where Swift can enforce it and otherwise at server construction, with a message naming the tool and the missing item.
- Required on every tool: a name, a title, a description and explicit values for `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`. The spec defaults `destructiveHint` and `openWorldHint` to true and the others to false (*2026-07-28 server/tools*, ToolAnnotations); the library requires the author to choose rather than inherit them. This goes beyond the spec.
- Required on every input and output property and every enum case: a description. A Swift doc comment is the default source. This goes beyond the spec.
- Names match `^[A-Za-z0-9_-]{1,64}$` and are unique within the server. This is the intersection of the MCP recommendation (*2025-11-25 server/tools*, SEP-986) and the Anthropic and OpenAI tool-name rules. It goes beyond the spec.
- The description states what the tool does, when to use it, when not to, and its limits. The library rejects a description shorter than a minimum length; see the [open decision](decisions.md#owner-decisions) on the threshold.

### Schemas

- `inputSchema` and `outputSchema` are generated from the Swift types. Hand-written schemas are not accepted.
- Schemas use JSON Schema 2020-12 and do not emit `$schema` for another dialect (*2025-11-25 basic*, SEP-1613). Clients have rejected non-default dialects in practice.
- The input root is `type: "object"`. A tool with no inputs emits `{"type":"object","additionalProperties":false}` (*2026-07-28 server/tools*).
- By default schemas use a portable subset: every object sets `additionalProperties: false`; no `allOf`, `not`, `if`/`then`/`else`, `dependentRequired` or `dependentSchemas`; no remote `$ref`. This keeps schemas accepted by OpenAI strict mode and by the clients with known validator gaps. Using a wider 2020-12 feature (allowed by *2026-07-28 basic*, SEP-2106) is an explicit opt-in on that tool. This goes beyond the spec.
- Enums are preferred to free text wherever the value set is closed. Constraints the type knows (ranges, lengths, patterns, formats, item counts) appear in the schema.
- Output types with an `outputSchema` always produce `structuredContent` that conforms to it (*2026-07-28 server/tools*, output schema). Some clients fail a call that declares an output schema and returns none.

### Results

- A successful call returns `structuredContent` and the same value serialized as JSON in a text content block. The text block is derived from the structured value; the author cannot supply one without the other (*2026-07-28 server/tools*, backwards compatibility SHOULD).
- A tool may add image, audio, resource-link or embedded-resource blocks after the text block.
- Results that can be large are bounded. The library supplies a standard truncation and pagination shape whose message tells the agent how to narrow the request.
- `tools/list` is returned in a stable order and does not vary by connection (*2026-07-28 server/tools*). It carries `ttlMs` and `cacheScope` under 2026-07-28.

## Errors

Every error an agent can see is specific, typed and actionable. Nothing reports a bare failure.

### Protocol errors

JSON-RPC errors are reserved for requests the model cannot fix by changing arguments (*2025-11-25 server/tools*, error handling, SEP-1303):

| Case | Code |
|---|---|
| Unparseable JSON | `-32700` |
| Not a valid JSON-RPC request, or a batch | `-32600` |
| Unknown method | `-32601` |
| Unknown tool, missing required `_meta`, `CallToolRequest` shape violation | `-32602` |
| `Mcp-Method` or `Mcp-Name` header disagrees with the body (2026-07-28) | `-32020` |
| Unsupported protocol revision (2026-07-28) | `-32022` |
| Unexpected server failure | `-32603` |

An unexpected failure message names the tool and says the call can be retried or reported; it does not expose internal error text. The full error is available to the host through a logging hook.

### Argument errors

- Arguments that fail the tool's input schema or type validation return a tool result with `isError: true`, not a protocol error. This follows the spec's classification of input validation errors as tool execution errors so the model can self-correct (*2025-11-25 server/tools*, SEP-1303). The spec's own example uses `-32602` for a missing required property; the reading chosen here is recorded in [decisions](decisions.md#accepted).
- Validation collects every problem, not the first. Each problem has:
  - `type`: a stable snake_case identifier such as `missing`, `wrong_type`, `too_long`, `out_of_range`, `not_in_enum`, `unexpected_property`, `invalid_format`.
  - `path`: a JSON Pointer to the value.
  - `message`: one sentence naming the field and what was wrong.
  - `input`: the rejected value, bounded in size.
  - `context`: the constraint that failed, such as `{"maximum": 100}` or the allowed enum values with their descriptions.
  - `hint`: what to send instead, when the library can derive one.
- The problems are returned as `structuredContent` under a fixed error shape and rendered as a short numbered text list. The shape is part of the public contract and is versioned.

### Tool errors

- A handler reports expected failures by throwing its declared error type. Each case supplies a stable code, a message and a next step for the agent, for example "Call `find_chats` first and pass its `chatID`." Optional details are structured.
- An expired or unknown handle is a tool error that says so and tells the agent how to obtain a new one (*2026-07-28 server/tools*, stateful tools).
- A handler cannot return `isError: true` without a typed error.

## Caller identity

- Every request carries a caller identity: a short identifier for the configured client connection, such as `claude-code`, `codex`, `chatgpt-tunnel` or `muse`.
- The adapter resolves it from configuration the model cannot see or change: a launch argument for stream adapters, and a URL path segment or configured header for HTTP. It never comes from tool arguments or client-reported `clientInfo`.
- The server declares the identities it accepts. A request with a missing or unknown identity is rejected before dispatch. There is no default identity.
- Handlers and the host's logging hook receive the identity. Tailscale identity headers, when present, are carried alongside it and are informational; they are not the caller identity.

## Transports

### Streamable HTTP

- Serve MCP at one path on a loopback address or a Unix domain socket. Never bind a non-loopback interface.
- POST carries one JSON-RPC message. Requests are answered with `application/json`; streaming responses are not used. Notifications and responses from the client are answered with `202 Accepted`. GET and DELETE are answered with `405` (*2025-11-25 basic/transports*).
- Reject an invalid `Origin` with `403` (*2025-11-25 basic/transports*). Accept only configured `Host` values, to prevent DNS rebinding.
- Enforce `MCP-Protocol-Version` against the negotiated or per-request revision, and `Mcp-Method` and `Mcp-Name` under 2026-07-28 (SEP-2243).
- Limit request body size before parsing.
- Concurrent requests are isolated: request context never leaks between calls, including calls that reuse the same JSON-RPC id.
- A client disconnect or `notifications/cancelled` cancels the running handler.

### Newline-delimited stream

- One JSON-RPC message per line in each direction, UTF-8, with a size limit per message. Only protocol messages are written to the output stream.
- Suitable for stdio and for local Unix-socket bridges.

## Extensibility

- New capabilities, content types and request stages attach through the extension points in the [architecture](architecture.md#extension-points) without changing the tool API.
- Each extension point is exercised by a test-only extension so that the seam is proven while no extension ships.
