# Decisions

Accepted choices, owner decisions still open, and engineering questions a test or prototype can answer. A proposal stays a proposal until accepted.

## Accepted

- **Repository:** `swift-mcp-host`, public, personal account `ericfeunekes`. Owner.
- **Scope:** tools-only core; other capabilities designed for and deferred. Owner.
- **Protocol types:** owned by this library and decoded leniently, instead of the official Swift SDK's. The SDK declares client experimental capabilities as `[String: String]`, which rejects the valid nested JSON ChatGPT sends, and implements only 2025-11-25. Drift is controlled by validating output against the official schemas. Owner.
- **Agent ergonomics are mandatory:** descriptions, annotations and typed errors are required to register a tool, and argument errors are aggregated and detailed in the style of Pydantic. Owner.
- **Caller identity is required** and comes from configuration the model cannot change. It is a label, not authentication. Owner requirement; the label reading is the maintainer's, because an unauthenticated tailnet or loopback caller can present any value.
- **Dual-era server.** One endpoint serves 2026-07-28 statelessly and 2025-11-25 and 2025-06-18 through `initialize`, without HTTP sessions. Maintainer, from *2026-07-28 basic/versioning*.
- **Transports:** Streamable HTTP through Hummingbird, and newline-delimited streams. JSON responses only. Maintainer, from research.
- **Schema and validation engine:** swift-json-schema (schema builder, `@Schemable`, accumulated validation errors with JSON Pointers, 2020-12). Maintainer, from research.
- **Error results and `outputSchema`.** The spec's rule that structured results conform to the output schema is read as applying to successful results. Error results carry the library's error shape instead. The official TypeScript and Python clients skip output validation when `isError` is set. Maintainer.
- **Legacy HTTP cancellation is ignored.** Without sessions a `notifications/cancelled` request id is ambiguous across callers, so closing the connection is the only HTTP cancellation signal. Maintainer, from *2026-07-28 basic/patterns/cancellation*.

## Owner decisions

- **License.** MIT is in place, matching messages-swift.
- **Argument errors as tool errors under every revision.** Proposed: return schema and type failures as `isError: true` results with the detailed error shape. Basis: SEP-1303 (2025-11-25) classifies input validation errors as tool execution errors so models can self-correct, and clients SHOULD show tool errors to the model but only MAY show protocol errors. Deviations: the spec's own `-32602` example for a missing property, and 2025-06-18, which listed invalid arguments as a protocol error.
- **2025-03-26 support.** Adding it means accepting HTTP requests without `MCP-Protocol-Version` and receiving batches. Decide after the client survey in [engineering questions](#engineering-questions); messages-swift's own tests currently initialize with 2025-03-26.
- **Authoring API shape.** Macro-first (annotate a struct and its handler) or builder-first (declare fields in a result builder). A worked example of each will be shown before implementation.
- **Minimum description length** for tools, and whether it is a hard rule or a warning.
- **Consumer intake channel.** GitHub Issues (current default), or also requirement files in the repository.

## Engineering questions

- Which protocol revisions and headers do Claude Code, Codex, the OpenAI tunnel client and Muse send today? Answer from their opening requests against the example server.
- Which `Host` and `Origin` values arrive through Tailscale Serve, the OpenAI tunnel client and a Unix socket? The configured allow lists depend on it.
- Does Hummingbird 2.26 listen on a Unix domain socket in a way `tailscale serve unix:` can reach on macOS?
- Should optional properties use OpenAI strict-mode shape (required and nullable)? Which constraint keywords (`minLength`, `pattern`, `format` and others) does strict mode accept today? Test with a live strict-mode call and with Claude and Codex, then fix the portable profile.
- Does the resolved swift-syntax version use the toolchain's prebuilt copy, or rebuild from source for consumers?
- Can swift-json-schema's validation output supply every field of the argument error shape (`type`, `input`, `context`) without forking it?
- Does swift-json-schema's number handling preserve integer values exactly at the MCP boundary?

## Toolchain

- Swift 6.1 (Xcode 16.4) is the current floor. Hummingbird is pinned to 2.26.0, the last release that builds with 6.1 (tools version checked per tag). Moving to Xcode 26 and Swift 6.2 allows Hummingbird 2.27 and later.
- Minimum macOS is 14, required by swift-json-schema's generated schemas.
