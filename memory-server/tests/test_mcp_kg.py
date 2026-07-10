"""RED-spec test for loom-40ec.4.3 — MCP knowledge-graph tools
(mempalace_kg_add / mempalace_kg_query / mempalace_kg_invalidate /
mempalace_graph_stats).

Boots the SAME `dolt_server_env` fixture test_mcp_drawers.py and
test_mcp_search.py already define/reuse (imported here rather than
duplicated — see that fixture's docstring in test_mcp_drawers.py for
the full bring-up mechanics: ephemeral tmp data dir + free port via
scripts/start-server.sh, LOOM_MEMORY_* env vars pointed at it for the
duration of THIS test module too, since pytest re-instantiates a
module-scoped fixture per requesting module — this module gets its OWN
ephemeral dolt sql-server, isolated from every other test module's).

Calls the tool functions in mcp_server/tools/kg.py directly — same
plain-function-is-the-registered-tool pattern as tools/drawers.py and
tools/search.py (see tools/drawers.py's module docstring for why that
still exercises the identical code path a real MCP client invocation
would hit). No mocks anywhere in this file — every assertion below
runs against a real dolt sql-server.

Subjects/objects are randomized per test (`_uniq()`) so tests sharing
this module-scoped server never collide with each other's rows —
mirrors test_mcp_search.py's ALPHA_WING/BETA_WING randomization
convention.
"""
import os
import time

import pytest

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py
# rather than re-deriving the same bring-up boilerplate a third time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _uniq(label: str) -> str:
    return f"kgtest_{label}_{os.urandom(4).hex()}"


@pytest.fixture()
def kg_module(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    from mcp_server.tools import kg

    return kg


def test_kg_add_query_directions_and_invalidate_temporal_validity(kg_module):
    """The bead's RED-spec items 1-4, end to end against a real dolt
    sql-server:

      kg_add('A', 'grounded_in', 'B') returns a triple_id;
        kg_query('A', direction='outgoing') returns that fact with
        current=True.
      kg_query('B', direction='incoming') ALSO returns it (found via
        the object-side index).
      kg_query('A', direction='both') returns it too (both is
        genuinely the union, not just defaulting to one side).
      kg_invalidate(triple_id) marks it historical; a subsequent
        kg_query('A', direction='outgoing') (default as_of=None, so
        current-only) no longer includes it; but
        kg_query('A', as_of=<a timestamp from BEFORE the
        invalidation>) still includes it (temporal validity actually
        works).
    """
    k = kg_module
    subject = _uniq("A")
    obj = _uniq("B")

    triple_id = k.kg_add(subject, "grounded_in", obj)
    assert isinstance(triple_id, str) and triple_id

    # Capture a "before invalidation" timestamp for the as_of
    # assertion below, then sleep past a whole-second boundary:
    # kg_triples' valid_to/valid_from columns are plain DATETIME (no
    # fractional-seconds precision), so NOW() at invalidate-time must
    # land in a LATER whole second than this snapshot for the
    # valid_to > as_of comparison to be unambiguous. Dolt's NOW()
    # reflects the sql-server PROCESS's local timezone (verified
    # empirically: this test failed when the snapshot below used
    # time.gmtime() while the local machine's timezone trails UTC —
    # NOW()'s stored value was hours "earlier" than the UTC snapshot),
    # so this uses time.localtime() to match.
    before_invalidation = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    time.sleep(1.1)

    outgoing = k.kg_query(subject, direction="outgoing")
    assert len(outgoing) == 1
    fact = outgoing[0]
    assert fact["direction"] == "outgoing"
    assert fact["subject"] == subject
    assert fact["predicate"] == "grounded_in"
    assert fact["object"] == obj
    assert fact["current"] is True

    incoming = k.kg_query(obj, direction="incoming")
    assert len(incoming) == 1
    assert incoming[0]["direction"] == "incoming"
    assert incoming[0]["subject"] == subject
    assert incoming[0]["object"] == obj

    both = k.kg_query(subject, direction="both")
    assert obj in [row["object"] for row in both]

    updated = k.kg_invalidate(triple_id=triple_id)
    assert updated == 1

    after_invalidate = k.kg_query(subject, direction="outgoing")
    assert after_invalidate == []

    before_snapshot = k.kg_query(subject, direction="outgoing", as_of=before_invalidation)
    assert len(before_snapshot) == 1
    assert before_snapshot[0]["subject"] == subject
    assert before_snapshot[0]["object"] == obj


def test_kg_invalidate_requires_exactly_one_match_form(kg_module):
    """RED-spec item 5: kg_invalidate with neither triple_id nor a
    full subject/predicate/object raises a clear error — and, since
    the brief's validation is symmetric, so does supplying BOTH forms
    or only a PARTIAL (subject, predicate, object)."""
    k = kg_module

    with pytest.raises(ValueError):
        k.kg_invalidate()

    with pytest.raises(ValueError):
        k.kg_invalidate(triple_id="triple_deadbeefdeadbeef", subject=_uniq("X"))

    with pytest.raises(ValueError):
        k.kg_invalidate(subject=_uniq("X"), predicate="grounded_in")  # object missing


def test_kg_invalidate_no_match_returns_zero(kg_module):
    """A triple_id (or subject/predicate/object combo) that matches no
    row is informational, not an error: 0 rows updated."""
    k = kg_module
    assert k.kg_invalidate(triple_id="triple_does_not_exist_00000000") == 0
    assert (
        k.kg_invalidate(
            subject=_uniq("nope"), predicate="grounded_in", object=_uniq("nope2")
        )
        == 0
    )


def test_kg_query_invalid_direction_raises(kg_module):
    k = kg_module
    with pytest.raises(ValueError):
        k.kg_query(_uniq("whatever"), direction="sideways")


def test_graph_stats_reflects_seeded_data(kg_module):
    """RED-spec item 6: graph_stats() reflects seeded data correctly
    across a handful of triples spanning distinct subjects/objects/
    predicates. Asserts DELTAS against a freshly-read baseline (rather
    than absolute counts) since this module-scoped dolt server may
    already carry rows from earlier tests in this module."""
    k = kg_module
    baseline = k.graph_stats()

    s1, s2 = _uniq("s1"), _uniq("s2")
    o1, o2 = _uniq("o1"), _uniq("o2")

    id1 = k.kg_add(s1, "grounded_in", o1)
    k.kg_add(s1, "supersedes_design_of", o2)
    k.kg_add(s2, "grounded_in", o1)

    stats = k.graph_stats()
    assert stats["triple_count"] == baseline["triple_count"] + 3
    assert stats["current_count"] == baseline["current_count"] + 3
    assert stats["expired_count"] == baseline["expired_count"]
    # 4 distinct NEW entities (s1, s2, o1, o2) -- randomized suffixes
    # guarantee none collide with the baseline's existing entities.
    assert stats["entity_count"] == baseline["entity_count"] + 4

    k.kg_invalidate(triple_id=id1)
    stats2 = k.graph_stats()
    assert stats2["triple_count"] == stats["triple_count"]
    assert stats2["current_count"] == stats["current_count"] - 1
    assert stats2["expired_count"] == stats["expired_count"] + 1


def test_kg_tools_registered_on_server():
    """mempalace_kg_add/mempalace_kg_query/mempalace_kg_invalidate/
    mempalace_graph_stats are registered on the FastMCP server built by
    create_server(), alongside the drawer + search tools."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert {
        "mempalace_kg_add",
        "mempalace_kg_query",
        "mempalace_kg_invalidate",
        "mempalace_graph_stats",
    } <= tool_names
