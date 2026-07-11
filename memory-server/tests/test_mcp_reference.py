"""RED-spec test for loom-40ec.4.5.5 — reference/static-data MCP tools
(mempalace_get_taxonomy / mempalace_get_aaak_spec).

Two trivial reference tools ported from old MemPalace:

  get_taxonomy() -> dict   {wing: {room: count}} — a wing->room->count
    census of the drawers table, with each wing's room counts summing
    to that wing's total row count.
  get_aaak_spec() -> dict  {"aaak_spec": "<non-empty string>"} — the
    verbatim old-MemPalace static spec constant (the exact text is the
    implementer's responsibility to source; this test pins only the
    type/shape contract, not the literal string).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py defines (this module gets its OWN isolated,
module-scoped ephemeral server instance). Seeds via add_drawer() (the
real write path, no hand-rolled INSERT SQL) and cross-checks
get_taxonomy() against a direct GROUP BY query issued over the SAME
ephemeral instance via mcp_server.db.connect — no mocks.

Calls the tool functions in mcp_server/tools/reference.py directly —
same plain-function-is-the-registered-tool pattern as tools/drawers.py
and tools/status.py (see tools/drawers.py's module docstring for why
that still exercises the identical code path a real MCP client
invocation would hit).

The module-scoped dolt server is SHARED by every DB-touching test
below, so the seeded-count tests assert scoped, order-independent facts
(per-wing/room counts for a wing unique to each test) rather than
absolute totals.
"""
import os

from mcp_server.db import connect
from mcp_server.tools.drawers import add_drawer

# The functions under test — do NOT exist yet (loom-40ec.4.5.5 is RED
# until the implementer adds mcp_server/tools/reference.py). This
# module-level import is the RED signal: while RED it surfaces as an
# ImportError collection error naming the missing module.
from mcp_server.tools.reference import (
    get_aaak_spec,
    get_taxonomy,
    register_reference_tools,  # noqa: F401 - imported to pin the public surface
)

# Reuse the existing dolt_server_env fixture rather than re-deriving the
# bring-up boilerplate a fourth time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _uniq(label: str) -> str:
    return f"reftest_{label}_{os.urandom(4).hex()}"


def _direct_wing_room_census(wing: str):
    """Ground truth straight from SQL over the same ephemeral instance:
    returns (census, total) where census is {room: int count} from a
    GROUP BY scoped to `wing`, and total is COUNT(*) for that wing."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT room, COUNT(*) AS n FROM drawers WHERE wing = %s GROUP BY room",
                (wing,),
            )
            census = {row["room"]: int(row["n"]) for row in cur.fetchall()}
            cur.execute("SELECT COUNT(*) AS n FROM drawers WHERE wing = %s", (wing,))
            total = int(cur.fetchone()["n"])
    finally:
        conn.close()
    return census, total


def test_get_taxonomy_wing_room_breakdown(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """get_taxonomy() returns {wing: {room: count}}: the seeded wing is a
    top-level key, its value is a room->count dict, those counts match a
    direct GROUP BY over the same instance, and they sum to the wing's
    total row count."""
    wing = _uniq("wing")
    # Seed across TWO distinct rooms in the same wing.
    for i in range(2):
        add_drawer(wing, "decisions", f"d{i}", f"decision body {i}")
    for i in range(3):
        add_drawer(wing, "notes", f"n{i}", f"notes body {i}")

    taxonomy = get_taxonomy()

    assert isinstance(taxonomy, dict)
    # Every top-level value is itself a room->count dict.
    assert all(isinstance(v, dict) for v in taxonomy.values())

    assert wing in taxonomy, f"seeded wing {wing!r} missing from taxonomy keys"
    rooms = taxonomy[wing]
    assert isinstance(rooms, dict)
    assert rooms["decisions"] == 2
    assert rooms["notes"] == 3

    census, total = _direct_wing_room_census(wing)
    assert rooms == census
    # The per-room counts sum to the wing's total row count.
    assert sum(rooms.values()) == total == 5


def test_get_taxonomy_counts_are_ints(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Every room count in the taxonomy is a plain int (JSON-serializable,
    not a driver-specific numeric wrapper)."""
    wing = _uniq("intwing")
    add_drawer(wing, "decisions", "t", "b")

    taxonomy = get_taxonomy()

    assert wing in taxonomy
    assert all(
        isinstance(count, int)
        for room_counts in taxonomy.values()
        for count in room_counts.values()
    )


def test_get_aaak_spec_shape():
    """get_aaak_spec() returns {"aaak_spec": "<non-empty string>"} — a
    dict with an 'aaak_spec' key whose value is a non-empty string. The
    verbatim spec text is the implementer's responsibility (sourced from
    old MemPalace); this test pins only the type/shape contract, not the
    literal string. Static data — no dolt server required."""
    result = get_aaak_spec()

    assert isinstance(result, dict)
    assert "aaak_spec" in result
    spec = result["aaak_spec"]
    assert isinstance(spec, str)
    assert spec.strip(), "aaak_spec must be a non-empty string"


def test_reference_tools_registered_on_server():
    """mempalace_get_taxonomy / mempalace_get_aaak_spec are registered on
    the FastMCP server built by create_server() (matching the sibling
    registration tests for the drawer/search/status/kg tool groups)."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert {"mempalace_get_taxonomy", "mempalace_get_aaak_spec"} <= tool_names
