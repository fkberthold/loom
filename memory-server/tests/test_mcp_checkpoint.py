"""RED-spec test for loom-40ec.4.5.4 — mempalace_checkpoint (composed
dedupe-then-add-then-diary convenience wrapper).

checkpoint is a PURE COMPOSITION of three existing tools — no new
schema, no new query logic: for each input item it runs
check_duplicate() (tools/search.py), and if the item is not already a
near-duplicate it runs add_drawer() (tools/drawers.py); an optional
`diary` argument finally runs diary_write() (tools/diary.py). The batch
partitions its input items across three parallel result lists —
`added` / `duplicates` / `errors` — and reports the diary write (if
any) under `diary`.

Interface under test (does not exist yet — this is the RED signal):

    # mcp_server/tools/checkpoint.py
    def checkpoint(items, diary=None, dedup_threshold=0.9) -> dict
        # -> {added: [...], duplicates: [...], errors: [...],
        #     diary: {...} or None}
    def register_checkpoint_tools(mcp) -> None   # registers mempalace_checkpoint

Each item is a {wing, room, title, content} dict; `title` is REQUIRED
(a title-omitted item is out of scope by design and is NOT tested as a
"should work" case). Per-item failures (e.g. a malformed item missing a
required field) are caught and land in `errors` rather than aborting the
whole batch.

Boots a REAL dolt sql-server via the SAME module-scoped `dolt_server_env`
fixture tests/test_mcp_drawers.py defines (imported here rather than
duplicated — this module gets its OWN isolated ephemeral server
instance). Calls checkpoint() directly (same plain-function-is-the-
registered-tool pattern as every sibling tool module) — no mocks
anywhere; every assertion runs against real embeddings + VEC_DISTANCE
+ real SQL.

While RED, `checkpoint` does not exist: the `checkpoint_module` fixture's
`from mcp_server.tools import checkpoint` raises ImportError (mirrors
test_mcp_kg.py's fixture-scoped-import convention), and
test_checkpoint_tools_registered_on_server() fails its membership
assertion because create_server() does not yet register the tool.

Cross-test dissimilarity note: the module-scoped dolt server is SHARED
by every test below, and checkpoint's dedup step (check_duplicate) is
UNSCOPED (corpus-wide). wing/room/title are randomized via _uniq() so
their ROWS never collide, but the embedded `content` cannot be a bare
short _uniq() token — two such tokens share a long literal prefix and
can embed above the 0.9 dedup threshold, producing a cross-test
false-duplicate verdict. So each test's `content` is a distinctive prose
sentence on its OWN topic, carrying a unique _uniq() marker — the exact
strategy tests/test_mcp_check_duplicate.py uses, so cross-test seeding
can neither satisfy nor defeat another test's dedup verdict.
"""
import os

import pytest

from mcp_server.tools.diary import diary_read
from mcp_server.tools.drawers import list_drawers

# Reuse the existing module-scoped dolt_server_env fixture rather than
# re-deriving the bring-up boilerplate.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _uniq(label: str) -> str:
    """Randomized-unique token for wing/room/title values (and the
    per-content marker below), so this module-scoped server's rows never
    collide across runs or between tests."""
    return f"cptest_{label}_{os.urandom(4).hex()}"


def _distinct_content(topic_sentence: str) -> str:
    """A distinctive prose `content` on its OWN topic, carrying a unique
    _uniq() marker. Distinct TOPICS keep different tests' contents
    mutually DISSIMILAR under the embedding model (so corpus-wide dedup
    never cross-fires); the marker keeps them unique across runs. See
    this module's docstring for why a bare _uniq() token is unsafe here.
    """
    return f"{topic_sentence} [{_uniq('marker')}]"


def _drawer_count(wing: str, room: str) -> int:
    """Exact row count in a (wing, room) via the real list_drawers()
    tool — its `total` field is COUNT(*) for that scope. Since wing/room
    are randomized-unique per test, this counts exactly the drawers the
    test under inspection created."""
    rows = list_drawers(wing=wing, room=room, limit=100)
    return rows[0]["total"] if rows else 0


@pytest.fixture()
def checkpoint_module(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Import mcp_server.tools.checkpoint AFTER the ephemeral server's
    env vars are set. While RED the module does not exist, so this import
    raises ImportError — the intended RED signal for this bead."""
    from mcp_server.tools import checkpoint

    return checkpoint


def test_checkpoint_fresh_add_returns_one_added_no_dups_no_errors(checkpoint_module):
    """A single item with no prior matching drawer: exactly one entry in
    `added`, empty `duplicates`/`errors`, and (no diary passed) `diary`
    is None. The drawer really lands — one row now lives in this test's
    unique (wing, room)."""
    cp = checkpoint_module
    wing, room = _uniq("wing"), _uniq("room")
    item = {
        "wing": wing,
        "room": room,
        "title": _uniq("t"),
        "content": _distinct_content(
            "The tin-trade tariff ledger for the northern estuary was "
            "ratified at first light by the harbor reeve."
        ),
    }

    result = cp.checkpoint([item])

    assert len(result["added"]) == 1
    assert result["duplicates"] == []
    assert result["errors"] == []
    # No diary argument -> diary field is None per the interface's
    # {..., diary: {...} or None} shape.
    assert result["diary"] is None
    # The add really happened.
    assert _drawer_count(wing, room) == 1


def test_checkpoint_same_item_twice_is_duplicate_not_added_row_count_unchanged(
    checkpoint_module,
):
    """Calling checkpoint AGAIN with the SAME item (identical content ->
    cosine similarity 1.0, well above the default 0.9 dedup threshold)
    classifies it under `duplicates`, NOT `added`, and creates no new
    drawer row: the drawers-table count for this (wing, room) is
    unchanged from the first call."""
    cp = checkpoint_module
    wing, room = _uniq("wing"), _uniq("room")
    item = {
        "wing": wing,
        "room": room,
        "title": _uniq("t"),
        "content": _distinct_content(
            "The glacier core drilled from the Sable Icefield preserved "
            "eleven distinct ash layers from ancient eruptions."
        ),
    }

    first = cp.checkpoint([item])
    assert len(first["added"]) == 1
    assert first["duplicates"] == []
    count_after_first = _drawer_count(wing, room)
    assert count_after_first == 1

    second = cp.checkpoint([item])
    assert len(second["duplicates"]) == 1
    assert second["added"] == []
    assert second["errors"] == []
    # Row count unchanged — the duplicate was NOT persisted a second time.
    assert _drawer_count(wing, room) == count_after_first


def test_checkpoint_writes_retrievable_diary(checkpoint_module):
    """Passing a diary={'agent_name', 'topic', 'entry'} results in a
    retrievable diary drawer afterward (diary_read finds the entry), and
    the `diary` result field is populated (a dict, not None). The item in
    the same call still lands in `added`."""
    cp = checkpoint_module
    wing, room = _uniq("wing"), _uniq("room")
    item = {
        "wing": wing,
        "room": room,
        "title": _uniq("t"),
        "content": _distinct_content(
            "The loom master recorded a new twill sequence for the "
            "crimson selvedge commissioned by the guild hall."
        ),
    }
    agent = _uniq("agent")
    topic = _uniq("topic")
    entry_text = _distinct_content(
        "Tonight the observatory recalibrated the meridian telescope "
        "against the drift of the polar star."
    )

    result = cp.checkpoint(
        [item],
        diary={"agent_name": agent, "topic": topic, "entry": entry_text},
    )

    # The item still went through the add path alongside the diary write.
    assert len(result["added"]) == 1
    # `diary` is populated (dict, not None) when a diary is written.
    assert isinstance(result["diary"], dict)

    # The diary entry is actually retrievable afterward.
    entries = diary_read(agent, 10)
    matching = [e for e in entries if e["entry"] == entry_text]
    assert len(matching) == 1
    assert matching[0]["topic"] == topic


def test_checkpoint_per_item_error_isolated_from_good_item(checkpoint_module):
    """A malformed item (missing the required `content` key) must be
    caught and land in `errors` WITHOUT aborting the batch: the good item
    in the same call still lands in `added`, and exactly the good item is
    persisted."""
    cp = checkpoint_module
    wing, room = _uniq("wing"), _uniq("room")
    good = {
        "wing": wing,
        "room": room,
        "title": _uniq("t"),
        "content": _distinct_content(
            "The apiary logged a surge in linden nectar from the terraced "
            "hives above the quarry road."
        ),
    }
    # Missing the required `content` key -> a per-item error, not a
    # batch-aborting exception.
    bad = {"wing": wing, "room": room, "title": _uniq("t")}

    # The whole call must NOT raise.
    result = cp.checkpoint([good, bad])

    assert len(result["added"]) == 1
    assert len(result["errors"]) == 1
    assert result["duplicates"] == []
    # Exactly the good item was persisted; the bad one created no row.
    assert _drawer_count(wing, room) == 1


def test_checkpoint_tools_registered_on_server():
    """mempalace_checkpoint is registered on the FastMCP server built by
    create_server(), alongside the drawer/search/kg/diary/status tool
    groups (mirrors the sibling registration tests)."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "mempalace_checkpoint" in tool_names
