"""RED-spec test for loom-40ec.4.2 — memsrv_search (MCP semantic
search tool, the mempalace_search equivalent).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py already defines (imported here rather than
duplicated — see that fixture's docstring in test_mcp_drawers.py for
the full bring-up mechanics: ephemeral tmp data dir + free port via
scripts/start-server.sh, LOOM_MEMORY_* env vars pointed at it for the
duration of THIS test module too, since pytest re-instantiates a
module-scoped fixture per requesting module).

Seeds a small multi-wing/multi-room corpus via add_drawer() (the real
write path — no hand-rolled INSERT SQL, per the bead brief) and
exercises memsrv_search's wing/room scoping end-to-end against real
VEC_DISTANCE queries. No mocks anywhere in this file.
"""
import os

import pytest

from mcp_server.tools import drawers as drawers_mod
from mcp_server.tools.search import search

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py
# rather than re-deriving the same bring-up boilerplate a second time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401

# Randomized wing names so this module's corpus can never collide with
# rows any other test module (or a prior run) may have left behind in
# the (ephemeral, per-module) dolt server.
ALPHA_WING = f"loomtest_search_alpha_{os.urandom(4).hex()}"
BETA_WING = f"loomtest_search_beta_{os.urandom(4).hex()}"
KITTENS_ROOM = "kittens"
PUPPIES_ROOM = "puppies"
WIDGETS_ROOM = "widgets"

# A phrase distinctive enough that a real embedding model's
# nearest-neighbor search reliably surfaces its owning drawer at the
# very top when the SAME phrase is used as the query — this is a
# semantic-search test, not an exact-string-match test, but copying
# the phrase verbatim (per the bead's RED spec) gives the strongest,
# least-flaky signal.
UNIQUE_PHRASE = (
    "The zorbleflax nebula emits chartreuse photons in irregular "
    "bursts every third Tuesday, according to the observatory log."
)

# Appended to every seeded drawer's body so an UNSCOPED search on this
# marker phrase deterministically has a "closest match" in each wing
# (used by the cross-wing + narrowing tests below).
SHARED_MARKER = (
    "Cross-project calibration marker sentence for the unscoped "
    "search regression test."
)


@pytest.fixture(scope="module")
def seeded_corpus(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Seeds >=20 drawers spanning 2 distinct wings via add_drawer()
    (the real write path): ALPHA_WING has two rooms (kittens: 6 rows,
    puppies: 6 rows), BETA_WING has one room (widgets: 10 rows) —
    22 rows total. Returns a dict of drawer_ids grouped by
    wing/room so tests can assert on specific ids."""
    ids = {"alpha_kittens": [], "alpha_puppies": [], "beta_widgets": []}

    # alpha/kittens: one drawer carries UNIQUE_PHRASE, the rest are a
    # topically-distinct filler cluster (photosynthesis).
    ids["alpha_kittens"].append(
        drawers_mod.add_drawer(
            ALPHA_WING,
            KITTENS_ROOM,
            "Zorbleflax nebula observation",
            f"{UNIQUE_PHRASE} {SHARED_MARKER}",
        )
    )
    for i in range(5):
        ids["alpha_kittens"].append(
            drawers_mod.add_drawer(
                ALPHA_WING,
                KITTENS_ROOM,
                f"Kitten photosynthesis note {i}",
                f"Chlorophyll absorbs sunlight in leaf cell {i}. {SHARED_MARKER}",
            )
        )

    # alpha/puppies: same wing, DIFFERENT room, unrelated topic (urban
    # beekeeping) — exercises the "room narrows further than wing
    # alone" RED-spec item.
    for i in range(6):
        ids["alpha_puppies"].append(
            drawers_mod.add_drawer(
                ALPHA_WING,
                PUPPIES_ROOM,
                f"Urban beekeeping note {i}",
                f"Beekeepers inspect hive frame {i} for larvae. {SHARED_MARKER}",
            )
        )

    # beta/widgets: entirely different wing, unrelated topic
    # (quarterly financial reporting).
    for i in range(10):
        ids["beta_widgets"].append(
            drawers_mod.add_drawer(
                BETA_WING,
                WIDGETS_ROOM,
                f"Quarterly compliance memo {i}",
                f"Finance reviewed ledger reconciliation item {i}. {SHARED_MARKER}",
            )
        )

    return ids


def test_search_scoped_to_wing_returns_seeded_drawer(seeded_corpus):
    """search(<phrase copied from a seeded drawer's text>,
    wing=<that drawer's wing>) returns that drawer's id in the top
    results (and, given how distinctive UNIQUE_PHRASE is against the
    filler corpus, as the single closest match)."""
    target_id = seeded_corpus["alpha_kittens"][0]
    results = search(UNIQUE_PHRASE, wing=ALPHA_WING, limit=5)
    result_ids = [r["id"] for r in results]
    assert target_id in result_ids
    assert results[0]["id"] == target_id


def test_search_scoped_to_other_wing_excludes_it(seeded_corpus):
    """The SAME query with wing=<the OTHER wing> does NOT return the
    alpha drawer — confirms wing scoping actually FILTERS via the
    WHERE clause (+ the (wing, room) index), not just re-ranks."""
    target_id = seeded_corpus["alpha_kittens"][0]
    results = search(UNIQUE_PHRASE, wing=BETA_WING, limit=10)
    result_ids = [r["id"] for r in results]
    assert target_id not in result_ids
    assert all(r["wing"] == BETA_WING for r in results)


def test_search_unscoped_spans_both_wings(seeded_corpus):
    """An UNSCOPED search (no wing/room) still returns results across
    both wings — cross-project search still works."""
    total_seeded = sum(len(v) for v in seeded_corpus.values())
    results = search(SHARED_MARKER, limit=total_seeded)
    wings_seen = {r["wing"] for r in results}
    assert ALPHA_WING in wings_seen
    assert BETA_WING in wings_seen


def test_search_wing_and_room_narrows_further_than_wing_alone(seeded_corpus):
    """search(query, wing=X, room=Y) narrows further than wing=X
    alone (ALPHA_WING has 2 distinct rooms: kittens, puppies)."""
    wing_only = search(SHARED_MARKER, wing=ALPHA_WING, limit=100)
    wing_and_room = search(
        SHARED_MARKER, wing=ALPHA_WING, room=KITTENS_ROOM, limit=100
    )

    assert len(wing_and_room) < len(wing_only)
    assert all(r["room"] == KITTENS_ROOM for r in wing_and_room)
    assert {r["id"] for r in wing_and_room} <= {r["id"] for r in wing_only}


def test_search_result_shape(seeded_corpus):
    """Result dicts carry exactly the documented shape:
    {id, wing, room, title, snippet, distance}."""
    results = search(UNIQUE_PHRASE, wing=ALPHA_WING, limit=1)
    assert len(results) == 1
    row = results[0]
    assert set(row.keys()) == {"id", "wing", "room", "title", "snippet", "distance"}
    assert isinstance(row["snippet"], str)
    assert isinstance(row["distance"], float)


def test_search_registered_on_server():
    """memsrv_search is registered on the FastMCP server built by
    create_server(), alongside the drawer tools."""
    from mcp_server.server import create_server

    server = create_server()
    # FastMCP.list_tools() is async (it's an MCP-protocol handler);
    # the underlying ToolManager.list_tools() is sync and gives the
    # same registered-tools view, so this test stays a plain sync
    # test rather than needing asyncio machinery.
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "memsrv_search" in tool_names
