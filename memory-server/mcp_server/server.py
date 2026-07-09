"""mcp_server/server.py — loom shared memory server, MCP scaffold
(loom-40ec.4.1).

SDK confirmation (per the bead brief's instruction to verify before
committing to an assumed API): the official MCP Python SDK is
published on PyPI as the `mcp` package (pinned here at 1.28.1 — the
current latest release as of 2026-07-09; the environment also had
1.27.0 pre-installed globally, same API). Its ergonomic server class
is `FastMCP`, imported as `from mcp.server.fastmcp import FastMCP` —
verified directly against the installed package (`inspect.signature`
on `FastMCP.__init__`/`.tool`/`.run`), NOT assumed from docs. Context7
docs for `/modelcontextprotocol/python-sdk` describe a newer
`mcp.server.mcpserver.MCPServer` class (`@mcp.tool()` /
`mcp.run()`-shaped, similar ergonomics) that does NOT exist in either
the installed 1.27.0 or the latest released 1.28.1 — that shape
appears to be from the SDK's in-progress main branch, not yet
released to PyPI. Verified by installing 1.28.1 into a scratch venv
and confirming `from mcp.server.mcpserver import MCPServer` raises
ModuleNotFoundError while `from mcp.server.fastmcp import FastMCP`
succeeds. Using FastMCP here as the actually-available, currently
correct API.

Exposed over stdio transport (`FastMCP.run(transport="stdio")`,
also FastMCP's default) — the transport Claude Code's MCP client
expects for a local server process.

Connects to the Dolt sql-server started by ../scripts/start-server.sh
via PyMySQL (see db.py) — host/port/database configurable via env vars
matching that script's conventions (LOOM_MEMORY_HOST, LOOM_MEMORY_PORT,
defaulting to 127.0.0.1:3307 / database doltdb).
"""
from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from mcp_server.tools.drawers import register_drawer_tools
from mcp_server.tools.kg import register_kg_tools
from mcp_server.tools.search import register_search_tools

SERVER_NAME = "loom-memory-server"


def create_server() -> FastMCP:
    """Build the FastMCP server instance with all tool groups
    registered. Split out from main() so tests can construct a server
    (e.g. to introspect registered tools) without also calling
    .run()."""
    mcp = FastMCP(SERVER_NAME)
    register_drawer_tools(mcp)
    register_search_tools(mcp)
    register_kg_tools(mcp)
    return mcp


def main() -> None:
    server = create_server()
    server.run(transport="stdio")


if __name__ == "__main__":
    main()
