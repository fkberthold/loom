#!/usr/bin/env python3
"""memory-server/scripts/eval-recall.py — in-the-wild recall eval harness
(loom-rpsf.1, epic loom-rpsf S0).

This is the ACCEPTANCE GATE for every stage of the loom-rpsf pipeline
(D8 in drawer_loom_decisions_04b915d08eac99c49cef0f1f; gate-dont-advise,
loom-wj26.1). Every later stage (chunking, re-embedding, search-tuning)
is measured against the baseline this harness records. A change that
does not move Recall@10 / MRR on the held-out set is not an improvement.

WHAT IT MEASURES — IN-THE-WILD recall, NOT known-item precision
----------------------------------------------------------------
"In-the-wild recall" = surfacing prior art you did NOT search for by id.
The realistic use is bug-family search: an agent starts a bead, describes
the *symptom* in natural words, and the memory server should surface the
prior decision drawers that bear on it — even though the query shares no
id and little verbatim vocabulary with those drawers.

This is DISTINCT from — and deliberately avoids — the failure mode
loom-buqk flagged in the SPIKE-1 ground truth (~/loom-spike1-benchmark/
build_ground_truth_full.py): that builder emits one "lineage" query per
drawer where `query == drawer.title` and the relevant set is that
drawer's own lineage links. Querying with a drawer's own title is
essentially a known-item lookup — the query lexically almost IS the
target — so it inflates recall in a way that does not reflect the
in-the-wild "I did not know this drawer existed" retrieval we care about.

This harness therefore:
  1. Filters the held-out set to genuinely in-the-wild pairs by default
     (`--kinds bug_family`, dropping the lineage-narrow `kind=lineage`
     rows), and
  2. Offers `--strict-wild`, which HARD-FAILS if any surviving query is
     a known-item leak (its text contains a relevant drawer's id, or a
     relevant drawer's title is a substring of the query). This turns
     "the eval set is not lineage-narrow" from a comment into a checked,
     enforceable property.

METRICS (definitions match SPIKE-1's load_and_benchmark_full.py exactly,
so this harness's numbers are comparable to that lineage):
  * Recall@k  = |top-k retrieved ∩ relevant| / |relevant|, averaged over
                queries. "Of the drawers that SHOULD have surfaced, what
                fraction landed in the top k?"
  * MRR       = mean over queries of 1/(1-based rank of the first
                relevant drawer in the retrieved list), 0 if none in the
                retrieved list.

ARCHITECTURE — the metric math is decoupled from the search backend
-------------------------------------------------------------------
`evaluate()` and the pure `recall_at_k()` / `reciprocal_rank()` helpers
take already-ranked id lists and known relevant sets. They contain NO
embedding, NO SQL, NO model — so the metric math is verifiable on a
fixture corpus with hand-constructed rankings, WITHOUT a live server or
sentence-transformers (see tests/test_eval_recall.py). `run_eval()` adds
one seam: it takes an INJECTABLE `search_fn(query) -> ranked_ids`, so the
orchestration (ground-truth iteration → search → metric aggregation) is
testable with a deterministic fake search, again with no heavy deps. The
real backend, `make_dolt_search_fn()`, wires the production search shape
(embed query with all-MiniLM-L6-v2, `ORDER BY VEC_DISTANCE ... LIMIT k`
— the SAME query mcp_server/tools/search.py runs) onto that seam.

BASELINE (the ~0.50 Recall@10 measurement) IS AN ATTENDED STEP
--------------------------------------------------------------
Running this against the LIVE production corpus to record the ~0.50
baseline is done by a human at an attended run — NOT by this file's
tests and NOT automatically. `main()` is the entry point for that run;
it stands up an EPHEMERAL dolt sql-server over a temp data dir (it never
touches the live server on ports 3307/3308), loads a corpus + held-out
ground truth, and prints a JSON report carrying recall@k, MRR, per-kind
breakdown, and a `baseline` note.

Usage (attended baseline run):
  scripts/eval-recall.py --corpus CORPUS.jsonl --ground-truth GT.jsonl \\
      [-k 10] [--kinds bug_family] [--strict-wild]

Corpus JSONL rows: {"id"|"drawer_id", "wing", "room", "title", "text"}.
Ground-truth JSONL rows:
  {"query": str, "relevant_drawer_ids": [str, ...], "kind": str}

Requires (for the live/`main()` path only, NOT for the metric tests):
sentence-transformers, numpy — see scripts/requirements-benchmark.txt.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Iterable, Optional, Sequence

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
START_SERVER = MEMSERVER_ROOT / "scripts" / "start-server.sh"

MODEL_NAME = "all-MiniLM-L6-v2"
DEFAULT_K = 10
# The pre-chunking baseline this gate exists to hold later stages against.
# Reported as context in the JSON output; the actual number is captured at
# the attended live run, not hard-coded as an assertion.
BASELINE_RECALL_AT_10 = 0.50


# --------------------------------------------------------------------------
# Pure metric math — no embeddings, no SQL, no model. Verifiable on a
# fixture with hand-constructed rankings (the RED spec's core).
# --------------------------------------------------------------------------
def recall_at_k(
    ranked_ids: Sequence[str], relevant_ids: Iterable[str], k: int = DEFAULT_K
) -> float:
    """Recall@k = |top-k retrieved ∩ relevant| / |relevant|.

    The fraction of the relevant drawers that appear within the first `k`
    retrieved ids. Returns 0.0 when `relevant_ids` is empty (no credit
    possible, no division by zero). Matches SPIKE-1's
    `len(set(hits)) / len(relevant)` definition.
    """
    relevant = set(relevant_ids)
    if not relevant:
        return 0.0
    topk = set(ranked_ids[:k])
    return len(topk & relevant) / len(relevant)


def reciprocal_rank(ranked_ids: Sequence[str], relevant_ids: Iterable[str]) -> float:
    """1 / (1-based rank of the FIRST relevant id in `ranked_ids`), or
    0.0 if no relevant id appears. `ranked_ids` is expected to already be
    the top-k retrieved list (search runs with LIMIT k), so this doubles
    as reciprocal-rank@k — matching SPIKE-1, which computed RR over its
    k-limited result set.
    """
    relevant = set(relevant_ids)
    for i, rid in enumerate(ranked_ids):
        if rid in relevant:
            return 1.0 / (i + 1)
    return 0.0


def evaluate(rankings: Sequence[dict], k: int = DEFAULT_K) -> dict:
    """Aggregate Recall@k + MRR over a list of per-query ranking records.

    Each record is a dict with:
      - "ranked_ids":   the retrieved id list (top-k), closest first
      - "relevant_ids": the known-relevant id set for that query
      - "kind" (opt):   a category label for a per-kind breakdown
      - "query" (opt):  carried into per_query detail for reporting

    Returns {recall_at_k, mrr, n_queries, k, per_kind, per_query}.
    `recall_at_k` and `mrr` are the means across queries. `per_kind` maps
    each kind -> {n, recall_at_k, mrr}. An empty `rankings` yields 0.0
    metrics over 0 queries (an honest empty result, never a crash).
    """
    per_query = []
    for rec in rankings:
        ranked = rec["ranked_ids"]
        relevant = rec["relevant_ids"]
        r = recall_at_k(ranked, relevant, k)
        rr = reciprocal_rank(ranked, relevant)
        per_query.append(
            {
                "query": rec.get("query"),
                "kind": rec.get("kind"),
                "recall_at_k": r,
                "reciprocal_rank": rr,
                "n_relevant": len(set(relevant)),
                "n_retrieved": len(ranked),
            }
        )

    n = len(per_query)
    mean_recall = sum(p["recall_at_k"] for p in per_query) / n if n else 0.0
    mrr = sum(p["reciprocal_rank"] for p in per_query) / n if n else 0.0

    per_kind: dict = {}
    for p in per_query:
        kind = p["kind"] or "unspecified"
        per_kind.setdefault(kind, []).append(p)
    per_kind_summary = {
        kind: {
            "n": len(items),
            "recall_at_k": sum(i["recall_at_k"] for i in items) / len(items),
            "mrr": sum(i["reciprocal_rank"] for i in items) / len(items),
        }
        for kind, items in per_kind.items()
    }

    return {
        "recall_at_k": mean_recall,
        "mrr": mrr,
        "n_queries": n,
        "k": k,
        "per_kind": per_kind_summary,
        "per_query": per_query,
    }


# --------------------------------------------------------------------------
# Orchestration — injectable search_fn seam. Testable with a fake search.
# --------------------------------------------------------------------------
def run_eval(
    ground_truth: Sequence[dict],
    search_fn: Callable[[str], Sequence[str]],
    k: int = DEFAULT_K,
) -> dict:
    """Run the eval: for every ground-truth entry, call
    `search_fn(query)` -> ranked id list, pair it with that entry's
    relevant ids, and hand the whole set to `evaluate()`.

    `search_fn` is injected so the orchestration is testable with a
    deterministic fake (no dolt, no model); `make_dolt_search_fn()` is the
    production backend. Each ground-truth entry is
    {"query", "relevant_drawer_ids", "kind"?}.
    """
    rankings = []
    for gt in ground_truth:
        query = gt["query"]
        ranked = list(search_fn(query))
        rankings.append(
            {
                "query": query,
                "kind": gt.get("kind"),
                "ranked_ids": ranked,
                "relevant_ids": list(gt.get("relevant_drawer_ids", [])),
            }
        )
    return evaluate(rankings, k)


# --------------------------------------------------------------------------
# In-the-wild guard (operationalizes the loom-buqk methodology concern).
# --------------------------------------------------------------------------
def _normalize(text: str) -> str:
    """Lowercase and collapse to single-spaced alphanumeric tokens, so
    title/query comparison ignores punctuation, markdown, and case."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def is_known_item(query: str, relevant_ids: Iterable[str], corpus_by_id: dict) -> bool:
    """True when `query` is a KNOWN-ITEM (lineage-narrow) lookup rather
    than an in-the-wild query — i.e. it leaks the identity of a relevant
    drawer. Two leak forms are detected, matching the two ways SPIKE-1's
    lineage builder produced known-item pairs:

      1. id leak    — a relevant drawer's id appears verbatim in the query.
      2. title leak — a relevant drawer's (normalized) title is a
                      substring of the (normalized) query, or vice versa
                      (the `query == drawer.title` construction).

    `corpus_by_id` maps drawer id -> row dict (needs a "title"). Ids not
    present in the corpus can only be checked for the id-leak form.
    """
    nq = _normalize(query)
    for rid in relevant_ids:
        if rid and rid in query:
            return True
        row = corpus_by_id.get(rid)
        if not row:
            continue
        ntitle = _normalize(row.get("title") or "")
        if ntitle and (ntitle in nq or nq in ntitle):
            return True
    return False


def partition_in_the_wild(ground_truth: Sequence[dict], corpus_by_id: dict):
    """Split ground truth into (in_the_wild, known_item) lists using
    `is_known_item`. Lets the caller drop or flag the lineage-narrow rows
    loom-buqk warned against."""
    wild, known = [], []
    for gt in ground_truth:
        if is_known_item(gt["query"], gt.get("relevant_drawer_ids", []), corpus_by_id):
            known.append(gt)
        else:
            wild.append(gt)
    return wild, known


# --------------------------------------------------------------------------
# I/O helpers
# --------------------------------------------------------------------------
def _corpus_id(row: dict) -> str:
    """Corpus rows use either "id" (memory-server / benchmark-at-scale
    shape) or "drawer_id" (SPIKE-1 shape). Accept both."""
    return row.get("id") or row["drawer_id"]


def load_corpus(path: Path) -> list:
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def load_ground_truth(path: Path, kinds: Optional[Sequence[str]] = None) -> list:
    """Load held-out query->relevant-drawer pairs from JSONL. When `kinds`
    is given, keep only entries whose `kind` is in that set — the default
    caller passes `["bug_family"]` to drop the lineage-narrow rows."""
    kinds_set = set(kinds) if kinds else None
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            gt = json.loads(line)
            if kinds_set is not None and gt.get("kind") not in kinds_set:
                continue
            out.append(gt)
    return out


def corpus_by_id(rows: Sequence[dict]) -> dict:
    return {_corpus_id(r): r for r in rows}


# --------------------------------------------------------------------------
# Real dolt search backend (production search shape) + ephemeral bring-up.
# --------------------------------------------------------------------------
def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _vec_literal(vec) -> str:
    """Format a vector as the `[..]` literal Dolt's string_to_vector()
    expects (mirrors mcp_server/embeddings.vector_literal + SPIKE-1)."""
    return "[" + ",".join(f"{float(x):.6f}" for x in vec) + "]"


def make_dolt_search_fn(conn, model, k: int = DEFAULT_K) -> Callable[[str], list]:
    """Build the production-shaped search backend as a `search_fn` for
    `run_eval`: embed the query with `model`, run
    `ORDER BY VEC_DISTANCE(embedding, :q) LIMIT k` (the exact
    nearest-neighbor query shape mcp_server/tools/search.py uses), and
    return the retrieved drawer ids closest-first. Unscoped (no wing/room
    filter) — in-the-wild recall is corpus-wide."""

    def search_fn(query: str) -> list:
        qvec = model.encode(query)
        vec_str = _vec_literal(qvec.tolist() if hasattr(qvec, "tolist") else qvec)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, VEC_DISTANCE(embedding, string_to_vector(%s)) AS dist "
                "FROM drawers ORDER BY dist ASC LIMIT %s",
                (vec_str, int(k)),
            )
            rows = cur.fetchall()
        # DictCursor -> row["id"]; plain cursor -> row[0].
        return [(r["id"] if isinstance(r, dict) else r[0]) for r in rows]

    return search_fn


def start_dolt_server(data_dir: Path, port: int, socket_path: Path):
    """Boot an EPHEMERAL dolt sql-server via scripts/start-server.sh over
    a temp data dir (never the live server). Mirrors the bring-up in
    scripts/benchmark-at-scale.py and tests/test_mcp_drawers.py."""
    import pymysql

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
            raise RuntimeError(
                f"start-server.sh exited early (code {proc.returncode}):\n{out}"
            )
        try:
            conn = pymysql.connect(
                host="127.0.0.1", port=port, user="root", password="",
                database="doltdb", autocommit=True, connect_timeout=2,
                cursorclass=pymysql.cursors.DictCursor,
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


def insert_corpus(conn, rows, embeddings, batch_size: int = 200) -> None:
    """Insert corpus rows + their embeddings into the ephemeral drawers
    table (parameterized, string_to_vector for the VECTOR column)."""
    cur = conn.cursor()
    batch = []

    def flush(b):
        values_sql = ",".join(
            "(%s,%s,%s,%s,%s,string_to_vector(%s),NOW(),%s,%s,%s,%s)" for _ in b
        )
        args = []
        for (id_, wing, room, title, text, vec_str) in b:
            args.extend(
                [id_, wing, room, title, text, vec_str, "eval-recall", 0, None, "eval"]
            )
        cur.execute(
            "INSERT INTO drawers (id, wing, room, title, text, embedding, filed_at, "
            "source_file, chunk_index, parent_drawer_id, added_by) VALUES " + values_sql,
            args,
        )

    for row, emb in zip(rows, embeddings):
        vec_str = _vec_literal(emb.tolist() if hasattr(emb, "tolist") else emb)
        wing = row.get("wing") or "eval"
        room = row.get("room") or "corpus"
        title = (row.get("title") or f"{wing}/{room}")[:512]
        text = (row.get("text") or "")[:8000]
        batch.append((_corpus_id(row), wing, room, title, text, vec_str))
        if len(batch) >= batch_size:
            flush(batch)
            batch = []
    if batch:
        flush(batch)
    cur.close()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus", type=Path, required=True,
                    help="corpus JSONL: {id|drawer_id, wing, room, title, text}")
    ap.add_argument("--ground-truth", type=Path, required=True,
                    help="held-out JSONL: {query, relevant_drawer_ids, kind}")
    ap.add_argument("-k", "--k", type=int, default=DEFAULT_K)
    ap.add_argument(
        "--kinds", default="bug_family",
        help="comma-separated ground-truth kinds to KEEP (default "
             "'bug_family' — drops lineage-narrow rows per loom-buqk); pass "
             "'all' to keep every kind.",
    )
    ap.add_argument(
        "--strict-wild", action="store_true",
        help="hard-fail if any surviving query is a known-item leak "
             "(id or title leak) rather than genuinely in-the-wild.",
    )
    args = ap.parse_args()

    from sentence_transformers import SentenceTransformer

    corpus = load_corpus(args.corpus)
    cbyid = corpus_by_id(corpus)
    kinds = None if args.kinds.strip().lower() == "all" else [
        s.strip() for s in args.kinds.split(",") if s.strip()
    ]
    gt = load_ground_truth(args.ground_truth, kinds=kinds)

    wild, known = partition_in_the_wild(gt, cbyid)
    if known:
        msg = (
            f"{len(known)} of {len(gt)} surviving queries are KNOWN-ITEM "
            "(lineage-narrow) leaks, not in-the-wild"
        )
        if args.strict_wild:
            raise SystemExit(f"[eval-recall] STRICT-WILD FAIL: {msg}.")
        print(f"[eval-recall] WARNING: {msg}; keeping them.", file=sys.stderr)

    print(f"[eval-recall] loading {MODEL_NAME}...", file=sys.stderr)
    model = SentenceTransformer(MODEL_NAME)

    print(f"[eval-recall] embedding {len(corpus)} corpus rows...", file=sys.stderr)
    texts = [(r.get("text") or "")[:1000] for r in corpus]
    embeddings = model.encode(texts, batch_size=64, show_progress_bar=False)

    run_id = os.getpid()
    data_dir = Path(f"/tmp/loom-eval-recall-{run_id}/doltdb")
    socket_path = Path(f"/tmp/loom-eval-recall-{run_id}/loom-memory.sock")
    port = _free_port()

    print(f"[eval-recall] starting EPHEMERAL dolt sql-server (data dir {data_dir})",
          file=sys.stderr)
    proc, conn = start_dolt_server(data_dir, port, socket_path)
    try:
        print(f"[eval-recall] inserting {len(corpus)} rows...", file=sys.stderr)
        insert_corpus(conn, corpus, embeddings)
        search_fn = make_dolt_search_fn(conn, model, k=args.k)
        result = run_eval(gt, search_fn, k=args.k)
    finally:
        conn.close()
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    result["model"] = MODEL_NAME
    result["corpus_size"] = len(corpus)
    result["ground_truth_path"] = str(args.ground_truth)
    result["kinds_kept"] = kinds or "all"
    result["baseline"] = {
        "recall_at_10_reference": BASELINE_RECALL_AT_10,
        "note": (
            "Pre-chunking in-the-wild baseline this gate holds later "
            "loom-rpsf stages against. This value is the reference target; "
            "the recorded number above is THIS run's measurement."
        ),
    }
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
