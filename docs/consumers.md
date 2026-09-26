# Consumers

A consumer is a project that builds an MCP server with this library. Consumers bring real needs; this library turns the ones that belong in a shared contract into requirements.

## Current consumers

| Consumer | Uses | Notes |
|---|---|---|
| [messages-swift](https://github.com/ericfeunekes/messages-swift) | Core, HTTP, stream | Apple Messages. Stdio bridge for Claude Code and Codex, the OpenAI tunnel, and HTTP through Tailscale Serve for Muse. |

Add a row when a new consumer starts depending on the library.

## What belongs here

A request belongs in this library when it is true for every consumer:

- protocol behavior: revisions, methods, transports, headers, errors;
- how tools are declared, validated, described or rendered for agents;
- caller identity, request stages and other cross-cutting pipeline behavior;
- an MCP capability or extension more than one consumer could use.

It belongs in the consumer when it is about that consumer's domain: which tools exist, their names and descriptions, business rules, permissions, process lifetime, supervision and deployment. When in doubt, file it; triage will say which.

## Requesting a change

Open a GitHub Issue at <https://github.com/ericfeunekes/swift-mcp-host/issues> with the **Consumer requirement** form. An agent may file with the GitHub CLI instead, using a body with exactly these headings, each filled in:

```markdown
### Consumer
### Need
### Why the library
### Contract example
### Clients
### Spec basis
### Proof available
```

- **Consumer:** which project needs it.
- **Need:** what the agent or user must be able to do, as an outcome rather than an API.
- **Why the library:** why it meets the criteria above.
- **Contract example:** the MCP request, the expected result or error, and the protocol revision, as JSON.
- **Clients:** which clients must work with it.
- **Spec basis:** the MCP section, SEP or client documentation it relies on, or "none".
- **Proof available:** what the consumer can run to show it works.

For example: `gh issue create --repo ericfeunekes/swift-mcp-host --label consumer-request --title "[consumer] <summary>" --body-file request.md`.

Use synthetic values only: no real user data, credentials or hostnames.

## From request to requirement

1. **Triage.** The maintainer adds one label and a comment with the reason:
   - `accepted`: it belongs here and will be specified;
   - `needs-decision`: it depends on an owner choice, recorded in [decisions](decisions.md);
   - `consumer-owned`: it belongs in the consumer, with a pointer to how the consumer can do it with the current library.
2. **Decide.** An owner choice is recorded in [decisions](decisions.md) before anything depends on it. An engineering question gets a test or prototype.
3. **Specify.** An accepted request becomes text in [requirements](requirements.md) under a heading, with its citation. Extensions go through the [extension points](architecture.md#extension-points).
4. **Prove.** The change lands with the proof [validation](validation.md) requires for that layer.
5. **Close.** The issue links to the requirement heading and the change.

## Compatibility for consumers

- Until 1.0, minor versions may change the public API. Each release notes the change and the migration.
- The error result shape and the caller identity rules are part of the public contract. Changes to them are called out in release notes even before 1.0.
