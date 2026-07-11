"""mcp_server/tools/tags.py — drawer tagging tools (loom-40ec.4.5.2).

Three tools, prefixed `mempalace_` (matching tools/drawers.py's,
tools/search.py's, and tools/kg.py's naming convention):

  mempalace_tag_drawer(drawer_id, tag) -> None
  mempalace_untag_drawer(drawer_id, tag) -> None
  mempalace_list_tags(drawer_id) -> list[str]

Backed by the `drawer_tags` join table (schema.sql): a plain
(drawer_id, tag) composite-primary-key table with no metadata beyond
`created_at`. This is FRESH design — no upstream reference
implementation existed. The contract lives in MemPalace decision
drawer drawer_loom_decisions_350baa9c115ba358532a8e00 section 2 and on
bd loom-40ec.4.5.2.

Each function below is a plain, directly-callable Python function
(importable and testable without going through the MCP/stdio
protocol) — same pattern as tools/drawers.py / tools/search.py /
tools/kg.py. `register_tag_tools()` registers thin wrappers around
them on a FastMCP server instance.
"""
from __future__ import annotations

from mcp_server.db import connect


def tag_drawer(drawer_id: str, tag: str) -> None:
    """Apply `tag` to `drawer_id`. Idempotent: re-tagging with the same
    (drawer_id, tag) pair is a no-op, not an error or a duplicate —
    the composite PK (drawer_id, tag) makes the ON DUPLICATE KEY
    branch fire on re-tag."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO drawer_tags (drawer_id, tag, created_at) "
                "VALUES (%s, %s, NOW()) "
                "ON DUPLICATE KEY UPDATE created_at = created_at",
                (drawer_id, tag),
            )
    finally:
        conn.close()

    return None


def untag_drawer(drawer_id: str, tag: str) -> None:
    """Remove `tag` from `drawer_id`. Idempotent: removing a tag that
    was never applied (or already removed) is a no-op, not an error —
    DELETE is naturally idempotent regardless of rows affected."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM drawer_tags WHERE drawer_id = %s AND tag = %s",
                (drawer_id, tag),
            )
    finally:
        conn.close()

    return None


def list_tags(drawer_id: str) -> list[str]:
    """Return all tags applied to `drawer_id` as a plain list[str]
    (empty list if the drawer has never been tagged)."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT tag FROM drawer_tags WHERE drawer_id = %s",
                (drawer_id,),
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    return [row["tag"] for row in rows]


def register_tag_tools(mcp) -> None:
    """Register the three drawer-tagging tools on a FastMCP server
    instance, prefixed `mempalace_`."""
    mcp.tool(name="mempalace_tag_drawer")(tag_drawer)
    mcp.tool(name="mempalace_untag_drawer")(untag_drawer)
    mcp.tool(name="mempalace_list_tags")(list_tags)
