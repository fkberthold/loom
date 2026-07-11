"""RED-spec test for loom-40ec.4.5.3 — drawer-deletion MCP tools
(mempalace_delete_drawer / mempalace_delete_by_source).

Ports the deletion capability the retired MemPalace/chroma system had
but this Dolt-backed server does not yet: delete a single drawer by id,
and bulk-delete every drawer sharing a source_file — the latter guarded
by a dry_run=True DEFAULT, so an accidental call previews rather than
destroys.

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py defines (imported here rather than
duplicated — this module gets its OWN isolated, module-scoped ephemeral
server instance; see that fixture's docstring for the bring-up
mechanics). Calls the tool functions in mcp_server/tools/drawers.py
DIRECTLY, the same plain-function-is-the-registered-tool pattern the
sibling drawer/kg/search test modules use (see tools/drawers.py's
module docstring for why that exercises the identical code path a real
MCP client invocation would hit). Seeds via the real add_drawer() write
path (no hand-rolled INSERT SQL) and counts rows via the real connect()
helper. No mocks anywhere in this file.

delete_drawer / delete_by_source do NOT exist on the drawers module
yet — this bead is RED until the implementer adds them. They are
accessed as ATTRIBUTES on the fixture-provided module (d.delete_drawer),
NOT module-level imports, so while RED each test surfaces an
AttributeError naming the missing function rather than a whole-module
collection error (which would also mask the registration test). That
AttributeError is the expected RED signal.

Every test uses a randomized-unique source_file / content marker
(`_uniq()`) so tests sharing this module-scoped server never satisfy or
defeat one another's match counts — mirrors test_mcp_kg.py's per-test
randomization convention.
"""
import os

import pytest

from mcp_server.db import connect

# Reuse the existing dolt_server_env fixture rather than re-deriving the
# bring-up boilerplate a fourth time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def _uniq(label: str) -> str:
    return f"deltest_{label}_{os.urandom(4).hex()}"


def _row_count() -> int:
    """Total drawer rows, via the same connect() helper the tools use —
    the 'COUNT before/after' instrument the dry-run contract calls for."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS c FROM drawers")
            return cur.fetchone()["c"]
    finally:
        conn.close()


@pytest.fixture()
def drawers_module(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Import mcp_server.tools.drawers AFTER the ephemeral server's env
    vars are set (dolt_server_env set them at module scope by the time
    any test using this fixture runs)."""
    from mcp_server.tools import drawers

    return drawers


def test_delete_drawer_removes_it(drawers_module):
    """Core RED spec: create a throwaway drawer, delete_drawer(its_id)
    removes it — a subsequent get_drawer on that id raises
    DrawerNotFoundError. The return dict carries
    {success, drawer_id, deleted_ids, chunks_deleted}.
    """
    d = drawers_module
    drawer_id = d.add_drawer("loom", "decisions", "throwaway", _uniq("body"))

    # Precondition: it exists.
    assert d.get_drawer(drawer_id)["id"] == drawer_id

    result = d.delete_drawer(drawer_id)
    assert result["success"] is True
    assert result["drawer_id"] == drawer_id
    assert drawer_id in result["deleted_ids"]
    assert isinstance(result["chunks_deleted"], int)

    # Postcondition: it's gone — get_drawer now 404s.
    with pytest.raises(d.DrawerNotFoundError):
        d.get_drawer(drawer_id)


def test_delete_drawer_nonexistent_is_idempotent(drawers_module):
    """delete_drawer on an id that matches no row does NOT raise
    (idempotent) — it returns success=False with an empty deleted_ids
    and zero chunks_deleted, rather than surfacing an error."""
    d = drawers_module
    missing = f"drawer_does_not_exist_{os.urandom(12).hex()}"

    result = d.delete_drawer(missing)  # must not raise
    assert result["success"] is False
    assert result["drawer_id"] == missing
    assert result["deleted_ids"] == []
    assert result["chunks_deleted"] == 0


def test_delete_by_source_dry_run_no_match_deletes_nothing(drawers_module):
    """delete_by_source(<a source nothing matches>, dry_run=True) reports
    a zero match count and deletes nothing — verified via a total-row
    COUNT that is unchanged across the call."""
    d = drawers_module
    # Seed one drawer under an UNRELATED source so the corpus is
    # non-empty and a stray "delete everything" bug would move the count.
    d.add_drawer(
        "loom", "decisions", "unrelated", _uniq("body"),
        source_file=f"{_uniq('other')}.md",
    )

    fake_source = f"nonexistent/{_uniq('fake')}/path.md"
    before = _row_count()
    result = d.delete_by_source(fake_source, dry_run=True)
    after = _row_count()

    assert result["matched_count"] == 0
    assert result["deleted"] is False
    assert result["sample"] == []
    assert after == before


def test_delete_by_source_dry_run_matching_reports_without_deleting(drawers_module):
    """delete_by_source(<matching source>, dry_run=True) returns the
    correct match count and a non-empty sample WITHOUT deleting — every
    matched row still fetches after the dry run, and the total row count
    is unchanged."""
    d = drawers_module
    source = f"{_uniq('match')}.md"
    ids = [
        d.add_drawer("loom", "decisions", f"m{i}", _uniq(f"body{i}"), source_file=source)
        for i in range(3)
    ]

    before = _row_count()
    result = d.delete_by_source(source, dry_run=True)
    after = _row_count()

    assert result["matched_count"] == 3
    assert result["deleted"] is False
    assert isinstance(result["sample"], list) and len(result["sample"]) >= 1
    # Nothing was deleted: count unchanged AND every row still fetches.
    assert after == before
    for drawer_id in ids:
        assert d.get_drawer(drawer_id)["id"] == drawer_id


def test_delete_by_source_defaults_to_dry_run(drawers_module):
    """The dry_run DEFAULT is itself the safety contract: calling
    delete_by_source with ONLY source_file (no dry_run arg) must NOT
    delete matching rows — it previews, exactly like an explicit
    dry_run=True. Test the default directly rather than always passing
    dry_run explicitly."""
    d = drawers_module
    source = f"{_uniq('default')}.md"
    ids = [
        d.add_drawer("loom", "decisions", f"d{i}", _uniq(f"body{i}"), source_file=source)
        for i in range(2)
    ]

    result = d.delete_by_source(source)  # NO dry_run arg — default must be safe

    assert result["matched_count"] == 2
    assert result["deleted"] is False
    # The whole point: rows survive the default (no-dry_run-arg) call.
    for drawer_id in ids:
        assert d.get_drawer(drawer_id)["id"] == drawer_id


def test_delete_by_source_actually_deletes_when_dry_run_false(drawers_module):
    """Only an EXPLICIT dry_run=False actually deletes: two+ throwaway
    drawers sharing a unique source_file are all removed, and each one
    then raises DrawerNotFoundError on get_drawer. A follow-up match over
    the now-purged source finds nothing (proving the rows are really
    gone, not just hidden)."""
    d = drawers_module
    source = f"{_uniq('purge')}.md"
    ids = [
        d.add_drawer("loom", "decisions", f"p{i}", _uniq(f"body{i}"), source_file=source)
        for i in range(3)
    ]

    result = d.delete_by_source(source, dry_run=False)
    assert result["matched_count"] == 3
    assert result["deleted"] is True

    for drawer_id in ids:
        with pytest.raises(d.DrawerNotFoundError):
            d.get_drawer(drawer_id)

    # The source now matches nothing.
    followup = d.delete_by_source(source, dry_run=True)
    assert followup["matched_count"] == 0


def test_delete_tools_registered_on_server():
    """mempalace_delete_drawer / mempalace_delete_by_source are
    registered on the FastMCP server built by create_server(), alongside
    the existing drawer/search/kg tool groups (mirrors
    test_kg_tools_registered_on_server)."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert {"mempalace_delete_drawer", "mempalace_delete_by_source"} <= tool_names
