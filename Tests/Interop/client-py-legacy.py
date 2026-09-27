"""
Minimal client using the legacy-only official Python SDK (mcp==1.9.4 on
PyPI; LATEST_PROTOCOL_VERSION == "2025-03-26", zero 2026-07-28 support in
this release). Connects over Streamable HTTP, initializes, lists tools,
calls one.

Run: uv run --with mcp==1.9.4 python client-py-legacy.py <server url>
"""

import asyncio
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


async def main(url: str) -> None:
    async with streamablehttp_client(url) as (read, write, _get_session_id):
        async with ClientSession(read, write) as session:
            result = await session.initialize()
            print("[py-legacy] negotiated protocol version:", result.protocolVersion)
            print("[py-legacy] server info:", result.serverInfo)

            tools = await session.list_tools()
            print("[py-legacy] tools:", [t.name for t in tools.tools])

            call = await session.call_tool("test_simple_text", {})
            print("[py-legacy] call result:", call)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python client-py-legacy.py <server url>")
    target = sys.argv[1]
    asyncio.run(main(target))
