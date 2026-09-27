/**
 * Minimal client using the legacy-only official TypeScript SDK
 * (@modelcontextprotocol/sdk@1.30.1, LATEST_PROTOCOL_VERSION = "2025-11-25",
 * no 2026-07-28 support at all). Connects over Streamable HTTP, lists tools,
 * calls one.
 *
 * Run: npx tsx client-ts-legacy.ts
 */
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

if (!process.argv[2]) throw new Error('usage: tsx client-ts-legacy.ts <server url>');
const url = new URL(process.argv[2]);

const client = new Client({ name: 'interop-client-ts-legacy', version: '1.0.0' });
const transport = new StreamableHTTPClientTransport(url);

await client.connect(transport);
console.log('[ts-legacy] connected. Negotiated protocol version:', client.getServerVersion?.() ?? '(n/a)');

const tools = await client.listTools();
console.log('[ts-legacy] tools:', tools.tools.map((t) => t.name));

const result = await client.callTool({ name: 'test_simple_text', arguments: {} });
console.log('[ts-legacy] call result:', JSON.stringify(result));

await client.close();
