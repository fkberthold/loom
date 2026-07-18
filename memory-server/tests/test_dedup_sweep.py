"""Unit tests for scripts/dedup-sweep.py find_near_duplicates (loom-2fyd).

find_near_duplicates is PURE (no DB, no model) — it takes candidate dicts
with precomputed embeddings, so it is unit-testable with synthetic vectors.
These pin the loom-2fyd precision-first redesign:
  * grouping by (wing, room), never source_file / cross-wing
  * flag a near-dup IFF cosine_dist <= threshold (default 0.08) AND a
    structural agreement signal (title Jaccard >= 0.8 OR same leading
    bead-id token)
  * protected ids are never removed

Regression anchor: the loom-40ec.4.5.6 "retire fallback" vs loom-jk17
"build fallback" pair — distinct decisions on the same topic, ~0.1384
cosine apart — must NOT be flagged (the old 0.15 threshold + no structural
guard deleted the "retire" record, losing real decision history).
"""
import importlib.util
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "dedup_sweep",
    Path(__file__).resolve().parent.parent / "scripts" / "dedup-sweep.py",
)
dedup = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(dedup)
find_near_duplicates = dedup.find_near_duplicates


def _cand(id, wing, room, title, text, embedding):
    return {
        "id": id,
        "wing": wing,
        "room": room,
        "title": title,
        "text": text,
        "embedding": embedding,
    }


# Synthetic 2D vectors with known cosine distance to V_BASE=[1,0]:
V_BASE = [1.0, 0.0]
V_IDENT = [1.0, 0.03]  # dist ~0.0004  (near-identical)
V_CLOSE = [0.95, 0.3122]  # dist ~0.05   (cos 0.95, within 0.08)
V_FP = [0.8616, 0.5076]  # dist ~0.1384 (the real false-positive distance)


def test_true_duplicate_flagged():
    # Same (wing,room), near-identical embedding AND title -> the shorter
    # body is flagged as a dup of the longer (kept) canonical.
    cands = [
        _cand("keep", "loom", "decisions", "# loom-ab12 — foo bar baz", "x" * 500, V_BASE),
        _cand("dup", "loom", "decisions", "# loom-ab12 — foo bar baz", "x" * 100, V_IDENT),
    ]
    out = find_near_duplicates(cands)
    assert [r["id"] for r in out] == ["dup"]
    assert out[0]["canonical_id"] == "keep"


def test_false_positive_same_topic_kept():
    # THE regression: distinct decisions on the same topic, ~0.1384 apart,
    # different bead-ids + titles. Must NOT be flagged.
    cands = [
        _cand(
            "jk17", "loom", "decisions",
            "# loom-jk17 — exploration-discovery fallback for missing mempalace_tag_drawer",
            "x" * 600, V_BASE,
        ),
        _cand(
            "retire", "loom", "decisions",
            "# loom-40ec.4.5.6 SHIPPED — retire exploration-discovery interim fallback now that mempalace_tag_drawer landed",
            "x" * 500, V_FP,
        ),
    ]
    assert find_near_duplicates(cands) == []


def test_close_embedding_but_distinct_decision_kept():
    # Embedding within 0.08 but different bead-ids + titles -> the
    # structural guard blocks removal even though distance alone would pass.
    cands = [
        _cand("a", "loom", "decisions", "# loom-aaa1 — the alpha decision about widgets", "x" * 600, V_BASE),
        _cand("b", "loom", "decisions", "# loom-bbb2 — the beta decision about gadgets", "x" * 500, V_CLOSE),
    ]
    assert find_near_duplicates(cands) == []


def test_cross_wing_not_compared():
    # Near-identical bodies+titles but DIFFERENT wings -> different groups,
    # never compared (source_file grouping used to merge these).
    cands = [
        _cand("t", "technical", "facts", "# Reading sessions auto-generate drawers", "x" * 300, V_BASE),
        _cand("s", "sir", "method", "# Reading sessions auto-generate drawers", "x" * 300, V_IDENT),
    ]
    assert find_near_duplicates(cands) == []


def test_same_bead_id_different_title_flagged():
    # Same leading bead-id, close embedding, titles otherwise differ ->
    # the structural OR branch (same bead-id) flags it.
    cands = [
        _cand("keep", "loom", "decisions", "# loom-xy34 — initial draft of the thing", "x" * 600, V_BASE),
        _cand("dup", "loom", "decisions", "# loom-xy34 — updated wholly reworded notes", "x" * 100, V_CLOSE),
    ]
    out = find_near_duplicates(cands)
    assert [r["id"] for r in out] == ["dup"]


def test_protected_id_never_removed():
    # A genuine dup whose id is protected is never flagged for removal.
    cands = [
        _cand("keep", "loom", "decisions", "# loom-ab12 — foo bar baz", "x" * 500, V_BASE),
        _cand("prot", "loom", "decisions", "# loom-ab12 — foo bar baz", "x" * 100, V_IDENT),
    ]
    assert find_near_duplicates(cands, protected_ids={"prot"}) == []
