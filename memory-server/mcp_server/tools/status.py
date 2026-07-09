"""mcp_server/tools/status.py — memsrv_status / memsrv_kg_stats tools
(loom-40ec.4.4).

  memsrv_status() -> dict
    {total_drawers, by_wing: {wing: count, ...}, by_room: {room: count, ...},
     dolt_reachable: bool}

  memsrv_kg_stats() -> dict
    {entity_count, triple_count}

memsrv_status mirrors the real mempalace_status tool's shape MINUS
anything chroma/sqlite-specific (this is a Dolt backend, not chroma):
the "backend health" concept is replaced with a cheap Dolt-appropriate
check (`SELECT 1`) plus a `dolt_reachable` boolean. status() is meant
to be a health-check tool, so it degrades gracefully rather than
raising -- a connection failure (dolt sql-server down/unreachable)
returns `dolt_reachable: False` with empty counts instead of
propagating the exception.

memsrv_kg_stats is a thin wrapper: if the sibling bead loom-40ec.4.3
(KG tools) has landed, mcp_server/tools/kg.py exists with a
graph_stats() function that this delegates to directly. If not (the
sibling hasn't merged yet), a minimal standalone implementation runs
a direct query against kg_triples. The import is attempted at CALL
time (not module import time) so this module works correctly whether
loaded before or after kg.py lands -- no code change needed here once
the sibling merges, the delegation just starts firing.
"""
from __future__ import annotations

from mcp_server.db import connect


def status() -> dict:
    """Cheap Dolt-backed health/stats check. Never raises: any
    connection or query failure is caught and reported as
    `dolt_reachable: False` with empty counts, since this tool exists
    precisely to answer "is the backend healthy" even when it isn't.
    """
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cur:
            # Connectivity check, per the bead brief.
            cur.execute("SELECT 1")
            cur.fetchone()

            cur.execute("SELECT COUNT(*) AS total FROM drawers")
            total_drawers = cur.fetchone()["total"]

            cur.execute("SELECT wing, COUNT(*) AS cnt FROM drawers GROUP BY wing")
            by_wing = {row["wing"]: row["cnt"] for row in cur.fetchall()}

            cur.execute("SELECT room, COUNT(*) AS cnt FROM drawers GROUP BY room")
            by_room = {row["room"]: row["cnt"] for row in cur.fetchall()}

        return {
            "dolt_reachable": True,
            "total_drawers": total_drawers,
            "by_wing": by_wing,
            "by_room": by_room,
        }
    except Exception:  # noqa: BLE001 - deliberately broad: a health
        # check must degrade gracefully on ANY failure mode (refused
        # connection, timeout, query error on a half-provisioned DB),
        # not just a specific exception type.
        return {
            "dolt_reachable": False,
            "total_drawers": 0,
            "by_wing": {},
            "by_room": {},
        }
    finally:
        if conn is not None:
            conn.close()


def _standalone_graph_stats() -> dict:
    """Minimal kg_stats implementation used when the sibling
    loom-40ec.4.3 bead's tools/kg.py has not landed yet:
    entity_count = COUNT(DISTINCT subject UNION DISTINCT object),
    triple_count = COUNT(*), both against kg_triples directly."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS triple_count FROM kg_triples")
            triple_count = cur.fetchone()["triple_count"]

            cur.execute(
                "SELECT COUNT(*) AS entity_count FROM ("
                "SELECT subject AS entity FROM kg_triples "
                "UNION "
                "SELECT object AS entity FROM kg_triples"
                ") AS entities"
            )
            entity_count = cur.fetchone()["entity_count"]
    finally:
        conn.close()

    return {"entity_count": entity_count, "triple_count": triple_count}


def kg_stats() -> dict:
    """Thin wrapper: delegates to mcp_server.tools.kg.graph_stats() if
    that sibling module has landed (loom-40ec.4.3), else falls back to
    a minimal standalone implementation. The import is attempted at
    call time so this keeps working correctly regardless of merge
    order between this bead and the sibling."""
    try:
        from mcp_server.tools.kg import graph_stats
    except ImportError:
        return _standalone_graph_stats()
    return graph_stats()


def register_status_tools(mcp) -> None:
    """Register the status + kg-stats tools on a FastMCP server
    instance, prefixed `memsrv_`."""
    mcp.tool(name="memsrv_status")(status)
    mcp.tool(name="memsrv_kg_stats")(kg_stats)
