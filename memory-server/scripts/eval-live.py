#!/usr/bin/env python3
"""memory-server/scripts/eval-live.py — the D8 before/after measurement
driver (loom-rpsf.7, epic loom-rpsf).

WHY THIS EXISTS
---------------
scripts/eval-recall.py is the acceptance gate's metric engine: its
`run_eval(ground_truth, search_fn, k)` is an injectable seam, and
`make_dolt_search_fn()` wires the OLD raw-VEC nearest-neighbor query
(`ORDER BY VEC_DISTANCE ... LIMIT k`) onto it. But eval-recall's `main()`
only ever measures that raw-VEC baseline against an EPHEMERAL corpus it
stands up itself. There is no way to measure the NEW shipped pipeline —
`mcp_server.tools.search.search` (chunk rollup + BM25 + Reciprocal Rank
Fusion, loom-rpsf.2/.4/.5) — as it actually runs, against the LIVE prod
corpus. Without an apples-to-apples before/after over the SAME ground
truth, the deploy gate (runbook Step D, docs/DEPLOY-recall-pipeline.md)
cannot read off a real Recall@10 / MRR delta. This driver closes that gap.

THE TWO MODES
-------------
Both modes run eval-recall's SAME `run_eval` over the SAME held-out
ground truth and emit Recall@10 + MRR JSON. They differ ONLY in which
search backend produces the rankings:

  * ``--mode before`` — the OLD pipeline. Injects
    ``eval_recall.make_dolt_search_fn(connect(), model, k)``: embed the
    query with all-MiniLM-L6-v2 and run the raw ``VEC_DISTANCE`` k-NN
    query. This is the pre-loom-rpsf behavior, the baseline the gate
    holds the new work against.
  * ``--mode after`` — the NEW pipeline. Injects
    ``mcp_server.tools.search.search`` (the shipped tool) directly,
    mapping its ``[{"id": ...}, ...]`` result rows down to the ranked-id
    list ``run_eval`` expects. This measures hybrid rollup+BM25+RRF as
    users get it.

Run both against the live server, diff the numbers, and you have the
before/after the deploy decision needs.

LIVE-SERVER TARGET, port 3308
-----------------------------
Unlike eval-recall's `main()` (which stands up its OWN ephemeral dolt),
this driver measures against the LIVE production server. `main()` pins
``LOOM_MEMORY_PORT=3308`` (overridable if already set) so both
``connect()`` (before) and ``search()`` (after, via mcp_server.db) hit
prod. Nothing here writes — it only reads.

TESTABILITY — the mode routing is a CHECKED property, not a comment
-------------------------------------------------------------------
The backend construction is factored into small module-level seams
(`make_before_search_fn`, `make_after_search_fn`, dispatched via
`SEARCH_FN_BUILDERS`) plus `run_mode()`, and the model load is isolated
in `_load_model()`. tests/test_eval_live.py stubs those seams (and the
production `search()` symbol) to prove — with NO live server and NO
sentence-transformers — that `--mode after` routes through the new
`search()`, `--mode before` routes through raw VEC, and both feed the
identical metric math. That is the loom-rpsf.7 RED spec, enforced.

Usage (attended live before/after run):
  LOOM_MEMORY_PORT=3308 scripts/eval-live.py --mode before \\
      --ground-truth GT.jsonl [-k 10] [--kinds bug_family] [--strict-wild]
  LOOM_MEMORY_PORT=3308 scripts/eval-live.py --mode after  \\
      --ground-truth GT.jsonl [-k 10] [--kinds bug_family] [--strict-wild]

Ground-truth JSONL rows: {"query", "relevant_drawer_ids", "kind"}.

Requires (for the live run only, NOT for the fixture tests):
sentence-transformers (the `before` model) and a reachable dolt
sql-server on LOOM_MEMORY_PORT.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Callable, Sequence

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# scripts/eval-recall.py has a hyphen in its name, so it cannot be a plain
# `import`; load it via importlib and reuse its public seams (run_eval,
# load_ground_truth, make_dolt_search_fn, partition_in_the_wild, MODEL_NAME).
_ER_SPEC = importlib.util.spec_from_file_location(
    "eval_recall", ROOT / "scripts" / "eval-recall.py"
)
er = importlib.util.module_from_spec(_ER_SPEC)
_ER_SPEC.loader.exec_module(er)

from mcp_server.db import connect  # noqa: E402  (after sys.path insert)

MODEL_NAME = er.MODEL_NAME
DEFAULT_K = er.DEFAULT_K
DEFAULT_PORT = "3308"


# --------------------------------------------------------------------------
# Search-backend seams. Each returns (search_fn, cleanup): search_fn maps a
# query -> ranked drawer-id list for run_eval; cleanup releases any resource
# the backend opened (a live connection for `before`; nothing for `after`).
# Kept as small module-level functions so tests can stub them and pin the
# mode routing without a live server or sentence-transformers.
# --------------------------------------------------------------------------
def _load_model():
    """Load the sentence-transformers model for the raw-VEC (`before`)
    backend. Isolated in its own seam so the fixture test can stub it
    without importing the heavy dependency."""
    from sentence_transformers import SentenceTransformer

    return SentenceTransformer(MODEL_NAME)


def make_before_search_fn(k: int) -> tuple[Callable[[str], Sequence[str]], Callable[[], None]]:
    """--mode before: the OLD pipeline. Build eval-recall's raw-VEC backend
    (`make_dolt_search_fn`) over a fresh LIVE connection + the embedding
    model. The returned cleanup closes that connection."""
    conn = connect()
    search_fn = er.make_dolt_search_fn(conn, _load_model(), k=k)
    return search_fn, conn.close


def make_after_search_fn(k: int) -> tuple[Callable[[str], Sequence[str]], Callable[[], None]]:
    """--mode after: the NEW pipeline. Inject the shipped hybrid tool
    `mcp_server.tools.search.search` (rollup+BM25+RRF), mapping its
    ``[{"id": ...}, ...]`` rows down to the ranked-id list run_eval wants.
    No resource to release, so cleanup is a no-op."""
    from mcp_server.tools.search import search

    def search_fn(query: str) -> list:
        return [row["id"] for row in search(query, limit=k)]

    return search_fn, (lambda: None)


SEARCH_FN_BUILDERS = {
    "before": make_before_search_fn,
    "after": make_after_search_fn,
}


def run_mode(mode: str, ground_truth: Sequence[dict], k: int = DEFAULT_K) -> dict:
    """Build the backend for `mode`, run eval-recall's `run_eval` over
    `ground_truth`, tag the result dict with the mode, and return it. The
    backend's cleanup runs even if `run_eval` raises."""
    try:
        build = SEARCH_FN_BUILDERS[mode]
    except KeyError:
        raise ValueError(
            f"unknown mode {mode!r}; expected 'before' or 'after'"
        ) from None
    search_fn, cleanup = build(k)
    try:
        result = er.run_eval(ground_truth, search_fn, k=k)
    finally:
        cleanup()
    result["mode"] = mode
    return result


def _enforce_strict_wild(ground_truth: Sequence[dict]) -> None:
    """Known-item leak guard (operationalizes loom-buqk over the LIVE
    corpus). Pull parent-drawer (id, title) from the live server and
    hard-fail if any surviving query leaks a relevant drawer's identity —
    i.e. is a lineage-narrow known-item lookup rather than in-the-wild."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, title FROM drawers WHERE parent_drawer_id IS NULL"
            )
            rows = cur.fetchall()
    finally:
        conn.close()
    # connect() yields a DictCursor, so rows are {"id", "title"} dicts;
    # tolerate a tuple cursor too.
    corpus_by_id = {
        (r["id"] if isinstance(r, dict) else r[0]): (
            r if isinstance(r, dict) else {"id": r[0], "title": r[1]}
        )
        for r in rows
    }
    _, known = er.partition_in_the_wild(ground_truth, corpus_by_id)
    if known:
        raise SystemExit(
            f"[eval-live] STRICT-WILD FAIL: {len(known)} of "
            f"{len(ground_truth)} surviving queries are known-item leaks, "
            "not in-the-wild."
        )


def main() -> None:
    # Target the LIVE prod server by default; an explicit LOOM_MEMORY_PORT
    # wins (both connect() and search()'s mcp_server.db read it at call time).
    os.environ.setdefault("LOOM_MEMORY_PORT", DEFAULT_PORT)

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", choices=["before", "after"], required=True,
                    help="'before' = raw VEC_DISTANCE (old); 'after' = new "
                         "hybrid rollup+BM25+RRF search().")
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

    kinds = None if args.kinds.strip().lower() == "all" else [
        s.strip() for s in args.kinds.split(",") if s.strip()
    ]
    gt = er.load_ground_truth(args.ground_truth, kinds=kinds)

    if args.strict_wild:
        _enforce_strict_wild(gt)

    print(f"[eval-live] mode={args.mode} k={args.k} "
          f"n_queries={len(gt)} port={os.environ.get('LOOM_MEMORY_PORT')}",
          file=sys.stderr)

    result = run_mode(args.mode, gt, k=args.k)

    result["model"] = MODEL_NAME
    result["ground_truth_path"] = str(args.ground_truth)
    result["kinds_kept"] = kinds or "all"
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
