"""mcp_server/tools/reference.py — trivial reference/static-data MCP
tools (loom-40ec.4.5.5).

Two tools, prefixed `mempalace_` (matching tools/drawers.py's and
tools/kg.py's naming convention):

  mempalace_get_taxonomy() -> dict   {wing: {room: int count}} — a
                wing->room->count census of the drawers table.
  mempalace_get_aaak_spec() -> dict  {"aaak_spec": "<spec text>"} — the
                verbatim old-MemPalace AAAK dialect spec, ported
                unchanged from mempalace/mcp_server.py's AAAK_SPEC
                constant.

Each function below is a plain, directly-callable Python function
(importable and testable without going through the MCP/stdio
protocol) — same pattern as tools/drawers.py/tools/kg.py.
`register_reference_tools()` registers thin wrappers around them on a
FastMCP server instance; `mcp.tool()(fn)` returns the SAME function
object it decorates (verified in tools/drawers.py's module docstring),
so the registered tool and the plain function are identical.
"""
from __future__ import annotations

from mcp_server.db import connect

# Verbatim port of the AAAK_SPEC constant from old MemPalace's
# installed package (~/.local/share/pipx/venvs/mempalace/lib/python3.12/
# site-packages/mempalace/mcp_server.py, lines 1805-1822). Copied
# character-for-character — not paraphrased, not summarized.
AAAK_SPEC = """AAAK is a compressed memory dialect that MemPalace uses for efficient storage.
It is designed to be readable by both humans and LLMs without decoding.

FORMAT:
  ENTITIES: 3-letter uppercase codes. ALC=Alice, JOR=Jordan, RIL=Riley, MAX=Max, BEN=Ben.
  EMOTIONS: *action markers* before/during text. *warm*=joy, *fierce*=determined, *raw*=vulnerable, *bloom*=tenderness.
  STRUCTURE: Pipe-separated fields. FAM: family | PROJ: projects | ⚠: warnings/reminders.
  DATES: ISO format (2026-03-31). COUNTS: Nx = N mentions (e.g., 570x).
  IMPORTANCE: ★ to ★★★★★ (1-5 scale).
  HALLS: hall_facts, hall_events, hall_discoveries, hall_preferences, hall_advice.
  WINGS: wing_user, wing_agent, wing_team, wing_code, wing_myproject, wing_hardware, wing_ue5, wing_ai_research.
  ROOMS: Hyphenated slugs representing named ideas (e.g., chromadb-setup, gpu-pricing).

EXAMPLE:
  FAM: ALC→♡JOR | 2D(kids): RIL(18,sports) MAX(11,chess+swimming) | BEN(contributor)

Read AAAK naturally — expand codes mentally, treat *markers* as emotional context.
When WRITING AAAK: use entity codes, mark emotions, keep structure tight."""


def get_taxonomy() -> dict:
    """Wing/room census of the drawers table: {wing: {room: int count}}.

    Single GROUP BY wing, room query; reshaped into a nested dict in
    Python (Dolt/MySQL has no native nested-dict aggregate)."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT wing, room, COUNT(*) AS n FROM drawers GROUP BY wing, room")
            rows = cur.fetchall()
    finally:
        conn.close()

    taxonomy: dict = {}
    for row in rows:
        wing = row["wing"]
        room = row["room"]
        count = int(row["n"])
        taxonomy.setdefault(wing, {})[room] = count
    return taxonomy


def get_aaak_spec() -> dict:
    """Return the verbatim AAAK dialect spec as {"aaak_spec": "..."}.
    Static data — no DB access needed."""
    return {"aaak_spec": AAAK_SPEC}


def register_reference_tools(mcp) -> None:
    """Register the two reference tools on a FastMCP server instance,
    prefixed `mempalace_`."""
    mcp.tool(name="mempalace_get_taxonomy")(get_taxonomy)
    mcp.tool(name="mempalace_get_aaak_spec")(get_aaak_spec)
