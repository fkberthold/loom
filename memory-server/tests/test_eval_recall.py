"""RED-spec test for loom-rpsf.1 — the in-the-wild recall eval harness
(scripts/eval-recall.py), the acceptance gate for epic loom-rpsf.

RED spec (loom-rpsf.1):
  INVARIANT: the harness reports Recall@10 + MRR over a held-out set of
  realistic should-have-surfaced query->drawer pairs (multi-hop/fuzzy,
  NOT lineage-narrow single-answer queries), and records the current
  baseline so later stages are measured against it.

This file proves the harness on a FIXTURE corpus with KNOWN relevant
pairs, so the metric math is verifiable WITHOUT the production server:

  * Layer 1 — pure metric math (recall_at_k / reciprocal_rank / evaluate)
    on hand-constructed rankings whose Recall@10 + MRR are computed by
    hand. Deterministic, no deps.
  * Layer 2 — run_eval() orchestration driven by an INJECTABLE fake
    search_fn over a fixture corpus + in-the-wild ground truth, asserting
    the aggregate Recall@10 + MRR. Deterministic, no deps.
  * Layer 3 — the in-the-wild guard (is_known_item / partition), which
    operationalizes the loom-buqk concern: it FLAGS a lineage-narrow
    query==title pair and PASSES a genuinely fuzzy one.
  * Layer 4 — a real end-to-end pass against an EPHEMERAL dolt sql-server
    with a tiny synthetic corpus (skipped when dolt / sentence-
    transformers are unavailable). Proves the production search backend
    wires onto the same metric math.

The harness script has a hyphen in its name (scripts/eval-recall.py), so
it is loaded here via importlib rather than a plain `import`.
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
EVAL_RECALL_PATH = MEMSERVER_ROOT / "scripts" / "eval-recall.py"


def _load_eval_recall():
    spec = importlib.util.spec_from_file_location("eval_recall", EVAL_RECALL_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


er = _load_eval_recall()


# ==========================================================================
# Layer 1 — pure metric math (deterministic, no deps)
# ==========================================================================
def test_recall_at_k_single_relevant_in_topk():
    # target at rank 2 (index 1), k=10 -> all 1 relevant is inside top-10.
    ranked = ["a", "target", "c", "d", "e"]
    assert er.recall_at_k(ranked, ["target"], k=10) == 1.0


def test_recall_at_k_relevant_outside_k_is_zero():
    # target at rank 11 (index 10) is OUTSIDE the top-10 window.
    ranked = [f"d{i}" for i in range(10)] + ["target"]
    assert er.recall_at_k(ranked, ["target"], k=10) == 0.0


def test_recall_at_k_partial_multi_relevant():
    # relevant = {a, b}; a at rank 1 (in), b at rank 15 (out, k=10)
    # -> recall@10 = 1/2.
    ranked = ["a"] + [f"d{i}" for i in range(13)] + ["b"]
    assert er.recall_at_k(ranked, ["a", "b"], k=10) == 0.5


def test_recall_at_k_empty_relevant_is_zero():
    assert er.recall_at_k(["a", "b"], [], k=10) == 0.0


def test_reciprocal_rank_first_relevant_position():
    # first (and only) relevant at index 2 -> rank 3 -> RR = 1/3.
    ranked = ["x", "y", "target", "z"]
    assert er.reciprocal_rank(ranked, ["target"]) == pytest.approx(1.0 / 3.0)


def test_reciprocal_rank_uses_earliest_relevant():
    # two relevant; earliest at rank 2 -> RR = 1/2 (not the later one).
    ranked = ["x", "b", "y", "a"]
    assert er.reciprocal_rank(ranked, ["a", "b"]) == pytest.approx(0.5)


def test_reciprocal_rank_none_present_is_zero():
    assert er.reciprocal_rank(["x", "y", "z"], ["target"]) == 0.0


def test_evaluate_aggregates_recall_and_mrr_over_queries():
    """evaluate() means Recall@10 and RR across queries, and reports
    n_queries + k. Hand-computed:
      q1: target at rank 1 -> recall 1.0, RR 1.0
      q2: target at rank 4 -> recall 1.0, RR 1/4
      q3: target absent     -> recall 0.0, RR 0.0
    mean recall = (1+1+0)/3 = 0.6667 ; MRR = (1 + 0.25 + 0)/3 = 0.4167
    """
    rankings = [
        {"query": "q1", "ranked_ids": ["t1", "a", "b"], "relevant_ids": ["t1"]},
        {"query": "q2", "ranked_ids": ["a", "b", "c", "t2"], "relevant_ids": ["t2"]},
        {"query": "q3", "ranked_ids": ["a", "b", "c"], "relevant_ids": ["t3"]},
    ]
    res = er.evaluate(rankings, k=10)
    assert res["n_queries"] == 3
    assert res["k"] == 10
    assert res["recall_at_k"] == pytest.approx(2.0 / 3.0)
    assert res["mrr"] == pytest.approx((1.0 + 0.25 + 0.0) / 3.0)


def test_evaluate_empty_is_honest_zero():
    res = er.evaluate([], k=10)
    assert res["n_queries"] == 0
    assert res["recall_at_k"] == 0.0
    assert res["mrr"] == 0.0


def test_evaluate_per_kind_breakdown():
    rankings = [
        {"query": "q1", "kind": "bug_family", "ranked_ids": ["t1"], "relevant_ids": ["t1"]},
        {"query": "q2", "kind": "bug_family", "ranked_ids": ["x"], "relevant_ids": ["t2"]},
        {"query": "q3", "kind": "lineage", "ranked_ids": ["t3"], "relevant_ids": ["t3"]},
    ]
    res = er.evaluate(rankings, k=10)
    assert res["per_kind"]["bug_family"]["n"] == 2
    assert res["per_kind"]["bug_family"]["recall_at_k"] == pytest.approx(0.5)
    assert res["per_kind"]["lineage"]["recall_at_k"] == pytest.approx(1.0)


# ==========================================================================
# Layer 2 — run_eval() orchestration with an injectable fake search_fn
# ==========================================================================
# A fixture corpus of synthetic drawers on distinct topics, with known
# relevant pairs. In-the-wild ground truth: queries are fuzzy/multi-hop
# descriptions that do NOT contain the target drawer's title or id.
FIXTURE_CORPUS = [
    {"id": "d_worktree", "wing": "loom", "room": "decisions",
     "title": "bd worktree preseed empty dolt state",
     "text": "A fresh git worktree inherits an empty embedded dolt; the "
             "first write-class bd call overwrites issues.jsonl and loses "
             "every other issue on merge."},
    {"id": "d_dispatch", "wing": "loom", "room": "decisions",
     "title": "background dispatch is the default",
     "text": "Central dispatches workers in the background so it yields "
             "the turn instead of sitting idle waiting for the worker."},
    {"id": "d_merge", "wing": "loom", "room": "decisions",
     "title": "bd-state auto-merge protection",
     "text": "Line-based three-way merge of issues.jsonl silently reverts "
             "closed beads back to in_progress across parallel branches."},
    {"id": "d_photo", "wing": "garden", "room": "notes",
     "title": "photosynthesis basics",
     "text": "Chlorophyll in leaf cells absorbs sunlight to convert carbon "
             "dioxide and water into glucose."},
]

# Fuzzy, in-the-wild queries (no title/id leak) -> the drawer that SHOULD
# surface. These stand in for the realistic held-out set the attended
# baseline run supplies.
FIXTURE_GROUND_TRUTH = [
    {"query": "new checkout starts with an empty issue store and destroys "
              "the shared task list on merge",
     "relevant_drawer_ids": ["d_worktree"], "kind": "bug_family"},
    {"query": "the orchestrator agent sits blocked instead of doing other "
              "work while a subagent runs",
     "relevant_drawer_ids": ["d_dispatch"], "kind": "bug_family"},
    {"query": "finished tickets quietly flip back to open when parallel "
              "branches combine",
     "relevant_drawer_ids": ["d_merge"], "kind": "bug_family"},
]


def _fake_search_fn(ranking_by_query):
    """Return a deterministic search_fn that yields a pre-baked ranked id
    list for each query (no embeddings, no dolt)."""
    return lambda q: ranking_by_query[q]


def test_run_eval_orchestrates_search_into_metrics():
    """run_eval() calls search_fn per query, pairs results with relevant
    ids, and produces aggregate Recall@10 + MRR. Hand-baked rankings:
      q1: target at rank 1   -> recall 1.0, RR 1.0
      q2: target at rank 3   -> recall 1.0, RR 1/3
      q3: target absent (k=10) beyond window -> recall 0.0, RR 0.0
    mean recall = 2/3 ; MRR = (1 + 1/3 + 0)/3
    """
    q1 = FIXTURE_GROUND_TRUTH[0]["query"]
    q2 = FIXTURE_GROUND_TRUTH[1]["query"]
    q3 = FIXTURE_GROUND_TRUTH[2]["query"]
    rankings = {
        q1: ["d_worktree", "d_photo", "d_dispatch"],
        q2: ["d_photo", "d_merge", "d_dispatch"],
        q3: ["d_photo", "d_dispatch", "d_worktree"],  # d_merge absent
    }
    res = er.run_eval(FIXTURE_GROUND_TRUTH, _fake_search_fn(rankings), k=10)
    assert res["n_queries"] == 3
    assert res["recall_at_k"] == pytest.approx(2.0 / 3.0)
    assert res["mrr"] == pytest.approx((1.0 + 1.0 / 3.0 + 0.0) / 3.0)


def test_run_eval_perfect_retrieval_scores_one():
    """When every target is retrieved at rank 1, both metrics are 1.0."""
    rankings = {gt["query"]: gt["relevant_drawer_ids"] + ["d_photo"]
                for gt in FIXTURE_GROUND_TRUTH}
    res = er.run_eval(FIXTURE_GROUND_TRUTH, _fake_search_fn(rankings), k=10)
    assert res["recall_at_k"] == pytest.approx(1.0)
    assert res["mrr"] == pytest.approx(1.0)


# ==========================================================================
# Layer 3 — in-the-wild guard (operationalizes loom-buqk)
# ==========================================================================
def test_is_known_item_flags_title_as_query_leak():
    """The SPIKE-1 lineage builder used query == drawer.title. Such a pair
    is a known-item lookup, NOT in-the-wild — the guard must flag it."""
    cbyid = er.corpus_by_id(FIXTURE_CORPUS)
    leak_query = "bd worktree preseed empty dolt state"  # == d_worktree's title
    assert er.is_known_item(leak_query, ["d_worktree"], cbyid) is True


def test_is_known_item_flags_id_leak():
    cbyid = er.corpus_by_id(FIXTURE_CORPUS)
    assert er.is_known_item("see drawer d_worktree for context", ["d_worktree"], cbyid) is True


def test_is_known_item_passes_genuine_in_the_wild_query():
    """A fuzzy symptom description that shares neither the title nor the id
    of its target is genuinely in-the-wild — the guard must NOT flag it."""
    cbyid = er.corpus_by_id(FIXTURE_CORPUS)
    fuzzy = FIXTURE_GROUND_TRUTH[0]["query"]
    assert er.is_known_item(fuzzy, ["d_worktree"], cbyid) is False


def test_partition_splits_wild_from_known_item():
    cbyid = er.corpus_by_id(FIXTURE_CORPUS)
    mixed = list(FIXTURE_GROUND_TRUTH) + [
        {"query": "bd worktree preseed empty dolt state",
         "relevant_drawer_ids": ["d_worktree"], "kind": "lineage"},
    ]
    wild, known = er.partition_in_the_wild(mixed, cbyid)
    assert len(wild) == 3
    assert len(known) == 1
    assert known[0]["kind"] == "lineage"


def test_load_ground_truth_kind_filter_drops_lineage(tmp_path):
    """load_ground_truth(kinds=[...]) keeps only the requested kinds — the
    default caller passes ['bug_family'] to drop lineage-narrow rows."""
    import json

    gt_path = tmp_path / "gt.jsonl"
    rows = [
        {"query": "fuzzy one", "relevant_drawer_ids": ["a"], "kind": "bug_family"},
        {"query": "some title", "relevant_drawer_ids": ["b"], "kind": "lineage"},
    ]
    gt_path.write_text("\n".join(json.dumps(r) for r in rows))
    kept = er.load_ground_truth(gt_path, kinds=["bug_family"])
    assert len(kept) == 1
    assert kept[0]["kind"] == "bug_family"


# ==========================================================================
# Layer 4 — real end-to-end against an ephemeral dolt sql-server
# ==========================================================================
def _deps_available():
    if not (MEMSERVER_ROOT / "bin" / "dolt").exists() and shutil.which("dolt") is None:
        return False
    try:
        import sentence_transformers  # noqa: F401
    except Exception:
        return False
    return True


# Reuse the proven ephemeral-server fixture the rest of the suite uses.
if _deps_available():
    from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


@pytest.mark.skipif(not _deps_available(),
                    reason="requires bin/dolt + sentence-transformers")
def test_end_to_end_recall_against_real_dolt(dolt_server_env):  # noqa: F811
    """Full pipeline on a tiny synthetic corpus: embed corpus, insert into
    the ephemeral dolt, build the production search backend, run the eval.
    A distinctive exact-phrase query is expected to surface its own drawer
    at rank 1; all metrics stay in [0, 1]. Deliberately loose (real
    embeddings are model-dependent) — this proves the WIRING, while the
    exact metric values are pinned by Layers 1-2."""
    from sentence_transformers import SentenceTransformer
    from mcp_server.db import connect

    model = SentenceTransformer(er.MODEL_NAME)
    conn = connect()
    try:
        texts = [r["text"] for r in FIXTURE_CORPUS]
        embeddings = model.encode(texts, show_progress_bar=False)
        er.insert_corpus(conn, FIXTURE_CORPUS, embeddings)

        # An exact-phrase query reliably surfaces its owning drawer at
        # rank 1 even against real embeddings (strongest, least-flaky
        # signal — same tactic as tests/test_mcp_search.py's UNIQUE_PHRASE).
        exact = FIXTURE_CORPUS[0]["text"]
        ground_truth = [
            {"query": exact, "relevant_drawer_ids": ["d_worktree"], "kind": "bug_family"},
        ] + FIXTURE_GROUND_TRUTH

        search_fn = er.make_dolt_search_fn(conn, model, k=10)
        res = er.run_eval(ground_truth, search_fn, k=10)

        assert res["n_queries"] == 4
        assert 0.0 <= res["recall_at_k"] <= 1.0
        assert 0.0 <= res["mrr"] <= 1.0
        # The exact-phrase query must retrieve its own drawer within top-10.
        exact_detail = next(p for p in res["per_query"] if p["query"] == exact)
        assert exact_detail["recall_at_k"] == 1.0
        assert exact_detail["reciprocal_rank"] == pytest.approx(1.0)
    finally:
        conn.close()
