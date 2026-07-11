"""RED-spec test for loom-40ec.4.5.2 — drawer tagging tools
(mempalace_tag_drawer / mempalace_untag_drawer / mempalace_list_tags)
plus the new `tag_filter` parameter on mempalace_search.

This is FRESH design — no upstream reference implementation existed
(grepped, confirmed absent). The contract lives in MemPalace decision
drawer drawer_loom_decisions_350baa9c115ba358532a8e00 section 2 and on
bd loom-40ec.4.5.2.

Boots the SAME `dolt_server_env` fixture test_mcp_drawers.py /
test_mcp_search.py / test_mcp_kg.py already define/reuse (imported here
rather than duplicated — see that fixture's docstring in
test_mcp_drawers.py for the full bring-up mechanics: ephemeral tmp data
dir + free port via scripts/start-server.sh, LOOM_MEMORY_* env vars
pointed at it for the duration of THIS test module too, since pytest
re-instantiates a module-scoped fixture per requesting module — this
module gets its OWN ephemeral dolt sql-server, isolated from every
other test module's).

Throwaway drawers are created via the REAL write path
(mcp_server.tools.drawers.add_drawer) — no hand-rolled INSERT SQL, per
the bead brief. Wing/room/content are randomized (`_uniq()`) so tests
sharing this module-scoped server never collide with each other's rows
— mirrors test_mcp_search.py's ALPHA_WING/BETA_WING and test_mcp_kg.py's
_uniq() convention. No mocks anywhere in this file: every assertion
runs against a real dolt sql-server.

RED signals (this file is authored BEFORE the implementation):
  * The tag_drawer / untag_drawer / list_tags tests take the
    `tags_module` fixture, whose body does `from mcp_server.tools import
    tags`. Because mcp_server/tools/tags.py does not exist yet, that
    import fails (ModuleNotFoundError) — the expected RED signal for
    those tests.
  * The `tag_filter`-on-search tests call the real, already-existing
    mcp_server.tools.search.search() with the new `tag_filter=` kwarg.
    Until the implementer adds that parameter, the call raises
    `TypeError: search() got an unexpected keyword argument
    'tag_filter'` — a valid, expected RED signal for those tests.
  * test_tag_tools_registered_on_server asserts the three new tool
    names are registered on create_server()'s FastMCP instance; until
    register_tag_tools() is wired into mcp_server/server.py the set is
    absent (AssertionError) — the expected RED signal there.
"""
import os

import pytest

from mcp_server.tools import drawers as drawers_mod
from mcp_server.tools.search import search

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py
# rather than re-deriving the same bring-up boilerplate a fourth time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _uniq(label: str) -> str:
    return f"tagtest_{label}_{os.urandom(4).hex()}"


# A phrase distinctive enough that a real embedding model's
# nearest-neighbor search reliably keeps this module's seeded drawers
# clustered together at the top of an (in-wing-scoped) query, so that
# what differentiates the search results is the tag_filter, not the
# semantic distance. Copied verbatim as the query per the same
# strongest-signal reasoning test_mcp_search.py's UNIQUE_PHRASE uses.
MARKER_PHRASE = (
    "The quornbeck cistern hums at forty-two hertz beneath the "
    "abandoned funicular, per the caretaker's midnight ledger."
)


@pytest.fixture()
def tags_module(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Import mcp_server.tools.tags AFTER the ephemeral server's env
    vars are set. Since tools/tags.py does not exist yet, this import
    fails — THAT ModuleNotFoundError is the RED signal for every test
    that takes this fixture."""
    from mcp_server.tools import tags

    return tags


# --------------------------------------------------------------------------
# tag_drawer / untag_drawer / list_tags — the join-table CRUD contract
# --------------------------------------------------------------------------


def test_tag_then_list_returns_the_tag(tags_module):
    """RED-spec item 1: tag_drawer(existing_drawer_id, 'exploration')
    followed by list_tags(existing_drawer_id) returns ['exploration'].
    """
    t = tags_module
    wing, room = _uniq("wing"), "drawers"
    drawer_id = drawers_mod.add_drawer(wing, room, "taggable", _uniq("body"))

    assert t.tag_drawer(drawer_id, "exploration") is None
    assert t.list_tags(drawer_id) == ["exploration"]


def test_tag_drawer_is_idempotent_no_duplicate(tags_module):
    """RED-spec item 2: calling tag_drawer twice with the same
    (drawer_id, tag) does not error and does not duplicate —
    list_tags still returns exactly one 'exploration' entry."""
    t = tags_module
    wing, room = _uniq("wing"), "drawers"
    drawer_id = drawers_mod.add_drawer(wing, room, "double tag", _uniq("body"))

    t.tag_drawer(drawer_id, "exploration")
    t.tag_drawer(drawer_id, "exploration")  # second call must be a no-op, not an error

    tags = t.list_tags(drawer_id)
    assert tags == ["exploration"]
    assert tags.count("exploration") == 1


def test_list_tags_returns_all_distinct_tags(tags_module):
    """A drawer can carry multiple distinct tags; list_tags returns
    them all (order-independent — compared as a set)."""
    t = tags_module
    wing, room = _uniq("wing"), "drawers"
    drawer_id = drawers_mod.add_drawer(wing, room, "multi tag", _uniq("body"))

    t.tag_drawer(drawer_id, "exploration")
    t.tag_drawer(drawer_id, "design")
    t.tag_drawer(drawer_id, "provenance:mined")

    assert set(t.list_tags(drawer_id)) == {"exploration", "design", "provenance:mined"}


def test_list_tags_empty_for_untagged_drawer(tags_module):
    """A freshly-created, never-tagged drawer has an empty tag list
    (not an error, not None)."""
    t = tags_module
    wing, room = _uniq("wing"), "drawers"
    drawer_id = drawers_mod.add_drawer(wing, room, "untagged", _uniq("body"))

    assert t.list_tags(drawer_id) == []


def test_untag_drawer_removes_tag(tags_module):
    """RED-spec item 4 (part 1): untag_drawer(drawer_id, tag) removes
    the tag."""
    t = tags_module
    wing, room = _uniq("wing"), "drawers"
    drawer_id = drawers_mod.add_drawer(wing, room, "untag me", _uniq("body"))

    t.tag_drawer(drawer_id, "exploration")
    t.tag_drawer(drawer_id, "design")
    assert set(t.list_tags(drawer_id)) == {"exploration", "design"}

    assert t.untag_drawer(drawer_id, "exploration") is None
    assert t.list_tags(drawer_id) == ["design"]


def test_untag_drawer_absent_tag_is_idempotent(tags_module):
    """RED-spec item 4 (part 2): untag_drawer is idempotent — removing
    a tag the drawer never had does not error and leaves the existing
    tags untouched."""
    t = tags_module
    wing, room = _uniq("wing"), "drawers"
    drawer_id = drawers_mod.add_drawer(wing, room, "idempotent untag", _uniq("body"))

    t.tag_drawer(drawer_id, "design")

    # Removing a tag that was never applied: no error, no effect.
    assert t.untag_drawer(drawer_id, "exploration") is None
    assert t.list_tags(drawer_id) == ["design"]

    # Removing the same tag twice is likewise a no-op the second time.
    t.untag_drawer(drawer_id, "design")
    assert t.list_tags(drawer_id) == []
    t.untag_drawer(drawer_id, "design")  # already gone — still no error
    assert t.list_tags(drawer_id) == []


# --------------------------------------------------------------------------
# search(tag_filter=...) — the new parameter on the EXISTING search()
# --------------------------------------------------------------------------


def test_search_tag_filter_excludes_untagged_drawer(dolt_server_env):
    """RED via TypeError: this test deliberately does NOT take the
    tags_module fixture, so it isolates the `search(tag_filter=...)`
    signature addition. It calls the real, existing search() with the
    new `tag_filter=` kwarg — which raises
    `TypeError: search() got an unexpected keyword argument
    'tag_filter'` until the implementer adds the parameter (the
    expected RED signal here).

    Once implemented, the assertion is meaningful without any tagging:
    an untagged drawer must be EXCLUDED from a tag_filter'd search
    (tag_filter='exploration' keeps only drawers carrying that tag).
    """
    wing = _uniq("wing")
    body = f"{MARKER_PHRASE} {_uniq('untagged')}"
    drawer_id = drawers_mod.add_drawer(wing, "drawers", "untagged", body)

    results = search(MARKER_PHRASE, wing=wing, tag_filter=["exploration"], limit=100)
    result_ids = [r["id"] for r in results]
    assert drawer_id not in result_ids


def test_search_tag_filter_single_tag_returns_only_tagged(tags_module):
    """RED-spec item 3: mempalace_search(query=..., tag_filter=
    ['exploration']) only returns drawers that have been tagged
    'exploration'. Single-tag (the common case): of two drawers
    carrying the same marker phrase, only the one tagged 'exploration'
    comes back."""
    t = tags_module
    wing = _uniq("wing")

    tagged_id = drawers_mod.add_drawer(
        wing, "drawers", "tagged", f"{MARKER_PHRASE} {_uniq('tagged')}"
    )
    untagged_id = drawers_mod.add_drawer(
        wing, "drawers", "untagged", f"{MARKER_PHRASE} {_uniq('untagged')}"
    )
    t.tag_drawer(tagged_id, "exploration")

    results = search(MARKER_PHRASE, wing=wing, tag_filter=["exploration"], limit=100)
    result_ids = {r["id"] for r in results}

    assert tagged_id in result_ids
    assert untagged_id not in result_ids


def test_search_tag_filter_and_semantics_multi_tag(tags_module):
    """RED-spec item 5: tag_filter uses ALL-match / AND semantics when
    multiple tags are given — a drawer must carry EVERY tag in
    tag_filter to match.

      A: tagged {exploration, design}  -> matches ['exploration','design']
      B: tagged {exploration}          -> does NOT match (missing design)
      C: tagged {design}               -> does NOT match (missing exploration)
    """
    t = tags_module
    wing = _uniq("wing")

    a_id = drawers_mod.add_drawer(wing, "drawers", "A both", f"{MARKER_PHRASE} {_uniq('A')}")
    b_id = drawers_mod.add_drawer(wing, "drawers", "B expl", f"{MARKER_PHRASE} {_uniq('B')}")
    c_id = drawers_mod.add_drawer(wing, "drawers", "C dsgn", f"{MARKER_PHRASE} {_uniq('C')}")

    t.tag_drawer(a_id, "exploration")
    t.tag_drawer(a_id, "design")
    t.tag_drawer(b_id, "exploration")
    t.tag_drawer(c_id, "design")

    results = search(
        MARKER_PHRASE, wing=wing, tag_filter=["exploration", "design"], limit=100
    )
    result_ids = {r["id"] for r in results}

    assert a_id in result_ids
    assert b_id not in result_ids
    assert c_id not in result_ids


def test_search_without_tag_filter_unaffected(tags_module):
    """Regression guard: search WITHOUT tag_filter (or tag_filter=None)
    still returns tagged AND untagged drawers alike — the new parameter
    is purely additive and does not change unfiltered behavior."""
    t = tags_module
    wing = _uniq("wing")

    tagged_id = drawers_mod.add_drawer(
        wing, "drawers", "tagged", f"{MARKER_PHRASE} {_uniq('tagged')}"
    )
    untagged_id = drawers_mod.add_drawer(
        wing, "drawers", "untagged", f"{MARKER_PHRASE} {_uniq('untagged')}"
    )
    t.tag_drawer(tagged_id, "exploration")

    results = search(MARKER_PHRASE, wing=wing, limit=100)
    result_ids = {r["id"] for r in results}

    assert tagged_id in result_ids
    assert untagged_id in result_ids


# --------------------------------------------------------------------------
# Registration sanity check — mirrors test_kg_tools_registered_on_server
# --------------------------------------------------------------------------


def test_tag_tools_registered_on_server():
    """mempalace_tag_drawer / mempalace_untag_drawer / mempalace_list_tags
    are registered on the FastMCP server built by create_server(),
    alongside the drawer + search + kg tools."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert {
        "mempalace_tag_drawer",
        "mempalace_untag_drawer",
        "mempalace_list_tags",
    } <= tool_names
