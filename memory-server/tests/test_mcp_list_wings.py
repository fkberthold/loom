"""RED-spec test for loom-4cb6 — mempalace_list_wings (MCP wing-census
tool).

list_wings is a thin, standalone wrapper over
SELECT wing, COUNT(*) FROM drawers GROUP BY wing — the same by_wing
logic status() computes internally, surfaced on its own as
{"wings": {"<wing>": <int count>, ...}}. Unscoped: it censuses the
WHOLE drawers table.

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py defines (this module gets its OWN isolated,
module-scoped ephemeral server instance). Seeds via add_drawer() (the
real write path, no hand-rolled INSERT SQL) and cross-checks
list_wings() against a direct COUNT(*) GROUP BY query issued over the
SAME ephemeral instance via mcp_server.db.connect — no mocks.

The module-scoped dolt server is SHARED by every test below, so the
seeded-count tests assert scoped, order-independent facts (per-wing
counts for wings unique to each test) rather than absolute totals.
"""
import os

import pytest

from mcp_server.db import connect
from mcp_server.tools.drawers import add_drawer

# The function under test — does not exist yet (loom-4cb6 is RED until
# the implementer adds list_wings to mcp_server/tools/status.py).
# Module-level import mirrors the sibling test convention; while RED it
# surfaces as an ImportError collection error naming the missing symbol.
from mcp_server.tools.status import list_wings

# Reuse the existing dolt_server_env fixture rather than re-deriving the
# bring-up boilerplate a second time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _direct_wing_census():
    """Ground truth straight from SQL over the same ephemeral instance:
    returns (census, total) where census is {wing: int count} from a
    GROUP BY and total is COUNT(*) over the whole drawers table."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT wing, COUNT(*) AS n FROM drawers GROUP BY wing")
            census = {row["wing"]: int(row["n"]) for row in cur.fetchall()}
            cur.execute("SELECT COUNT(*) AS n FROM drawers")
            total = int(cur.fetchone()["n"])
    finally:
        conn.close()
    return census, total


def test_list_wings_shape(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Return shape is exactly {"wings": {<wing>: <int count>}} — a
    single top-level key whose value is a dict of int counts."""
    add_drawer(f"lw_shape_{os.urandom(4).hex()}", "notes", "t", "b")

    result = list_wings()

    assert set(result.keys()) == {"wings"}
    assert isinstance(result["wings"], dict)
    assert all(isinstance(v, int) for v in result["wings"].values())


def test_list_wings_counts_seeded_wings(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """With drawers seeded across >=2 distinct wings, list_wings()
    reports the correct per-wing count for each seeded wing. Scoped,
    order-independent assertion — the module-shared server may carry
    rows from other tests in other wings."""
    wing_a = f"lw_a_{os.urandom(4).hex()}"
    wing_b = f"lw_b_{os.urandom(4).hex()}"
    for i in range(3):
        add_drawer(wing_a, "notes", f"a{i}", f"body a{i}")
    for i in range(2):
        add_drawer(wing_b, "notes", f"b{i}", f"body b{i}")

    wings = list_wings()["wings"]

    assert wings[wing_a] == 3
    assert wings[wing_b] == 2


def test_list_wings_matches_direct_group_by_and_sums_to_total(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """list_wings()'s census matches a direct COUNT(*) GROUP BY wing
    over the same instance EXACTLY, and its per-wing values sum to the
    total row count in the drawers table."""
    # Seed across two more distinct wings so the corpus spans >=2 wings
    # regardless of test execution order.
    seed_wing_x = f"lw_total_x_{os.urandom(4).hex()}"
    seed_wing_y = f"lw_total_y_{os.urandom(4).hex()}"
    for i in range(4):
        add_drawer(seed_wing_x, "notes", f"x{i}", f"bx{i}")
    add_drawer(seed_wing_y, "notes", "y", "by")

    wings = list_wings()["wings"]
    census, total = _direct_wing_census()

    assert wings == census
    assert sum(wings.values()) == total


def test_list_wings_registered_on_server():
    """mempalace_list_wings is registered on the FastMCP server built by
    create_server() (matching the sibling registration tests for the
    search/status/kg tool groups)."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "mempalace_list_wings" in tool_names
