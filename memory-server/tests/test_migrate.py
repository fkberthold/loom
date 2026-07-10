"""RED-spec test for loom-40ec.5 — MemPalace-to-Dolt migration pipeline
(scripts/migrate.py).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
test_mcp_drawers.py and its siblings use (see that fixture's docstring
for why a fresh module-scoped server per requesting module is
intentional, not wasteful duplication), and runs
scripts/migrate.py's migrate_drawers()/migrate_kg_triples() against:

  - the FULL committed scripts/at-scale-corpus.jsonl fixture (5,772
    real MemPalace drawers, gathered by loom-40ec.7) for the drawers
    loader — this is real data at real scale, not a synthetic sample.
  - a synthetic-but-realistically-shaped kg_triples JSONL for the KG
    loader (no equivalent real-KG-triple corpus was gathered by a
    prior bead; this module builds a representative one inline using
    loom's own soft-recommended KG predicate vocabulary).

Asserted here (not just claimed in migrate.py's docstring):
  - all 5,772 rows land correctly, with a content-fidelity spot-check
    against the source JSONL;
  - re-running the SAME migration is a safe, real, tested no-op
    (idempotency);
  - throughput numbers are LOGGED (to stderr, matching every sibling
    test module's print-timing convention) for the bead's report;
  - the lightweight checkpoint/resume mechanism actually skips
    already-processed rows on a simulated-crash-then-resume, not just
    "doesn't crash on a second call".

Deliberately NOT covered here: running migrate.py against a REAL
production Dolt server or a REAL fully-gathered ~791k-row MemPalace
export — that is an explicit non-goal of this bead (loom-40ec.5); see
the bead's brief and scripts/migrate.py's module docstring.
"""
import json
import sys
import time
from pathlib import Path

import pytest

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
CORPUS_PATH = MEMSERVER_ROOT / "scripts" / "at-scale-corpus.jsonl"
SCRIPTS_DIR = MEMSERVER_ROOT / "scripts"

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py
# (same server-per-module convention every sibling MCP-tool test module
# follows — see that fixture's docstring for why this is a module-scoped
# fixture per requesting module, not shared global state).
from tests.test_mcp_drawers import dolt_server_env  # noqa: E402,F401


def _load_corpus_rows(path: Path) -> list[dict]:
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


CORPUS_ROWS = _load_corpus_rows(CORPUS_PATH)
CORPUS_SIZE = len(CORPUS_ROWS)

# The real ~24,401-row full non-sessions total as of 2026-07-09, per
# docs/vector-index-scaling.md's "Corpus provenance" section — used
# below only to extrapolate an estimated full-migration wall-clock
# time from this test's measured throughput, never asserted directly.
FULL_NON_SESSIONS_ESTIMATE = 24401


@pytest.fixture(scope="module")
def migrate_module(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Import scripts/migrate.py AFTER the ephemeral server's env vars
    are set (dolt_server_env's fixture body already set them at module
    scope by the time any test using this fixture runs) — mirrors
    tests/test_mcp_drawers.py's drawers_module fixture."""
    import migrate  # scripts/migrate.py, importable via the sys.path insert above

    return migrate


def test_corpus_fixture_shape_sanity():
    """Guard against a future at-scale-corpus.jsonl edit silently
    changing shape out from under this test module's assumptions."""
    assert CORPUS_SIZE == 5772
    sample = CORPUS_ROWS[0]
    assert set(sample.keys()) == {"id", "wing", "room", "text"}


@pytest.fixture(scope="module")
def full_corpus_migration(migrate_module, dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Runs migrate_drawers() against the FULL committed
    at-scale-corpus.jsonl exactly once for the module, timing it.
    Returns {"elapsed_s", "rows", "rows_per_sec"}. Shared by the
    content-fidelity tests; the idempotency test below calls
    migrate_drawers() a SECOND time itself against this same
    already-migrated state."""
    t0 = time.time()
    total = migrate_module.migrate_drawers(str(CORPUS_PATH), batch_size=200)
    elapsed = time.time() - t0
    rate = total / elapsed if elapsed > 0 else 0.0
    print(
        f"\n[test_migrate] FULL corpus initial load: {total} rows in "
        f"{elapsed:.2f}s ({rate:.1f} rows/sec)",
        file=sys.stderr,
    )
    return {"elapsed_s": elapsed, "rows": total, "rows_per_sec": rate}


def test_migrate_drawers_loads_full_corpus(full_corpus_migration):
    """The bead's RED spec: all 5,772 real rows land in the drawers
    table, with real throughput numbers logged (not run silently) and
    an extrapolated estimate for a full ~24,401-row migration."""
    from mcp_server.db import connect

    assert full_corpus_migration["rows"] == CORPUS_SIZE

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM drawers")
        count = cur.fetchone()["n"]
    finally:
        conn.close()
    assert count == CORPUS_SIZE

    rate = full_corpus_migration["rows_per_sec"]
    if rate > 0:
        est_seconds = FULL_NON_SESSIONS_ESTIMATE / rate
        print(
            f"[test_migrate] measured rate={rate:.1f} rows/sec -> "
            f"extrapolated ~{FULL_NON_SESSIONS_ESTIMATE}-row full migration "
            f"estimate: {est_seconds:.1f}s (~{est_seconds / 60:.1f} min)",
            file=sys.stderr,
        )


def test_migrate_drawers_content_fidelity_spot_check(full_corpus_migration):
    """Spot-check several rows (first, middle, last, and a handful
    picked at random with a fixed seed) against the source JSONL for
    id/wing/room/text fidelity + correct title derivation (the corpus
    fixture carries no `title` field, so EVERY row's title must be
    derived from text's first non-blank line)."""
    import random

    from mcp_server.db import connect
    from migrate import _derive_title

    random.seed(20260709)
    indices = sorted(
        {0, CORPUS_SIZE // 2, CORPUS_SIZE - 1, *random.sample(range(CORPUS_SIZE), 5)}
    )

    conn = connect()
    try:
        cur = conn.cursor()
        for idx in indices:
            src = CORPUS_ROWS[idx]
            cur.execute(
                "SELECT id, wing, room, title, text, source_file, chunk_index, "
                "parent_drawer_id, added_by FROM drawers WHERE id = %s",
                (src["id"],),
            )
            row = cur.fetchone()
            assert row is not None, (
                f"row {src['id']!r} (corpus index {idx}) missing from drawers table"
            )
            assert row["wing"] == src["wing"]
            assert row["room"] == src["room"]
            assert row["text"] == src["text"]
            assert row["title"] == _derive_title(src["text"])
            # optional fields absent from the corpus fixture -> NULL
            assert row["source_file"] is None
            assert row["chunk_index"] is None
            assert row["parent_drawer_id"] is None
    finally:
        conn.close()


def test_migrate_drawers_embedding_is_real_384dim(full_corpus_migration):
    """Sanity check that migrated rows carry a real 384-dim embedding
    (not e.g. an empty/garbled vector) — mirrors
    test_memory_server.py's equivalent self-distance check."""
    from mcp_server.db import connect

    sample_id = CORPUS_ROWS[0]["id"]
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT VEC_DISTANCE(embedding, embedding) AS self_dist "
            "FROM drawers WHERE id = %s",
            (sample_id,),
        )
        row = cur.fetchone()
    finally:
        conn.close()
    assert row is not None
    assert row["self_dist"] == pytest.approx(0.0, abs=1e-6)


def test_migrate_drawers_rerun_is_idempotent_noop(migrate_module, full_corpus_migration):
    """The bead's idempotency RED spec: re-running migrate_drawers
    against the SAME full corpus is a safe no-op — same row count,
    same content, no duplicates."""
    from mcp_server.db import connect

    t0 = time.time()
    total_second_run = migrate_module.migrate_drawers(str(CORPUS_PATH), batch_size=200)
    elapsed = time.time() - t0
    print(
        f"\n[test_migrate] idempotency re-run: {total_second_run} rows "
        f"reprocessed in {elapsed:.2f}s",
        file=sys.stderr,
    )
    assert total_second_run == CORPUS_SIZE

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM drawers")
        count = cur.fetchone()["n"]

        sample = CORPUS_ROWS[0]
        cur.execute("SELECT COUNT(*) AS n FROM drawers WHERE id = %s", (sample["id"],))
        dup_count = cur.fetchone()["n"]

        cur.execute("SELECT text FROM drawers WHERE id = %s", (sample["id"],))
        text_after = cur.fetchone()["text"]
    finally:
        conn.close()

    assert count == CORPUS_SIZE, "re-running the same migration must not duplicate rows"
    assert dup_count == 1, "the same drawer id must appear exactly once after a re-run"
    assert text_after == sample["text"], "re-run must not corrupt/change existing content"


# --------------------------------------------------------------------------
# kg_triples loader
# --------------------------------------------------------------------------


def _kg_fixture_rows(n: int = 250) -> list[dict]:
    """A synthetic-but-realistically-shaped kg_triples JSONL fixture —
    no equivalent real-KG-triple corpus was gathered by a prior bead
    (only scripts/at-scale-corpus.jsonl, which is drawers-shaped), so
    this module builds a representative one inline: predicates drawn
    from loom's own soft-recommended KG vocabulary (see CLAUDE.md's
    "Design-cycle KG predicate set" note), with confidence/valid_from/
    source_closet present on SOME rows and absent on others —
    exercising migrate.py's optional-field defaulting."""
    predicates = ["supersedes_design_of", "grounded_in", "emits_bead", "depends_on_invariant"]
    rows = []
    for i in range(n):
        row = {
            "id": f"triple_migrate_test_{i:05d}",
            "subject": f"loom-test-subject-{i % 37}",
            "predicate": predicates[i % len(predicates)],
            "object": f"loom-test-object-{i % 53}",
        }
        if i % 2 == 0:
            row["confidence"] = round(0.5 + (i % 5) * 0.1, 2)
        if i % 3 == 0:
            row["source_closet"] = f"drawer_loom_decisions_{i:024x}"
        if i % 7 == 0:
            row["valid_from"] = "2026-01-01T00:00:00"
        rows.append(row)
    return rows


@pytest.fixture(scope="module")
def kg_fixture(tmp_path_factory):
    rows = _kg_fixture_rows()
    path = tmp_path_factory.mktemp("loom-migrate-kg") / "kg-fixture.jsonl"
    with open(path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")
    return path, rows


def test_migrate_kg_triples_loads_and_round_trips(migrate_module, kg_fixture):
    path, rows = kg_fixture
    from mcp_server.db import connect

    total = migrate_module.migrate_kg_triples(str(path), batch_size=50)
    assert total == len(rows)

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM kg_triples WHERE id LIKE 'triple_migrate_test_%'")
        count = cur.fetchone()["n"]

        sample = rows[0]  # i=0 -> %2==0, %3==0, %7==0: has ALL optional fields
        cur.execute(
            "SELECT subject, predicate, object, confidence, valid_from, "
            "source_closet, `current` FROM kg_triples WHERE id = %s",
            (sample["id"],),
        )
        row = cur.fetchone()

        # a row with NO optional fields at all (i=1: not %2, not %3, not %7)
        bare_sample = rows[1]
        cur.execute(
            "SELECT confidence, valid_from, source_closet, `current` "
            "FROM kg_triples WHERE id = %s",
            (bare_sample["id"],),
        )
        bare_row = cur.fetchone()
    finally:
        conn.close()

    assert count == len(rows)
    assert row is not None
    assert row["subject"] == sample["subject"]
    assert row["predicate"] == sample["predicate"]
    assert row["object"] == sample["object"]
    assert row["confidence"] == pytest.approx(sample["confidence"])
    assert bool(row["current"]) is True
    assert row["source_closet"] == sample["source_closet"]
    assert row["valid_from"] is not None

    assert bare_row is not None
    assert bare_row["confidence"] == pytest.approx(1.0)  # documented default
    assert bare_row["valid_from"] is None
    assert bare_row["source_closet"] is None
    assert bool(bare_row["current"]) is True  # documented default


def test_migrate_kg_triples_rerun_is_idempotent_noop(migrate_module, kg_fixture):
    path, rows = kg_fixture
    from mcp_server.db import connect

    total = migrate_module.migrate_kg_triples(str(path), batch_size=50)
    assert total == len(rows)

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM kg_triples WHERE id LIKE 'triple_migrate_test_%'")
        count = cur.fetchone()["n"]
    finally:
        conn.close()
    assert count == len(rows), "re-running the same KG migration must not duplicate triples"


# --------------------------------------------------------------------------
# checkpoint / resume
# --------------------------------------------------------------------------


def test_migrate_drawers_resume_after_interruption(
    migrate_module, dolt_server_env, tmp_path, monkeypatch  # noqa: F811 - pytest fixture param, not a redefinition
):
    """Resumability RED spec: a checkpoint file lets a re-run after a
    simulated mid-migration crash SKIP already-processed rows (not
    just re-run-safely-via-idempotency) and still land every row
    correctly."""
    from mcp_server.db import connect

    rows = [
        {
            "id": f"drawer_migrate_resume_test_{i:04d}",
            "wing": "loom",
            "room": "migrate-resume-test",
            "text": f"Resume test drawer body number {i}.",
        }
        for i in range(30)
    ]
    input_path = tmp_path / "resume-fixture.jsonl"
    with open(input_path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")

    checkpoint_path = tmp_path / "checkpoint.json"

    orig_flush = migrate_module._flush_drawer_batch
    calls = {"n": 0}

    def crashing_flush(cur, batch, default_filed_at):
        calls["n"] += 1
        if calls["n"] == 2:
            raise RuntimeError("simulated crash on 2nd batch")
        return orig_flush(cur, batch, default_filed_at)

    monkeypatch.setattr(migrate_module, "_flush_drawer_batch", crashing_flush)

    with pytest.raises(RuntimeError, match="simulated crash"):
        migrate_module.migrate_drawers(
            str(input_path), batch_size=10, checkpoint_file=str(checkpoint_path)
        )

    checkpoint_data = json.loads(checkpoint_path.read_text())
    assert checkpoint_data["completed_rows"] == 10

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM drawers WHERE room = %s", ("migrate-resume-test",))
        count_after_crash = cur.fetchone()["n"]
    finally:
        conn.close()
    assert count_after_crash == 10

    processed_ids = []

    def tracking_flush(cur, batch, default_filed_at):
        processed_ids.extend(row["id"] for row in batch)
        return orig_flush(cur, batch, default_filed_at)

    monkeypatch.setattr(migrate_module, "_flush_drawer_batch", tracking_flush)

    total = migrate_module.migrate_drawers(
        str(input_path), batch_size=10, checkpoint_file=str(checkpoint_path)
    )
    assert total == 30
    # The resumed run must only reprocess the remaining 20 rows, not
    # re-embed the first 10 already committed before the crash.
    assert len(processed_ids) == 20
    assert processed_ids[0] == "drawer_migrate_resume_test_0010"

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM drawers WHERE room = %s", ("migrate-resume-test",))
        final_count = cur.fetchone()["n"]
    finally:
        conn.close()
    assert final_count == 30


# --------------------------------------------------------------------------
# small pure-function unit tests (no dolt server needed)
# --------------------------------------------------------------------------


def test_derive_title_uses_first_nonblank_line():
    from migrate import _derive_title

    assert _derive_title("first line\nsecond line") == "first line"
    assert _derive_title("\n\n  \nreal content here\nmore") == "real content here"
    assert _derive_title("") == "(untitled)"
    assert _derive_title("   \n   \n") == "(untitled)"


def test_derive_title_truncates_to_column_limit():
    from migrate import TITLE_MAX_LEN, _derive_title

    long_line = "x" * 1000
    title = _derive_title(long_line)
    assert len(title) == TITLE_MAX_LEN


def test_normalize_dt_converts_t_separator_only():
    from migrate import _normalize_dt

    assert _normalize_dt("2026-07-09T12:00:00") == "2026-07-09 12:00:00"
    assert _normalize_dt("2026-07-09 12:00:00") == "2026-07-09 12:00:00"
    assert _normalize_dt(None) is None
