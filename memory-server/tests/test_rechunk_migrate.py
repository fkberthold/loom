"""RED-spec test for loom-rpsf.3 (epic loom-rpsf S1b, design D7) —
scripts/rechunk-migrate.py, the re-chunk of the historical whole-drawer
corpus through the S1 chunker (mcp_server/chunking.py).

Background. loom-40ec.6.3's reexport-full-content.py repaired a
content-truncation bug by writing ONE full-text row per logical drawer
(a `"".join(parts)` un-chunking) and loading it via migrate.py — so the
~12k historical drawers now live in Dolt as single whole-drawer rows
with NO chunk-level children. That means a long historical drawer still
embeds as one 256-token-truncated vector (the F12 problem the S1 chunker
solves for NEW drawers). This bead re-chunks those historical rows so
they gain the same chunk-level recall new drawers get.

The RED invariant (from the bead's `RED:` line):
  - after the migration, every existing drawer with len(text) > 800 has
    child chunk rows AND its parent id is UNCHANGED (so KG grounded_in /
    tunnel references that point at the parent id stay valid);
  - children are `{parent}_chunk_{i:06d}`;
  - running it twice yields an identical row set (idempotent, via
    migrate.py's INSERT ... ON DUPLICATE KEY UPDATE upsert).

Proven here on a FIXTURE corpus loaded into the SAME ephemeral dolt
sql-server every sibling MCP-tool test module uses (dolt_server_env),
NEVER against the live production corpus — the real production re-chunk
is a separate, attended checkpoint (see the bead's PRODUCTION GATE
note). This module both boots a real dolt end-to-end (integration) and
exercises the pure row-mapping (unit, no server) so the parent/child
storage shape is pinned at both altitudes.
"""
import importlib.util
import json
import sys
from pathlib import Path

import pytest

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = MEMSERVER_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

# Reuse the ephemeral-dolt fixture every sibling MCP-tool test module
# uses (module-scoped real dolt sql-server per requesting module — see
# its docstring). Importing it registers it as a fixture in THIS module.
from tests.test_mcp_drawers import dolt_server_env  # noqa: E402,F401

RECHUNK_SCRIPT = SCRIPTS_DIR / "rechunk-migrate.py"


def _load_rechunk_module():
    """scripts/rechunk-migrate.py is HYPHENATED (a run-as-CLI script,
    like scripts/reexport-full-content.py), so it cannot be reached with
    a bare `import`. Load it by path via importlib — the module still
    gets a real __file__, so its own SCRIPT_DIR/MEMSERVER_ROOT sys.path
    bootstrap (and its `import migrate`) resolves exactly as under a CLI
    run. SCRIPTS_DIR is already on sys.path (above) so its
    `import migrate` succeeds."""
    spec = importlib.util.spec_from_file_location("rechunk_migrate", RECHUNK_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["rechunk_migrate"] = mod
    spec.loader.exec_module(mod)
    return mod


# --------------------------------------------------------------------------
# Fixture corpus — a mix that straddles the 800-char CHUNK_SIZE boundary.
# Built from natural prose (not a single repeated char) so the embeddings
# migrate.py computes are non-degenerate.
# --------------------------------------------------------------------------

_SENTENCE = "The mind palace stores cross-session lessons for later recall. "


def _body(n_chars: int) -> str:
    """A deterministic prose body of exactly n_chars characters."""
    reps = (n_chars // len(_SENTENCE)) + 1
    return (_SENTENCE * reps)[:n_chars]


# len > 800 -> chunked. 2000 -> ceil(2000/800) = 3 children (800/800/400).
LONG_A_LEN = 2000
# len > 800 -> chunked. 1300 -> ceil(1300/800) = 2 children (800/500).
LONG_B_LEN = 1300
# len < 800 -> single standalone row, no children.
SHORT_LEN = 500
# len == 800 -> NOT chunked (should_chunk is a STRICT `>`): boundary case.
EXACT_LEN = 800

# Seeded to mirror reexport-full-content.py's actual output shape: one
# logical whole-drawer row per drawer, carrying chunk_index=0 (the quirk
# reexport emits) and parent_drawer_id absent (-> NULL). The re-chunk
# must normalize the parent's chunk_index 0 -> NULL and add children.
FIXTURE_DRAWERS = [
    {"id": "drawer_rechunk_long_a", "wing": "loom", "room": "rechunk-test",
     "text": _body(LONG_A_LEN), "chunk_index": 0},
    {"id": "drawer_rechunk_long_b", "wing": "loom", "room": "rechunk-test",
     "text": _body(LONG_B_LEN), "chunk_index": 0},
    {"id": "drawer_rechunk_short", "wing": "loom", "room": "rechunk-test",
     "text": _body(SHORT_LEN), "chunk_index": 0},
    {"id": "drawer_rechunk_exact800", "wing": "loom", "room": "rechunk-test",
     "text": _body(EXACT_LEN), "chunk_index": 0},
]

CHUNKED_IDS = {"drawer_rechunk_long_a", "drawer_rechunk_long_b"}
UNCHUNKED_IDS = {"drawer_rechunk_short", "drawer_rechunk_exact800"}


# --------------------------------------------------------------------------
# Pure unit tests (no dolt server needed) — pin the parent/child row
# mapping directly against the RED invariant.
# --------------------------------------------------------------------------


@pytest.fixture(scope="module")
def rechunk_mod():
    return _load_rechunk_module()


def test_rechunk_source_row_long_body_parent_preserved_children_added(rechunk_mod):
    """A >800 source row maps to: one parent row (SAME id, FULL text,
    chunk_index None, parent_drawer_id None) + one child per
    non-overlapping 800-char slice with id `{parent}_chunk_{i:06d}`."""
    from mcp_server.chunking import chunk_text

    body = _body(LONG_A_LEN)
    source = {
        "id": "drawer_rechunk_long_a",
        "wing": "loom",
        "room": "rechunk-test",
        "title": "Some Title",
        "text": body,
        "source_file": None,
        "filed_at": None,
        "added_by": None,
    }
    rows = rechunk_mod.rechunk_source_row(source)

    parents = [r for r in rows if r["parent_drawer_id"] is None]
    children = [r for r in rows if r["parent_drawer_id"] is not None]

    assert len(parents) == 1
    parent = parents[0]
    assert parent["id"] == "drawer_rechunk_long_a"  # parent id UNCHANGED
    assert parent["text"] == body  # full body preserved (get_drawer intact)
    assert parent["chunk_index"] is None  # normalized: parent is not a chunk

    expected_slices = chunk_text(body)
    assert len(children) == len(expected_slices) == 3
    for i, (child, slice_text) in enumerate(zip(children, expected_slices)):
        assert child["id"] == f"drawer_rechunk_long_a_chunk_{i:06d}"
        assert child["text"] == slice_text
        assert child["chunk_index"] == i
        assert child["parent_drawer_id"] == "drawer_rechunk_long_a"
        # children inherit the parent's carried metadata
        assert child["wing"] == "loom"
        assert child["room"] == "rechunk-test"


def test_rechunk_source_row_short_body_single_row_no_children(rechunk_mod):
    """A <=800 source row maps to exactly ONE standalone row (no
    children), preserving its id."""
    for n in (SHORT_LEN, EXACT_LEN):
        source = {
            "id": "drawer_rechunk_x",
            "wing": "loom",
            "room": "rechunk-test",
            "title": "T",
            "text": _body(n),
            "source_file": None,
            "filed_at": None,
            "added_by": None,
        }
        rows = rechunk_mod.rechunk_source_row(source)
        assert len(rows) == 1
        assert rows[0]["id"] == "drawer_rechunk_x"
        assert rows[0]["parent_drawer_id"] is None
        assert rows[0]["chunk_index"] is None
        assert rows[0]["text"] == _body(n)


# --------------------------------------------------------------------------
# Integration — real ephemeral dolt end-to-end.
# --------------------------------------------------------------------------


def _seed_historical_corpus(rechunk_mod, tmp_path):
    """Load the fixture whole-drawer rows into the ephemeral dolt via the
    SAME migrate_drawers loader the real reexport pipeline used — this is
    the 'current Dolt full-text bodies' state the re-chunk reads from."""
    seed_path = tmp_path / "seed-corpus.jsonl"
    with open(seed_path, "w", encoding="utf-8") as f:
        for d in FIXTURE_DRAWERS:
            f.write(json.dumps(d) + "\n")
    rechunk_mod.migrate.migrate_drawers(str(seed_path), batch_size=50)


def _snapshot_drawers():
    """Full-table snapshot as a sorted list of (id, text, chunk_index,
    parent_drawer_id) — the row-set identity the idempotency invariant
    compares. Restricted to the fixture room so it never sees unrelated
    rows if the ephemeral server is ever shared."""
    from mcp_server.db import connect

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, text, chunk_index, parent_drawer_id FROM drawers "
            "WHERE room = %s ORDER BY id",
            ("rechunk-test",),
        )
        return [
            (r["id"], r["text"], r["chunk_index"], r["parent_drawer_id"])
            for r in cur.fetchall()
        ]
    finally:
        conn.close()


@pytest.fixture(scope="module")
def first_rechunk_run(dolt_server_env, rechunk_mod, tmp_path_factory):  # noqa: F811
    """Seed the historical whole-drawer corpus, then run the re-chunk
    ONCE against the live ephemeral dolt. Returns the run result dict."""
    tmp = tmp_path_factory.mktemp("rechunk")
    _seed_historical_corpus(rechunk_mod, tmp)
    out_path = tmp / "rechunked.jsonl"
    result = rechunk_mod.run(str(out_path), batch_size=50)
    return result


def test_parent_ids_unchanged_and_long_drawers_gain_children(first_rechunk_run):
    """RED invariant, integration altitude: every >800 drawer keeps its
    exact parent id + full text and gains correctly-named/ordered child
    chunk rows; every <=800 drawer keeps a single childless row."""
    from mcp_server.chunking import chunk_text
    from mcp_server.db import connect

    conn = connect()
    try:
        cur = conn.cursor()
        for src in FIXTURE_DRAWERS:
            pid = src["id"]
            body = src["text"]

            # parent row survives with same id + FULL text + no chunk role
            cur.execute(
                "SELECT id, text, chunk_index, parent_drawer_id FROM drawers "
                "WHERE id = %s",
                (pid,),
            )
            parent = cur.fetchone()
            assert parent is not None, f"parent {pid} vanished"
            assert parent["text"] == body, f"parent {pid} full text not preserved"
            assert parent["parent_drawer_id"] is None
            assert parent["chunk_index"] is None  # reexport's 0 normalized to NULL

            # children present iff len(text) > 800
            cur.execute(
                "SELECT id, text, chunk_index, parent_drawer_id FROM drawers "
                "WHERE parent_drawer_id = %s ORDER BY chunk_index",
                (pid,),
            )
            children = cur.fetchall()
            if len(body) > 800:
                slices = chunk_text(body)
                assert len(children) == len(slices) > 1
                for i, (child, slice_text) in enumerate(zip(children, slices)):
                    assert child["id"] == f"{pid}_chunk_{i:06d}"
                    assert child["text"] == slice_text
                    assert child["chunk_index"] == i
                    assert child["parent_drawer_id"] == pid
            else:
                assert len(children) == 0, f"{pid} (len {len(body)}) must stay childless"
    finally:
        conn.close()

    # run result accounting: 4 sources -> 4 parents + (3 + 2) children = 9 rows
    assert first_rechunk_run["sources"] == 4
    assert first_rechunk_run["emitted"] == 9
    assert first_rechunk_run["loaded"] == 9


def test_rerun_is_idempotent_identical_row_set(first_rechunk_run, rechunk_mod, tmp_path_factory):
    """RED invariant, idempotency: running the re-chunk a SECOND time
    over the already-re-chunked state yields a byte-identical row set —
    children are excluded from the re-read source scan, and plan_rows
    regenerates the same rows deterministically, so the upsert is a
    no-op on the row set."""
    before = _snapshot_drawers()
    # sanity: first run already produced the full 9-row set
    assert len(before) == 9

    out_path = tmp_path_factory.mktemp("rechunk-rerun") / "rechunked2.jsonl"
    second = rechunk_mod.run(str(out_path), batch_size=50)

    after = _snapshot_drawers()

    assert after == before, "re-run must yield an identical row set"
    # the second run still reads only the 4 logical parents as sources
    # (children carry a non-NULL parent_drawer_id and are skipped)
    assert second["sources"] == 4
    assert second["emitted"] == 9


def test_dry_run_emits_jsonl_without_loading(dolt_server_env, rechunk_mod, tmp_path_factory):  # noqa: F811
    """`load=False` (the CLI --dry-run) writes the parent+child JSONL and
    reports counts but performs NO Dolt write — the attended-run preview
    the PRODUCTION GATE relies on. `run()` is table-wide (it re-chunks
    EVERY logical drawer, as production must), so assertions here filter
    by the dry drawer's own id rather than assuming room isolation on the
    module-scoped shared server."""
    tmp = tmp_path_factory.mktemp("rechunk-dry")
    seed = tmp / "seed.jsonl"
    with open(seed, "w", encoding="utf-8") as f:
        f.write(json.dumps({
            "id": "drawer_rechunk_dry_long", "wing": "loom",
            "room": "rechunk-dry-test", "text": _body(2000), "chunk_index": 0,
        }) + "\n")
    rechunk_mod.migrate.migrate_drawers(str(seed), batch_size=50)

    from mcp_server.db import connect

    out_path = tmp / "dry.jsonl"
    result = rechunk_mod.run(str(out_path), batch_size=50, load=False)

    assert result["loaded"] == 0  # dry-run loads NOTHING

    # the dry drawer's full plan (1 parent + 3 children) is in the JSONL
    lines = [json.loads(x) for x in out_path.read_text().splitlines() if x.strip()]
    dry_rows = [r for r in lines if r["id"].startswith("drawer_rechunk_dry_long")]
    dry_children = [r for r in dry_rows if r["parent_drawer_id"] is not None]
    assert len(dry_rows) == 4
    assert len(dry_children) == 3
    assert {r["id"] for r in dry_children} == {
        f"drawer_rechunk_dry_long_chunk_{i:06d}" for i in range(3)
    }

    # but Dolt is untouched: no child rows were inserted for the dry drawer
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT COUNT(*) AS n FROM drawers WHERE parent_drawer_id = %s",
            ("drawer_rechunk_dry_long",),
        )
        assert cur.fetchone()["n"] == 0
    finally:
        conn.close()
