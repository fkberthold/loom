#!/usr/bin/env python3
"""memory-server/scripts/reexport-full-content.py — one-off repair for
loom-40ec.6.3's content-truncation finding.

ROOT CAUSE: the loom-40ec.6.2 real production migration's dispatch
brief instructed the worker to gather drawer content via
`mempalace_list_drawers`'s `content_preview` field ("cheap preview-text
is sufficient") — a shortcut copied from loom-40ec.7's BENCHMARK
sampling, where truncated preview text is fine because only retrieval
SCORING is being measured. For a REAL migration meant to preserve
verbatim memory content, this was wrong: every one of the ~12,029
migrated rows landed with only its first ~200 characters (the preview
truncation length), regardless of wing or whether the original drawer
was chunked.

FIX: read the OLD MemPalace's underlying chroma sqlite3 store
DIRECTLY (read-only) instead of going through the slow/truncating MCP
list_drawers path. This is empirically verified to reconstruct
byte-identical content to `mempalace_get_drawer`'s own reconstruction
(see loom-40ec.6.3's closing drawer for the verification record: a
naive ordered concatenation of a multi-chunk drawer's raw
`chroma:document` fields matched `mempalace_get_drawer`'s "content"
field exactly, so MemPalace's chunker uses non-overlapping splits).

Reads ONLY `embeddings` + `embedding_metadata` in the
`mempalace_drawers` collection's METADATA segment (id
92e6e9c8-4e09-4dcc-afe0-8cf3fc2a244e, verified against `collections`/
`segments` — the other segment, e7cede19..., is `mempalace_closets`
and out of scope). Opens the sqlite file with `mode=ro` in the
connection URI, which never takes a write lock — safe to run
concurrently with a live mempalace-mcp server process (this repo has
a documented history of MemPalace lock fragility; this script never
touches MemPalace's own fcntl advisory lock since it bypasses the
application layer entirely).

Grouping logic (replicates what `mempalace_list_drawers` itself
appears to do for the "one representative row per logical drawer"
decision, per the same investigation): an embedding_id matching
`<base>_chunk_<6-digit-index>` groups under `<base>`, ordered by the
`chunk_index` metadata; anything else (auto-mined content with no
shared-prefix chunk siblings) is its own standalone logical drawer
keyed by its own embedding_id.

Same wing-allowlist as loom-40ec.6.2 (see
docs/sessions-wing-migration-policy.md): exclude `sessions` entirely,
exclude the liza-family wings EXCEPT `liza_base`, include everything
else.

Usage:
    .venv/bin/python scripts/reexport-full-content.py [--out PATH] [--dry-run]

Writes a drawers-shaped JSONL (`{id, wing, room, text, source_file,
filed_at, added_by, chunk_index, parent_drawer_id}`) matching
migrate.py's expected input shape. Load it with:

    .venv/bin/python scripts/migrate.py drawers <out.jsonl>

against the production instance (LOOM_MEMORY_PORT=3308) — migrate.py's
`ON DUPLICATE KEY UPDATE` upsert overwrites the truncated rows in
place, keyed by the same `id`s already in production.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

CHROMA_SQLITE_PATH = "/home/frank/.mempalace/palace/chroma.sqlite3"
DRAWERS_METADATA_SEGMENT_ID = "92e6e9c8-4e09-4dcc-afe0-8cf3fc2a244e"

# Same allowlist loom-40ec.6.2's dispatch brief used.
EXCLUDE_WINGS = {
    "sessions",
    "liza",
    "liza_current",
    "liza_live",
    "liza-live",
    "wing_liza",
    "wing_liza_base",
    "wing_liza_base_session_assistant",
    "save_liza",
}

_CHUNK_SUFFIX_RE = re.compile(r"^(?P<base>.+)_chunk_(?P<idx>\d{6})$")


def _base_id_and_order(embedding_id: str, chunk_index) -> tuple[str, int]:
    """Returns (grouping_key, sort_order). Suffix-matching ids group
    under their shared base; everything else is its own standalone
    group (grouping_key == embedding_id) — see module docstring."""
    m = _CHUNK_SUFFIX_RE.match(embedding_id)
    if m:
        return m.group("base"), int(m.group("idx"))
    return embedding_id, int(chunk_index) if chunk_index is not None else 0


def _load_all_metadata(conn: sqlite3.Connection) -> dict[int, dict]:
    """One pass over embedding_metadata for the drawers segment's
    embedding internal ids, pivoted from EAV rows into a per-id dict.
    Cheaper than one query per embedding (791k rows total in this
    table across all segments)."""
    cur = conn.cursor()
    cur.execute(
        "SELECT e.id, e.embedding_id, m.key, m.string_value, m.int_value "
        "FROM embeddings e JOIN embedding_metadata m ON m.id = e.id "
        "WHERE e.segment_id = ?",
        (DRAWERS_METADATA_SEGMENT_ID,),
    )
    by_id: dict[int, dict] = {}
    for internal_id, embedding_id, key, str_val, int_val in cur.fetchall():
        row = by_id.setdefault(internal_id, {"embedding_id": embedding_id})
        row[key] = str_val if str_val is not None else int_val
    return by_id


def gather(conn: sqlite3.Connection) -> list[dict]:
    by_id = _load_all_metadata(conn)

    groups: dict[str, list[dict]] = {}
    for internal_id, meta in by_id.items():
        wing = meta.get("wing")
        if wing is None or wing in EXCLUDE_WINGS:
            continue
        embedding_id = meta["embedding_id"]
        chunk_index = meta.get("chunk_index")
        base_id, order = _base_id_and_order(embedding_id, chunk_index)
        groups.setdefault(base_id, []).append(
            {
                "order": order,
                "text": meta.get("chroma:document") or "",
                "wing": wing,
                "room": meta.get("room"),
                "filed_at": meta.get("filed_at"),
                "source_file": meta.get("source_file"),
                "added_by": meta.get("added_by"),
            }
        )

    rows = []
    for base_id, parts in groups.items():
        parts.sort(key=lambda p: p["order"])
        first = parts[0]
        rows.append(
            {
                "id": base_id,
                "wing": first["wing"],
                "room": first["room"],
                "text": "".join(p["text"] for p in parts),
                "filed_at": first["filed_at"],
                "source_file": first["source_file"],
                "added_by": first["added_by"],
                "chunk_index": 0,
                "parent_drawer_id": None,
            }
        )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="scripts/production-corpus-fixed.jsonl")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(f"file:{CHROMA_SQLITE_PATH}?mode=ro", uri=True)
    try:
        rows = gather(conn)
    finally:
        conn.close()

    by_wing: dict[str, int] = {}
    for r in rows:
        by_wing[r["wing"]] = by_wing.get(r["wing"], 0) + 1

    print(f"Reconstructed {len(rows)} logical drawers across {len(by_wing)} wings", file=sys.stderr)
    for wing, count in sorted(by_wing.items(), key=lambda kv: -kv[1])[:15]:
        print(f"  {wing}: {count}", file=sys.stderr)

    if args.dry_run:
        return 0

    out_path = Path(args.out)
    with open(out_path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"Wrote {len(rows)} rows to {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
