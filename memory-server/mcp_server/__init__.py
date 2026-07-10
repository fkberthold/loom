"""mcp_server — MCP server package for loom's shared, Dolt-backed
memory server (epic loom-40ec, this bead loom-40ec.4.1).

Exposes a stdio-transport MCP server (see server.py) backed by the
production schema in ../schema.sql and a running `dolt sql-server`
(../scripts/start-server.sh). Tools are prefixed `mempalace_`,
matching the retired MemPalace/chroma system's tool names exactly
(loom-40ec.6.4 cutover) for full backward compatibility with every
existing skill/hook/doc reference across loom.
"""
