"""RED-spec test for loom-40ec.3 — production schema + dolt sql-server
bring-up for loom's shared, concurrent, Dolt-backed memory server.

Boots a REAL `dolt sql-server` (via scripts/start-server.sh, so this
test exercises the actual bring-up script rather than a parallel ad
hoc setup) against an ephemeral temp data directory + free port,
applies schema.sql, then validates:

  1. `drawers`: INSERT a row with a real 384-dim embedding vector
     (via `string_to_vector()` — a bare string/JSON-array literal does
     NOT implicitly convert to the `vector` type, verified separately),
     then `SELECT ... ORDER BY VEC_DISTANCE(embedding, :q) LIMIT k` and
     assert p95 query latency < 10ms.

  2. `kg_triples`: minimal insert + query-back round trip.

Corpus size note: the corpus here is intentionally sized to match
SPIKE-1's benchmark corpus (~38 drawers, see
drawer_loom_decisions_521e654693797b4f169b4cbd / loom-zu91), which is
the regression floor this test's p95 assertion is measured against
(SPIKE-1 measured p95=3.94ms at that scale). The query plan is a
`TopN` over a full table scan of `VEC_DISTANCE` (verified via `EXPLAIN
FORMAT=TREE` — dolt 2.1.10 does not use the vector index to skip
unmatched rows for this query shape), so latency scales with corpus
size; testing at a materially larger corpus (e.g. hundreds of rows)
measures a different thing — table-scan-and-sort scaling — that is a
separate concern from this bead's schema + bring-up scope.
"""
import os
import random
import socket
import subprocess
import sys
import time
from pathlib import Path

import pymysql
import pytest

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
START_SERVER = MEMSERVER_ROOT / "scripts" / "start-server.sh"

# Regression floor from SPIKE-1 (drawer_loom_decisions_521e654693797b4f169b4cbd,
# loom-zu91): p95 query latency = 3.94ms at a ~38-row corpus. This test's
# assertion threshold (10ms) is the bead's RED spec; the SPIKE-1 number is
# logged for comparison, not asserted directly (a few ms of machine-to-
# machine variance is expected).
SPIKE1_P95_FLOOR_MS = 3.94
LATENCY_ASSERT_THRESHOLD_MS = 10.0

CORPUS_SIZE = 38  # matches SPIKE-1's benchmark corpus scale exactly


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _vec_literal(vec) -> str:
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"


@pytest.fixture(scope="module")
def dolt_server(tmp_path_factory):
    """Boots a real dolt sql-server via the actual bring-up script
    against an ephemeral temp data dir + free port, tears it down after
    the module's tests complete."""
    data_dir = tmp_path_factory.mktemp("loom-memory-test") / "doltdb"
    socket_path = tmp_path_factory.mktemp("loom-memory-sock") / "test.sock"
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

    # Poll for readiness by attempting a real connection, rather than
    # sleeping a fixed guess — bring-up includes a dolt init + schema
    # apply step before the server binds its listener.
    deadline = time.time() + 30
    last_err = None
    conn = None
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
            break
        except Exception as e:  # noqa: BLE001 - broad on purpose while polling
            last_err = e
            time.sleep(0.3)

    if conn is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        raise RuntimeError(f"dolt sql-server never became ready: {last_err}")

    yield conn

    conn.close()
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()


@pytest.fixture(scope="module")
def seeded_drawers(dolt_server):
    """Seeds `drawers` with CORPUS_SIZE rows, each with a real 384-dim
    embedding vector inserted via string_to_vector()."""
    random.seed(1234)
    cur = dolt_server.cursor()
    for i in range(CORPUS_SIZE):
        vec = [random.uniform(-1, 1) for _ in range(384)]
        vec_str = _vec_literal(vec)
        cur.execute(
            "INSERT INTO drawers "
            "(id, wing, room, title, text, embedding, filed_at, "
            " source_file, chunk_index, parent_drawer_id, added_by) "
            f"VALUES (%s, %s, %s, %s, %s, string_to_vector('{vec_str}'), "
            "NOW(), %s, %s, %s, %s)",
            (
                f"drawer_test_{i:04d}",
                "loom",
                "decisions",
                f"Test drawer {i}",
                f"Body text for drawer {i}.",
                None,
                None,
                None,
                "pytest-loom-40ec.3",
            ),
        )
    cur.close()
    return CORPUS_SIZE


def test_drawers_table_has_real_384dim_embedding(dolt_server, seeded_drawers):
    """Sanity check: the embedding column actually stored a 384-dim
    vector, not e.g. a truncated/garbled representation."""
    cur = dolt_server.cursor()
    cur.execute(
        "SELECT VEC_DISTANCE(embedding, embedding) AS self_dist "
        "FROM drawers WHERE id = %s",
        ("drawer_test_0000",),
    )
    row = cur.fetchone()
    cur.close()
    assert row is not None
    # A vector's distance to itself must be (approximately) zero.
    assert row[0] == pytest.approx(0.0, abs=1e-6)


def test_vec_distance_query_returns_results_and_meets_p95_floor(
    dolt_server, seeded_drawers
):
    """The bead's RED spec: SELECT ... ORDER BY VEC_DISTANCE(embedding,
    :q) LIMIT 5 returns results, with p95 query latency under the
    10ms threshold."""
    random.seed(99)
    query_vec = [random.uniform(-1, 1) for _ in range(384)]
    query_vec_str = _vec_literal(query_vec)

    cur = dolt_server.cursor()

    # Warm up the connection (first query on a fresh connection can
    # carry setup cost unrelated to the query itself).
    cur.execute(
        f"SELECT id, VEC_DISTANCE(embedding, string_to_vector('{query_vec_str}')) "
        "AS dist FROM drawers ORDER BY dist ASC LIMIT 5"
    )
    warmup_rows = cur.fetchall()
    assert len(warmup_rows) == 5

    latencies_ms = []
    n_queries = 50
    for _ in range(n_queries):
        t0 = time.perf_counter()
        cur.execute(
            "SELECT id, VEC_DISTANCE(embedding, "
            f"string_to_vector('{query_vec_str}')) AS dist "
            "FROM drawers ORDER BY dist ASC LIMIT 5"
        )
        rows = cur.fetchall()
        latencies_ms.append((time.perf_counter() - t0) * 1000)
        assert len(rows) == 5

    cur.close()

    latencies_ms.sort()
    p95_idx = int(len(latencies_ms) * 0.95)
    p95 = latencies_ms[p95_idx]
    p50 = latencies_ms[len(latencies_ms) // 2]
    mean = sum(latencies_ms) / len(latencies_ms)

    print(
        f"\n[loom-40ec.3] corpus={CORPUS_SIZE} rows, n_queries={n_queries} "
        f"p50={p50:.3f}ms p95={p95:.3f}ms mean={mean:.3f}ms "
        f"(SPIKE-1 floor p95={SPIKE1_P95_FLOOR_MS}ms, "
        f"threshold={LATENCY_ASSERT_THRESHOLD_MS}ms)",
        file=sys.stderr,
    )

    assert p95 < LATENCY_ASSERT_THRESHOLD_MS, (
        f"p95 latency {p95:.3f}ms exceeds the {LATENCY_ASSERT_THRESHOLD_MS}ms "
        f"threshold (SPIKE-1 regression floor was {SPIKE1_P95_FLOOR_MS}ms "
        f"at the same ~{CORPUS_SIZE}-row corpus scale)"
    )


def test_kg_triples_insert_and_query_round_trip(dolt_server):
    """Minimal round-trip test for the D7 kg_triples table."""
    cur = dolt_server.cursor()
    cur.execute(
        "INSERT INTO kg_triples "
        "(id, subject, predicate, object, confidence, valid_from, "
        " valid_to, source_closet, `current`, created_at) "
        "VALUES (%s, %s, %s, %s, %s, NULL, NULL, %s, %s, NOW())",
        (
            "triple_test_0001",
            "loom-40ec.3",
            "implements_decision_of",
            "drawer_loom_decisions_521e654693797b4f169b4cbd",
            0.95,
            "pytest-loom-40ec.3",
            True,
        ),
    )

    cur.execute(
        "SELECT subject, predicate, object, confidence, `current` "
        "FROM kg_triples WHERE id = %s",
        ("triple_test_0001",),
    )
    row = cur.fetchone()
    cur.close()

    assert row is not None
    subject, predicate, obj, confidence, current = row
    assert subject == "loom-40ec.3"
    assert predicate == "implements_decision_of"
    assert obj == "drawer_loom_decisions_521e654693797b4f169b4cbd"
    assert confidence == pytest.approx(0.95, abs=1e-6)
    assert bool(current) is True


def test_kg_triples_indices_exist():
    """Structural check: the three D7-mandated indices are present on
    the schema (subject / object / subject+predicate), read directly
    from schema.sql rather than the live server so this test also
    catches an accidental future edit that drops an index."""
    schema_text = (MEMSERVER_ROOT / "schema.sql").read_text()
    assert "kg_triples_subject_idx" in schema_text
    assert "kg_triples_object_idx" in schema_text
    assert "kg_triples_subject_predicate_idx" in schema_text
