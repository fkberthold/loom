"""mcp_server/tools/search.py — semantic search tool (loom-40ec.4.2)
plus corpus-wide near-duplicate detection (loom-4cb6).

  mempalace_search(query, wing=None, room=None, limit=10) -> list[dict]
  mempalace_check_duplicate(content, threshold=0.9) -> dict

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

`check_duplicate` (loom-4cb6) is registered as `mempalace_check_duplicate`,
matching every other tool in this server under the `mempalace_*` prefix
(loom-40ec.6.4 cutover). It reuses `search()`'s embed + VEC_DISTANCE
query shape but is deliberately UNSCOPED (no wing/room filter) since
dedup checks the whole corpus, not a sub-tree of it.

Distance-to-similarity conversion for the threshold check: `VEC_DISTANCE`
here resolves to Dolt's `VEC_DISTANCE_L2_SQUARED` (confirmed via
`EXPLAIN FORMAT=TREE` in docs/vector-index-scaling.md's query-plan
dump), and `embeddings.py`'s all-MiniLM-L6-v2 model emits L2-unit-
normalized vectors (empirically verified: `norm(embed(x)) ~= 1.0` for
arbitrary x — this model ships a built-in Normalize pooling layer).
For unit vectors a and b, `||a-b||^2 = ||a||^2 + ||b||^2 - 2*a.b
= 2 - 2*cos_sim(a, b)`, so `cos_sim = 1 - (L2_squared / 2)`. This is
the standard identity, not a fit to any specific test input — it holds
for any pair of unit vectors in this embedding space, which is why the
threshold test (loose 0.5 vs strict 0.999 against the SAME near-
duplicate pair) calibrates correctly without special-casing.
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
    tag_filter: list[str] | None = None,
    limit: int = 10,
) -> list[dict]:
    """Semantic search over `drawers`. Embeds `query`, then runs an
    ORDER BY VEC_DISTANCE ... LIMIT query, optionally scoped by
    `wing` and/or `room` (both optional, AND-joined when both given
    — mirrors list_drawers()'s conditional-WHERE-building pattern in
    tools/drawers.py). Returns a list of
    {id, wing, room, title, snippet, distance} dicts ordered by
    ascending distance (closest match first).

    `tag_filter` (optional): when a non-empty list of tags is given,
    restricts results to drawers carrying ALL of those tags (AND
    semantics — a drawer must match every tag in the list, not just
    one). Implemented as a subquery condition against `drawer_tags`
    appended to the same `conditions`/`params` lists wing/room use:
    `id IN (SELECT drawer_id FROM drawer_tags WHERE tag IN (...)
    GROUP BY drawer_id HAVING COUNT(DISTINCT tag) = len(tag_filter))`.
    `None` or an empty list leaves results unaffected (purely
    additive parameter).
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
    if tag_filter:
        placeholders = ", ".join(["%s"] * len(tag_filter))
        conditions.append(
            "id IN (SELECT drawer_id FROM drawer_tags "
            f"WHERE tag IN ({placeholders}) "
            "GROUP BY drawer_id HAVING COUNT(DISTINCT tag) = %s)"
        )
        params.extend(tag_filter)
        params.append(len(tag_filter))
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



# Candidate pool size for check_duplicate's underlying VEC_DISTANCE
# query: pulled BEFORE the threshold filter is applied, since (unlike
# search()'s top-K "best few matches") we need every row that clears
# the similarity bar, not just the single nearest one. 50 is a
# generous cap for the "duplicate cluster" case (genuine near-dupes
# of one drawer are realistically a handful, not hundreds) while
# still bounding the Python-side filtering work.
_DUPLICATE_CANDIDATE_LIMIT = 50


def check_duplicate(content: str, threshold: float = 0.9) -> dict:
    """Corpus-wide near-duplicate check. Embeds `content`, runs the
    same embed + VEC_DISTANCE nearest-neighbor query as search() but
    UNSCOPED (no wing/room filter — dedup spans the whole `drawers`
    table), converts each candidate's distance to a cosine similarity
    (see module docstring for the derivation), and keeps only
    candidates whose similarity clears `threshold` (higher threshold
    = stricter = fewer/no duplicates flagged).

    Returns {"is_duplicate": bool, "matches": [...]}: `is_duplicate`
    is True iff at least one candidate clears the threshold; `matches`
    holds ONLY the qualifying (above-threshold) candidates, each a
    dict mirroring search()'s per-result shape
    ({id, wing, room, title, snippet, distance}), ordered by ascending
    distance (closest/most-similar first).
    """
    vec_literal = vector_literal(embed(content))

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title, text, "
                f"VEC_DISTANCE(embedding, string_to_vector('{vec_literal}')) AS dist "
                "FROM drawers "
                "ORDER BY dist ASC LIMIT %s",
                [_DUPLICATE_CANDIDATE_LIMIT],
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    matches = []
    for row in rows:
        dist = float(row["dist"])
        similarity = 1.0 - (dist / 2.0)
        if similarity < threshold:
            continue
        text = row.get("text") or ""
        matches.append(
            {
                "id": row["id"],
                "wing": row["wing"],
                "room": row["room"],
                "title": row["title"],
                "snippet": _snippet(text),
                "distance": dist,
            }
        )

    return {"is_duplicate": len(matches) > 0, "matches": matches}


def register_search_tools(mcp) -> None:
    """Register the semantic-search + duplicate-check tools on a
    FastMCP server instance. `search` keeps the `mempalace_` prefix
    (matching register_drawer_tools's convention); `check_duplicate`
    is registered under the final `mempalace_` name directly (see
    module docstring — new tools in this mid-rename window land under
    the final name rather than being renamed later)."""
    mcp.tool(name="mempalace_search")(search)
    mcp.tool(name="mempalace_check_duplicate")(check_duplicate)
