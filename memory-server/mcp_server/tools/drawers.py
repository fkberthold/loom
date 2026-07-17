"""mcp_server/tools/drawers.py — core drawer CRUD tools (loom-40ec.4.1).

Four tools, prefixed `mempalace_` (loom-40ec.6.4 cutover — matches the
retired MemPalace/chroma system's tool names exactly, for full
backward compatibility):

  mempalace_get_drawer(drawer_id) -> dict
  mempalace_add_drawer(wing, room, title, content, source_file=None) -> str
  mempalace_update_drawer(drawer_id, content) -> bool
  mempalace_list_drawers(wing=None, room=None, limit=20, offset=0) -> list[dict]

Each function below is a plain, directly-callable Python function
(importable and testable without going through the MCP/stdio
protocol); `register_drawer_tools()` registers thin wrappers around
them on a FastMCP server instance. `mcp.tool()(fn)` (per the installed
mcp SDK — verified empirically, see server.py's module docstring)
returns the SAME function object it decorates, so the registered tool
and the plain function are identical, not a proxy — no shape drift
between "what a test calls" and "what the MCP client calls".

Concurrency (D6, drawer_loom_decisions_521e654693797b4f169b4cbd):
no branch-per-session, no custom CAS — rely on Dolt's native OCC at
commit time, wrapped in a thin optimistic-retry. See update_drawer's
docstring for the empirically-verified mechanics (Dolt's default
REPEATABLE-READ isolation does NOT raise on a same-row concurrent
write — it silently lets the later commit win — so the retry
transaction explicitly upgrades to SERIALIZABLE, which DOES raise).
"""
from __future__ import annotations

import secrets
from datetime import datetime
from typing import Any

import pymysql

from mcp_server.chunking import plan_rows, should_chunk
from mcp_server.db import connect
from mcp_server.embeddings import embed, vector_literal


class DrawerNotFoundError(Exception):
    """Raised by mempalace_get_drawer / mempalace_update_drawer when no row
    matches the given drawer_id — the MCP-tool-layer equivalent of a
    404, surfaced as a clear error rather than returning None/empty."""


class ConcurrentModificationError(Exception):
    """Raised by mempalace_update_drawer when D6's optimistic retry
    (refetch + reapply the caller's content once) STILL hits a Dolt
    serialization conflict on the second attempt. Surfaced to the
    caller rather than silently dropping the update or retrying
    forever."""


class _OccConflict(Exception):
    """Internal signal only — never escapes update_drawer(). Raised by
    _attempt_update() when the commit hits Dolt's serialization
    failure; caught by update_drawer()'s retry wrapper."""


# MySQL "deadlock / serialization failure" errno, reused by Dolt's
# sql-server for same-row OCC conflicts under SERIALIZABLE isolation.
# Empirically verified against a live dolt 2.1.10 sql-server: two
# connections each open an explicit transaction, both read + update
# the same row, the first COMMIT succeeds and the SECOND COMMIT raises
#   pymysql.err.OperationalError(1213,
#     'serialization failure: this transaction conflicts with a
#      committed transaction from another client, try restarting
#      transaction.')
# This conflict is ONLY raised under SERIALIZABLE isolation — a probe
# against Dolt's default REPEATABLE-READ isolation showed the second
# commit succeeding silently, with the loser's write discarded and NO
# exception raised (last-committer-wins). That silent-loss behavior is
# exactly what D6's optimistic-retry exists to avoid surfacing as data
# loss, hence _attempt_update explicitly upgrades the session's
# isolation level before its transaction.
_SERIALIZATION_FAILURE_ERRNO = 1213


def _generate_drawer_id(wing: str, room: str) -> str:
    """Match MemPalace's existing drawer_id shape:
    `drawer_<wing>_<room>_<24-hex-char-random>` (e.g.
    `drawer_loom_decisions_2ee82f47ed6bc219866cd5c4`, seen throughout
    this repo's existing decision-drawer references). `secrets.token_hex(12)`
    gives 24 hex characters, matching that observed suffix length.
    """
    return f"drawer_{wing}_{room}_{secrets.token_hex(12)}"


def _jsonify(value: Any) -> Any:
    """MCP tool results get JSON-serialized; convert non-JSON-native
    types (datetime) coming back from the DB driver."""
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _serialize_row(row: dict) -> dict:
    return {key: _jsonify(value) for key, value in row.items()}


def get_drawer(drawer_id: str) -> dict:
    """Full row (id, wing, room, title, text, + metadata columns).
    Raises DrawerNotFoundError (a clear, 404-equivalent error) if no
    row matches `drawer_id`."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title, text, filed_at, source_file, "
                "chunk_index, parent_drawer_id, added_by "
                "FROM drawers WHERE id = %s",
                (drawer_id,),
            )
            row = cur.fetchone()
    finally:
        conn.close()

    if row is None:
        raise DrawerNotFoundError(f"no drawer found with id={drawer_id!r}")
    return _serialize_row(row)


def _insert_row(cur, wing, room, title, source_file, row_id, text, vec_literal,
                chunk_index, parent_drawer_id) -> None:
    """INSERT one drawer/chunk row. Children share the parent's
    wing/room/title/source_file/added_by so list/search scoping and
    delete_by_source stay consistent across the whole logical drawer."""
    cur.execute(
        "INSERT INTO drawers "
        "(id, wing, room, title, text, embedding, filed_at, "
        " source_file, chunk_index, parent_drawer_id, added_by) "
        f"VALUES (%s, %s, %s, %s, %s, string_to_vector('{vec_literal}'), "
        "NOW(), %s, %s, %s, %s)",
        (row_id, wing, room, title, text, source_file, chunk_index,
         parent_drawer_id, "memsrv"),
    )


def add_drawer(
    wing: str,
    room: str,
    title: str,
    content: str,
    source_file: str | None = None,
) -> str:
    """Embed `content` (all-MiniLM-L6-v2) and insert a new drawer.

    Chunking (loom-rpsf.2): a body <= CHUNK_SIZE stores as one row
    (embedding = embed(full text), as before). A body > CHUNK_SIZE
    stores as one parent row holding the FULL body (embedding =
    embed(title)) plus one child row per non-overlapping CHUNK_SIZE-char
    slice (embedding = embed(slice)) — so search can match anywhere in a
    long body instead of only within the model's 256-token truncation of
    the whole thing. See mcp_server/chunking.py for the row plan.

    All rows for the drawer are written in a single transaction so a
    long drawer can never be left half-chunked (parent without children
    or vice versa). Embeddings are computed BEFORE the transaction opens
    so the slow model work does not hold the write lock.

    Returns the newly-generated (parent) drawer_id.
    """
    drawer_id = _generate_drawer_id(wing, room)
    specs = plan_rows(drawer_id, title, content)
    rows = [
        (s.row_id, s.text, vector_literal(embed(s.embed_source)),
         s.chunk_index, s.parent_drawer_id)
        for s in specs
    ]

    conn = connect(autocommit=False)
    try:
        with conn.cursor() as cur:
            for row_id, text, vec_literal, chunk_index, parent_id in rows:
                _insert_row(cur, wing, room, title, source_file, row_id, text,
                            vec_literal, chunk_index, parent_id)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return drawer_id


def _is_serialization_conflict(exc: pymysql.err.OperationalError) -> bool:
    return bool(exc.args) and exc.args[0] == _SERIALIZATION_FAILURE_ERRNO


def _attempt_update(
    drawer_id: str,
    wing: str,
    room: str,
    title: str,
    source_file: str | None,
    plan_emb: list[tuple],
) -> None:
    """One attempt at the re-chunk-then-write, inside an explicit
    SERIALIZABLE transaction so a same-row concurrent write is caught
    (raises _OccConflict) rather than silently overwritten (see the
    module-level _SERIALIZATION_FAILURE_ERRNO comment for the
    empirical basis).

    `plan_emb` is the precomputed row plan for the NEW content: a list
    of (row_id, text, vec_literal, chunk_index, parent_drawer_id,
    is_parent) tuples (embeddings already computed outside this
    transaction). Exactly one entry is the parent (row_id == drawer_id,
    is_parent True); the rest are child chunks.

    The update is re-chunk-safe (loom-rpsf.2): it deletes ALL existing
    child rows for this drawer, UPDATEs the parent row's text/embedding
    (resetting it to a parent/standalone shape: chunk_index NULL,
    parent_drawer_id NULL), then INSERTs the new children. Doing the
    whole thing in one SERIALIZABLE transaction keeps a concurrent
    writer from observing a torn re-chunk and preserves D6's OCC guard.

    Raises DrawerNotFoundError if the row disappeared between the
    caller's original call and this attempt (rare, but a real 404 if
    it happens — not an OCC conflict, so not retried).
    """
    conn = connect(autocommit=False)
    try:
        with conn.cursor() as cur:
            cur.execute("SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE")
            # Refetch: confirm the row still exists and establish this
            # transaction's read snapshot immediately before the write.
            cur.execute("SELECT id FROM drawers WHERE id = %s", (drawer_id,))
            row = cur.fetchone()
            if row is None:
                conn.rollback()
                raise DrawerNotFoundError(f"no drawer found with id={drawer_id!r}")

            # Drop any existing children before re-chunking so a body
            # that shrinks (fewer chunks) or de-chunks (<= CHUNK_SIZE)
            # never leaves stale chunk rows behind.
            cur.execute(
                "DELETE FROM drawers WHERE parent_drawer_id = %s", (drawer_id,)
            )

            for row_id, text, vec_lit, chunk_index, parent_id, is_parent in plan_emb:
                if is_parent:
                    cur.execute(
                        "UPDATE drawers SET text = %s, "
                        f"embedding = string_to_vector('{vec_lit}'), "
                        "chunk_index = NULL, parent_drawer_id = NULL "
                        "WHERE id = %s",
                        (text, drawer_id),
                    )
                else:
                    _insert_row(cur, wing, room, title, source_file, row_id,
                                text, vec_lit, chunk_index, parent_id)
        conn.commit()
    except pymysql.err.OperationalError as exc:
        conn.rollback()
        if _is_serialization_conflict(exc):
            raise _OccConflict() from exc
        raise
    finally:
        conn.close()


def update_drawer(drawer_id: str, content: str) -> bool:
    """Re-embed `content` and replace the drawer's text + embedding
    (title/wing/room unchanged), re-chunking as needed (loom-rpsf.2):
    the new body is re-planned through mcp_server.chunking, existing
    child chunks are deleted, and fresh children are inserted when the
    new body exceeds CHUNK_SIZE.

    Implements D6's locked concurrency model
    (drawer_loom_decisions_521e654693797b4f169b4cbd): no
    branch-per-session, no custom CAS — a thin optimistic-retry on
    Dolt's native OCC-at-commit-time. On a conflict, refetch the row
    and reapply the caller's new content ONCE more; if that retry
    ALSO conflicts, raise ConcurrentModificationError to the caller
    rather than retrying forever or silently dropping the update.
    """
    # The parent row of a chunked drawer embeds its TITLE (not its
    # body), and update_drawer's signature does not carry the title, so
    # fetch the drawer's current title/wing/room/source_file only when
    # the new body actually chunks. A short body embeds its own text and
    # needs no metadata read — this also keeps the DB-mocked isolation
    # test (which drives a short body) from touching a real server.
    wing = room = source_file = None
    title = ""
    if should_chunk(content):
        existing = get_drawer(drawer_id)  # raises DrawerNotFoundError if gone
        title = existing["title"]
        wing = existing["wing"]
        room = existing["room"]
        source_file = existing.get("source_file")

    specs = plan_rows(drawer_id, title, content)
    plan_emb = [
        (s.row_id, s.text, vector_literal(embed(s.embed_source)),
         s.chunk_index, s.parent_drawer_id, s.is_parent)
        for s in specs
    ]

    try:
        _attempt_update(drawer_id, wing, room, title, source_file, plan_emb)
        return True
    except _OccConflict:
        try:
            _attempt_update(drawer_id, wing, room, title, source_file, plan_emb)
            return True
        except _OccConflict as exc:
            raise ConcurrentModificationError(
                f"concurrent modification detected for drawer "
                f"{drawer_id!r}: the retry-once attempt also hit a "
                "Dolt serialization conflict — refusing to retry "
                "indefinitely"
            ) from exc


def list_drawers(
    wing: str | None = None,
    room: str | None = None,
    limit: int = 20,
    offset: int = 0,
) -> list[dict]:
    """Paginated listing with a content preview per row, matching the
    shape a caller would expect from the existing mempalace_list_drawers
    tool: id, wing, room, title, preview, and a `total` count (for
    pagination) repeated on every row so the return type stays a flat
    list[dict] rather than a wrapper object.
    """
    # `parent_drawer_id IS NULL` restricts the listing to LOGICAL
    # drawers (standalone rows + chunked-drawer parents), never the
    # child chunk rows a long drawer is split into (loom-rpsf.2). The
    # COUNT(*) total inherits the same filter, so a chunked drawer
    # counts once, not once-per-chunk.
    conditions: list[str] = ["parent_drawer_id IS NULL"]
    params: list[Any] = []
    if wing is not None:
        conditions.append("wing = %s")
        params.append(wing)
    if room is not None:
        conditions.append("room = %s")
        params.append(room)
    where_clause = f"WHERE {' AND '.join(conditions)}"

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) AS total FROM drawers {where_clause}", params)
            total = cur.fetchone()["total"]

            cur.execute(
                "SELECT id, wing, room, title, text, filed_at FROM drawers "
                f"{where_clause} ORDER BY filed_at DESC, id ASC LIMIT %s OFFSET %s",
                [*params, int(limit), int(offset)],
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
                "preview": text[:200],
                "total": total,
            }
        )
    return results


def delete_drawer(drawer_id: str) -> dict:
    """Delete a single drawer by id (and any chunk rows chained to it
    via parent_drawer_id). Idempotent: deleting a nonexistent id does
    NOT raise — it returns success=False with empty deleted_ids and
    zero chunks_deleted, rather than surfacing an error."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM drawers WHERE id = %s OR parent_drawer_id = %s",
                (drawer_id, drawer_id),
            )
            affected = cur.rowcount
    finally:
        conn.close()

    if affected == 0:
        return {
            "success": False,
            "drawer_id": drawer_id,
            "deleted_ids": [],
            "chunks_deleted": 0,
        }

    return {
        "success": True,
        "drawer_id": drawer_id,
        "deleted_ids": [drawer_id],
        "chunks_deleted": affected - 1,
    }


def delete_by_source(source_file: str, dry_run: bool = True) -> dict:
    """Bulk-delete every drawer sharing `source_file`. Always previews
    first (matched_count + a sample of matching rows); only actually
    deletes when `dry_run` is explicitly False."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title FROM drawers WHERE source_file = %s",
                (source_file,),
            )
            rows = cur.fetchall()
            matched_count = len(rows)
            sample = [_serialize_row(row) for row in rows[:5]]

            if dry_run:
                return {
                    "matched_count": matched_count,
                    "sample": sample,
                    "deleted": False,
                }

            cur.execute(
                "DELETE FROM drawers WHERE source_file = %s",
                (source_file,),
            )
    finally:
        conn.close()

    return {
        "matched_count": matched_count,
        "sample": sample,
        "deleted": True,
    }


def register_drawer_tools(mcp) -> None:
    """Register the four drawer-CRUD tools on a FastMCP server
    instance, prefixed `mempalace_`."""
    mcp.tool(name="mempalace_get_drawer")(get_drawer)
    mcp.tool(name="mempalace_add_drawer")(add_drawer)
    mcp.tool(name="mempalace_update_drawer")(update_drawer)
    mcp.tool(name="mempalace_list_drawers")(list_drawers)
    mcp.tool(name="mempalace_delete_drawer")(delete_drawer)
    mcp.tool(name="mempalace_delete_by_source")(delete_by_source)
