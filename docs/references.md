# References

Sources behind the requirements, checked on 2026-09-26. Re-check a source before relying on it for a new requirement.

## Model Context Protocol

- Specification, current revision 2026-07-28: <https://modelcontextprotocol.io/specification/2026-07-28/>. Earlier supported revisions: [2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/), [2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18/).
- Specification source, schemas and examples: <https://github.com/modelcontextprotocol/modelcontextprotocol> (`schema/<revision>/schema.ts`, `schema.json`, `examples/`; `docs/specification/<revision>/`). Vendored schemas will record the commit they were taken from.
- 2026-07-28 changelog: <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/changelog.mdx>. Release candidate notes: <https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/>.
- SEPs cited: SEP-986 tool names, SEP-973 icons and metadata, SEP-1303 input validation errors, SEP-1613 JSON Schema 2020-12, SEP-2106 schema composition and any-JSON structured content, SEP-2133 extensions, SEP-2243 routing headers, SEP-2322 multi-round-trip results, SEP-2549 list caching, SEP-2575 statelessness.
- Conformance suite: <https://github.com/modelcontextprotocol/conformance> (`npx @modelcontextprotocol/conformance server --url <url>`).
- Official Swift SDK, for comparison: <https://github.com/modelcontextprotocol/swift-sdk> (0.12.1, implements 2025-11-25).

## Libraries

- swift-json-schema (MIT): <https://github.com/ajevans99/swift-json-schema>. 0.14.1, Swift tools 6.1, macOS 14, JSON Schema 2020-12, Bowtie-tracked.
- swift-mcp-toolkit (prior art, not a dependency): <https://github.com/ajevans99/swift-mcp-toolkit>. Connects `@Schemable` types to the official SDK; documents a lossless number conversion policy worth matching.
- Hummingbird: <https://github.com/hummingbird-project/hummingbird>. 2.26.0 is the last release with Swift tools 6.1.
- SwiftMCP (prior art): <https://github.com/Cocoanetics/SwiftMCP>. Macro-based; parses doc comments into descriptions.
- iMCP (prior art): <https://github.com/loopwork-ai/iMCP>. A macOS app exposing Messages and other data over stdio MCP.

## Agent-facing guidance

- Anthropic, Writing effective tools for agents: <https://www.anthropic.com/engineering/writing-tools-for-agents>.
- Anthropic tool-use best practices: <https://docs.claude.com/en/docs/agents-and-tools/tool-use/implement-tool-use>.
- OpenAI function calling and strict mode: <https://platform.openai.com/docs/guides/function-calling>, <https://platform.openai.com/docs/guides/structured-outputs>.
- OpenAI tool planning guide: <https://developers.openai.com/plugins/plan/tools>.
- Pydantic validation errors, the model for the argument error shape: <https://docs.pydantic.dev/latest/errors/errors/>.

## Clients and transport

- Claude remote connectors: <https://claude.com/docs/connectors/custom/remote-mcp>.
- OpenAI Secure MCP Tunnel: <https://developers.openai.com/api/docs/guides/secure-mcp-tunnels>.
- Tailscale Serve: <https://tailscale.com/kb/1312/serve>.

## Known client issues to guard against

These are reports, not specifications, and may already be fixed:

- A client failing calls to tools that declare `outputSchema` but return no `structuredContent`.
- Claude Code dropping or not calling tools with an `outputSchema`, and rejecting a draft-07 `$schema`.
- Cursor rejecting valid 2020-12 tuple schemas.
