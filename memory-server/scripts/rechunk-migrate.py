#!/usr/bin/env python3
"""memory-server/scripts/rechunk-migrate.py — re-chunk the historical
whole-drawer corpus through the S1 chunker (loom-rpsf.3, epic loom-rpsf
S1b, design D7).

WHY. The S1 chunker (mcp_server/chunking.py, loom-rpsf.2) gives NEW
drawers chunk-level recall: a body longer than CHUNK_SIZE (800 chars)
is stored as a parent row holding the full text PLUS one child row per
non-overlapping 800-char slice, so every part of a long body embeds in
full instead of vanishing past all-MiniLM-L6-v2's 256-token truncation
(the F12 problem). The ~12k HISTORICAL drawers never got that shape:
loom-40ec.6.3's reexport-full-content.py wrote each logical drawer back
to Dolt as ONE full-text row (a `"".join(parts)` un-chunking) to repair
a content-truncation bug, so today a long historical drawer still
embeds as one truncated whole-drawer vector. This script REVERSES that
collapse — it reads each current whole-drawer body straight from Dolt,
re-chunks it through the SAME S1 chunker, and re-loads the resulting
parent+child rows through the EXISTING migrate.py loader.

WHAT IT REUSES (does NOT reimplement).
  - mcp_server.chunking.plan_rows — the single source of truth for the
    parent/child storage shape, child ids (`{parent}_chunk_{i:06d}`),
    and the strict `len > CHUNK_SIZE` chunk boundary. This script only
    maps each RowSpec onto migrate.py's drawers-JSONL row shape.
  - scripts/migrate.py.migrate_drawers — the idempotent, checkpoint-
    resumable, non-truncating batch loader (INSERT ... ON DUPLICATE KEY
    UPDATE keyed on id). Re-loading a parent row upserts it to identical
    values; new child rows are inserted. Running the whole re-chunk
    twice yields an identical row set.

THE PARENT-ID INVARIANT. A parent row is re-emitted under its OWN
unchanged id (plan_rows keeps `row_id == drawer_id` for the parent), so
every KG `grounded_in` edge and MemPalace tunnel that references a
drawer by id stays valid. Only NEW child ids are introduced.

EMBEDDING NOTE (deliberate, documented). migrate.py embeds each row's
stored `text` column. For CHILD rows that is exactly right — each child
embeds its own 800-char slice, which is the whole recall win. For the
PARENT row it means the parent re-embeds its FULL body (as it already
did when reexport->migrate first loaded it), NOT the drawer title.
That diverges from the LIVE add_drawer path (tools/drawers.py), which
embeds the parent from `RowSpec.embed_source` (the title). The
divergence is intentional here: (a) reusing the batch migrate loader is
the bead's explicit contract, and migrate.py has no per-row embed-source
channel; (b) re-embedding the parent's full body is a NO-OP on the
parent's existing vector, so the re-chunk never disturbs recall that
already works — it only ADDS child-level recall. The parent's vector is
therefore unchanged by this migration; the children carry the new
chunk-level recall.

SOURCE = the current Dolt full-text bodies, NOT chroma. The re-read
selects only LOGICAL drawers (`parent_drawer_id IS NULL`); child rows
from a prior re-chunk run carry a non-NULL parent_drawer_id and are
skipped as sources (plan_rows regenerates them from their parent, so
idempotency holds without re-reading them).

PRODUCTION GATE. This script is BUILT + fixture-tested (see
tests/test_rechunk_migrate.py) but the real production run is an
ATTENDED checkpoint, bracketed by an S0 Recall@10 measurement before
and after. Preview first with --dry-run (writes the JSONL + reports
counts, writes NOTHING to Dolt), inspect the counts, then run for real.

Usage:
    # against the production instance (LOOM_MEMORY_PORT=3308) — ATTENDED
    .venv/bin/python scripts/rechunk-migrate.py --dry-run          # preview counts
    .venv/bin/python scripts/rechunk-migrate.py --out rechunked.jsonl
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable, Iterator

SCRIPT_DIR = Path(__file__).resolve().parent
MEMSERVER_ROOT = SCRIPT_DIR.parent
for _p in (str(MEMSERVER_ROOT), str(SCRIPT_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import migrate  # scripts/migrate.py — reuse its migrate_drawers loader  # noqa: E402
from mcp_server.chunking import CHUNK_SIZE, plan_rows  # noqa: E402
from mcp_server.db import connect  # noqa: E402

# Columns read from each logical (parent-less) source drawer. Carried
# forward onto every emitted parent+child row so the re-chunk preserves
# wing/room/provenance metadata rather than re-deriving it.
_SOURCE_COLUMNS = (
    "id",
    "wing",
    "room",
    "title",
    "text",
    "source_file",
    "filed_at",
    "added_by",
)


def _as_dt_string(value):
    """DictCursor returns a datetime for the DATETIME `filed_at` column;
    JSON can't serialize that. Format it to the space-separated string
    migrate.py's `_normalize_dt` accepts. None / already-string values
    pass through."""
    if value is None:
        return None
    if hasattr(value, "strftime"):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return str(value)


def iter_source_drawers(conn) -> Iterator[dict]:
    """Yield every LOGICAL drawer (parent_drawer_id IS NULL) from the
    live Dolt drawers table — the historical whole-drawer rows to
    re-chunk. Child rows from a prior re-chunk run (parent_drawer_id NOT
    NULL) are excluded: plan_rows regenerates them deterministically from
    their parent, so a re-run stays idempotent without re-reading them."""
    cur = conn.cursor()
    try:
        cur.execute(
            f"SELECT {', '.join(_SOURCE_COLUMNS)} FROM drawers "
            "WHERE parent_drawer_id IS NULL"
        )
        for row in cur.fetchall():
            yield row
    finally:
        cur.close()


def rechunk_source_row(source: dict, chunk_size: int = CHUNK_SIZE) -> list[dict]:
    """Map one logical source drawer to the parent+child drawers-JSONL
    rows that reproduce its chunked storage shape, via the S1 chunker's
    plan_rows. The parent row keeps the source's id + FULL text; each
    child carries a `{parent}_chunk_{i:06d}` id and its 800-char slice.
    Carried metadata (wing/room/title/source_file/filed_at/added_by) is
    copied onto every row (title is NOT NULL in the schema, so children
    inherit the parent's title)."""
    title = source.get("title") or ""
    filed_at = _as_dt_string(source.get("filed_at"))
    specs = plan_rows(source["id"], title, source["text"], chunk_size)
    rows: list[dict] = []
    for spec in specs:
        rows.append(
            {
                "id": spec.row_id,
                "wing": source["wing"],
                "room": source["room"],
                "title": title,
                "text": spec.text,
                "source_file": source.get("source_file"),
                "filed_at": filed_at,
                "chunk_index": spec.chunk_index,
                "parent_drawer_id": spec.parent_drawer_id,
                "added_by": source.get("added_by"),
            }
        )
    return rows


def build_rechunked_jsonl(
    conn, out_path: str | Path, chunk_size: int = CHUNK_SIZE
) -> tuple[int, int]:
    """Read every logical drawer from `conn`, re-chunk each through the
    S1 chunker, and write the resulting parent+child rows as a
    drawers-shaped JSONL to out_path (migrate.py's expected input shape).
    Returns (source_drawer_count, emitted_row_count)."""
    sources = 0
    emitted = 0
    with open(out_path, "w", encoding="utf-8") as f:
        for source in iter_source_drawers(conn):
            sources += 1
            for row in rechunk_source_row(source, chunk_size):
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
                emitted += 1
    return sources, emitted


def run(
    out_path: str | Path,
    batch_size: int = migrate.DEFAULT_BATCH_SIZE,
    checkpoint_file: str | Path | None = None,
    chunk_size: int = CHUNK_SIZE,
    load: bool = True,
) -> dict:
    """End-to-end re-chunk: read the live whole-drawer bodies from Dolt,
    emit the re-chunked parent+child JSONL to out_path, and (unless
    load=False, i.e. a dry-run) load it back through migrate_drawers'
    idempotent upsert. Returns {sources, emitted, loaded}."""
    conn = connect()
    try:
        sources, emitted = build_rechunked_jsonl(conn, out_path, chunk_size)
    finally:
        conn.close()

    loaded = 0
    if load:
        loaded = migrate.migrate_drawers(
            out_path, batch_size=batch_size, checkpoint_file=checkpoint_file
        )
    print(
        f"[rechunk-migrate] sources={sources} emitted={emitted} loaded={loaded}"
        f"{' (dry-run: NOT loaded)' if not load else ''}",
        file=sys.stderr,
    )
    return {"sources": sources, "emitted": emitted, "loaded": loaded}


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Re-chunk the live Dolt drawer corpus through the S1 chunker so "
            "historical whole-drawer rows gain chunk-level recall. ATTENDED "
            "for production — preview with --dry-run first."
        )
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("scripts/rechunked-corpus.jsonl"),
        help="path for the emitted re-chunked drawers JSONL",
    )
    parser.add_argument("--batch-size", type=int, default=migrate.DEFAULT_BATCH_SIZE)
    parser.add_argument("--checkpoint-file", type=Path, default=None)
    parser.add_argument("--chunk-size", type=int, default=CHUNK_SIZE)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="emit the JSONL + report counts, but write NOTHING to Dolt",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    run(
        args.out,
        batch_size=args.batch_size,
        checkpoint_file=args.checkpoint_file,
        chunk_size=args.chunk_size,
        load=not args.dry_run,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
