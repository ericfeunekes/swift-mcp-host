# Validation

A claim is proven at the boundary it describes. Reading the source, or a unit test of a helper, does not prove protocol, transport or client behavior.

## Layers

| Layer | Proves | How | Runs |
|---|---|---|---|
| Core | JSON-RPC parsing, every row of the revision selection table, dispatch, error classification, validation problem mapping | Swift tests against the pipeline with in-memory frames | Every change |
| Schema contract | Every message the server emits matches the official schema for its revision, and every successful `structuredContent` matches its tool's `outputSchema` | Validate outgoing messages from the example server against the vendored `schema.json` for 2025-03-26, 2025-06-18, 2025-11-25 and 2026-07-28, and each result against its tool's generated schema | Every change |
| Authoring rules | Tools missing descriptions, annotations or typed errors do not compile or do not register | Macro expansion and diagnostic tests; construction tests for runtime checks | Every change |
| Portable schema profile | Generated schemas stay inside the default profile unless a tool opts out | Check generated schemas for forbidden keywords and for `additionalProperties: false` on every object | Every change |
| HTTP boundary | Origin and host rejection, unknown identity, header checks and status codes per revision, body limit, `202`/`405`, no leakage between concurrent requests with colliding ids, cancellation on disconnect | A real Hummingbird server on loopback and on a Unix socket, driven by a real HTTP client | Every change |
| Stream boundary | Framing, message size limit, stdout discipline, end of input | The example server as a child process over pipes | Every change |
| Conformance | Behavior over HTTP matches the protocol as the maintainers test it | `npx @modelcontextprotocol/conformance@0.2.0-alpha.11 server --url …` against the example server, with a checked-in baseline of accepted failures and the reason for each | Before merge |
| Interoperability | Independent implementations of both eras can use the server | The pinned official clients in [`Tests/Interop`](../Tests/Interop/README.md), covering 2025-03-26, 2025-11-25 and 2026-07-28, each listing and calling the example server's tools over HTTP and stdio | Before merge |
| Client handshakes | Real client requests are accepted and answered correctly | The sanitized requests Claude Code, Codex and the OpenAI tunnel client sent to a capture server, in [`client-handshakes`](../Tests/MCPHostContractTests/Resources/client-handshakes/README.md), replayed through the pipeline and checked against the revision table and the official schemas | Every change |

## Rules

- Fixtures are synthetic. A fixture copied from a real client keeps its structure and replaces every value.
- The vendored MCP schemas record their source commit and license in [references](references.md).
- A failure in the conformance baseline needs a reason and a link to the requirement or decision that accepts it.
- A tool author's guarantee (for example "cannot register without a description") needs a test showing the failure, not only the success.
- Real-client proof (Claude Code, Codex, the OpenAI tunnel, Muse) belongs to each consumer, which has the real tools. The library proves the contract; the consumer proves the deployment.

## Conformance suite

- Pin the exact version. The `latest` npm tag (0.1.16) does not cover 2026-07-28; 0.2.0-alpha.11 does.
- Server mode tests only HTTP. The stream adapter is proven by the stream boundary and interoperability layers.
- The example server implements the suite's fixture tools that fall within scope, under the names the suite expects: `test_simple_text`, `test_error_handling`, `test_image_content`, `test_audio_content`, `test_embedded_resource` and `test_multiple_content_types`. Confirm the current list with the suite's `list` output before relying on it.
- Scenarios for out-of-scope capabilities (resources, prompts, completion, logging, sampling, elicitation, progress, tasks, SSE streams) are baselined. Baseline entries cite the [scope](requirements.md#scope) or the decision that excludes them. Where the suite reports individual checks, a scenario's wire-schema check must stay enforced even when its functional checks are baselined.
- A baseline entry for a scenario that now passes fails the run, so the baseline cannot go stale.

## Tool-level checks

- MCP Inspector 2.8.0 runs headless (`npx @modelcontextprotocol/inspector@2.8.0 --cli … --protocol-era legacy|auto|modern`). It is a convenient manual check and has a `--strict` schema-portability lint; it does not replace the layers above.

## Commands

| Layer | Command | State |
|---|---|---|
| Core, schema contract | `swift test` | Running: revision and identity rules, and the schema harness (every official 2026-07-28 example validates; a broken message fails; vendored revisions match supported revisions) |
| Pipeline | `swift test` (`PipelineTests`) | Running: envelope errors, every revision-selection row, unknown identity, status per era, notification acceptance, internal-failure redaction |
| Number boundary | `swift test` (`NumberBoundaryTests`) | Running: exact integers beyond double precision, integral decimals |
| Authoring rules | `swift test` (`MCPHostMacrosTests`) | Running: macro expansion and every diagnostic |
| Portable profile, argument errors, registration | `swift test` (`ToolRegistryTests`) | Running: prepared schemas, defaults, aggregated argument issues, tool errors, registration failures |
| HTTP and stream boundaries | `swift test` | Waits on the adapters |
| Conformance | `npx @modelcontextprotocol/conformance server --url <example server>` | Waits on the example server |
| Interoperability | Pinned TypeScript and Python clients | Waits on the example server |

CI runs `swift build --build-tests` and `swift test` on macOS with Xcode 16.4 (Swift 6.1).

## Schema harness notes

- 2025-06-18 is published as draft-07; the validator implements only 2020-12. The harness evaluates it as 2020-12, and a test proves that document uses none of the keywords whose meaning differs (`additionalItems`, `dependencies`, array-form `items`).
- The official examples exist only for 2026-07-28. Earlier revisions are checked through the messages the example server emits.
