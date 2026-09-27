"""
Minimal client using the modern-capable official Python SDK (mcp==2.2.0 on
PyPI, ships alongside the mcp_types companion package with
MODERN_PROTOCOL_VERSIONS == ("2026-07-28",)). Connects over Streamable HTTP,
probes+adopts the modern era via ClientSession.discover() (a wrapper around
send_discover()+adopt()), lists tools, calls one.

Note the Python SDK has no single declarative "mode" like the TS client's
versionNegotiation option: the caller explicitly chooses discover() (modern)
vs initialize() (legacy) per connection.

Run: uv run --with mcp==2.2.0 python client-py-modern.py <server url>
"""

import asyncio
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


async def main(url: str) -> None:
    async with streamable_http_client(url) as (read, write):
        async with ClientSession(read, write) as session:
            discover_result = await session.discover()
            print("[py-modern] supported versions:", discover_result.supported_versions)
            print("[py-modern] server capabilities:", discover_result.capabilities)

            tools = await session.list_tools()
            print("[py-modern] tools:", [t.name for t in tools.tools])

            call = await session.call_tool("test_simple_text", {})
            print("[py-modern] call result:", call)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python client-py-modern.py <server url>")
    target = sys.argv[1]
    asyncio.run(main(target))
