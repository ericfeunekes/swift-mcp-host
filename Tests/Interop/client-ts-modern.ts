/**
 * Minimal client using the modern, split official TypeScript SDK package
 * (@modelcontextprotocol/client@2.1.0), pinned to 2026-07-28. Connects over
 * Streamable HTTP, lists tools, calls one, and calls server/discover.
 *
 * Note: even this newer package defaults its `versionNegotiation.mode` to
 * 'legacy' (byte-identical to the 2025 handshake). Pinning is required to
 * exercise the modern per-request _meta path.
 *
 * Run: npx tsx client-ts-modern.ts <server url>
 */
import { Client } from '@modelcontextprotocol/client';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/client';

if (!process.argv[2]) throw new Error('usage: tsx client-ts-modern.ts <server url>');
const url = new URL(process.argv[2]);

const client = new Client(
  { name: 'interop-client-ts-modern', version: '1.0.0' },
  { versionNegotiation: { mode: { pin: '2026-07-28' } } }
);
const transport = new StreamableHTTPClientTransport(url);

await client.connect(transport);
console.log('[ts-modern] connected.');

const discover = client.getDiscoverResult?.();
console.log('[ts-modern] discover result:', JSON.stringify(discover));

const tools = await client.listTools();
console.log('[ts-modern] tools:', tools.tools.map((t) => t.name));

const result = await client.callTool({ name: 'test_simple_text', arguments: {} });
console.log('[ts-modern] call result:', JSON.stringify(result));

await client.close();
