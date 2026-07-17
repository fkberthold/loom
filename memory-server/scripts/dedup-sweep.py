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

Algorithm (locked by D6):
  * candidates = logical drawers only (parent_drawer_id IS NULL); child
    chunk rows are never swept independently.
  * group PER source_file — duplicates almost always share a provenance.
  * within each group, process LONGEST-FIRST: the longest body is kept
    as the canonical (it carries the most content), and any later body
    within `--distance` cosine of an already-kept canonical is a
    near-duplicate to remove.
  * cosine distance threshold defaults to 0.15 (D6).

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
import math
import sys
from pathlib import Path

# Allow `import mcp_server...` when run as a bare script from anywhere.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Default cosine-distance threshold below which two drawers are treated
# as near-duplicates (D6). Distance = 1 - cosine_similarity, so smaller
# is more similar; 0.15 flags bodies that are ~85%+ cosine-similar.
DEFAULT_DISTANCE = 0.15


def cosine_distance(a: list[float], b: list[float]) -> float:
    """1 - cosine_similarity(a, b), clamped to [0, 2]. A zero-magnitude
    vector has no defined direction, so it is treated as maximally
    distant (1.0) from everything rather than raising."""
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    if na == 0.0 or nb == 0.0:
        return 1.0
    return 1.0 - (dot / (na * nb))


def find_near_duplicates(
    candidates: list[dict], threshold: float = DEFAULT_DISTANCE
) -> list[dict]:
    """Identify near-duplicate drawers to remove.

    `candidates` is a list of dicts, each with keys: id, text, embedding
    (list[float]), source_file. Grouped PER source_file; within each
    group, processed LONGEST-first (by len(text)). The longest body is
    always kept as a canonical; each subsequent body within `threshold`
    cosine distance of an already-kept canonical is flagged as a
    near-duplicate of the NEAREST such canonical.

    Returns a list of dicts {id, canonical_id, source_file, distance},
    one per drawer to remove. Pure — no DB, no embedding model — so it is
    unit-testable with synthetic vectors.
    """
    groups: dict[object, list[dict]] = {}
    for cand in candidates:
        groups.setdefault(cand.get("source_file"), []).append(cand)

    to_remove: list[dict] = []
    for source_file, group in groups.items():
        # Longest-first; ties broken by id for a deterministic canonical.
        ordered = sorted(
            group, key=lambda c: (-len(c.get("text") or ""), c["id"])
        )
        kept: list[dict] = []
        for cand in ordered:
            nearest_id = None
            nearest_dist = None
            for canonical in kept:
                dist = cosine_distance(cand["embedding"], canonical["embedding"])
                if dist <= threshold and (
                    nearest_dist is None or dist < nearest_dist
                ):
                    nearest_dist = dist
                    nearest_id = canonical["id"]
            if nearest_id is not None:
                to_remove.append(
                    {
                        "id": cand["id"],
                        "canonical_id": nearest_id,
                        "source_file": source_file,
                        "distance": nearest_dist,
                    }
                )
            else:
                kept.append(cand)
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
    from mcp_server.embeddings import embed

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

    candidates = []
    for row in rows:
        text = row.get("text") or ""
        candidates.append(
            {
                "id": row["id"],
                "wing": row["wing"],
                "room": row["room"],
                "title": row["title"],
                "text": text,
                "source_file": row.get("source_file"),
                "embedding": embed(text),
            }
        )
    return candidates


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
        "--apply",
        action="store_true",
        help="ACTUALLY delete the near-duplicates (default: dry-run preview).",
    )
    args = parser.parse_args(argv)

    candidates = load_candidate_drawers(
        source_file=args.source_file, wing=args.wing, room=args.room
    )
    to_remove = find_near_duplicates(candidates, threshold=args.distance)

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(
        f"[dedup-sweep {mode}] {len(candidates)} candidate drawers, "
        f"threshold={args.distance}, {len(to_remove)} near-duplicate(s) found."
    )
    for item in to_remove:
        print(
            f"  - {item['id']}  (dup of {item['canonical_id']}, "
            f"distance={item['distance']:.4f}, source_file={item['source_file']!r})"
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
