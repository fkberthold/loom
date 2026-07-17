"""RED-spec test for loom-40ec.4.1 — MCP server scaffold + core drawer
CRUD (mempalace_get_drawer / mempalace_add_drawer / mempalace_update_drawer /
mempalace_list_drawers).

Boots a REAL `dolt sql-server` (via scripts/start-server.sh, same
ephemeral-tmp-dir + free-port fixture pattern as
tests/test_memory_server.py's `dolt_server` fixture) and calls the
tool functions in mcp_server/tools/drawers.py DIRECTLY (not through a
full stdio MCP-client round-trip — see that module's docstring: the
plain functions and the registered MCP tools are the SAME callable
object, so calling the functions directly exercises the identical
code path a real MCP client invocation would hit). This still
exercises real dolt SQL end-to-end (no mocks) for every RED-spec
assertion; the ONE exception is test_update_drawer_occ_retry_logic_in_isolation,
which deliberately mocks the DB layer to deterministically drive the
retry-then-raise path (see that test's docstring for why).
"""
import os
import socket
import subprocess
import time
from pathlib import Path
from unittest import mock

import pymysql
import pytest

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
START_SERVER = MEMSERVER_ROOT / "scripts" / "start-server.sh"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def dolt_server_env(tmp_path_factory):
    """Boots a real dolt sql-server via the actual bring-up script
    against an ephemeral temp data dir + free port, and sets the
    LOOM_MEMORY_* env vars mcp_server/db.py reads so the tools under
    test connect to THIS ephemeral server rather than any production
    instance. Tears down after the module's tests complete."""
    data_dir = tmp_path_factory.mktemp("loom-mcp-test") / "doltdb"
    socket_path = tmp_path_factory.mktemp("loom-mcp-sock") / "test.sock"
    port = _free_port()

    env = os.environ.copy()
    env["LOOM_MEMORY_DATA_DIR"] = str(data_dir)
    env["LOOM_MEMORY_HOST"] = "127.0.0.1"
    env["LOOM_MEMORY_PORT"] = str(port)
    env["LOOM_MEMORY_SOCKET"] = str(socket_path)

    proc = subprocess.Popen(
        ["bash", str(START_SERVER)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    deadline = time.time() + 30
    last_err = None
    ready = False
    while time.time() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read() if proc.stdout else ""
            raise RuntimeError(
                f"start-server.sh exited early (code {proc.returncode}):\n{out}"
            )
        try:
            conn = pymysql.connect(
                host="127.0.0.1",
                port=port,
                user="root",
                password="",
                database="doltdb",
                autocommit=True,
                connect_timeout=2,
            )
            conn.close()
            ready = True
            break
        except Exception as e:  # noqa: BLE001 - broad on purpose while polling
            last_err = e
            time.sleep(0.3)

    if not ready:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        raise RuntimeError(f"dolt sql-server never became ready: {last_err}")

    # Point mcp_server/db.py's connection_config() at the ephemeral
    # server for the rest of this test module. Set (not just copy)
    # directly on os.environ so code under test (which reads
    # os.environ at call time, not at import time) picks it up.
    prev = {
        k: os.environ.get(k)
        for k in ("LOOM_MEMORY_HOST", "LOOM_MEMORY_PORT", "LOOM_MEMORY_DATABASE")
    }
    os.environ["LOOM_MEMORY_HOST"] = "127.0.0.1"
    os.environ["LOOM_MEMORY_PORT"] = str(port)
    os.environ["LOOM_MEMORY_DATABASE"] = "doltdb"

    yield {"host": "127.0.0.1", "port": port, "database": "doltdb"}

    for k, v in prev.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v

    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()


@pytest.fixture()
def drawers_module(dolt_server_env):
    """Import mcp_server.tools.drawers AFTER the ephemeral server's
    env vars are set (dolt_server_env's fixture body already set
    them at module scope by the time any test using this fixture
    runs)."""
    from mcp_server.tools import drawers

    return drawers


def test_add_get_update_list_round_trip(drawers_module):
    """The bead's RED spec, end to end against a real dolt sql-server:

      mempalace_add_drawer('loom', 'decisions', 'test title', 'test body')
        returns a drawer_id;
      mempalace_get_drawer(that_id) returns matching title/body;
      mempalace_update_drawer(that_id, 'new body') then
        mempalace_get_drawer(that_id) reflects the new body;
      mempalace_list_drawers(wing='loom') includes that drawer_id.
    """
    d = drawers_module

    drawer_id = d.add_drawer("loom", "decisions", "test title", "test body")
    assert isinstance(drawer_id, str) and drawer_id

    fetched = d.get_drawer(drawer_id)
    assert fetched["id"] == drawer_id
    assert fetched["title"] == "test title"
    assert fetched["text"] == "test body"
    assert fetched["wing"] == "loom"
    assert fetched["room"] == "decisions"

    updated_ok = d.update_drawer(drawer_id, "new body")
    assert updated_ok is True

    refetched = d.get_drawer(drawer_id)
    assert refetched["text"] == "new body"
    # title/wing/room unchanged by update_drawer per spec
    assert refetched["title"] == "test title"
    assert refetched["wing"] == "loom"
    assert refetched["room"] == "decisions"

    listing = d.list_drawers(wing="loom")
    listed_ids = [row["id"] for row in listing]
    assert drawer_id in listed_ids

    # list_drawers shape check: id/wing/room/title/preview/total present
    matching = next(row for row in listing if row["id"] == drawer_id)
    assert matching["wing"] == "loom"
    assert matching["room"] == "decisions"
    assert matching["title"] == "test title"
    assert matching["preview"].startswith("new body")
    assert matching["total"] >= 1


def test_add_drawer_with_source_file(drawers_module):
    d = drawers_module
    drawer_id = d.add_drawer(
        "loom", "decisions", "sourced title", "sourced body", source_file="notes.md"
    )
    fetched = d.get_drawer(drawer_id)
    assert fetched["source_file"] == "notes.md"


def test_get_drawer_not_found_raises_clear_error(drawers_module):
    d = drawers_module
    with pytest.raises(d.DrawerNotFoundError):
        d.get_drawer("drawer_does_not_exist_ffffffffffffffffffffffff")


def test_update_drawer_not_found_raises_clear_error(drawers_module):
    d = drawers_module
    with pytest.raises(d.DrawerNotFoundError):
        d.update_drawer("drawer_does_not_exist_ffffffffffffffffffffffff", "new body")


def test_list_drawers_pagination(drawers_module):
    d = drawers_module
    room = f"pagination_room_{os.urandom(4).hex()}"
    ids = [
        d.add_drawer("loom", room, f"title {i}", f"body {i}") for i in range(5)
    ]

    page1 = d.list_drawers(wing="loom", room=room, limit=2, offset=0)
    page2 = d.list_drawers(wing="loom", room=room, limit=2, offset=2)

    assert len(page1) == 2
    assert len(page2) == 2
    assert page1[0]["total"] == 5
    assert page2[0]["total"] == 5
    # no overlap between the two pages
    page1_ids = {row["id"] for row in page1}
    page2_ids = {row["id"] for row in page2}
    assert page1_ids.isdisjoint(page2_ids)
    assert page1_ids <= set(ids)
    assert page2_ids <= set(ids)


def test_list_drawers_content_preview_truncated(drawers_module):
    d = drawers_module
    long_body = "x" * 500
    drawer_id = d.add_drawer("loom", "decisions", "long body title", long_body)
    listing = d.list_drawers(wing="loom")
    matching = next(row for row in listing if row["id"] == drawer_id)
    assert len(matching["preview"]) <= 200
    assert matching["preview"] == long_body[:200]


def test_update_drawer_occ_conflict_real_dolt_retry_succeeds(drawers_module, dolt_server_env):
    """Drives a REAL same-row concurrent-write conflict against the
    live dolt sql-server (not mocked): two independent connections
    each start a SERIALIZABLE transaction, read the row, and attempt
    to write; the first to commit wins, and D6's retry-once wrapper
    in update_drawer() must recover from the second's serialization
    conflict rather than raising on the first attempt.

    This exercises the SAME _attempt_update() code path
    update_drawer() itself uses, by racing update_drawer() against a
    manually-driven concurrent transaction held open across the
    window where update_drawer's own SELECT-then-UPDATE happens.
    """
    d = drawers_module
    drawer_id = d.add_drawer("loom", "decisions", "occ title", "occ original")

    from mcp_server.db import connection_config

    cfg = connection_config()

    # Open a competing connection and hold a SERIALIZABLE transaction
    # open on the same row, across update_drawer()'s own transaction,
    # so update_drawer's first _attempt_update() is guaranteed to
    # collide.
    competitor = pymysql.connect(autocommit=False, connect_timeout=5, **cfg)
    try:
        with competitor.cursor() as cur:
            cur.execute("SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE")
            cur.execute("SELECT id FROM drawers WHERE id = %s", (drawer_id,))
            cur.fetchone()
            cur.execute(
                "UPDATE drawers SET text = %s WHERE id = %s",
                ("competitor's write", drawer_id),
            )

        # At this point the competitor has an uncommitted write to
        # the same row. Call update_drawer() in a background thread
        # so its own transaction opens and attempts to commit WHILE
        # the competitor is still open, then have the competitor
        # commit first — forcing update_drawer's first attempt to
        # hit the serialization conflict and fall through to its
        # retry.
        import threading

        result = {}

        def _run_update():
            try:
                result["ok"] = d.update_drawer(drawer_id, "update_drawer's new body")
            except Exception as exc:  # noqa: BLE001
                result["error"] = exc

        t = threading.Thread(target=_run_update)
        t.start()
        # Give update_drawer's first attempt a moment to open its
        # transaction and reach its own commit attempt.
        time.sleep(0.5)
        competitor.commit()
        t.join(timeout=15)

        assert not t.is_alive(), "update_drawer() did not return in time"
        assert "error" not in result, f"update_drawer raised: {result.get('error')!r}"
        assert result.get("ok") is True
    finally:
        competitor.close()

    final = d.get_drawer(drawer_id)
    # update_drawer's retry re-reads and reapplies its OWN new
    # content regardless of what the competitor wrote, so the final
    # state must reflect update_drawer's content, not the
    # competitor's.
    assert final["text"] == "update_drawer's new body"


def test_update_drawer_occ_retry_logic_in_isolation():
    """Unit-tests JUST the retry-then-raise control flow of
    update_drawer(), with the DB layer mocked out.

    Deterministically driving a SECOND consecutive real-dolt conflict
    (to prove the "raise ConcurrentModificationError after the retry
    ALSO conflicts" branch) is awkward to arrange reliably against a
    live server without a fragile timing race stacked on top of
    test_update_drawer_occ_conflict_real_dolt_retry_succeeds's
    already-real race. This test instead mocks
    mcp_server.tools.drawers._attempt_update directly to force BOTH
    calls to raise _OccConflict, and asserts update_drawer() surfaces
    ConcurrentModificationError (not an infinite retry, not a silent
    no-op) — the one branch the real-dolt test above cannot exercise
    deterministically.
    """
    from mcp_server.tools import drawers as d

    with mock.patch.object(d, "_attempt_update", side_effect=d._OccConflict()) as m:
        with pytest.raises(d.ConcurrentModificationError):
            d.update_drawer("drawer_whatever", "new content")
        assert m.call_count == 2, "expected exactly one retry (two attempts total)"


# ---------------------------------------------------------------------------
# loom-rpsf.2 — document chunking + search rollup (S1).
#
# RED invariant (from the bead):
#   len(text) <= 800  => exactly ONE row (parent_drawer_id NULL,
#     chunk_index NULL, embedding = embed(full text)).
#   len(text) > 800   => ONE parent row (text = full body,
#     embedding = embed(title), parent_drawer_id/chunk_index NULL)
#     PLUS ceil(len/800) CHILD rows: id = f"{parent}_chunk_{i:06d}",
#     text = i-th non-overlapping 800-char slice, embedding =
#     embed(slice), chunk_index = i, parent_drawer_id = parent.
#   A 2000-char drawer => 1 parent + 3 children (800/800/400);
#     get_drawer(parent) returns the full 2000 chars; list_drawers
#     never returns a chunk row.
# ---------------------------------------------------------------------------


def _rows_for_parent(parent_id):
    """Return every row whose id == parent_id OR whose parent_drawer_id
    == parent_id, straight from the DB (bypassing the tool layer) so a
    test can inspect the raw stored chunk shape."""
    from mcp_server.db import connect

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, text, chunk_index, parent_drawer_id "
                "FROM drawers WHERE id = %s OR parent_drawer_id = %s "
                "ORDER BY (parent_drawer_id IS NOT NULL), chunk_index",
                (parent_id, parent_id),
            )
            return cur.fetchall()
    finally:
        conn.close()


# --- pure chunking-logic unit tests (no dolt server needed) ---


def test_chunk_text_non_overlapping_slices():
    from mcp_server.chunking import chunk_text

    slices = chunk_text("a" * 2000, chunk_size=800)
    assert [len(s) for s in slices] == [800, 800, 400]
    # non-overlapping + lossless: concatenation reproduces the original
    assert "".join(slices) == "a" * 2000


def test_should_chunk_boundary():
    from mcp_server.chunking import should_chunk

    assert should_chunk("a" * 800, chunk_size=800) is False
    assert should_chunk("a" * 801, chunk_size=800) is True


def test_plan_rows_short_body_single_standalone_row():
    from mcp_server.chunking import plan_rows

    specs = plan_rows("drawer_x", "the title", "short body", chunk_size=800)
    assert len(specs) == 1
    (spec,) = specs
    assert spec.row_id == "drawer_x"
    assert spec.text == "short body"
    assert spec.embed_source == "short body"  # embed(full text)
    assert spec.chunk_index is None
    assert spec.parent_drawer_id is None
    assert spec.is_parent is True


def test_plan_rows_long_body_parent_plus_children():
    from mcp_server.chunking import plan_rows

    body = "a" * 2000
    specs = plan_rows("drawer_x", "the title", body, chunk_size=800)
    # 1 parent + ceil(2000/800)=3 children
    assert len(specs) == 4

    parent = specs[0]
    assert parent.row_id == "drawer_x"
    assert parent.text == body  # full body lives on the parent
    assert parent.embed_source == "the title"  # embed(title)
    assert parent.chunk_index is None
    assert parent.parent_drawer_id is None
    assert parent.is_parent is True

    children = specs[1:]
    assert [c.row_id for c in children] == [
        "drawer_x_chunk_000000",
        "drawer_x_chunk_000001",
        "drawer_x_chunk_000002",
    ]
    assert [c.chunk_index for c in children] == [0, 1, 2]
    assert [len(c.text) for c in children] == [800, 800, 400]
    assert all(c.parent_drawer_id == "drawer_x" for c in children)
    assert all(c.is_parent is False for c in children)
    # each child embeds its own slice
    assert all(c.embed_source == c.text for c in children)


# --- integration tests against a real dolt sql-server ---


def test_short_drawer_stored_as_single_row(drawers_module):
    """len(text) <= 800 => exactly one row, parent_drawer_id NULL,
    chunk_index NULL (no chunk rows created)."""
    d = drawers_module
    drawer_id = d.add_drawer("loom", "decisions", "short title", "x" * 800)

    rows = _rows_for_parent(drawer_id)
    assert len(rows) == 1
    (row,) = rows
    assert row["id"] == drawer_id
    assert row["chunk_index"] is None
    assert row["parent_drawer_id"] is None
    assert row["text"] == "x" * 800


def test_long_drawer_stored_as_parent_plus_children(drawers_module):
    """A 2000-char drawer => 1 parent + 3 child rows (800/800/400).
    get_drawer(parent) returns the full 2000 chars; list_drawers never
    returns a chunk row."""
    d = drawers_module
    # room name deliberately avoids the substring "_chunk_" so the
    # "no chunk row in listing" assertion below cannot false-positive on
    # the parent drawer's OWN id (which embeds wing/room).
    room = f"bigbody_room_{os.urandom(4).hex()}"
    body = "".join(chr(ord("a") + (i % 26)) for i in range(2000))
    assert len(body) == 2000

    drawer_id = d.add_drawer("loom", room, "big title", body)

    rows = _rows_for_parent(drawer_id)
    # 1 parent + 3 children
    assert len(rows) == 4

    parent = next(r for r in rows if r["id"] == drawer_id)
    assert parent["parent_drawer_id"] is None
    assert parent["chunk_index"] is None
    assert parent["text"] == body  # full body on the parent

    children = sorted(
        (r for r in rows if r["parent_drawer_id"] == drawer_id),
        key=lambda r: r["chunk_index"],
    )
    assert [c["id"] for c in children] == [
        f"{drawer_id}_chunk_000000",
        f"{drawer_id}_chunk_000001",
        f"{drawer_id}_chunk_000002",
    ]
    assert [c["chunk_index"] for c in children] == [0, 1, 2]
    assert [len(c["text"]) for c in children] == [800, 800, 400]
    # non-overlapping slices reconstruct the full body
    assert "".join(c["text"] for c in children) == body
    assert children[0]["text"] == body[0:800]
    assert children[1]["text"] == body[800:1600]
    assert children[2]["text"] == body[1600:2000]

    # get_drawer(parent) returns the FULL 2000 chars
    fetched = d.get_drawer(drawer_id)
    assert fetched["text"] == body
    assert len(fetched["text"]) == 2000

    # list_drawers NEVER returns a chunk row
    listing = d.list_drawers(wing="loom", room=room, limit=100)
    listed_ids = {r["id"] for r in listing}
    assert drawer_id in listed_ids
    assert not any("_chunk_" in i for i in listed_ids)
    # the logical drawer is counted once, not once-per-chunk
    assert listing[0]["total"] == 1


def test_update_drawer_rechunks(drawers_module):
    """update_drawer deletes existing children then re-inserts:
    short->long grows children, long->short removes them."""
    d = drawers_module
    room = f"rechunk_room_{os.urandom(4).hex()}"

    # start short: one standalone row, no children
    drawer_id = d.add_drawer("loom", room, "rechunk title", "tiny body")
    assert len(_rows_for_parent(drawer_id)) == 1

    # grow to long: parent + 3 children
    long_body = "z" * 2000
    assert d.update_drawer(drawer_id, long_body) is True
    rows = _rows_for_parent(drawer_id)
    assert len(rows) == 4
    parent = next(r for r in rows if r["id"] == drawer_id)
    assert parent["text"] == long_body
    assert parent["parent_drawer_id"] is None
    assert parent["chunk_index"] is None
    assert d.get_drawer(drawer_id)["text"] == long_body

    # shrink back to short: children are deleted, one row remains
    assert d.update_drawer(drawer_id, "small again") is True
    rows = _rows_for_parent(drawer_id)
    assert len(rows) == 1
    assert rows[0]["id"] == drawer_id
    assert rows[0]["parent_drawer_id"] is None
    assert d.get_drawer(drawer_id)["text"] == "small again"


def test_update_drawer_relayers_children_on_length_change(drawers_module):
    """long -> shorter-but-still-long re-chunks: stale children from the
    previous body must not linger (delete-then-reinsert, not merge)."""
    d = drawers_module
    room = f"relayer_room_{os.urandom(4).hex()}"

    drawer_id = d.add_drawer("loom", room, "relayer title", "a" * 2400)  # 3 chunks
    assert len(_rows_for_parent(drawer_id)) == 4  # parent + 3

    assert d.update_drawer(drawer_id, "b" * 900) is True  # now ceil(900/800)=2
    rows = _rows_for_parent(drawer_id)
    assert len(rows) == 3  # parent + 2 (the third stale chunk is gone)
    children = sorted(
        (r for r in rows if r["parent_drawer_id"] == drawer_id),
        key=lambda r: r["chunk_index"],
    )
    assert [c["chunk_index"] for c in children] == [0, 1]
    assert f"{drawer_id}_chunk_000002" not in {r["id"] for r in rows}
