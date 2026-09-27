# Interoperability clients

Official SDK clients used to prove that independent implementations of both protocol eras can use a swift-mcp-host server. See [validation](../../docs/validation.md#layers).

| Script | Client | Revision |
|---|---|---|
| `client-ts-legacy.ts` | `@modelcontextprotocol/sdk` 1.30.1 | 2025-11-25 via `initialize` |
| `client-ts-modern.ts` | `@modelcontextprotocol/client` 2.1.0, negotiation pinned to 2026-07-28 | 2026-07-28 |
| `client-py-legacy.py` | `mcp` 1.9.4 | 2025-03-26 via `initialize` |
| `client-py-modern.py` | `mcp` 2.2.0 using `discover()` | 2026-07-28 |

Each takes the server URL as its only argument, lists tools and calls `test_simple_text`. They were verified against the official TypeScript reference server over Streamable HTTP on 2026-09-27. They are not yet wired to the example server, stdio or CI; that is tracked as an Issue.

```sh
npm ci --prefix Tests/Interop
npx --prefix Tests/Interop tsx Tests/Interop/client-ts-modern.ts http://127.0.0.1:PORT/c/test/mcp
uv run --with mcp==2.2.0 python Tests/Interop/client-py-modern.py http://127.0.0.1:PORT/c/test/mcp
```
