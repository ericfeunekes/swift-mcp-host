# Consumers

A consumer is a project that builds an MCP server with this library. Consumers bring real needs; this library turns the ones that belong in a shared contract into requirements.

## Current consumers

| Consumer | Uses | Notes |
|---|---|---|
| [messages-swift](https://github.com/ericfeunekes/messages-swift) | Core, HTTP, stream | Apple Messages. Stdio bridge for Claude Code and Codex, the OpenAI tunnel, and HTTP through Tailscale Serve for Muse. |

Add a row when a new consumer starts depending on the library.

## Requesting a change

Open a GitHub Issue with the **Consumer requirement** form. A complete request states:

- **Consumer:** which project needs it.
- **Need:** what the agent or user must be able to do, in outcome terms, not the proposed API.
- **Why the library:** why this belongs in the shared contract rather than in the consumer. Tool-specific behavior stays in the consumer.
- **Contract example:** the MCP messages involved: a request, the expected result or error, and which protocol revision.
- **Clients:** which clients must work with it.
- **Spec basis:** the MCP section, SEP or client documentation it relies on, if any.
- **Proof available:** what the consumer can run to show it works.

An agent working on a consumer can file the request directly. Keep real user data, credentials and hostnames out of the example; use synthetic values.

## From request to requirement

1. **Triage.** The maintainer labels the request `accepted`, `needs-decision` or `consumer-owned`, and says why.
2. **Decide.** An owner choice is recorded in [decisions](decisions.md) before anything depends on it. An engineering question gets a test or prototype.
3. **Specify.** An accepted request becomes text in [requirements](requirements.md) with its citation. Extensions go through the [extension points](architecture.md#extension-points).
4. **Prove.** The change lands with the proof [validation](validation.md) requires for that layer.
5. **Close.** The issue links to the requirement and the change.

## Compatibility for consumers

- Until 1.0, minor versions may change the public API. Each release notes the change and the migration.
- The argument error shape and caller identity rules are part of the public contract; changing them is called out in the release notes even before 1.0.
