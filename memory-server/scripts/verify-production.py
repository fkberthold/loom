#!/usr/bin/env python3
"""memory-server/scripts/verify-production.py — pre-cutover smoke test
(loom-40ec.6.3).

Round-trips each mempalace_* tool against the REAL production Dolt
instance (loom-40ec.6.1, port 3308 by default) and reports pass/fail
per check. Read-only against `drawers`/`kg_triples` — the one write
path (mempalace_add_drawer) is deliberately NOT exercised here; the
CRUD/OCC paths are already covered by tests/test_mcp_drawers.py against
an ephemeral instance, and this script's job is confirming the
production data itself, not re-proving code paths the suite already
covers.

Usage:
  .venv/bin/python scripts/verify-production.py

Env vars (all optional, default to the production port per
deploy/loom-memory-server.service):
  LOOM_MEMORY_HOST  default: 127.0.0.1
  LOOM_MEMORY_PORT  default: 3308  (production; NOT the 3307 test default)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ.setdefault("LOOM_MEMORY_PORT", "3308")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp_server.tools import drawers, kg, search, status  # noqa: E402

PASS = "PASS"
FAIL = "FAIL"

results: list[tuple[str, str, str]] = []


def check(name: str, condition: bool, detail: str) -> None:
    results.append((name, PASS if condition else FAIL, detail))
    print(f"[{PASS if condition else FAIL}] {name} — {detail}")


def main() -> int:
    print(f"Verifying production server against "
          f"{os.environ.get('LOOM_MEMORY_HOST', '127.0.0.1')}:"
          f"{os.environ['LOOM_MEMORY_PORT']}\n")

    # 1. mempalace_status — real migrated row counts.
    st = status.status()
    check(
        "mempalace_status.dolt_reachable",
        st["dolt_reachable"] is True,
        f"dolt_reachable={st['dolt_reachable']}",
    )
    check(
        "mempalace_status.total_drawers > 0",
        st["total_drawers"] > 0,
        f"total_drawers={st['total_drawers']}",
    )
    print(f"  by_wing (top 10): "
          f"{dict(sorted(st['by_wing'].items(), key=lambda kv: -kv[1])[:10])}")

    # 2. mempalace_kg_stats — real migrated KG triples.
    kstats = status.kg_stats()
    check(
        "mempalace_kg_stats.triple_count > 0",
        kstats["triple_count"] > 0,
        f"triple_count={kstats['triple_count']}, entity_count={kstats['entity_count']}",
    )

    # 3. mempalace_list_drawers scoped to wing='loom'.
    loom_drawers = drawers.list_drawers(wing="loom", limit=5)
    check(
        "mempalace_list_drawers(wing=loom) returns rows",
        len(loom_drawers) > 0,
        f"got {len(loom_drawers)} rows, total={loom_drawers[0]['total'] if loom_drawers else 'n/a'}",
    )

    # 4. mempalace_get_drawer on a real id pulled from the list above.
    if loom_drawers:
        sample_id = loom_drawers[0]["id"]
        got = drawers.get_drawer(sample_id)
        check(
            "mempalace_get_drawer round-trips id/title from list_drawers",
            got["id"] == sample_id and got["title"] == loom_drawers[0]["title"],
            f"id={sample_id}, title={got['title']!r}",
        )
    else:
        check("mempalace_get_drawer round-trips id/title from list_drawers", False, "no loom drawers to sample")

    # 5. mempalace_search with a real query phrase.
    hits = search.search("MemPalace cutover Dolt", wing="loom", limit=5)
    check(
        "mempalace_search(wing=loom) returns sensible results",
        len(hits) > 0,
        f"got {len(hits)} hits, top={hits[0]['title']!r} dist={hits[0]['distance']:.4f}" if hits else "0 hits",
    )

    # 6. mempalace_kg_query against a real migrated entity. `loom_repo` is
    # used (not e.g. `loom-40ec`) because the KG migration is a
    # best-effort BFS entity crawl with documented ~65% coverage
    # (loom-40ec.6.2) -- individual bead-id entities like `loom-40ec`
    # are known-accepted gaps, not a fair signal for this smoke test.
    # `loom_repo` was hand-verified byte-identical against the old
    # MemPalace during loom-40ec.6.3's closing verification.
    facts = kg.kg_query("loom_repo", direction="both")
    check(
        "mempalace_kg_query('loom_repo') returns facts",
        len(facts) > 0,
        f"got {len(facts)} facts",
    )

    print()
    n_fail = sum(1 for _, verdict, _ in results if verdict == FAIL)
    print(f"{len(results) - n_fail}/{len(results)} checks passed")
    return 1 if n_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
