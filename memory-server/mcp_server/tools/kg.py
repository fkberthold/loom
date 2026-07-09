"""mcp_server/tools/kg.py — knowledge-graph CRUD/query tools
(loom-40ec.4.3).

Four tools, prefixed `memsrv_` (matching tools/drawers.py's and
tools/search.py's naming convention — final naming/config-swap against
the still-live `mempalace_*` tools is loom-40ec.6's job, not this
bead's):

  memsrv_kg_add(subject, predicate, object, confidence=1.0,
                source_closet=None) -> str
  memsrv_kg_query(entity, direction="both", as_of=None) -> list[dict]
  memsrv_kg_invalidate(triple_id=None, subject=None, predicate=None,
                        object=None) -> int
  memsrv_graph_stats() -> dict

Each function below is a plain, directly-callable Python function
(importable and testable without going through the MCP/stdio
protocol) — same pattern as tools/drawers.py/tools/search.py.
`register_kg_tools()` registers thin wrappers around them on a
FastMCP server instance; `mcp.tool()(fn)` returns the SAME function
object it decorates (verified in tools/drawers.py's module docstring),
so the registered tool and the plain function are identical.

`predicate` is FREE-TEXT per the locked D7 design decision
(drawer_loom_decisions_521e654693797b4f169b4cbd) — this module does
NOT validate predicate values against a fixed enum. loom's own KG has
hundreds of ad-hoc predicates invented per design-cycle (see
CLAUDE.md's "Design-cycle KG predicate set" note: the recommended
vocabulary is a SOFT recommendation, not a locked schema).
"""
from __future__ import annotations

import secrets
from datetime import datetime
from typing import Any

from mcp_server.db import connect

_VALID_DIRECTIONS = {"outgoing", "incoming", "both"}


def _generate_triple_id() -> str:
    """`triple_<16-hex>` via secrets.token_hex(8) — mirrors
    tools/drawers.py's `_generate_drawer_id`'s random-hex-suffix
    convention, sized shorter (16 hex chars vs. drawers' 24): kg_triples'
    `id` column is VARCHAR(64) and triples are expected at much higher
    volume than drawers (a design-cycle KG can carry hundreds of
    triples), so a compact fixed-width random suffix keeps ids short
    while remaining collision-safe (2**64 keyspace) at any scale this
    table will realistically see.
    """
    return f"triple_{secrets.token_hex(8)}"


def _jsonify(value: Any) -> Any:
    """MCP tool results get JSON-serialized; convert non-JSON-native
    types (datetime) coming back from the DB driver. Mirrors
    tools/drawers.py's `_jsonify` — kept as a local copy rather than a
    cross-module import since both modules treat it as a private
    module-level helper (not part of either module's public surface)."""
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _normalize_as_of(as_of: str) -> str:
    """Normalize an ISO 8601 datetime string into the space-separated
    form MySQL/Dolt's implicit string->DATETIME conversion reliably
    accepts. Python's `datetime.isoformat()` (what `_jsonify` above
    produces, and what a caller round-tripping a value this module
    returned would naturally pass back in) uses a literal `T` as the
    date/time separator (`2026-07-09T12:00:00`); Dolt's DATETIME
    comparison expects the SQL-standard space-separated form
    (`2026-07-09 12:00:00`). A caller-supplied plain-space string
    passes through unchanged.
    """
    return as_of.replace("T", " ", 1) if "T" in as_of else as_of


def _serialize_fact(row: dict, direction: str) -> dict:
    """Shape a raw kg_triples row into the documented memsrv_kg_query
    return shape: {direction, subject, predicate, object, confidence,
    valid_from, valid_to, source_closet, current} — mirrors the real
    mempalace_kg_query tool's field names exactly (per this bead's
    brief)."""
    confidence = row["confidence"]
    current = row["current"]
    return {
        "direction": direction,
        "subject": row["subject"],
        "predicate": row["predicate"],
        "object": row["object"],
        "confidence": float(confidence) if confidence is not None else None,
        "valid_from": _jsonify(row["valid_from"]),
        "valid_to": _jsonify(row["valid_to"]),
        "source_closet": row["source_closet"],
        "current": bool(current) if current is not None else None,
    }


def kg_add(
    subject: str,
    predicate: str,
    object: str,
    confidence: float = 1.0,
    source_closet: str | None = None,
) -> str:
    """Insert a new kg_triples row and return the generated triple_id.

    `current=True`, `created_at=NOW()`. `valid_from`/`valid_to` are
    left NULL unless a caller has a specific reason to set them — a
    freshly-added triple's validity window is open-ended by default;
    it only becomes bounded later via memsrv_kg_invalidate.
    """
    triple_id = _generate_triple_id()

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO kg_triples "
                "(id, subject, predicate, object, confidence, valid_from, "
                " valid_to, source_closet, `current`, created_at) "
                "VALUES (%s, %s, %s, %s, %s, NULL, NULL, %s, TRUE, NOW())",
                (triple_id, subject, predicate, object, confidence, source_closet),
            )
    finally:
        conn.close()

    return triple_id


def _fetch_side(entity: str, column: str, direction: str, as_of: str | None) -> list[dict]:
    """Query one side (subject or object) of the graph for `entity`,
    tagging every returned fact with `direction` (the caller-facing
    label for which side matched — "outgoing" for the subject side,
    "incoming" for the object side).

    `as_of` (optional): an ISO date/datetime string. When given,
    filters to triples valid AT that point in time —
    `(valid_from IS NULL OR valid_from <= as_of) AND
     (valid_to IS NULL OR valid_to > as_of)` — regardless of the
    row's CURRENT `current` flag (a temporal-validity query answers
    "what was true then", not "what does the live current flag say
    now"). When `as_of` is omitted, defaults to only `current=TRUE`
    rows (today's live facts) — the common case and the cheaper query
    (an equality filter vs. two open-interval comparisons).
    """
    conn = connect()
    try:
        with conn.cursor() as cur:
            if as_of is None:
                cur.execute(
                    "SELECT subject, predicate, object, confidence, valid_from, "
                    "valid_to, source_closet, `current` FROM kg_triples "
                    f"WHERE {column} = %s AND `current` = TRUE",
                    (entity,),
                )
            else:
                normalized = _normalize_as_of(as_of)
                cur.execute(
                    "SELECT subject, predicate, object, confidence, valid_from, "
                    "valid_to, source_closet, `current` FROM kg_triples "
                    f"WHERE {column} = %s "
                    "AND (valid_from IS NULL OR valid_from <= %s) "
                    "AND (valid_to IS NULL OR valid_to > %s)",
                    (entity, normalized, normalized),
                )
            rows = cur.fetchall()
    finally:
        conn.close()

    return [_serialize_fact(row, direction) for row in rows]


def kg_query(
    entity: str,
    direction: str = "both",
    as_of: str | None = None,
) -> list[dict]:
    """Query the graph for facts touching `entity`.

    direction="outgoing": WHERE subject = entity (entity is the
      subject of the returned facts).
    direction="incoming": WHERE object = entity (entity is the object
      of the returned facts).
    direction="both" (default): the UNION of the two above — a
      genuine union (both queries run and their results are
      concatenated), not a default to one side.

    Each returned row carries a `direction` field so a caller
    consuming a "both" result can tell which side matched. See
    `_fetch_side`'s docstring for `as_of` semantics.
    """
    if direction not in _VALID_DIRECTIONS:
        raise ValueError(
            f"direction must be one of {sorted(_VALID_DIRECTIONS)}, got {direction!r}"
        )

    results: list[dict] = []
    if direction in ("outgoing", "both"):
        results.extend(_fetch_side(entity, "subject", "outgoing", as_of))
    if direction in ("incoming", "both"):
        results.extend(_fetch_side(entity, "object", "incoming", as_of))
    return results


def kg_invalidate(
    triple_id: str | None = None,
    subject: str | None = None,
    predicate: str | None = None,
    object: str | None = None,
) -> int:
    """Mark matching triple(s) as historical: `current=FALSE`,
    `valid_to=NOW()`.

    Accepts EITHER a direct `triple_id` OR a full
    `(subject, predicate, object)` triple to match on — exactly one of
    the two forms. Raises ValueError if both are given, if neither is
    given, or if only SOME of subject/predicate/object are given (a
    partial triple is not a valid match key).

    Returns the number of rows updated (0 if nothing matched — that is
    informational, not an error: an already-historical or
    never-existed triple is a legitimate no-op call).
    """
    spo_given = subject is not None or predicate is not None or object is not None

    if triple_id is not None and spo_given:
        raise ValueError(
            "provide either triple_id OR (subject, predicate, object), not both"
        )
    if triple_id is None and not spo_given:
        raise ValueError(
            "must provide either triple_id or a full (subject, predicate, object) triple"
        )
    if triple_id is None and (subject is None or predicate is None or object is None):
        raise ValueError(
            "subject, predicate, and object must ALL be provided together "
            "when not matching by triple_id"
        )

    conn = connect()
    try:
        with conn.cursor() as cur:
            if triple_id is not None:
                cur.execute(
                    "UPDATE kg_triples SET `current` = FALSE, valid_to = NOW() "
                    "WHERE id = %s",
                    (triple_id,),
                )
            else:
                cur.execute(
                    "UPDATE kg_triples SET `current` = FALSE, valid_to = NOW() "
                    "WHERE subject = %s AND predicate = %s AND object = %s",
                    (subject, predicate, object),
                )
            updated = cur.rowcount
    finally:
        conn.close()

    return updated


def graph_stats() -> dict:
    """Summary counts over the whole kg_triples table:
    {entity_count, triple_count, current_count, expired_count}.

    `entity_count` is the count of DISTINCT entities appearing as
    EITHER a subject OR an object (a real unique-entity count, via a
    UNION of the two columns — not just a subject count, which would
    silently undercount any entity that only ever appears as an
    object).
    """
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) AS entity_count FROM ("
                "  SELECT subject AS entity FROM kg_triples"
                "  UNION"
                "  SELECT object AS entity FROM kg_triples"
                ") AS entities"
            )
            entity_count = cur.fetchone()["entity_count"]

            cur.execute("SELECT COUNT(*) AS triple_count FROM kg_triples")
            triple_count = cur.fetchone()["triple_count"]

            cur.execute(
                "SELECT COUNT(*) AS current_count FROM kg_triples WHERE `current` = TRUE"
            )
            current_count = cur.fetchone()["current_count"]

            cur.execute(
                "SELECT COUNT(*) AS expired_count FROM kg_triples WHERE `current` = FALSE"
            )
            expired_count = cur.fetchone()["expired_count"]
    finally:
        conn.close()

    return {
        "entity_count": entity_count,
        "triple_count": triple_count,
        "current_count": current_count,
        "expired_count": expired_count,
    }


def register_kg_tools(mcp) -> None:
    """Register the four knowledge-graph tools on a FastMCP server
    instance, prefixed `memsrv_`."""
    mcp.tool(name="memsrv_kg_add")(kg_add)
    mcp.tool(name="memsrv_kg_query")(kg_query)
    mcp.tool(name="memsrv_kg_invalidate")(kg_invalidate)
    mcp.tool(name="memsrv_graph_stats")(graph_stats)
