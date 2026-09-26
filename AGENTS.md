# swift-mcp-host

A Swift library for tools-only MCP servers whose defaults make tools easy for agents to use. Read [requirements](docs/requirements.md) before changing behavior and [architecture](docs/architecture.md) before adding code, targets or dependencies.

- Consumer requests arrive through the [consumer process](docs/consumers.md). A request is not a requirement until it is accepted into [requirements](docs/requirements.md). Record unresolved scope in [decisions](docs/decisions.md); separate an owner decision from an engineering question a test can answer.
- Every protocol rule in the requirements cites the MCP revision and section it comes from. When the spec is ambiguous, record the reading chosen and why in [decisions](docs/decisions.md).
- Agent ergonomics are defaults, not options. Do not add a path that registers a tool, field or error without a description, or that emits an untyped error.
- The core is transport-independent. Adapters own transport and caller identity; they do not own naming, schemas, validation or error rendering.
- Extensions are designed for but not implemented. Add one only through an accepted requirement.
- Follow [validation](docs/validation.md). Source inspection is not runtime proof. Contract claims need schema validation against the official MCP schemas and a run of the official conformance suite; client claims need that client.
- Test fixtures are synthetic. Do not commit captured traffic that contains real user data, credentials or hostnames.
- Scratch work belongs in ignored `.scratch/`.
- When behavior changes, update its owning document and its proof in the same change.
