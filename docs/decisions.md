# Decisions

Accepted choices, owner decisions still open, and engineering questions a test or prototype can answer. A proposal stays a proposal until accepted.

## Accepted

- **Repository:** `swift-mcp-host`, public, personal account `ericfeunekes`. Owner.
- **License:** MIT, matching messages-swift. Owner to confirm.
- **Scope:** tools-only core; other capabilities designed for and deferred. Owner.
- **Protocol types:** owned by this library and decoded leniently, instead of the official Swift SDK's types. The SDK declares client experimental capabilities as `[String: String]`, which rejects valid nested JSON sent by ChatGPT, and it implements only 2025-11-25. Drift is controlled by validating output against the official schemas. Owner.
- **Agent ergonomics are mandatory:** descriptions, annotations and typed errors are required to register a tool; argument errors are aggregated and detailed in the style of Pydantic. Owner.
- **Argument validation errors are tool errors (`isError: true`), not `-32602`.** The spec classifies input validation errors as tool execution errors so models can self-correct (*2025-11-25 server/tools*, SEP-1303), while its example for a missing property uses `-32602`. Clients SHOULD show tool errors to the model but only MAY show protocol errors, so the tool-error reading serves self-correction. Reversible if a client mishandles it. Proposed by the maintainer, pending owner confirmation.
- **Caller identity is required** and comes from configuration the model cannot change. Owner.
- **Transports:** Streamable HTTP through Hummingbird, and newline-delimited streams. JSON responses only. Maintainer, from research.
- **Schema and validation engine:** swift-json-schema (schema builder, `@Schemable`, accumulated validation errors with JSON Pointers, 2020-12). Maintainer, from research.

## Owner decisions

- **Authoring API shape.** Macro-first (annotate a struct and its handler) or builder-first (declare fields in a result builder). A worked example of each will be shown before implementation.
- **Minimum description length** for tools, and whether it is a hard rule or a warning.
- **Consumer intake channel.** GitHub Issues with the consumer requirement form (current default), or also accepting requirement files in the repository.

## Engineering questions

- Which protocol revisions do Claude Code, Codex, the OpenAI tunnel client and Muse send today? Answer from their opening messages against the example server.
- Does Hummingbird 2.26 listen on a Unix domain socket in a way `tailscale serve unix:` can reach on macOS?
- Does the resolved swift-syntax version use the toolchain's prebuilt copy, or rebuild from source for consumers?
- Can swift-json-schema's validation output be mapped to every field of the argument error shape (`type`, `input`, `context`) without forking it?
- Does swift-json-schema's number handling preserve integer values exactly at the MCP boundary?
- Which validation keywords break OpenAI strict mode today? Confirm the portable profile against a live strict-mode call.

## Toolchain

- Swift 6.1 (Xcode 16.4) is the current floor. Hummingbird is pinned to 2.26.0, the last release that builds with 6.1. Moving to Xcode 26 and Swift 6.2 allows Hummingbird 2.27 and later.
- Minimum macOS is 14, required by swift-json-schema's generated schemas.
