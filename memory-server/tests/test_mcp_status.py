"""RED-spec test for loom-40ec.4.4 — memsrv_status / memsrv_kg_stats
(MCP status + KG-stats tools).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py already defines (imported here rather than
duplicated -- pytest re-instantiates a module-scoped fixture per
requesting module, so this file gets its OWN isolated ephemeral
server instance). No mocks, except for the one deliberate
DB-unreachable simulation below (there is no other way to exercise a
connection failure against a real, otherwise-healthy server).
"""
import os

from mcp_server.tools.drawers import add_drawer
from mcp_server.tools.status import kg_stats, status

# Reuse the existing dolt_server_env fixture rather than re-deriving
# the bring-up boilerplate a second time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def test_status_reflects_seeded_drawer_count(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Rather than asserting an exact total_drawers count (this
    module's dolt_server_env instance is isolated per-module, but
    OTHER tests within THIS SAME module share it and may seed rows
    before or after this test runs), seed a handful of drawers in a
    wing unique to this test and assert status()'s by_wing count for
    that wing exactly matches what was just seeded -- a structural,
    order-independent assertion. total_drawers/by_room are asserted
    with >= floors for the same reason."""
    probe_wing = f"status_probe_{os.urandom(4).hex()}"
    for i in range(3):
        add_drawer(probe_wing, "notes", f"title {i}", f"body {i}")

    result = status()
    assert result["dolt_reachable"] is True
    assert result["total_drawers"] >= 3
    assert result["by_wing"][probe_wing] == 3
    assert result["by_room"]["notes"] >= 3


def test_status_shape(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    result = status()
    assert set(result.keys()) == {
        "dolt_reachable",
        "total_drawers",
        "by_wing",
        "by_room",
    }
    assert isinstance(result["by_wing"], dict)
    assert isinstance(result["by_room"], dict)


def test_status_degrades_gracefully_when_dolt_unreachable(monkeypatch):
    """A DB-down scenario (connect() raising) must NOT crash status()
    -- it degrades to dolt_reachable=False + empty counts rather than
    propagating the exception, since status() is meant to be a
    health-check tool."""
    import mcp_server.tools.status as status_mod

    def _boom(*args, **kwargs):
        raise ConnectionError("dolt sql-server unreachable (simulated)")

    monkeypatch.setattr(status_mod, "connect", _boom)
    result = status_mod.status()
    assert result == {
        "dolt_reachable": False,
        "total_drawers": 0,
        "by_wing": {},
        "by_room": {},
    }


def test_kg_stats_returns_expected_keys(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """kg_stats() must return AT LEAST {entity_count, triple_count},
    whether it's running the standalone fallback (2 keys) or
    delegating to loom-40ec.4.3's tools/kg.py graph_stats() (4 keys,
    adding current_count/expired_count) -- both are correct depending
    on merge order; this asserts the shared subset rather than an
    exact key set so it passes either way. As of this test running
    (post loom-40ec.4.3 merge), delegation is active."""
    result = kg_stats()
    assert {"entity_count", "triple_count"}.issubset(result.keys())
    assert isinstance(result["entity_count"], int)
    assert isinstance(result["triple_count"], int)


def test_kg_stats_counts_seeded_triples(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Seed a couple of kg_triples rows directly (there is no
    memsrv_kg_add tool yet in this worktree -- that's the sibling
    bead's job) and confirm kg_stats() reflects the growth. Uses a
    before/after delta rather than an exact absolute count, for the
    same cross-test-within-module reason test_status_reflects_seeded_
    drawer_count uses a scoped assertion."""
    from mcp_server.db import connect as db_connect

    before = kg_stats()

    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO kg_triples "
                "(id, subject, predicate, object, created_at) "
                "VALUES (%s, %s, %s, %s, NOW())",
                (
                    f"kg_stats_probe_{os.urandom(4).hex()}",
                    "loom-40ec.4.4",
                    "tests",
                    "kg_stats",
                ),
            )
    finally:
        conn.close()

    after = kg_stats()
    assert after["triple_count"] == before["triple_count"] + 1
    assert after["entity_count"] >= before["entity_count"]


def test_status_and_kg_stats_registered_on_server():
    """memsrv_status/memsrv_kg_stats are registered on the FastMCP
    server built by create_server(), alongside the other tool
    groups."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "memsrv_status" in tool_names
    assert "memsrv_kg_stats" in tool_names
