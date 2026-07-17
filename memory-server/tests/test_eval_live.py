"""RED-spec test for loom-rpsf.7 — the D8 before/after measurement driver
(scripts/eval-live.py). This is the tool that lets the deploy gate measure
BOTH the raw-VEC baseline and the shipped hybrid pipeline against the same
held-out ground truth, so a real Recall@10 / MRR delta can be read off.

RED spec (loom-rpsf.7):
  eval-live.py --mode before injects make_dolt_search_fn (raw VEC_DISTANCE,
  the OLD pipeline); --mode after injects mcp_server.tools.search.search
  (the NEW hybrid rollup+BM25+RRF pipeline); both run eval-recall's
  run_eval over the ground truth and emit Recall@10 + MRR JSON.

  The fixture test proves, WITHOUT a live server and WITHOUT
  sentence-transformers:
    * --mode after routes through the NEW search() (not raw VEC),
    * --mode before routes through raw VEC (make_dolt_search_fn),
    * both compute the correct metrics on a fixture corpus + GT.

The driver reuses eval-recall.py's public seams (run_eval,
load_ground_truth, make_dolt_search_fn, partition_in_the_wild,
MODEL_NAME). The mode routing is tested by STUBBING those seams (and the
production search() symbol) and asserting which one each mode invokes —
this is what pins "after really uses the new search()" as a checked
property, not a comment.

Both scripts have a hyphen in the name (scripts/eval-*.py), so each is
loaded via importlib rather than a plain import.
"""
import importlib.util
from pathlib import Path

import pytest

MEMSERVER_ROOT = Path(__file__).resolve().parent.parent
EVAL_LIVE_PATH = MEMSERVER_ROOT / "scripts" / "eval-live.py"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


el = _load("eval_live", EVAL_LIVE_PATH)
er = el.er  # the sibling eval-recall module the driver loads and reuses


# --------------------------------------------------------------------------
# Fixture ground truth + baked per-query rankings. The rankings are chosen
# so Recall@10 + MRR are computable by hand and are the SAME regardless of
# which backend produced them (both modes must feed the identical metric
# math via run_eval):
#   q1: target d1 at rank 1 -> recall 1.0, RR 1.0
#   q2: target d2 at rank 3 -> recall 1.0, RR 1/3
#   q3: target d3 absent    -> recall 0.0, RR 0.0
#   mean recall = 2/3 ; MRR = (1 + 1/3 + 0)/3
# --------------------------------------------------------------------------
Q1 = "fresh checkout starts with an empty issue store and wipes the shared list on merge"
Q2 = "the orchestrator sits blocked instead of doing other work while a subagent runs"
Q3 = "finished tickets quietly flip back to open when parallel branches combine"

FIXTURE_GT = [
    {"query": Q1, "relevant_drawer_ids": ["d1"], "kind": "bug_family"},
    {"query": Q2, "relevant_drawer_ids": ["d2"], "kind": "bug_family"},
    {"query": Q3, "relevant_drawer_ids": ["d3"], "kind": "bug_family"},
]

RANKINGS = {
    Q1: ["d1", "x", "y"],   # target at rank 1
    Q2: ["x", "y", "d2"],   # target at rank 3
    Q3: ["x", "y", "z"],    # target absent
}

EXPECTED_RECALL = 2.0 / 3.0
EXPECTED_MRR = (1.0 + 1.0 / 3.0 + 0.0) / 3.0


# ==========================================================================
# Mode routing — the core RED spec.
# ==========================================================================
def test_after_mode_routes_through_new_search(monkeypatch):
    """--mode after must call the SHIPPED hybrid search()
    (mcp_server.tools.search.search) — never the raw-VEC backend. The
    driver maps search()'s [{'id': ...}, ...] result shape down to ranked
    ids, so the fixture spy returns dicts to prove that extraction too."""
    calls = []

    def fake_search(query, limit=10):
        calls.append(query)
        return [{"id": rid} for rid in RANKINGS[query]]

    def forbidden_make_dolt_search_fn(*a, **k):
        raise AssertionError("mode=after must NOT build the raw-VEC backend")

    monkeypatch.setattr("mcp_server.tools.search.search", fake_search)
    monkeypatch.setattr(er, "make_dolt_search_fn", forbidden_make_dolt_search_fn)

    res = el.run_mode("after", FIXTURE_GT, k=10)

    assert calls == [Q1, Q2, Q3]  # new search() called once per query
    assert res["mode"] == "after"
    assert res["n_queries"] == 3
    assert res["recall_at_k"] == pytest.approx(EXPECTED_RECALL)
    assert res["mrr"] == pytest.approx(EXPECTED_MRR)


def test_before_mode_routes_through_raw_vec(monkeypatch):
    """--mode before must build the raw-VEC backend via eval-recall's
    make_dolt_search_fn over a fresh connection + the model — never the
    new hybrid search(). Deps (connect / model / search) are stubbed so
    the routing is provable without a live server."""
    captured = {}
    sentinel_conn = _FakeConn(rows=[])
    sentinel_model = object()

    def fake_make_dolt_search_fn(conn, model, k=10):
        captured["conn"] = conn
        captured["model"] = model
        captured["k"] = k
        return lambda q: RANKINGS[q]

    def forbidden_search(*a, **k):
        raise AssertionError("mode=before must NOT call the new hybrid search()")

    monkeypatch.setattr(el, "connect", lambda *a, **k: sentinel_conn)
    monkeypatch.setattr(el, "_load_model", lambda: sentinel_model)
    monkeypatch.setattr(er, "make_dolt_search_fn", fake_make_dolt_search_fn)
    monkeypatch.setattr("mcp_server.tools.search.search", forbidden_search)

    res = el.run_mode("before", FIXTURE_GT, k=10)

    # raw-VEC backend built with the live conn + model + k
    assert captured["conn"] is sentinel_conn
    assert captured["model"] is sentinel_model
    assert captured["k"] == 10
    # connection was cleaned up
    assert sentinel_conn.closed is True
    assert res["mode"] == "before"
    assert res["recall_at_k"] == pytest.approx(EXPECTED_RECALL)
    assert res["mrr"] == pytest.approx(EXPECTED_MRR)


def test_before_and_after_agree_on_metric_math(monkeypatch):
    """Given identical rankings, both modes must produce identical
    Recall@10 + MRR — the ONLY thing that differs between them is which
    backend produced the rankings, never the metric aggregation."""
    monkeypatch.setattr(
        "mcp_server.tools.search.search",
        lambda query, limit=10: [{"id": rid} for rid in RANKINGS[query]],
    )
    after = el.run_mode("after", FIXTURE_GT, k=10)

    monkeypatch.setattr(el, "connect", lambda *a, **k: _FakeConn(rows=[]))
    monkeypatch.setattr(el, "_load_model", lambda: object())
    monkeypatch.setattr(
        er, "make_dolt_search_fn",
        lambda conn, model, k=10: (lambda q: RANKINGS[q]),
    )
    before = el.run_mode("before", FIXTURE_GT, k=10)

    assert after["recall_at_k"] == pytest.approx(before["recall_at_k"])
    assert after["mrr"] == pytest.approx(before["mrr"])


def test_run_mode_rejects_unknown_mode():
    with pytest.raises(ValueError):
        el.run_mode("sideways", FIXTURE_GT, k=10)


def test_after_respects_k_limit_passed_to_search(monkeypatch):
    """The k the driver is given must flow to search()'s `limit` — the gate
    measures Recall@k, so the wrong limit silently corrupts the number."""
    seen = {}

    def fake_search(query, limit=10):
        seen["limit"] = limit
        return [{"id": rid} for rid in RANKINGS[query]]

    monkeypatch.setattr("mcp_server.tools.search.search", fake_search)
    el.run_mode("after", FIXTURE_GT, k=5)
    assert seen["limit"] == 5


# ==========================================================================
# Strict-wild guard (main()-path known-item leak check against the corpus).
# ==========================================================================
class _FakeCursor:
    def __init__(self, rows):
        self._rows = rows

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, *a, **k):
        return None

    def fetchall(self):
        return list(self._rows)


class _FakeConn:
    def __init__(self, rows):
        self._rows = rows
        self.closed = False

    def cursor(self):
        return _FakeCursor(self._rows)

    def close(self):
        self.closed = True


def test_strict_wild_flags_known_item_leak(monkeypatch):
    """A query that leaks a corpus drawer's title is a known-item lookup,
    not in-the-wild — strict-wild must hard-fail (SystemExit)."""
    corpus_rows = [{"id": "drawer_ax", "title": "background dispatch is the default"}]
    monkeypatch.setattr(el, "connect", lambda *a, **k: _FakeConn(corpus_rows))

    leaking_gt = [
        {"query": "background dispatch is the default",
         "relevant_drawer_ids": ["drawer_ax"], "kind": "bug_family"},
    ]
    with pytest.raises(SystemExit):
        el._enforce_strict_wild(leaking_gt)


def test_strict_wild_passes_genuine_in_the_wild(monkeypatch):
    """A fuzzy symptom query sharing neither title nor id with its target
    is genuinely in-the-wild — strict-wild must NOT fail."""
    corpus_rows = [{"id": "d2", "title": "background dispatch is the default"}]
    monkeypatch.setattr(el, "connect", lambda *a, **k: _FakeConn(corpus_rows))
    el._enforce_strict_wild([FIXTURE_GT[1]])  # Q2 is fuzzy, no leak -> no raise
