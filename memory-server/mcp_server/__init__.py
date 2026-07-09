"""mcp_server — MCP server package for loom's shared, Dolt-backed
memory server (epic loom-40ec, this bead loom-40ec.4.1).

Exposes a stdio-transport MCP server (see server.py) backed by the
production schema in ../schema.sql and a running `dolt sql-server`
(../scripts/start-server.sh). Tools are prefixed `memsrv_` during
parallel operation alongside the still-live `mempalace_*` tools —
final naming/config-swap is loom-40ec.6's job.
"""
