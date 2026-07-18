#!/usr/bin/env python3
"""scripts/dedup-sweep.py — offline near-duplicate drawer sweep
(loom-rpsf.6, epic loom-rpsf S4, design D6, drawer
drawer_loom_decisions_04b915d08eac99c49cef0f1f).

A MAINTENANCE tool, run attended against the memory server — NOT part of
the request path and NOT run in CI. Its job is to clean up the
near-duplicate rows that accumulated in the candidate pool BEFORE
content-hash drawer ids made add_drawer idempotent: two adds of
substantially-identical content under the old random-id scheme produced
two distinct rows, both of which surface in recall as competing
near-dups.

Content-hash ids (this same bead) stop NEW exact-duplicate rows at the
source (an identical re-add now upserts). This sweep handles the
residual NEAR-duplicates — rows whose bodies differ slightly (a re-mine
with a reworded sentence, a trailing-whitespace drift) so their hashes
differ but their meaning does not.

Algorithm (D6, revised by loom-2fyd for precision on a decision corpus):
  * candidates = logical drawers only (parent_drawer_id IS NULL); child
    chunk rows are never swept independently.
  * group PER (wing, room) — the natural provenance proxy. (The original
    per-source_file grouping degenerated here: ~2100 NULL + ~1400 empty
    source_file drawers span unrelated wings, so it compared — and would
    have deleted — across projects. loom-2fyd.)
  * within each group, process LONGEST-FIRST: the longest body is kept as
    the canonical (it carries the most content), and a later body is a
    near-duplicate to remove ONLY when BOTH: (a) it is within `--distance`
    cosine of a kept canonical, AND (b) it AGREES structurally with that
    canonical — near-identical title (Jaccard >= 0.8) OR same leading
    bead-id. The structural guard is the precision-first fix for the class
    loom-2fyd caught: "build X" and "retire X" are ~85% cosine-similar yet
    are OPPOSITE decisions; distance alone deleted the "retire" record.
  * cosine distance threshold defaults to 0.08 (loom-2fyd tightened it from
    D6's 0.15, which admitted the same-topic-different-decision band).
  * ids passed via --protect-file are never removed (e.g. the eval
    ground-truth targets, so a sweep can't silently drop a gate drawer).

SAFETY: dry-run by DEFAULT. Nothing is deleted unless `--apply` is
passed. Deleting a canonical drawer removes its child chunk rows too
(via mcp_server.tools.drawers.delete_drawer).

PRODUCTION GATE: the live sweep against the running memory server (and
the accompanying content-hash id cutover) is an ATTENDED checkpoint with
the operator — see the epic's production-gate note. Run --dry-run first,
eyeball the report, and only then re-run with --apply.

Usage:
  # preview (default) — every group, what WOULD be removed, no writes:
  scripts/dedup-sweep.py

  # narrow to one provenance and a tighter threshold, still preview:
  scripts/dedup-sweep.py --source-file notes.md --distance 0.10

  # actually delete the near-dups (attended, after eyeballing preview):
  scripts/dedup-sweep.py --apply

The DB target is the same LOOM_MEMORY_* env the MCP tools read (see
mcp_server/db.py); point it at the intended server before running.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

# Allow `import mcp_server...` when run as a bare script from anywhere.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Default cosine-distance threshold below which two drawers are treated
# as near-duplicates (loom-2fyd tightened this from the original D6 0.15).
# Distance = 1 - cosine_similarity, so smaller is more similar; 0.08 flags
# only bodies that are ~92%+ cosine-similar (whitespace/reword drift), NOT
# the ~85% "same topic, different decision" band the 0.15 default deleted.
DEFAULT_DISTANCE = 0.08

# A near-dup candidate must also AGREE with its canonical on a NON-embedding
# signal (loom-2fyd precision-first guard): either near-identical titles
# (Jaccard >= this) or the same leading bead-id token.
TITLE_JACCARD_THRESHOLD = 0.8

_WORD_RE = re.compile(r"[a-z0-9][a-z0-9._-]*")
# A bead-id-shaped leading token: <prefix>-<id>, e.g. loom-jk17,
# loom-40ec.4.5.6. Anchored so only a full leading token qualifies.
_BEAD_ID_RE = re.compile(r"^[a-z][a-z0-9]*-[a-z0-9][a-z0-9.]*$")


def _title_tokens(title: str) -> set:
    return set(_WORD_RE.findall((title or "").lower()))


def _title_jaccard(t1: str, t2: str) -> float:
    """Token-set Jaccard of two titles. Two empty titles are identical
    (1.0); one empty and one not share nothing (0.0)."""
    s1, s2 = _title_tokens(t1), _title_tokens(t2)
    if not s1 and not s2:
        return 1.0
    if not s1 or not s2:
        return 0.0
    return len(s1 & s2) / len(s1 | s2)


def _leading_bead_id(title: str) -> str | None:
    """The leading `prefix-id` token of a title (e.g. '# loom-jk17 — ...'
    -> 'loom-jk17'), or None. Only the FIRST whitespace-delimited token is
    considered, so a compound word later in the title
    ('exploration-discovery') is never mistaken for a bead id."""
    stripped = (title or "").lstrip("# ").strip()
    if not stripped:
        return None
    first = stripped.split()[0].lower()
    return first if _BEAD_ID_RE.match(first) else None


def _structural_match(a: dict, b: dict) -> bool:
    """A near-dup must AGREE structurally with its canonical, not merely sit
    close in embedding space: near-identical titles OR the same leading
    bead-id. This is what keeps 'build X' and 'retire X' — same topic,
    OPPOSITE decisions, ~85% cosine-similar — from being deduped
    (loom-2fyd: the loom-40ec.4.5.6 vs loom-jk17 false positive)."""
    if _title_jaccard(a.get("title", ""), b.get("title", "")) >= TITLE_JACCARD_THRESHOLD:
        return True
    ba, bb = _leading_bead_id(a.get("title", "")), _leading_bead_id(b.get("title", ""))
    return ba is not None and ba == bb


def find_near_duplicates(
    candidates: list[dict],
    threshold: float = DEFAULT_DISTANCE,
    protected_ids=None,
) -> list[dict]:
    """Identify near-duplicate drawers to remove (loom-2fyd redesign).

    `candidates` is a list of dicts, each with keys: id, wing, room, title,
    text, embedding (list[float]). Grouped PER (wing, room) — the natural
    provenance proxy, and NEVER across wings (the old per-source_file
    grouping degenerated on this corpus because thousands of drawers share
    a NULL/empty source_file that spans unrelated wings). Within each group
    they are processed LONGEST-first (by len(text)); the longest body is
    kept as the canonical.

    A later body is flagged as a near-duplicate of the NEAREST kept
    canonical ONLY when BOTH hold (precision-first — deleting a real
    decision is far costlier than leaving a near-dup):
      1. cosine distance <= `threshold`, AND
      2. `_structural_match` — near-identical title OR same leading bead-id.
    Ids in `protected_ids` are never removed (they stay as canonicals).

    Returns a list of dicts {id, canonical_id, wing, room, distance}, one
    per drawer to remove. Pure — no DB, no embedding model — so it is
    unit-testable with synthetic vectors.
    """
    protected = set(protected_ids or [])
    groups: dict[object, list[dict]] = {}
    for cand in candidates:
        groups.setdefault((cand.get("wing"), cand.get("room")), []).append(cand)

    to_remove: list[dict] = []
    for (wing, room), group in groups.items():
        # Longest-first; ties broken by id for a deterministic canonical.
        ordered = sorted(group, key=lambda c: (-len(c.get("text") or ""), c["id"]))
        # Unit-normalize embeddings once (numpy) so cosine similarity is a
        # plain dot product. A zero-magnitude vector keeps a zero row, so it
        # registers as maximally distant (sim 0 -> dist 1) from everything.
        mat = np.asarray([c["embedding"] for c in ordered], dtype=float)
        norms = np.linalg.norm(mat, axis=1, keepdims=True)
        norms[norms == 0.0] = 1.0
        normed = mat / norms

        kept_idx: list[int] = []
        for i, cand in enumerate(ordered):
            nearest_id = None
            nearest_dist = None
            if kept_idx:
                dists = 1.0 - (normed[i] @ normed[kept_idx].T)
                for j, dist in zip(kept_idx, dists):
                    dist = float(dist)
                    if (
                        dist <= threshold
                        and _structural_match(cand, ordered[j])
                        and (nearest_dist is None or dist < nearest_dist)
                    ):
                        nearest_dist = dist
                        nearest_id = ordered[j]["id"]
            if nearest_id is not None and cand["id"] not in protected:
                to_remove.append(
                    {
                        "id": cand["id"],
                        "canonical_id": nearest_id,
                        "wing": wing,
                        "room": room,
                        "distance": nearest_dist,
                    }
                )
            else:
                kept_idx.append(i)
    return to_remove


def load_candidate_drawers(
    source_file: str | None = None,
    wing: str | None = None,
    room: str | None = None,
) -> list[dict]:
    """Load logical drawers (parent_drawer_id IS NULL) as candidates,
    re-embedding each body with the same model add_drawer uses so the
    sweep compares on the FULL text (a chunked parent's stored vector is
    embed(title), which is not what we want to dedup on). Optional
    source_file / wing / room filters narrow the sweep."""
    from mcp_server.db import connect
    from mcp_server.embeddings import embed_batch

    conditions = ["parent_drawer_id IS NULL"]
    params: list[object] = []
    if source_file is not None:
        conditions.append("source_file = %s")
        params.append(source_file)
    if wing is not None:
        conditions.append("wing = %s")
        params.append(wing)
    if room is not None:
        conditions.append("room = %s")
        params.append(room)
    where = " AND ".join(conditions)

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title, text, source_file "
                f"FROM drawers WHERE {where}",
                params,
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    texts = [(row.get("text") or "") for row in rows]
    # Batched embedding — ONE .encode() over the whole candidate set rather
    # than one per row (loom-2fyd feasibility: the per-row path made a ~12k
    # corpus sweep take 10-20 min and get killed).
    embeddings = embed_batch(texts) if texts else []
    candidates = []
    for row, text, emb in zip(rows, texts, embeddings):
        candidates.append(
            {
                "id": row["id"],
                "wing": row["wing"],
                "room": row["room"],
                "title": row["title"],
                "text": text,
                "source_file": row.get("source_file"),
                "embedding": emb,
            }
        )
    return candidates


def load_protected_ids(path) -> set:
    """Read drawer ids that must NEVER be removed. Accepts either a
    ground-truth JSONL (objects with a `relevant_drawer_ids` list — e.g.
    eval/bug-family-ground-truth.jsonl) or a plain one-id-per-line list.
    Protecting the eval targets keeps a sweep from silently deleting a gate
    drawer and dropping the recall score (runbook §8)."""
    protected: set = set()
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            protected.add(line)
            continue
        if isinstance(obj, dict) and "relevant_drawer_ids" in obj:
            protected.update(obj["relevant_drawer_ids"])
        elif isinstance(obj, str):
            protected.add(obj)
    return protected


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Offline near-duplicate drawer sweep (loom-rpsf.6, D6). "
        "Dry-run by default; pass --apply to delete."
    )
    parser.add_argument(
        "--distance",
        type=float,
        default=DEFAULT_DISTANCE,
        help=f"cosine-distance threshold (default {DEFAULT_DISTANCE}); "
        "drawers within this distance of a kept canonical are near-dups.",
    )
    parser.add_argument(
        "--source-file",
        default=None,
        help="only sweep drawers with this source_file.",
    )
    parser.add_argument("--wing", default=None, help="only sweep this wing.")
    parser.add_argument("--room", default=None, help="only sweep this room.")
    parser.add_argument(
        "--protect-file",
        type=Path,
        default=None,
        help="JSONL ground-truth file (or one-id-per-line list) whose drawer "
        "ids are NEVER removed (e.g. eval/bug-family-ground-truth.jsonl).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="ACTUALLY delete the near-duplicates (default: dry-run preview).",
    )
    args = parser.parse_args(argv)

    protected_ids = load_protected_ids(args.protect_file) if args.protect_file else set()
    candidates = load_candidate_drawers(
        source_file=args.source_file, wing=args.wing, room=args.room
    )
    to_remove = find_near_duplicates(
        candidates, threshold=args.distance, protected_ids=protected_ids
    )

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(
        f"[dedup-sweep {mode}] {len(candidates)} candidate drawers, "
        f"threshold={args.distance}, {len(protected_ids)} protected, "
        f"{len(to_remove)} near-duplicate(s) found."
    )
    for item in to_remove:
        print(
            f"  - {item['id']}  (dup of {item['canonical_id']}, "
            f"distance={item['distance']:.4f}, "
            f"wing={item['wing']!r}, room={item['room']!r})"
        )

    if not to_remove:
        return 0

    if not args.apply:
        print("\n[dedup-sweep] DRY-RUN — nothing deleted. Re-run with --apply "
              "to remove the near-duplicates above.")
        return 0

    from mcp_server.tools.drawers import delete_drawer

    deleted = 0
    for item in to_remove:
        result = delete_drawer(item["id"])
        if result.get("success"):
            deleted += 1
            print(f"  deleted {item['id']} "
                  f"(+{result.get('chunks_deleted', 0)} chunk rows)")
    print(f"\n[dedup-sweep] deleted {deleted}/{len(to_remove)} near-duplicate drawer(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
