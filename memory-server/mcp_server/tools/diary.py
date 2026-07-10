"""mcp_server/tools/diary.py — diary_write / diary_read tools
(loom-40ec.4.4).

Diary entries are stored AS drawers: the real MemPalace tool
convention this mirrors is that a diary entry for agent `X` lives in
wing `wing_X` (unless the caller overrides via `wing=`), room
"diary". `mempalace_diary_write` is a thin wrapper over `add_drawer()`
from tools/drawers.py -- it reuses that function's embed+insert path
directly rather than reimplementing it. `mempalace_diary_read` queries
`drawers` directly (`ORDER BY filed_at DESC LIMIT n`) rather than
routing through `list_drawers()`'s paginated/preview shape: a diary
read has a simpler contract -- "give me the last N entries, full
text, most-recent-first" -- with no offset/total-count concept.

Title/topic convention: a diary entry's `topic` argument (default
"general") becomes the underlying drawer's `title` column verbatim,
and is reported back by `mempalace_diary_read` as `topic` in its return
shape ({id, topic, entry, filed_at}); the drawer's `text` column comes
back as `entry`.

Ordering caveat: `drawers.filed_at` is a DATETIME column with
SECOND-level precision (verified empirically against a live dolt
2.1.10 server -- two inserts ~50ms apart land with an IDENTICAL
filed_at value). `ORDER BY filed_at DESC` is therefore only a
deterministic recency ordering across writes spaced more than ~1s
apart; a secondary `id DESC` tiebreak keeps the ordering at least
stable/deterministic (not chronological, since ids carry a random hex
suffix) for same-second writes rather than depending on undefined SQL
tie-break behavior.
"""
from __future__ import annotations

from datetime import datetime

from mcp_server.db import connect
from mcp_server.tools.drawers import add_drawer

DIARY_ROOM = "diary"


def _default_wing(agent_name: str, wing: str | None) -> str:
    return wing if wing is not None else f"wing_{agent_name}"


def diary_write(
    agent_name: str,
    entry: str,
    topic: str = "general",
    wing: str | None = None,
) -> str:
    """Write a diary entry for `agent_name`, stored as a drawer in
    wing `wing_<agent_name>` (or `wing`, if given, as an override) /
    room "diary". `topic` becomes the drawer's title. Delegates
    entirely to add_drawer() -- the same embed+insert path every
    other drawer write uses. Returns the new drawer_id."""
    target_wing = _default_wing(agent_name, wing)
    return add_drawer(target_wing, DIARY_ROOM, topic, entry)


def diary_read(
    agent_name: str,
    n: int = 3,
    wing: str | None = None,
) -> list[dict]:
    """Return the `n` most recent diary entries for `agent_name`
    (wing `wing_<agent_name>` by default, or `wing` override),
    most-recent-first. Each entry: {id, topic, entry, filed_at}.
    Queries `drawers` directly rather than going through
    list_drawers()'s paginated/preview shape -- see this module's
    docstring for why."""
    target_wing = _default_wing(agent_name, wing)

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, title, text, filed_at FROM drawers "
                "WHERE wing = %s AND room = %s "
                "ORDER BY filed_at DESC, id DESC LIMIT %s",
                (target_wing, DIARY_ROOM, int(n)),
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    results = []
    for row in rows:
        filed_at = row.get("filed_at")
        results.append(
            {
                "id": row["id"],
                "topic": row["title"],
                "entry": row["text"],
                "filed_at": filed_at.isoformat()
                if isinstance(filed_at, datetime)
                else filed_at,
            }
        )
    return results


def register_diary_tools(mcp) -> None:
    """Register the two diary tools on a FastMCP server instance,
    prefixed `mempalace_`."""
    mcp.tool(name="mempalace_diary_write")(diary_write)
    mcp.tool(name="mempalace_diary_read")(diary_read)
