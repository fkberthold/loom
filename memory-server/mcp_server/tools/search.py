"""mcp_server/tools/search.py — semantic search tool (loom-40ec.4.2).

  memsrv_search(query, wing=None, room=None, limit=10) -> list[dict]

The highest-value read path: embeds `query` (same all-MiniLM-L6-v2
model as add_drawer/update_drawer, via mcp_server/embeddings.py) and
runs a `VEC_DISTANCE` nearest-neighbor query against `drawers`,
optionally scoped by `wing`/`room`. Mirrors tools/drawers.py's style:
a plain, directly-callable, independently-testable function, plus a
`register_search_tools(mcp)` registration function following the same
`mcp.tool(name=...)` pattern as register_drawer_tools.

Conditional-WHERE-building mirrors list_drawers() in tools/drawers.py
exactly (wing then room, each optional, AND-joined) — this is also
what lets the query use the `(wing, room)` B-tree index from
schema.sql to narrow the candidate set before the VEC_DISTANCE/TopN
sort runs (see that index's inline comment). An unscoped call (no
wing/room) falls back to the documented full-table-scan behavior —
see docs/vector-index-scaling.md: ADEQUATE at real scale under a
sub-second latency bar, not something this bead attempts to fix.

`snippet` is a simple first-~300-chars truncation of `text`, not an
excerpt centered on the best-matching span — see this module's
docstring on `_snippet()` for why that nice-to-have was skipped.
"""
from __future__ import annotations

from typing import Any

from mcp_server.db import connect
from mcp_server.embeddings import embed, vector_literal

SNIPPET_LENGTH = 300


def _snippet(text: str) -> str:
    """A simple truncation of `text` to the first SNIPPET_LENGTH
    characters, per the bead brief's explicit "simple truncation is
    fine" allowance. NOT an excerpt centered on the best-matching
    span — that "nice-to-have" was skipped here: doing it well
    requires either (a) a second text-similarity pass per row (token
    overlap / substring search against the query) beyond the vector
    distance already computed, or (b) surfacing span offsets from the
    embedding model, neither of which this bead's scope asked for.
    Plain truncation is honest or "relevance-anchored" in the loose
    sense that the FULL `text` column always at least contains the
    real match (VEC_DISTANCE already selected it) even when the
    displayed excerpt doesn't start exactly at the matching phrase.
    """
    return text[:SNIPPET_LENGTH]


def search(
    query: str,
    wing: str | None = None,
    room: str | None = None,
    limit: int = 10,
) -> list[dict]:
    """Semantic search over `drawers`. Embeds `query`, then runs an
    ORDER BY VEC_DISTANCE ... LIMIT query, optionally scoped by
    `wing` and/or `room` (both optional, AND-joined when both given
    — mirrors list_drawers()'s conditional-WHERE-building pattern in
    tools/drawers.py). Returns a list of
    {id, wing, room, title, snippet, distance} dicts ordered by
    ascending distance (closest match first).
    """
    vec_literal = vector_literal(embed(query))

    conditions: list[str] = []
    params: list[Any] = []
    if wing is not None:
        conditions.append("wing = %s")
        params.append(wing)
    if room is not None:
        conditions.append("room = %s")
        params.append(room)
    where_clause = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title, text, "
                f"VEC_DISTANCE(embedding, string_to_vector('{vec_literal}')) AS dist "
                f"FROM drawers {where_clause} "
                "ORDER BY dist ASC LIMIT %s",
                [*params, int(limit)],
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    results = []
    for row in rows:
        text = row.get("text") or ""
        results.append(
            {
                "id": row["id"],
                "wing": row["wing"],
                "room": row["room"],
                "title": row["title"],
                "snippet": _snippet(text),
                # Explicit float() cast: VEC_DISTANCE's return type as
                # surfaced by pymysql is not guaranteed to already be
                # a native float (could come back as Decimal
                # depending on driver/server numeric-type mapping),
                # and MCP tool results get JSON-serialized -- a bare
                # Decimal is not JSON-native. Mirrors the defensive
                # posture of tools/drawers.py's _jsonify() for
                # datetime fields.
                "distance": float(row["dist"]),
            }
        )
    return results


def register_search_tools(mcp) -> None:
    """Register the semantic-search tool on a FastMCP server
    instance, prefixed `memsrv_` (matching register_drawer_tools's
    convention)."""
    mcp.tool(name="memsrv_search")(search)
