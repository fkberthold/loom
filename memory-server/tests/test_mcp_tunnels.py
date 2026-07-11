"""RED-spec test for loom-40ec.4.5.1 — MCP cross-project TUNNEL tools
(mempalace_create_tunnel / mempalace_list_tunnels / mempalace_delete_tunnel /
mempalace_follow_tunnels / mempalace_find_tunnels / mempalace_traverse_graph /
mempalace_graph_stats).

Root-cause fix for the post-cutover "system got dumber" regression: loom's
CLAUDE.md documents explicit cross-project tunnels (loom/decisions <->
hundred_acre_woods/decisions) as a core convention, but the new Dolt-backed
memory server never implemented tunnels, so cross-project context silently
stopped surfacing after the 2026-07-10 MemPalace cutover. Locked design:
MemPalace decision drawer drawer_loom_decisions_350baa9c115ba358532a8e00
section 1 (and this bead's own bd description).

Boots the SAME module-scoped `dolt_server_env` fixture test_mcp_drawers.py
and test_mcp_kg.py already define/reuse (imported here rather than
re-derived) — an ephemeral tmp dolt sql-server on a free port, with the
LOOM_MEMORY_* env vars pointed at it for the duration of THIS test module.
Calls the tool functions in mcp_server/tools/tunnels.py DIRECTLY — same
plain-function-is-the-registered-tool pattern as tools/drawers.py and
tools/kg.py (the registered MCP tool and the plain function are the SAME
callable object, so calling the function exercises the identical code path a
real MCP client invocation hits). No mocks — every assertion runs against a
real dolt sql-server.

RED SIGNAL: mcp_server/tools/tunnels.py does not exist yet, so the
`tunnels_module` fixture's import fails — that import failure is the expected
RED signal for every test using it; the registration test fails on its
assertion (the six new tunnel tool names are not yet on the server). Do NOT
add anything to schema.sql or create tunnels.py to make this pass at the
test-authoring stage — the failing import IS correct here.

Wing/room names are randomized per test (`_uniq()`) so tests sharing this
module-scoped server never collide with each other's rows and so
create_tunnel's endpoint-existence validation, find_tunnels' >=2-distinct-wings
rule, and graph_stats' baseline deltas all reason over a known, isolated set
of rows — mirrors test_mcp_kg.py's `_uniq()` convention.
"""
import os

import pytest

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py rather
# than re-deriving the same bring-up boilerplate a third time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _uniq(label: str) -> str:
    return f"tuntest_{label}_{os.urandom(4).hex()}"


@pytest.fixture()
def tunnels_module(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    # mcp_server/tools/tunnels.py does not exist yet — THIS import is the RED
    # signal for every test that takes the tunnels_module fixture.
    from mcp_server.tools import tunnels

    return tunnels


@pytest.fixture()
def drawers_module(dolt_server_env):  # noqa: F811
    # Reused verbatim to seed the throwaway drawers that create_tunnel's
    # endpoint-existence validation, follow_tunnels' preview hydration,
    # find_tunnels, and graph_stats all read against. add_drawer is the
    # existing function (loom-40ec.4.1) — not reimplemented here.
    from mcp_server.tools import drawers

    return drawers


def _seed_drawer(drawers_module, wing, room, body="tunnel endpoint drawer"):
    """Create one real drawer in (wing, room) so create_tunnel's endpoint
    validation (both endpoints must have >=1 drawer) has a real row to find.
    Returns the new drawer_id."""
    return drawers_module.add_drawer(wing, room, f"seed {room}", body)


def test_create_tunnel_symmetric_id_and_upsert(tunnels_module, drawers_module):
    """Headline contract: create_tunnel(A, B) then create_tunnel(B, A) (same
    endpoints, reversed) returns the SAME tunnel id and UPSERTS the row
    (updates the label in place, does NOT create a duplicate)."""
    t = tunnels_module
    wing_a, room_a = _uniq("wingA"), _uniq("roomA")
    wing_b, room_b = _uniq("wingB"), _uniq("roomB")
    _seed_drawer(drawers_module, wing_a, room_a)
    _seed_drawer(drawers_module, wing_b, room_b)

    id1 = t.create_tunnel(wing_a, room_a, wing_b, room_b, label="lineage")
    id2 = t.create_tunnel(wing_b, room_b, wing_a, room_a, label="lineage-v2")

    # Symmetric id: the two "wing/room" endpoint strings are sorted then
    # sha256'd and truncated to 16 hex chars, so (A,B) and (B,A) collide into
    # ONE id.
    assert isinstance(id1, str) and isinstance(id2, str)
    assert id1 == id2
    assert len(id1) == 16
    int(id1, 16)  # 16 *hex* chars — raises ValueError (fails the test) if not

    # Upsert, not duplicate: exactly ONE tunnel row touches the (unique) A wing.
    a_tunnels = t.list_tunnels(wing=wing_a)
    assert len(a_tunnels) == 1

    # ...and it carries the UPDATED label from the second (reversed) create.
    conns = [
        c
        for c in t.follow_tunnels(wing_a, room_a)
        if c["connected_wing"] == wing_b and c["connected_room"] == room_b
    ]
    assert len(conns) == 1
    assert conns[0]["label"] == "lineage-v2"
    assert conns[0]["tunnel_id"] == id1


def test_follow_tunnels_hydrates_drawer_preview(tunnels_module, drawers_module):
    """follow_tunnels(source) returns the connected (other-side) endpoint with a
    non-empty, <=300-char preview of the tunnel's drawer text when the tunnel
    carries a drawer_id — the capability that makes a tunnel useful for pulling
    cross-project context rather than just recording that a link exists.
    Symmetric: following from EITHER endpoint finds the same tunnel."""
    t = tunnels_module
    wing_a, room_a = _uniq("srcW"), _uniq("srcR")
    wing_b, room_b = _uniq("tgtW"), _uniq("tgtR")

    # Distinctive body, comfortably < 300 chars, so the hydrated preview equals
    # the full body verbatim. Both endpoints get the SAME text so the assertion
    # holds whether the preview is hydrated from the near- or far-side drawer.
    body = f"CROSSPROJECT-CONTEXT-{os.urandom(4).hex()} lineage payload text"
    assert len(body) < 300
    src_id = drawers_module.add_drawer(wing_a, room_a, "src", body)
    tgt_id = drawers_module.add_drawer(wing_b, room_b, "tgt", body)

    tid = t.create_tunnel(
        wing_a,
        room_a,
        wing_b,
        room_b,
        label="cross",
        source_drawer_id=src_id,
        target_drawer_id=tgt_id,
    )

    conns = [
        c
        for c in t.follow_tunnels(wing_a, room_a)
        if c["connected_wing"] == wing_b and c["connected_room"] == room_b
    ]
    assert len(conns) == 1
    conn = conns[0]
    assert "direction" in conn
    assert conn["tunnel_id"] == tid
    assert conn["label"] == "cross"
    preview = conn["drawer_preview"]
    assert preview  # non-empty when a drawer_id is carried
    assert len(preview) <= 300
    assert preview == body  # real hydrated drawer text, not a placeholder

    # Symmetric: following from the OTHER endpoint finds the same tunnel,
    # pointing back at the first endpoint.
    back = [
        c
        for c in t.follow_tunnels(wing_b, room_b)
        if c["connected_wing"] == wing_a and c["connected_room"] == room_a
    ]
    assert len(back) == 1
    assert back[0]["tunnel_id"] == tid


def test_follow_tunnels_empty_preview_without_drawer_id(tunnels_module, drawers_module):
    """A tunnel created with NO drawer_ids still follows (the link exists), but
    its drawer_preview is empty/absent — the preview is hydrated 'only if a
    drawer_id is set'."""
    t = tunnels_module
    wing_a, room_a = _uniq("plainW"), _uniq("plainR")
    wing_b, room_b = _uniq("plain2W"), _uniq("plain2R")
    _seed_drawer(drawers_module, wing_a, room_a)
    _seed_drawer(drawers_module, wing_b, room_b)

    t.create_tunnel(wing_a, room_a, wing_b, room_b, label="nolink")

    conns = [
        c
        for c in t.follow_tunnels(wing_a, room_a)
        if c["connected_wing"] == wing_b and c["connected_room"] == room_b
    ]
    assert len(conns) == 1
    # No drawer_id on the tunnel -> no hydrated preview (falsy: None, "", or absent).
    assert not conns[0].get("drawer_preview")


def test_create_tunnel_rejects_endpoint_with_zero_drawers(tunnels_module, drawers_module):
    """create_tunnel validates that BOTH endpoints have >=1 drawer in the live
    drawers table; an endpoint room with zero drawers is rejected with a
    ValueError (whichever side is empty, and when both are empty)."""
    t = tunnels_module
    real_w, real_r = _uniq("realW"), _uniq("realR")
    empty_w, empty_r = _uniq("emptyW"), _uniq("emptyR")
    _seed_drawer(drawers_module, real_w, real_r)
    # empty_w/empty_r deliberately gets NO drawer.

    with pytest.raises(ValueError):
        t.create_tunnel(real_w, real_r, empty_w, empty_r)  # target room empty
    with pytest.raises(ValueError):
        t.create_tunnel(empty_w, empty_r, real_w, real_r)  # source room empty
    with pytest.raises(ValueError):
        t.create_tunnel(empty_w, empty_r, _uniq("e2W"), _uniq("e2R"))  # both empty


def test_list_tunnels_filter_matches_either_endpoint(tunnels_module, drawers_module):
    """list_tunnels() with no arg returns all tunnels; list_tunnels(wing=X)
    returns tunnels where X matches EITHER the source OR the target endpoint
    (tunnels are symmetric)."""
    t = tunnels_module
    wing_p, room_p = _uniq("pW"), _uniq("pR")
    wing_q, room_q = _uniq("qW"), _uniq("qR")
    _seed_drawer(drawers_module, wing_p, room_p)
    _seed_drawer(drawers_module, wing_q, room_q)
    t.create_tunnel(wing_p, room_p, wing_q, room_q, label="pq")

    all_tunnels = t.list_tunnels()
    assert isinstance(all_tunnels, list)
    assert len(all_tunnels) >= 1

    # Unique source wing -> exactly the one tunnel I created touches it.
    assert len(t.list_tunnels(wing=wing_p)) == 1
    # Symmetric: matching on the TARGET wing finds the same tunnel.
    assert len(t.list_tunnels(wing=wing_q)) == 1
    # A wing that no tunnel touches -> none.
    assert t.list_tunnels(wing=_uniq("unrelatedW")) == []


def test_delete_tunnel_removes_and_is_idempotent(tunnels_module, drawers_module):
    """delete_tunnel(id) removes the tunnel by id and returns {"deleted": True};
    deleting an already-gone / never-existed id is an idempotent no-op that
    returns {"deleted": False} rather than raising."""
    t = tunnels_module
    wing_a, room_a = _uniq("delW"), _uniq("delR")
    wing_b, room_b = _uniq("del2W"), _uniq("del2R")
    _seed_drawer(drawers_module, wing_a, room_a)
    _seed_drawer(drawers_module, wing_b, room_b)
    tid = t.create_tunnel(wing_a, room_a, wing_b, room_b, label="doomed")
    assert len(t.list_tunnels(wing=wing_a)) == 1

    result = t.delete_tunnel(tid)
    assert isinstance(result, dict)
    assert result.get("deleted") is True
    assert t.list_tunnels(wing=wing_a) == []  # actually gone

    # Idempotent: deleting the same (now-gone) id again does NOT raise.
    again = t.delete_tunnel(tid)
    assert isinstance(again, dict)
    assert again.get("deleted") is False

    # A never-existed id is likewise a no-op, not an exception.
    never = t.delete_tunnel("tunnel_does_not_exist_0000")
    assert isinstance(never, dict)
    assert never.get("deleted") is False


def test_find_tunnels_surfaces_rooms_in_two_or_more_wings(tunnels_module, drawers_module):
    """find_tunnels() with no args returns any room name present in >=2 distinct
    wings in the live drawers table (a passive/derived tunnel); a room present
    in only ONE wing is NOT surfaced."""
    t = tunnels_module
    shared_room = _uniq("sharedR")
    wing_1, wing_2 = _uniq("fw1"), _uniq("fw2")
    # Same room name under TWO distinct wings -> a derived cross-project tunnel.
    _seed_drawer(drawers_module, wing_1, shared_room)
    _seed_drawer(drawers_module, wing_2, shared_room)

    lonely_room = _uniq("lonelyR")
    lonely_wing = _uniq("lonelyW")
    # Same room name, but only ONE wing (two drawers, still one wing) -> NOT a tunnel.
    _seed_drawer(drawers_module, lonely_wing, lonely_room)
    _seed_drawer(drawers_module, lonely_wing, lonely_room)

    found = t.find_tunnels()
    assert isinstance(found, list)
    found_rooms = {r.get("room") for r in found}
    assert shared_room in found_rooms
    assert lonely_room not in found_rooms

    # Narrowing to the two specific wings still surfaces the room they share.
    scoped = t.find_tunnels(wing_a=wing_1, wing_b=wing_2)
    assert isinstance(scoped, list)
    assert shared_room in {r.get("room") for r in scoped}


def test_traverse_graph_returns_list_and_tolerates_isolation(tunnels_module, drawers_module):
    """traverse_graph(start_room) returns a list and does not error. A room with
    no shared-wing connections yields an empty (or single-node) result; a room
    that shares a wing with another room yields a (non-erroring) list. Hop
    mechanics are an implementation detail and are deliberately NOT pinned."""
    t = tunnels_module
    # Isolated: a unique wing whose ONLY room is this one -> no shared-wing edges.
    iso_wing, iso_room = _uniq("isoW"), _uniq("isoR")
    _seed_drawer(drawers_module, iso_wing, iso_room)

    iso_result = t.traverse_graph(iso_room)
    assert isinstance(iso_result, list)
    assert len(iso_result) <= 1  # empty or single-node — never errors on isolation

    # Connected: two rooms sharing one wing -> a shared-wing edge between them.
    conn_wing = _uniq("connW")
    room_x, room_y = _uniq("rx"), _uniq("ry")
    _seed_drawer(drawers_module, conn_wing, room_x)
    _seed_drawer(drawers_module, conn_wing, room_y)

    conn_result = t.traverse_graph(room_x)
    assert isinstance(conn_result, list)


def test_graph_stats_reflects_cross_wing_rooms(tunnels_module, drawers_module):
    """graph_stats() returns at least {total_rooms, tunnel_rooms, total_edges}.
    Asserts DELTAS against a freshly-read baseline (this module-scoped server
    already carries rows from earlier tests): adding one NEW room under two
    distinct wings adds exactly one tunnel_room and strictly increases both
    total_rooms and total_edges. Same baseline-delta idiom as
    test_mcp_kg.py::test_graph_stats_reflects_seeded_data."""
    t = tunnels_module
    baseline = t.graph_stats()
    for key in ("total_rooms", "tunnel_rooms", "total_edges"):
        assert key in baseline
        assert isinstance(baseline[key], int)

    new_room = _uniq("statsR")
    _seed_drawer(drawers_module, _uniq("sw1"), new_room)
    _seed_drawer(drawers_module, _uniq("sw2"), new_room)

    stats = t.graph_stats()
    # Exactly one new room now spans >=2 distinct wings.
    assert stats["tunnel_rooms"] == baseline["tunnel_rooms"] + 1
    # A brand-new room name strictly grows the distinct-room count...
    assert stats["total_rooms"] > baseline["total_rooms"]
    # ...and a brand-new cross-wing room adds at least one derived edge.
    assert stats["total_edges"] > baseline["total_edges"]


def test_tunnel_tools_registered_on_server():
    """The tunnel tools are registered on the FastMCP server built by
    create_server(), prefixed `mempalace_` per the server.py convention —
    mirrors test_mcp_kg.py::test_kg_tools_registered_on_server.

    Asserts the SIX unambiguously-new tunnel tool names. `mempalace_graph_stats`
    is deliberately NOT asserted here: tools/kg.py already registers that exact
    name, so its presence would not distinguish tunnels' registration, and the
    graph_stats naming collision (both modules define a graph_stats) is an
    implementer decision this RED spec does not pin (design drawer
    drawer_loom_decisions_350baa9c115ba358532a8e00 section 1)."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {tool.name for tool in server._tool_manager.list_tools()}
    assert {
        "mempalace_create_tunnel",
        "mempalace_list_tunnels",
        "mempalace_delete_tunnel",
        "mempalace_follow_tunnels",
        "mempalace_find_tunnels",
        "mempalace_traverse_graph",
    } <= tool_names
