# Validation

A claim is proven at the boundary it describes. Reading the source, or a unit test of a helper, does not prove protocol, transport or client behavior.

## Layers

| Layer | Proves | How | Runs |
|---|---|---|---|
| Core | JSON-RPC parsing, version negotiation, dispatch, error classification, validation problem mapping | Swift tests against the pipeline with in-memory frames | Every change |
| Schema contract | Every message the server emits matches the official schema for its revision | Validate outgoing messages from the example server against the vendored `schema.json` for 2025-06-18, 2025-11-25 and 2026-07-28 | Every change |
| Authoring rules | Tools missing descriptions, annotations or typed errors do not compile or do not register | Macro expansion and diagnostic tests; construction tests for runtime checks | Every change |
| Portable schema profile | Generated schemas stay inside the default profile unless a tool opts out | Check generated schemas for forbidden keywords and for `additionalProperties: false` on every object | Every change |
| HTTP boundary | Origin and host rejection, header checks, body limit, `202`/`405`, no leakage between concurrent requests with colliding ids, cancellation on disconnect | A real Hummingbird server on loopback and on a Unix socket, driven by a real HTTP client | Every change |
| Stream boundary | Framing, message size limit, stdout discipline, end of input | The example server as a child process over pipes | Every change |
| Conformance | Behavior matches the protocol as the maintainers test it | `npx @modelcontextprotocol/conformance server --url …` against the example server, with a checked-in baseline of accepted failures and the reason for each | Before merge |
| Interoperability | Independent implementations can use the server | The official TypeScript and Python SDK clients list and call the example server's tools over HTTP and stdio | Before merge |
| Client handshakes | Real client opening messages are accepted | Synthetic fixtures in the shape each supported client sends, including nested experimental capabilities | Every change |

## Rules

- Fixtures are synthetic. A fixture copied from a real client keeps its structure and replaces every value.
- The vendored MCP schemas record their source commit and license in [references](references.md).
- A failure in the conformance baseline needs a reason and a link to the requirement or decision that accepts it.
- A tool author's guarantee (for example "cannot register without a description") needs a test showing the failure, not only the success.
- Real-client proof (Claude Code, Codex, the OpenAI tunnel, Muse) belongs to each consumer, which has the real tools. The library proves the contract; the consumer proves the deployment.

## Commands

To be added with the package. Each layer above gets one named command.
