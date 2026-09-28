# Decisions

Accepted choices, owner decisions still open, and engineering questions a test or prototype can answer. A proposal stays a proposal until accepted.

## Accepted

- **Repository:** `swift-mcp-host`, public, personal account `ericfeunekes`. Owner.
- **Scope:** tools-only core; other capabilities designed for and deferred. Owner.
- **Protocol types:** owned by this library and decoded leniently, instead of the official Swift SDK's. The SDK declares client experimental capabilities as `[String: String]`, which rejects the valid nested JSON ChatGPT sends, and implements only 2025-11-25. Drift is controlled by validating output against the official schemas. Owner.
- **Agent ergonomics are mandatory:** descriptions, annotations and typed errors are required to register a tool, and argument errors are aggregated and detailed in the style of Pydantic. Owner.
- **Caller identity is required** and comes from configuration the model cannot change. It is a label, not authentication. Owner requirement; the label reading is the maintainer's, because an unauthenticated tailnet or loopback caller can present any value.
- **Dual-era server.** One endpoint serves 2026-07-28 statelessly and 2025-11-25, 2025-06-18 and 2025-03-26 through `initialize`, without HTTP sessions. Maintainer, from *2026-07-28 basic/versioning*.
- **Transports:** Streamable HTTP through Hummingbird, and newline-delimited streams. JSON responses only. Maintainer, from research.
- **Schema and validation engine:** swift-json-schema (schema builder, `@Schemable`, accumulated validation errors with JSON Pointers, 2020-12). Maintainer, from research.
- **Error results and `outputSchema`.** The spec's rule that structured results conform to the output schema is read as applying to successful results. Error results carry the library's error shape instead. The official TypeScript and Python clients skip output validation when `isError` is set. Maintainer.
- **Argument errors are tool errors under every revision.** Schema and type failures return `isError: true` results with the detailed error shape. Basis: SEP-1303 (2025-11-25) classifies input validation errors as tool execution errors so models can self-correct, and clients SHOULD show tool errors to the model but only MAY show protocol errors. Accepted deviations: the spec's own `-32602` example for a missing property, and 2025-06-18, which listed invalid arguments as a protocol error. Owner.
- **Authoring API is macro-first.** Tools are `@Schemable @MCPTool` structs; nested types are `@MCPSchema` and enums `@MCPEnum`. The compiler rejects missing descriptions and annotations. The swift-json-schema builder remains available for shapes the macros cannot express, subject to the same registration checks. Owner. See [architecture](architecture.md#typed-tools).
- **License:** MIT, matching messages-swift. Owner.
- **2025-03-26 is supported.** HTTP requests without `MCP-Protocol-Version` are served as 2025-03-26, batches are accepted under that revision only, and output schemas and structured content are omitted for it. Owner, on the basis that the cost is small; messages-swift's own tests initialize with 2025-03-26.
- **Minimum tool description length is a hard registration rule at 40 characters** (`ToolRules.minimumDescriptionLength`). It is a floor against empty or one-word descriptions, not a quality bar; review and evals judge quality. Owner delegated; maintainer.
- **Extension seams stay internal until an extension is accepted.** The method table and the other seams are not public API before 1.0, so they can change while nothing depends on them. A consumer request for an extension decides what becomes public. Maintainer.
- **Pagination API.** Authors document `cursor` and `nextCursor` like other fields and registration appends the library's guidance, rather than exempting them from the doc-comment rule. The library supplies the `Truncation` type and the invalid-cursor code, message and next step, because it cannot add a case to a consumer's error type. Maintainer.
- **Consumer intake:** requirement documents in `docs/requests/` by pull request, or GitHub Issues; same headings and triage for both. Owner.
- **Adapter-level rejections produce no events.** Only requests that reach the core are reported, so the event type and the core stay transport-independent. Maintainer.
- **Startup errors are thrown, not printed.** The library never writes to standard output or error; startup problems are typed errors the consumer reports. Maintainer.
- **Legacy HTTP cancellation is ignored.** Without sessions a `notifications/cancelled` request id is ambiguous across callers, so closing the connection is the only HTTP cancellation signal. Maintainer, from *2026-07-28 basic/patterns/cancellation*.

## Owner decisions

None open.

## Engineering questions

Open:

- **Strict-mode schema shape.** Should optional properties use OpenAI strict-mode shape (required and nullable), and which constraint keywords does strict mode accept today? Needs a live OpenAI strict-mode call plus Claude and Codex runs against the example server. Until answered, optional properties are omitted from `required` and constraint keywords are emitted.
- **Muse.** Which revision, headers, `Host` and `Origin` does Muse send through `tailscale serve`? Needs the owner to point Muse at the example server.
- **Codex tool calls.** Codex's non-interactive mode refuses MCP tool calls under its approval policy, so its `tools/call` request has not been observed. Needs one interactive run by the owner.

Answered on 2026-09-27 by experiment (captures and scripts were kept in the maintainer's scratch space; the results are recorded here):

- **What clients send.** Claude Code 2.1.283 probes `server/discover` first on HTTP and stdio and stays on 2026-07-28 when the server supports it; against a legacy-only server it falls back to `initialize` with 2025-11-25 and sends one GET, tolerating `405`. It sends lowercase `mcp-method`, `mcp-protocol-version` and `mcp-name`, no `Origin` and no session id. Codex CLI 0.155.0 never probes: it sends `initialize` with 2025-06-18 on both transports, `mcp-protocol-version` afterwards, and no `Mcp-Method` or `Mcp-Name`; its stdio `initialize` carries a nested experimental capability object. The OpenAI tunnel client 0.0.14 speaks 2026-07-28 over HTTP with canonical-case headers, probes eagerly with an empty POST and a GET, and requests `/.well-known/oauth-protected-resource`. No surveyed client sends 2025-03-26; the legacy Python SDK 1.9.4 does.
- **Claude Code fails silently on an invalid modern result.** A `tools/list` result missing `ttlMs` or `cacheScope` made Claude Code retry four times and then drop every tool without an error. Schema-contract tests of every emitted message are therefore essential, not optional.
- **Host and Origin.** Through a Unix socket `Host` is `localhost`, directly or via `tailscale serve`; `tailscale serve` to TCP sends the machine's tailnet name. `Origin` is passed through unchanged. Serve adds `Tailscale-User-Login`, `Tailscale-User-Name`, `Tailscale-User-Profile-Pic` and `X-Forwarded-*`, and strips the `--set-path` prefix.
- **Hummingbird 2.26 on a Unix socket.** Works, alone or together with 127.0.0.1 in one process, and `tailscale serve --set-path <path> unix:<socket>` reaches it. Hummingbird does not set socket permissions and silently replaces a socket held by a live server, so the adapter must set permissions and check for a live server before binding. A client disconnect, including through Serve, reaches a handler only through Hummingbird's inbound-close cancellation API; ordinary task cancellation does not happen. Bodies can be capped before buffering.
- **swift-syntax build cost.** swift-syntax resolves to 604.0.0 and is compiled from source: about 2 minutes 20 seconds for a clean build on the Intel Mac. Swift 6.1's experimental prebuilt option finds no prebuilt copy for 604.0.0 or 601.0.1 on this machine. Accepted as a one-time build cost for consumers.
- **Numbers.** Integers beyond double precision, up to the `Int64` limits, pass through a tool call exactly, and `3.0` is accepted as an integer (`NumberBoundaryTests`). Integers outside the `Int64` range and values such as `1e400` are rejected, but the issue has an empty path instead of the field's path; that is a defect to fix.
- **swift-json-schema error detail.** Its validation errors carry the keyword and both the instance and keyword locations, so every field of the argument error shape can be filled without forking it.
- **Conformance suite.** Version 0.2.0-alpha.11 is the first to cover 2026-07-28; the `latest` npm tag (0.1.16) covers only the older revisions, so the version must be pinned. Server mode tests HTTP only. Tool scenarios expect fixture tools with fixed names (for example `test_simple_text`, `test_error_handling`, `test_image_content`). Out-of-scope scenarios still check wire-schema validity, so the accepted-failures baseline is kept per check, not per scenario.
- **Interoperability clients.** Legacy: TypeScript `@modelcontextprotocol/sdk` 1.30.1 (2025-11-25) and Python `mcp` 1.9.4 (2025-03-26). Modern: TypeScript `@modelcontextprotocol/client` 2.1.0 with version negotiation pinned to 2026-07-28 (it defaults to legacy), and Python `mcp` 2.2.0 using `discover()`. MCP Inspector 2.8.0 runs headless with `--cli` and `--protocol-era legacy|auto|modern`.

## Toolchain

- Swift 6.1 (Xcode 16.4) is the current floor. Hummingbird is pinned to 2.26.0, the last release that builds with 6.1 (tools version checked per tag). Moving to Xcode 26 and Swift 6.2 allows Hummingbird 2.27 and later.
- Minimum macOS is 14, required by swift-json-schema's generated schemas.
