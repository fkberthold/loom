#!/usr/bin/env python3
"""memory-server/scripts/benchmark-at-scale.py — realistic-scale vector-index
latency benchmark (loom-40ec.7).

loom-40ec.3 found that dolt 2.1.10's `CREATE VECTOR INDEX` is NOT used by
the query pattern `SELECT ... ORDER BY VEC_DISTANCE(embedding, :q) LIMIT k`
(confirmed via `EXPLAIN FORMAT=TREE` — a full-table-scan `TopN`, not an
index-assisted nearest-neighbor lookup) and measured latency at a tiny
38-row synthetic-random-vector corpus (p95=3.94ms) and a 200-row synthetic
corpus (p95=11.9ms, breaching the 10ms bar). This script re-measures at a
REALISTIC scale using REAL MemPalace data so the numbers reflect what
loom's actual eventual multi-project corpus will look like.

Corpus: scripts/at-scale-corpus.jsonl — 5,772 real, distinct MemPalace
drawers (id/wing/room/text) gathered via `mempalace_list_drawers`
pagination across the largest non-sessions wings (liza, liza_current,
e2e-api-tests, golden-path, wing_claude-opus, liza_base,
malleus-protocollum, sir, relationships, tla_puzzles, wing_claude-opus-4-7,
wing_liza, loom, world, dreamer-engine, mforth, liza_live, technical). The
`sessions` wing (766,720 drawers of known runaway-auto-mine garbage, see
loom-p01j) was excluded entirely, per the bead's instructions. See
docs/vector-index-scaling.md for full provenance + the ADEQUATE /
NOT-ADEQUATE judgment this script's numbers fed into.

Embedding model: all-MiniLM-L6-v2 via sentence-transformers (384-dim,
matching schema.sql's `embedding VECTOR(384)` column) — the SAME model
loom-40ec.3's SPIKE-1 lineage used, for numeric consistency across the two
measurements.

This script does NOT re-fetch MemPalace live — it consumes the cached
corpus file committed alongside it. It reuses schema.sql and
scripts/start-server.sh AS-IS (no schema/bring-up changes), pointing
LOOM_MEMORY_DATA_DIR at an ephemeral temp directory so no real data is
ever written to a tracked/committed data directory.

Two benchmark passes:
  1. PRIMARY — the real corpus exactly as gathered (5,772 rows), no
     synthetic padding at all.
  2. EXTRAPOLATED — the real corpus replicated + lightly jittered
     (gaussian noise on the embedding, sigma=0.01) up to a target row
     count matching loom's full realistic non-sessions total (~24,401 by
     default), modeling the "eventual" multi-project corpus the bead asks
     about. Row COUNT drives this query shape's full-table-scan latency,
     not per-row content uniqueness (VEC_DISTANCE is a fixed-cost
     384-float computation per row regardless of the vector's actual
     values) — so replication-with-jitter is a legitimate, honest way to
     model eventual scale without re-fetching tens of thousands more real
     MemPalace drawers. The pass is clearly labeled as extrapolated in
     the output; it is never presented as additional real data.

Usage:
  scripts/benchmark-at-scale.py [--corpus PATH] [--extrapolate-to N] [--skip-extrapolated]

Requires (in addition to requirements.txt): sentence-transformers, numpy
— see scripts/requirements-benchmark.txt. These are NOT added to the
production requirements.txt since the running memory server itself never
needs sentence-transformers; only this one-off benchmark does.
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import pymysql

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
START_SERVER = MEMSERVER_ROOT / "scripts" / "start-server.sh"
DEFAULT_CORPUS = MEMSERVER_ROOT / "scripts" / "at-scale-corpus.jsonl"

MODEL_NAME = "all-MiniLM-L6-v2"
N_QUERIES = 50
LATENCY_REFERENCE_THRESHOLD_MS = 10.0  # loom-40ec.3's original RED bar — reported for comparison only, not asserted.

# Realistic bug-family-search-style queries + real drawer-title-shaped
# phrasing, standing in for "a handful of realistic queries" per the
# bead's instructions (some paraphrase real content seen while gathering
# the corpus; none are copied verbatim from any single drawer).
REALISTIC_QUERIES = [
    "vector index full table scan latency at scale",
    "bd worktree preseed empty dolt state loses issues.jsonl on merge",
    "dispatch v2 lean central background worker default",
    "MemPalace update_drawer full rewrite cost precipitation",
    "TLA+ PlusCal algorithm block braces translator",
    "mforth REPL mlog equivalence property",
    "liza drought swerve insight capture",
    "dreamer engine five layer architecture physics utility BDI",
    "constitution enforce hook forbidden pip install",
    "cwd drift guard worktree merge push bd close",
    "API 529 overload resilience health probe backoff",
    "session close protocol push origin verify",
]


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _vec_literal(vec) -> str:
    return "[" + ",".join(f"{float(x):.6f}" for x in vec) + "]"


def load_corpus(path: Path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def start_dolt_server(data_dir: Path, port: int, socket_path: Path):
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

    deadline = time.time() + 90
    conn = None
    last_err = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read() if proc.stdout else ""
            raise RuntimeError(f"start-server.sh exited early (code {proc.returncode}):\n{out}")
        try:
            conn = pymysql.connect(
                host="127.0.0.1", port=port, user="root", password="",
                database="doltdb", autocommit=True, connect_timeout=2,
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
    return proc, conn


def _flush_batch(cur, batch):
    values_sql = ",".join(
        "(%s,%s,%s,%s,%s,string_to_vector(%s),NOW(),%s,%s,%s,%s)" for _ in batch
    )
    args = []
    for (id_, wing, room, title, text, vec_str) in batch:
        args.extend([id_, wing, room, title, text, vec_str, "at-scale-benchmark", 0, None, "benchmark"])
    sql = (
        "INSERT INTO drawers (id, wing, room, title, text, embedding, filed_at, "
        "source_file, chunk_index, parent_drawer_id, added_by) VALUES " + values_sql
    )
    cur.execute(sql, args)


def insert_rows(conn, rows, embeddings, batch_size=200):
    cur = conn.cursor()
    batch = []
    for row, emb in zip(rows, embeddings):
        vec_str = _vec_literal(emb)
        title = f"{row['wing']}/{row['room']}"[:512]
        text = (row.get("text") or "")[:8000]
        batch.append((row["id"], row["wing"], row["room"], title, text, vec_str))
        if len(batch) >= batch_size:
            _flush_batch(cur, batch)
            batch = []
    if batch:
        _flush_batch(cur, batch)
    cur.close()


def run_latency_bench(conn, query_vecs, n_queries=N_QUERIES):
    cur = conn.cursor()
    warm_vec_str = _vec_literal(query_vecs[0])
    cur.execute(
        f"SELECT id, VEC_DISTANCE(embedding, string_to_vector('{warm_vec_str}')) AS dist "
        "FROM drawers ORDER BY dist ASC LIMIT 5"
    )
    cur.fetchall()

    latencies_ms = []
    for i in range(n_queries):
        qv = query_vecs[i % len(query_vecs)]
        vec_str = _vec_literal(qv)
        t0 = time.perf_counter()
        cur.execute(
            f"SELECT id, VEC_DISTANCE(embedding, string_to_vector('{vec_str}')) AS dist "
            "FROM drawers ORDER BY dist ASC LIMIT 5"
        )
        rows = cur.fetchall()
        latencies_ms.append((time.perf_counter() - t0) * 1000)
        assert len(rows) == 5, f"expected 5 rows, got {len(rows)}"

    cur.close()
    latencies_ms.sort()
    p50 = latencies_ms[len(latencies_ms) // 2]
    p95 = latencies_ms[int(len(latencies_ms) * 0.95)]
    mean = sum(latencies_ms) / len(latencies_ms)
    return {"p50_ms": p50, "p95_ms": p95, "mean_ms": mean, "n_queries": n_queries}


def run_explain(conn):
    cur = conn.cursor()
    zero_vec_str = _vec_literal([0.0] * 384)
    cur.execute(
        f"EXPLAIN FORMAT=TREE SELECT id, VEC_DISTANCE(embedding, string_to_vector('{zero_vec_str}')) "
        "AS dist FROM drawers ORDER BY dist ASC LIMIT 5"
    )
    rows = cur.fetchall()
    cur.close()
    return "\n".join(r[0] for r in rows)


def extrapolate(rows, embeddings, target_n, seed=42):
    """Replicate the real corpus (with small gaussian jitter on the
    embeddings, sigma=0.01) up to target_n rows. See module docstring for
    why this is a legitimate way to model eventual scale for THIS query
    shape (full-table-scan cost is row-count-driven, not content-driven)."""
    import numpy as np

    rng = np.random.default_rng(seed)
    n_real = len(rows)
    if target_n <= n_real:
        return rows[:target_n], list(embeddings[:target_n])

    out_rows = list(rows)
    out_embs = [embeddings[i] for i in range(n_real)]
    i = 0
    while len(out_rows) < target_n:
        src_idx = i % n_real
        src_row = rows[src_idx]
        src_emb = embeddings[src_idx]
        jitter = rng.normal(0, 0.01, size=src_emb.shape).astype(src_emb.dtype)
        new_emb = src_emb + jitter
        new_row = dict(src_row)
        new_row["id"] = f"{src_row['id']}_dup{i:06d}"
        out_rows.append(new_row)
        out_embs.append(new_emb)
        i += 1
    return out_rows[:target_n], out_embs[:target_n]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    ap.add_argument(
        "--extrapolate-to", type=int, default=24401,
        help="secondary-pass target row count modeling loom's full realistic "
             "non-sessions corpus (default: 24401, the real non-sessions total "
             "as of 2026-07-09)",
    )
    ap.add_argument("--skip-extrapolated", action="store_true")
    args = ap.parse_args()

    from sentence_transformers import SentenceTransformer

    print(f"[benchmark-at-scale] loading corpus from {args.corpus}", file=sys.stderr)
    rows = load_corpus(args.corpus)
    print(f"[benchmark-at-scale] {len(rows)} real drawers loaded", file=sys.stderr)

    print(f"[benchmark-at-scale] loading {MODEL_NAME}...", file=sys.stderr)
    model = SentenceTransformer(MODEL_NAME)

    print("[benchmark-at-scale] embedding corpus text...", file=sys.stderr)
    t0 = time.time()
    texts = [(r.get("text") or "")[:1000] for r in rows]
    embeddings = model.encode(texts, batch_size=64, show_progress_bar=False)
    print(f"[benchmark-at-scale] embedded {len(rows)} rows in {time.time()-t0:.2f}s", file=sys.stderr)

    print(f"[benchmark-at-scale] embedding {len(REALISTIC_QUERIES)} realistic queries...", file=sys.stderr)
    query_vecs = model.encode(REALISTIC_QUERIES, batch_size=32, show_progress_bar=False)

    run_id = os.getpid()
    data_dir = Path(f"/tmp/loom-benchmark-at-scale-{run_id}/doltdb")
    socket_path = Path(f"/tmp/loom-benchmark-at-scale-{run_id}/loom-memory.sock")
    port = _free_port()

    print(f"[benchmark-at-scale] starting dolt sql-server (ephemeral data dir {data_dir})", file=sys.stderr)
    proc, conn = start_dolt_server(data_dir, port, socket_path)

    results = {
        "model": MODEL_NAME,
        "embedding_dim": 384,
        "n_queries_per_pass": N_QUERIES,
        "reference_threshold_ms": LATENCY_REFERENCE_THRESHOLD_MS,
        "passes": {},
    }
    try:
        # --- PRIMARY pass: real corpus, exactly as gathered ---
        print(f"[benchmark-at-scale] PRIMARY pass: inserting {len(rows)} real rows...", file=sys.stderr)
        t0 = time.time()
        insert_rows(conn, rows, embeddings)
        print(f"[benchmark-at-scale] insert took {time.time()-t0:.2f}s", file=sys.stderr)

        explain_primary = run_explain(conn)
        bench_primary = run_latency_bench(conn, query_vecs)
        results["passes"]["primary"] = {
            "corpus_size": len(rows),
            "corpus_description": "real MemPalace drawers (non-sessions wings), no synthetic padding",
            "explain_format_tree": explain_primary,
            **bench_primary,
        }
        print(
            f"[benchmark-at-scale] PRIMARY (n={len(rows)}): "
            f"p50={bench_primary['p50_ms']:.3f}ms p95={bench_primary['p95_ms']:.3f}ms "
            f"mean={bench_primary['mean_ms']:.3f}ms", file=sys.stderr,
        )

        # --- EXTRAPOLATED pass: replicate+jitter up to target_n ---
        if not args.skip_extrapolated and args.extrapolate_to > len(rows):
            print(
                f"[benchmark-at-scale] EXTRAPOLATED pass: replicating to "
                f"{args.extrapolate_to} rows...", file=sys.stderr,
            )
            ext_rows, ext_embs = extrapolate(rows, embeddings, args.extrapolate_to)
            extra_rows = ext_rows[len(rows):]
            extra_embs = ext_embs[len(rows):]
            t0 = time.time()
            insert_rows(conn, extra_rows, extra_embs)
            print(f"[benchmark-at-scale] extrapolation insert took {time.time()-t0:.2f}s", file=sys.stderr)

            explain_ext = run_explain(conn)
            bench_ext = run_latency_bench(conn, query_vecs)
            results["passes"]["extrapolated"] = {
                "corpus_size": len(ext_rows),
                "corpus_description": (
                    f"{len(rows)} real rows + {len(extra_rows)} replicated+jittered rows "
                    "modeling loom's eventual full non-sessions corpus"
                ),
                "explain_format_tree": explain_ext,
                **bench_ext,
            }
            print(
                f"[benchmark-at-scale] EXTRAPOLATED (n={len(ext_rows)}): "
                f"p50={bench_ext['p50_ms']:.3f}ms p95={bench_ext['p95_ms']:.3f}ms "
                f"mean={bench_ext['mean_ms']:.3f}ms", file=sys.stderr,
            )

    finally:
        conn.close()
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
