# Requirements

## Purpose

Make it easy, obvious and the default for a Swift utility to expose tools that agents use correctly the first time and recover from quickly when they do not. The library owns the MCP contract so that each utility owns only its tools.

Spec citations give the revision and page, for example *2026-07-28 server/tools*; the source files are listed in [references](references.md). A requirement that goes beyond the spec says so.

## Scope

- Tools-only servers: tool listing, tool calls and the protocol lifecycle needed to reach them.
- Transports: Streamable HTTP and newline-delimited streams (stdio and local sockets). The legacy HTTP+SSE transport is not supported (*2026-07-28 deprecated*).
- Out of scope until accepted through the [consumer process](consumers.md): resources, prompts, completion, tasks, MCP Apps, subscriptions, progress, sampling, elicitation, roots, logging and OAuth. The [architecture](architecture.md#extension-points) reserves a place for each.

## Protocol revisions

The server is dual-era (*2026-07-28 basic/versioning*, backward compatibility):

- **Modern:** 2026-07-28. Every request carries its revision and client capabilities in `_meta`. No handshake and no state.
- **Legacy:** 2025-11-25, 2025-06-18 and 2025-03-26, reached through `initialize`.

Both eras are served on the same endpoint or process.

### Selecting the revision

| Transport | Signal | Result |
|---|---|---|
| Any | Request `_meta` carries `io.modelcontextprotocol/protocolVersion` | Modern. A supported value is served under that revision; an unsupported value gets `-32022` (UnsupportedProtocolVersion) listing supported versions. |
| Any | `initialize` request | Legacy. The server answers with the client's requested version when it is a supported legacy version, and otherwise with 2025-11-25 (*2025-11-25 basic/lifecycle*). It never answers `initialize` with 2026-07-28. |
| stdio | `ping` before `initialize` | Answered (*2025-11-25 basic/lifecycle* allows pings before initialization). |
| stdio | Any other request before `initialize` | Error `-32602` stating that the request needs either modern `_meta` or a prior `initialize`. |
| stdio | A request after `initialize`, without modern `_meta` | Served under the revision negotiated by `initialize`. This is the only state the server keeps, and it lasts for the process (*2026-07-28 basic/versioning*). |
| HTTP | A request without modern `_meta` and with `MCP-Protocol-Version` naming a revision the server does not support | `400` with `-32022` listing every supported revision. |
| HTTP | A request without modern `_meta` and with `MCP-Protocol-Version` naming a supported legacy revision | Served statelessly under that revision. The server never issues `Mcp-Session-Id`, which is optional in those revisions (*2025-11-25 basic/transports*), so no state links requests. |
| HTTP | `initialize` without `MCP-Protocol-Version` | Accepted. Legacy clients send the header only after `initialize` (*2025-11-25 basic/transports*). |
| HTTP | Any other request without modern `_meta` and without `MCP-Protocol-Version` | Served as 2025-03-26, which did not define the header (*2026-07-28 basic/transports/streamable-http*). |

### Modern requests

- Reject a request missing `io.modelcontextprotocol/protocolVersion` or `io.modelcontextprotocol/clientCapabilities` with `-32602` (*2026-07-28 basic*).
- An unsupported revision in `_meta` gets `-32022` listing only the modern revisions, because a legacy revision cannot be used in `_meta`; older revisions use `initialize`. The spec's own dual-era example also lists legacy revisions; this is a deliberate narrowing.
- Notifications carry no revision under 2026-07-28, so they are routed without revision checks and never answered.
- `io.modelcontextprotocol/clientInfo` (and `clientInfo` from `initialize`, when a legacy client sent it on the same stream) is passed to the host in [server events](#server-events) for logging only. It is self-reported and never used for decisions.
- Implement `server/discover` returning `supportedVersions`, capabilities, instructions, `ttlMs` and `cacheScope` (*2026-07-28 server/discover*).
- Every result carries `resultType: "complete"` and `io.modelcontextprotocol/serverInfo` in `_meta` (*2026-07-28 basic*).

### Legacy requests

- `initialize` returns the negotiated version, server information, the `tools` capability and instructions. Accept `notifications/initialized`.
- Answer `ping`. `ping` is removed in 2026-07-28 and is `-32601` there.
- Under 2025-06-18 and later, reject JSON-RPC batches with `-32600` (removed in 2025-06-18).
- Under 2025-03-26, accept batches of requests and notifications, which that revision requires servers to receive (*2025-03-26 basic*). The revision is chosen once for the batch: over HTTP from the `MCP-Protocol-Version` header (absent or `2025-03-26`), on a stream from the negotiated revision. Answer with an array of responses for the requests, in request order, with HTTP `200` even when items are errors; a batch of only notifications gets `202`. An `initialize` item, or an item carrying 2026-07-28 `_meta`, is answered with `-32600` inside the array; other items are unaffected.
- Under 2025-03-26, tool definitions omit `outputSchema` and `title`, and results omit `structuredContent`; the serialized JSON text block carries the value. Those fields were added in 2025-06-18.

## Server description

- A server declares a name, title, version and instructions. Instructions explain how the tools fit together and when to use which. They do not repeat tool descriptions (*2026-07-28 schema*, DiscoverResult).
- `description`, `icons` and `websiteUrl` are sent for 2025-11-25 and later (*2025-11-25 schema*, Implementation).
- `capabilities.tools.listChanged` is `false`: the tool list is fixed for the lifetime of the process.

## Tools

### Definition

- A tool is registered from a Swift input type, an output type, a handler and a declared error type. Registration fails at compile time where Swift can enforce it and otherwise at server construction, with a message naming the tool and the missing item.
- Every tool needs a name, a title, a description and explicit values for `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`. The spec defaults `destructiveHint` and `openWorldHint` to true and the others to false (*2026-07-28 schema*, ToolAnnotations). The library makes the author choose instead of inheriting them. This goes beyond the spec.
- `openWorldHint` is true when the tool reaches the open internet or arbitrary external entities. A bounded private account or local data store is not open-world.
- Every input and output property and every enum case needs a description. A Swift doc comment is the default source. This goes beyond the spec.
- Names match `^[A-Za-z0-9_-]{1,64}$` and are unique within the server. This is the intersection of the MCP recommendation (*2025-11-25 server/tools*, SEP-986) and the Anthropic and OpenAI tool-name rules, so it goes beyond the spec.
- The description states what the tool does, when to use it, when not to, and its limits. It must be at least 40 characters; this is a floor against empty descriptions, not a quality bar (see [decisions](decisions.md#accepted)).

### Schemas

- `inputSchema` and `outputSchema` are generated from the Swift types. Hand-written schemas are not accepted.
- Schemas use JSON Schema 2020-12 and never declare another dialect (*2025-11-25 basic*, SEP-1613).
- The input root is `type: "object"`. A tool with no inputs emits `{"type":"object","additionalProperties":false}` (*2026-07-28 server/tools*).
- By default schemas use a **portable profile**:
  - every object sets `additionalProperties: false`;
  - no `allOf`, `oneOf`, `not`, `if`/`then`/`else`, `dependentRequired`, `dependentSchemas` or remote `$ref`;
  - a closed value set is a plain `enum`, and each case's description is listed in the property description, because `enum` cannot carry per-case descriptions portably;
  - an optional Swift property is omitted from `required`. Whether to emit OpenAI strict-mode shape instead (every property required, optional values nullable) is an [engineering question](decisions.md#engineering-questions).

  A wider 2020-12 feature (allowed by *2026-07-28 basic*, SEP-2106) will be an explicit opt-in on that tool. The opt-in is deferred until a consumer needs it; until then registration rejects such schemas. The profile goes beyond the spec.
- Numeric ranges, string lengths, patterns, formats and item counts appear in the schema when the type declares them. Which of these the portable profile keeps is decided by the strict-mode test in [decisions](decisions.md#engineering-questions).
- Schemas never emit `x-mcp-header` (*2026-07-28 server/tools*).
- A tool with an output type always returns `structuredContent` that conforms to its `outputSchema` (*2026-07-28 server/tools*, output schema). Some clients fail a call that declares an output schema and returns none.

### Results

- A successful call returns `structuredContent` and the same value serialized as JSON in the first text content block. The text is derived from the structured value; the author cannot supply one without the other (*2026-07-28 server/tools*, backwards compatibility).
- A tool may add image, audio, resource-link or embedded-resource blocks after that text block by returning them alongside its output value. Binary data is base64-encoded by the library with the declared MIME type. Under 2025-03-26, which has no resource links, a resource link is rendered as a text block naming the resource and its URI.

### Large results

Agents work best with bounded results that say how to get more. The library supplies one convention for this:

- **Pagination.** A tool that pages its results has an optional string `cursor` input and an optional string `nextCursor` output. `nextCursor` is absent when there are no more results. The author documents both fields like any other; registration appends the library's guidance to their descriptions: pass `nextCursor` back as `cursor` to continue, and never construct or modify a cursor. Registration fails if a tool has one field without the other.
- **Truncation.** A tool that cuts a result short includes an optional `truncation` output of the library type `Truncation`, with `shown` (how many items are included), `total` (how many exist, when known) and `message`. The tool supplies the counts and its narrowing advice; the library writes the message, for example "Showing 50 of 1,240 messages. Add `contains` or a date range to narrow the search."
- **Invalid cursors.** The library supplies the code (`invalid_cursor`), message and next step ("Repeat the call without `cursor` to start from the first page.") for an unknown or expired cursor, for the tool's own error type to return.

### Listing

- `tools/list` returns every tool in one page, in registration order. A request with any `cursor` gets `-32602` (*2026-07-28 server/tools*).
- The list does not vary by caller or connection. Under 2026-07-28 it carries `cacheScope: "public"` and a `ttlMs` configured by the server, default 300000 (*2026-07-28 server/utilities/caching*).

## Errors

Every error an agent can see is specific, typed and actionable. Nothing reports a bare failure.

### Protocol errors

JSON-RPC errors are reserved for requests the model cannot fix by changing arguments (*2025-11-25 server/tools*, error handling). The HTTP status applies to the Streamable HTTP transport (*2026-07-28 basic/transports/streamable-http*):

| Case | Code | HTTP, modern | HTTP, legacy |
|---|---|---|---|
| Unparseable JSON | `-32700` | 400 | 400 |
| Not a single valid JSON-RPC request or notification, including a batch outside 2025-03-26 | `-32600` | 400 | 400 |
| Unknown method | `-32601` | 404 | 200 |
| Unknown tool, missing required `_meta`, request shape violation, unsupported `cursor` | `-32602` | 400 | 200 |
| Header disagrees with the body, or a required header is missing or malformed | `-32020` | 400 | n/a |
| Unsupported protocol revision in `_meta` or in the `MCP-Protocol-Version` header | `-32022` | 400 | 400 |
| Failure inside the library | `-32603` | 500 | 500 |

- `MCP-Protocol-Version` must equal the `_meta` revision on modern requests. `Mcp-Method` must equal the method and `Mcp-Name` the tool name on `tools/call`, decoding the `=?base64?…?=` form (*2026-07-28 basic/transports/streamable-http*, SEP-2243).
- A `-32603` message names the tool and says the failure is on the server side, not the arguments. It does not expose internal error text. The full error goes to the host through a [server event](#server-events).

### Argument errors

- Arguments that fail the tool's input type return a tool result with `isError: true`, not a protocol error, under every revision. The spec classifies input validation errors as tool execution errors so the model can self-correct (*2025-11-25 server/tools*, SEP-1303). This deviates from the spec's `-32602` example for a missing property and from 2025-06-18, which listed invalid arguments as a protocol error; see [decisions](decisions.md#owner-decisions).
- Validation collects every problem, not only the first. Each problem has:
  - `type`: a stable snake_case identifier: `missing`, `wrong_type`, `too_short`, `too_long`, `out_of_range`, `not_in_enum`, `unexpected_property`, `invalid_format`, `pattern_mismatch`, `too_few_items`, `too_many_items`.
  - `path`: a JSON Pointer to the value. For a missing property it points to where the property belongs, such as `/chatID`.
  - `message`: one sentence naming the field and what was wrong.
  - `input`: the rejected value, truncated to a bounded size. Absent for `missing`.
  - `context`: the constraint that failed, such as `{"maximum": 100}` or the allowed enum values with their descriptions.
  - `hint`: what to send instead, when the library can derive one.

### Tool errors

- A handler declares its error type with Swift typed throws, `throws(E)`, where `E` conforms to the library's tool error protocol. Each case supplies a stable snake_case code, a message and a next step for the agent, for example "Call `find_chats` first and pass its `chatID`." Details are optional and structured.
- An expired or unknown handle is a tool error that says so and tells the agent how to get a new one (*2026-07-28 server/tools*, stateful tools).
- A handler cannot produce `isError: true` except by throwing its declared error type.

### Error result shape

Argument errors and tool errors share one shape, versioned by `schemaVersion`:

```json
{
  "error": {
    "schemaVersion": 1,
    "code": "invalid_arguments",
    "message": "2 problems with the arguments to read_messages.",
    "nextStep": "Fix the listed fields and call read_messages again.",
    "issues": [
      {"type": "missing", "path": "/chatID", "message": "chatID is required.", "context": {}, "hint": "Call find_chats to get a chatID."},
      {"type": "out_of_range", "path": "/limit", "message": "limit must be at most 100.", "input": 500, "context": {"maximum": 100}}
    ]
  }
}
```

- `code` is `invalid_arguments` for argument errors and the handler's code for tool errors. `issues` is present only for argument errors; `details` only for tool errors.
- The first text block is a short readable rendering: the message, a numbered list of issues and the next step. It is not JSON; the structured value carries the machine-readable form.
- Error results do not conform to the tool's `outputSchema`. The spec's conformance rule is read as applying to successful results; see [decisions](decisions.md#accepted).
- Changing the shape increments `schemaVersion` and is called out in release notes.

## Caller identity

- Every request carries a caller identity: a short label for a configured client connection, such as `claude-code`, `codex`, `chatgpt-tunnel` or `muse`. It matches `^[a-z0-9-]{1,32}$`.
- The identity is a label for attribution and per-caller behavior, **not a security boundary**. Anyone who can reach the endpoint can present any label. Access control is the transport's reachability: loopback, a user-private Unix socket, or Tailscale policy. Handles bound to an identity are attributed, not authenticated.
- The adapter resolves the identity from configuration the model cannot see or change. It never comes from tool arguments or `clientInfo`.
  - Stream adapter: set at launch. Starting with an identity the server does not accept throws a typed error naming it.
  - HTTP adapter: a path segment, `<base>/c/<identity>/mcp`. A request to an unknown identity gets `404` with a JSON-RPC error with no `id`, code `-32600`, whose message says the client URL must use an identity configured for this server.
- The server declares the identities it accepts. There is no default identity. The server's list is the only list: the HTTP adapter passes every well-formed identity segment to the core, and a segment that is not a valid identity label is a path that does not exist (`404`, no body).
- Handlers and the host's event hook receive the identity. Tailscale identity headers (`Tailscale-User-Login`, `Tailscale-User-Name`), when present, are passed alongside it as information.

## Server events

The host passes one event handler when it creates the server. The library calls it for:

- every completed tool call: caller identity, the client's self-reported name and version when known, Tailscale login when present, tool name, outcome (`success`, `invalid_arguments`, the tool error code, or `internal_failure`) and duration;
- every internal failure: caller identity, method, tool name when there is one, and the full error detail that the `-32603` response withholds;
- every request the core rejects before dispatch: caller identity, the reason, and the response status. Requests an adapter rejects before they reach the core (a bad `Host` or `Origin`, an oversized body, a path that is not an MCP path, GET or DELETE) produce no event; the adapter also keeps its framework's logging off, so nothing reaches standard output or error.

Events never contain argument values or results, so a host can log them without logging user data. The library writes nothing to standard output or standard error itself. Startup problems (an identity the server does not accept, a Unix socket held by a live server, an unusable listener) are thrown as typed errors naming the problem; the consumer decides how to report them and exit.

## Transports

### Streamable HTTP

- Listen on 127.0.0.1, a Unix domain socket, or both from one server. Never bind a non-loopback interface (*2026-07-28 basic/transports/streamable-http*, security).
- A Unix socket's directory is owner-only (`0700`) and the socket is owner-only (`0600`). Starting throws a typed error naming the path if another live server already answers on it; a stale socket file is replaced.
- Serve one MCP path per accepted identity, `<base>/c/<identity>/mcp`. The base path is the path the adapter receives, so it is usually empty behind `tailscale serve --set-path`, which strips its prefix.
- POST carries one JSON-RPC message. Requests are answered with `application/json`. Accepted notifications get `202 Accepted` with no body. An empty body is `-32700` with `400`. GET and DELETE on an MCP path get `405` with `Allow: POST` (*2025-11-25 basic/transports*); Claude Code sends one GET after a legacy `initialize` and continues on `405`.
- Any other path, including OAuth discovery paths such as `/.well-known/oauth-protected-resource`, gets `404` with no body. The server does not advertise authorization.
- An `Origin` header that is present and not configured gets `403` (*2026-07-28 basic/transports/streamable-http*). None of the surveyed clients send `Origin`. A `Host` that is not configured gets `403`, to prevent DNS rebinding. The host configures the values it expects; observed values are `localhost` through a Unix socket (directly or from `tailscale serve`), `127.0.0.1:<port>` directly over TCP, and `<machine>.<tailnet>.ts.net` from `tailscale serve` to TCP.
- Header names are matched case-insensitively. Claude Code sends `mcp-method`; the OpenAI tunnel client sends `Mcp-Method`.
- Enforce the header rules in [protocol errors](#protocol-errors).
- Limit the request body size before parsing; an oversized body gets `413`.
- Concurrent requests are isolated: no request context is shared between calls, including calls that reuse a JSON-RPC id.
- Closing the connection cancels the running handler, including when the client is behind `tailscale serve`, which passes the disconnect through. That is the only HTTP cancellation signal (*2026-07-28 basic/patterns/cancellation*). A legacy `notifications/cancelled` over HTTP gets `202` and is otherwise ignored, because without sessions its request id is ambiguous.

### Newline-delimited stream

- One JSON-RPC message per line in each direction, UTF-8, with a size limit per message. Only protocol messages are written to the output stream.
- A line over the size limit is discarded up to its newline and answered with `-32600` without an `id`; the stream continues.
- The revision negotiated by `initialize` lasts for the life of the stream. A second `initialize` on the same stream is `-32600`.
- `notifications/cancelled` cancels the named running request (*2026-07-28 basic/patterns/cancellation*).
- End of input stops the server after in-flight requests finish or are cancelled.

## Extensibility

- New capabilities, protocol extensions, content types, request stages and result types attach through the [extension points](architecture.md#extension-points) without changing how existing tools are written.
- Extensions that need streaming responses, HTTP authentication or multi-round-trip state need adapter or pipeline work described with each extension point. They are not free.
- Each extension point is exercised by a test-only extension, so the seam is proven while none ships.
