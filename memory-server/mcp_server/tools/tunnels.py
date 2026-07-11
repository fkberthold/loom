"""mcp_server/tools/tunnels.py — cross-project TUNNEL tools
(loom-40ec.4.5.1).

P0 root-cause fix for the post-cutover "system got dumber" regression:
loom's CLAUDE.md documents explicit cross-project tunnels
(loom/decisions <-> hundred_acre_woods/decisions) as a core
convention, but the new Dolt-backed memory server never implemented
tunnels, so cross-project context silently stopped surfacing after the
2026-07-10 MemPalace cutover. Locked design: MemPalace decision drawer
drawer_loom_decisions_350baa9c115ba358532a8e00 section 1.

Seven tools, prefixed `mempalace_` (matching tools/drawers.py's and
tools/kg.py's naming convention). NOTE the one exception:
`graph_stats()` is registered as `mempalace_tunnel_graph_stats`, NOT
`mempalace_graph_stats` — tools/kg.py already registers that exact
name for unrelated knowledge-graph stats (triple_count, entity_count,
...); this module's `graph_stats` is a same-named-but-distinct Python
function reporting on the passive/derived cross-wing room graph, and
the rename avoids the MCP server-registration collision. See
register_tunnel_tools()'s docstring.

  mempalace_create_tunnel(source_wing, source_room, target_wing,
                        target_room, label='', source_drawer_id=None,
                        target_drawer_id=None) -> str
  mempalace_list_tunnels(wing=None) -> list[dict]
  mempalace_delete_tunnel(tunnel_id) -> dict
  mempalace_follow_tunnels(wing, room) -> list[dict]
  mempalace_find_tunnels(wing_a=None, wing_b=None) -> list[dict]
  mempalace_traverse_graph(start_room, max_hops=2) -> list[dict]
  mempalace_tunnel_graph_stats() -> dict  (Python name: graph_stats)

Each function below is a plain, directly-callable Python function
(importable and testable without going through the MCP/stdio
protocol) — same pattern as tools/drawers.py and tools/kg.py.
`register_tunnel_tools()` registers thin wrappers around them on a
FastMCP server instance; `mcp.tool()(fn)` returns the SAME function
object it decorates (verified in tools/drawers.py's module docstring),
so the registered tool and the plain function are identical.

Tunnels are symmetric: `create_tunnel(A, B)` and `create_tunnel(B, A)`
(same two endpoints, reversed) collide onto the SAME deterministic id
(see `_canonical_tunnel_id`) and UPSERT the same row rather than
creating a duplicate — `list_tunnels`/`follow_tunnels` both check
EITHER side against the caller's filter for this reason.

Alongside the EXPLICIT tunnels table, this module also supports
PASSIVE/DERIVED tunnels: `find_tunnels()`/`traverse_graph()` derive
cross-project links directly from the live `drawers` table — any room
name present under >=2 distinct wings is treated as an implicit
cross-project connection, with no `tunnels` row required. This is the
"passive" half of the bead title (explicit + passive/derived).
"""
from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Any

from mcp_server.db import connect


def _canonical_tunnel_id(wing_a: str, room_a: str, wing_b: str, room_b: str) -> str:
    """Deterministic, symmetric tunnel id: build the two "wing/room"
    endpoint strings, sort the pair (so (A,B) and (B,A) produce the
    IDENTICAL input), join with "|", sha256, and take the first 16 hex
    characters of the hexdigest. Symmetry here is what makes
    create_tunnel's upsert work regardless of argument order."""
    endpoint_a = f"{wing_a}/{room_a}"
    endpoint_b = f"{wing_b}/{room_b}"
    joined = "|".join(sorted([endpoint_a, endpoint_b]))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]


def _jsonify(value: Any) -> Any:
    """MCP tool results get JSON-serialized; convert non-JSON-native
    types (datetime) coming back from the DB driver. Local copy —
    mirrors tools/drawers.py's/tools/kg.py's `_jsonify` (each module
    treats it as a private module-level helper, not shared)."""
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _serialize_row(row: dict) -> dict:
    return {key: _jsonify(value) for key, value in row.items()}


def _validate_endpoint_has_drawer(cur, wing: str, room: str) -> None:
    """Raise ValueError if (wing, room) has zero rows in the live
    `drawers` table. Callers wrap this in a try/except that re-raises
    ONLY ValueError and swallows everything else (connection errors,
    etc.) — per the design's fail-open posture, an infra failure
    during validation must not block tunnel creation."""
    cur.execute(
        "SELECT COUNT(*) AS cnt FROM drawers WHERE wing = %s AND room = %s",
        (wing, room),
    )
    count = cur.fetchone()["cnt"]
    if count == 0:
        raise ValueError(f"tunnel endpoint {wing}/{room} has no drawers")


def create_tunnel(
    source_wing: str,
    source_room: str,
    target_wing: str,
    target_room: str,
    label: str = "",
    source_drawer_id: str | None = None,
    target_drawer_id: str | None = None,
) -> str:
    """Create (or upsert) an explicit tunnel between two (wing, room)
    endpoints. Validates BOTH endpoints have >=1 drawer in the live
    drawers table before creating — but if the validation QUERY ITSELF
    raises (e.g. a connection hiccup), validation is skipped and
    creation proceeds rather than blocking on an infra failure.

    The tunnel id is deterministic and symmetric (see
    `_canonical_tunnel_id`): calling this again with the SAME two
    endpoints in EITHER order upserts the same row, with the LATEST
    call's argument order winning which side is recorded as "source"
    vs "target" (fine, since tunnels are symmetric and every reader
    checks both sides). `kind` is always 'explicit' for this bead.
    """
    tunnel_id = _canonical_tunnel_id(source_wing, source_room, target_wing, target_room)

    conn = connect()
    try:
        with conn.cursor() as cur:
            try:
                _validate_endpoint_has_drawer(cur, source_wing, source_room)
                _validate_endpoint_has_drawer(cur, target_wing, target_room)
            except ValueError:
                raise
            except Exception:  # noqa: BLE001 - fail-open on infra failure, by design
                pass

            cur.execute(
                "INSERT INTO tunnels "
                "(id, source_wing, source_room, source_drawer_id, "
                " target_wing, target_room, target_drawer_id, label, kind, created_at) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'explicit', NOW()) "
                "ON DUPLICATE KEY UPDATE "
                "source_wing=VALUES(source_wing), source_room=VALUES(source_room), "
                "source_drawer_id=VALUES(source_drawer_id), "
                "target_wing=VALUES(target_wing), target_room=VALUES(target_room), "
                "target_drawer_id=VALUES(target_drawer_id), label=VALUES(label)",
                (
                    tunnel_id,
                    source_wing,
                    source_room,
                    source_drawer_id,
                    target_wing,
                    target_room,
                    target_drawer_id,
                    label,
                ),
            )
    finally:
        conn.close()

    return tunnel_id


def list_tunnels(wing: str | None = None) -> list[dict]:
    """No `wing` -> every tunnel row. With `wing=` -> tunnels where
    `wing` matches EITHER the source OR the target endpoint (tunnels
    are symmetric)."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            if wing is None:
                cur.execute("SELECT * FROM tunnels")
            else:
                cur.execute(
                    "SELECT * FROM tunnels WHERE source_wing = %s OR target_wing = %s",
                    (wing, wing),
                )
            rows = cur.fetchall()
    finally:
        conn.close()

    return [_serialize_row(row) for row in rows]


def delete_tunnel(tunnel_id: str) -> dict:
    """Delete a tunnel by id. Idempotent: deleting an already-gone or
    never-existed id is a no-op that returns {"deleted": False} rather
    than raising."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM tunnels WHERE id = %s", (tunnel_id,))
            affected = cur.rowcount
    finally:
        conn.close()

    return {"deleted": affected > 0}


def follow_tunnels(wing: str, room: str) -> list[dict]:
    """Every tunnel touching (wing, room), from either side. For each
    match, returns a connection dict describing the OTHER
    ("connected") endpoint:

      direction: "outgoing" if (wing, room) matched the SOURCE side,
        "incoming" if it matched the TARGET side.
      connected_wing / connected_room: the other side's endpoint.
      label / tunnel_id: the tunnel row's label/id.
      drawer_preview: the other side's drawer text truncated to 300
        chars, hydrated ONLY if the other side carries a drawer_id —
        empty string otherwise (a tunnel with no drawer_id still
        follows, it just has no preview to hydrate).
    """
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM tunnels WHERE "
                "(source_wing = %s AND source_room = %s) "
                "OR (target_wing = %s AND target_room = %s)",
                (wing, room, wing, room),
            )
            rows = cur.fetchall()

            results: list[dict] = []
            for row in rows:
                is_source_match = row["source_wing"] == wing and row["source_room"] == room
                if is_source_match:
                    direction = "outgoing"
                    connected_wing = row["target_wing"]
                    connected_room = row["target_room"]
                    connected_drawer_id = row["target_drawer_id"]
                else:
                    direction = "incoming"
                    connected_wing = row["source_wing"]
                    connected_room = row["source_room"]
                    connected_drawer_id = row["source_drawer_id"]

                drawer_preview = ""
                if connected_drawer_id:
                    cur.execute(
                        "SELECT text FROM drawers WHERE id = %s", (connected_drawer_id,)
                    )
                    drawer_row = cur.fetchone()
                    if drawer_row and drawer_row.get("text"):
                        drawer_preview = drawer_row["text"][:300]

                results.append(
                    {
                        "direction": direction,
                        "connected_wing": connected_wing,
                        "connected_room": connected_room,
                        "label": row["label"],
                        "tunnel_id": row["id"],
                        "drawer_preview": drawer_preview,
                    }
                )
    finally:
        conn.close()

    return results


def find_tunnels(wing_a: str | None = None, wing_b: str | None = None) -> list[dict]:
    """Passive/derived tunnels: any room name present under >=2
    distinct wings in the live `drawers` table (no explicit `tunnels`
    row required). If `wing_a` AND `wing_b` are both given, further
    restricts to rooms present in BOTH those specific wings."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT room, COUNT(DISTINCT wing) AS wing_count, "
                "GROUP_CONCAT(DISTINCT wing) AS wings FROM drawers "
                "GROUP BY room HAVING wing_count >= 2"
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    results = []
    for row in rows:
        wings_raw = row.get("wings") or ""
        wings = wings_raw.split(",") if wings_raw else []
        results.append(
            {"room": row["room"], "wing_count": row["wing_count"], "wings": wings}
        )

    if wing_a is not None and wing_b is not None:
        results = [r for r in results if wing_a in r["wings"] and wing_b in r["wings"]]

    return results


def traverse_graph(start_room: str, max_hops: int = 2) -> list[dict]:
    """Minimal one-hop traversal: find every wing containing
    `start_room`, then every OTHER room in those same wings. A room
    with no shared-wing connections yields an empty list; hop mechanics
    beyond this single pass are deliberately not built out further —
    `max_hops` is accepted for forward-compatible signature shape but
    only one hop is currently computed."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT wing FROM drawers WHERE room = %s", (start_room,))
            wings = [row["wing"] for row in cur.fetchall()]
            if not wings:
                return []

            placeholders = ",".join(["%s"] * len(wings))
            cur.execute(
                f"SELECT DISTINCT room, wing FROM drawers "
                f"WHERE wing IN ({placeholders}) AND room != %s",
                (*wings, start_room),
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    return [{"room": row["room"], "wing": row["wing"], "hops": 1} for row in rows]


def graph_stats() -> dict:
    """Summary counts over the passive/derived cross-project room
    graph: {total_rooms, tunnel_rooms, total_edges}.

    total_rooms: COUNT(DISTINCT room) across all drawers.
    tunnel_rooms: count of rooms present under >=2 distinct wings (the
      same set find_tunnels() surfaces).
    total_edges: SUM(wing_count) across those tunnel rooms — a room
      spanning N wings contributes N to this total; strictly increases
      whenever a new cross-wing room is added.
    """
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(DISTINCT room) AS total_rooms FROM drawers")
            total_rooms = cur.fetchone()["total_rooms"]

            cur.execute(
                "SELECT room, COUNT(DISTINCT wing) AS wing_count FROM drawers "
                "GROUP BY room HAVING wing_count >= 2"
            )
            tunnel_rows = cur.fetchall()
    finally:
        conn.close()

    tunnel_rooms = len(tunnel_rows)
    total_edges = sum(row["wing_count"] for row in tunnel_rows)

    return {
        "total_rooms": int(total_rooms),
        "tunnel_rooms": int(tunnel_rooms),
        "total_edges": int(total_edges),
    }


def register_tunnel_tools(mcp) -> None:
    """Register the tunnel tools on a FastMCP server instance, prefixed
    `mempalace_`.

    NOTE: `graph_stats` is registered here as
    `mempalace_tunnel_graph_stats`, NOT `mempalace_graph_stats` —
    tools/kg.py already registers that exact name for the (unrelated)
    knowledge-graph stats tool. Using the same name here would silently
    clobber/collide with kg.py's registration on the shared FastMCP
    server instance; the `_tunnel_` infix disambiguates while keeping
    the `mempalace_` prefix convention."""
    mcp.tool(name="mempalace_create_tunnel")(create_tunnel)
    mcp.tool(name="mempalace_list_tunnels")(list_tunnels)
    mcp.tool(name="mempalace_delete_tunnel")(delete_tunnel)
    mcp.tool(name="mempalace_follow_tunnels")(follow_tunnels)
    mcp.tool(name="mempalace_find_tunnels")(find_tunnels)
    mcp.tool(name="mempalace_traverse_graph")(traverse_graph)
    mcp.tool(name="mempalace_tunnel_graph_stats")(graph_stats)
