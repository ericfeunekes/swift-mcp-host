# swift-mcp-host

A small Swift library for building tools-only [Model Context Protocol](https://modelcontextprotocol.io) servers that agents use well.

Tool authors write strict Swift types and handlers. The library turns them into the schemas, descriptions and results MCP clients understand, validates every call, and reports mistakes in a form an agent can act on. Good agent ergonomics are the default, not an option: a tool without descriptions, safety hints or typed errors does not register.

It is built for local macOS utilities that host their own engine (for example [messages-swift](https://github.com/ericfeunekes/messages-swift)) and expose it to Claude Code, Codex, the OpenAI Secure MCP Tunnel and tailnet clients through Tailscale Serve.

## Status

Contract written; implementation starting. The package builds and its schema harness runs, but no server behavior exists yet. Nothing is released.

## Development

Swift 6.1 or later on macOS 14 or later:

```sh
swift build --build-tests
swift test
```

[Validation](docs/validation.md#commands) lists what each test layer proves and what is still waiting.

## What it provides

- A transport-independent MCP core: JSON-RPC handling, version negotiation across supported protocol revisions, tool listing and tool calls.
- Typed tools: input and output schemas generated from the same Swift types that decode and validate.
- Agent-facing errors: every validation problem at once, each with a location, a stable type, the rejected input and a hint.
- Adapters: loopback or Unix-socket Streamable HTTP (Hummingbird) and newline-delimited streams (stdio and local sockets).
- A caller identity every request carries, resolved by the adapter from configuration the model cannot change.
- Extension points for resources, prompts, tasks, MCP Apps and authorization, designed but not implemented.

## Documentation

- [Requirements](docs/requirements.md): the contract, with spec citations.
- [Architecture](docs/architecture.md): targets, request pipeline and extension points.
- [Validation](docs/validation.md): the test suite and the proof each claim needs.
- [Decisions](docs/decisions.md): accepted choices and open questions.
- [References](docs/references.md): specifications, libraries and guidance used.
- [Consumers](docs/consumers.md): how a project that uses this library requests changes.
- [Agent guidance](AGENTS.md): how to work in this repository.

## License

[MIT](LICENSE).
