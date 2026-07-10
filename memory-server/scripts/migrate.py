#!/usr/bin/env python3
"""memory-server/scripts/migrate.py — MemPalace-to-Dolt migration pipeline
(loom-40ec.5).

Loads a JSONL export into the Dolt-backed `drawers` or `kg_triples`
tables (schema.sql, loom-40ec.3). This is a PIPELINE, built + validated
at real scale against the committed `scripts/at-scale-corpus.jsonl`
fixture (5,772 real MemPalace drawers, loom-40ec.7) — it is deliberately
NOT the thing that runs the actual full-production migration. Running
this against the real production Dolt server / the real full ~791k-row
MemPalace corpus is a separate, deliberate follow-up action (bundled
with the loom-40ec.6 cutover bead), not something this script does on
its own or that this bead executes.

Usage:
    scripts/migrate.py drawers <input.jsonl> [--batch-size N] \
        [--checkpoint-file PATH]
    scripts/migrate.py kg <input.jsonl> [--batch-size N] \
        [--checkpoint-file PATH]

Input shapes (one JSON object per line):
    drawers: {id, wing, room, text, [title], [source_file],
              [chunk_index], [parent_drawer_id], [added_by], [filed_at]}
    kg:      {id, subject, predicate, object, [confidence], [valid_from],
              [valid_to], [source_closet], [current], [created_at]}

Design decisions (documented per the bead's brief, each a real choice
made, not an unexamined default):

  Embedding — batch, not per-row. Uses mcp_server/embeddings.py's
    `embed_batch()` (added by this bead), the SAME all-MiniLM-L6-v2
    model/helper used throughout this project's benchmarking lineage
    (SPIKE-1/loom-zu91, loom-40ec.3, loom-40ec.7) for numeric
    consistency. One `.encode()` call per batch instead of one call
    per row is a measured ~1,100+ rows/sec on this machine for the
    embedding step alone (see docs/vector-index-scaling.md's sibling
    migration-throughput note in this bead's report).

  Loading path — raw batched INSERT, not tools/drawers.py's
    add_drawer()/tools/kg.py's kg_add(). add_drawer() embeds ONE row
    at a time and INSERTs ONE row at a time — correct for a live MCP
    tool call, wrong for a tens-of-thousands-of-rows migration where
    batch embedding + multi-row INSERT is the whole performance story.
    The column set and INSERT shape below are copy-consistent with
    those modules' single-row statements (same column list, same
    `string_to_vector(%s)` parameter-binding pattern used by
    scripts/benchmark-at-scale.py's `_flush_batch`) — this is
    deliberately a batched sibling of the same write path, not a
    divergent one.

  Idempotency — INSERT ... ON DUPLICATE KEY UPDATE keyed on `id`
    (both tables' primary key). Re-running the same input is a
    verified safe no-op: an existing id's row is overwritten with the
    SAME values, not duplicated. This is a real per-row upsert, not a
    pre-check-then-branch — cheaper (one round trip per batch either
    way) and correct under a concurrent partial-progress scenario
    (no TOCTOU window between a "does it exist" check and the write).

  Resumability — idempotency (above) already makes a naive full
    restart SAFE and CORRECT: re-running from line 0 after an
    interruption just re-upserts already-migrated rows to the same
    values. This script adds a LIGHTWEIGHT checkpoint file on top as a
    PERFORMANCE optimization, not a correctness requirement: after
    each successfully committed batch, `--checkpoint-file PATH` is
    updated with the count of input lines fully processed so far; a
    re-run with the same `--checkpoint-file` skips that many input
    lines before resuming, avoiding the CPU cost of re-embedding rows
    already safely landed. Skipping the checkpoint file entirely (the
    default) is a legitimate choice for a corpus small enough that
    full-restart-and-re-upsert is cheap enough not to bother.

  Batch size — one shared `--batch-size` (default 200) controls BOTH
    how many rows go into one `.encode()` call and how many rows go
    into one multi-row INSERT statement. A single knob keeps the CLI
    simple; 200 sits comfortably inside the range the bead's brief
    suggests (100-500) and matches scripts/benchmark-at-scale.py's own
    default flush size for its equivalent bulk-insert helper.

  Progress reporting — logged to STDERR (never stdout, which stays
    clean for any future machine-readable summary) at a fixed time
    interval (PROGRESS_LOG_INTERVAL_SEC) rather than a fixed row
    count, so progress is visible at a steady cadence regardless of
    per-row cost.

  Title derivation — a drawers row missing `title` gets one derived
    from the first non-blank line of `text`, truncated to the
    `title VARCHAR(512)` column's limit — matching the bead's brief
    exactly ("derive title from the first line of text if absent").

  Text/embedding fidelity — unlike scripts/benchmark-at-scale.py
    (which truncates stored text to 8000 chars and embedding input to
    1000 chars purely for benchmarking convenience/speed), this
    migration script does NOT truncate: `text` is LONGTEXT (no length
    limit) and the full text is passed to the embedder (any truncation
    to the model's own max sequence length happens internally inside
    sentence-transformers, not here). A migration script's job is
    faithful data transfer, not a latency benchmark.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Iterator

SCRIPT_DIR = Path(__file__).resolve().parent
MEMSERVER_ROOT = SCRIPT_DIR.parent
if str(MEMSERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(MEMSERVER_ROOT))

from mcp_server.db import connect  # noqa: E402
from mcp_server.embeddings import embed_batch, vector_literal  # noqa: E402

DEFAULT_BATCH_SIZE = 200
PROGRESS_LOG_INTERVAL_SEC = 2.0

TITLE_MAX_LEN = 512  # matches schema.sql's drawers.title VARCHAR(512)


# --------------------------------------------------------------------------
# Small shared helpers
# --------------------------------------------------------------------------


def _iter_jsonl(path: Path) -> Iterator[dict]:
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            yield json.loads(line)


def _count_jsonl_lines(path: Path) -> int:
    count = 0
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                count += 1
    return count


def _derive_title(text: str) -> str:
    """First non-blank line of `text`, truncated to TITLE_MAX_LEN.
    Falls back to a placeholder if `text` is empty/whitespace-only."""
    for line in (text or "").splitlines():
        stripped = line.strip()
        if stripped:
            return stripped[:TITLE_MAX_LEN]
    return "(untitled)"


def _normalize_dt(value):
    """Normalize an ISO-8601-with-'T' datetime string to the
    space-separated form Dolt/MySQL's DATETIME comparison/storage
    reliably accepts — mirrors mcp_server/tools/kg.py's
    `_normalize_as_of` helper. Non-string / already-space-separated
    values pass through unchanged; None passes through as None."""
    if isinstance(value, str) and "T" in value:
        return value.replace("T", " ", 1)
    return value


def _read_checkpoint(path: Path | None) -> int:
    if path is None or not path.exists():
        return 0
    try:
        data = json.loads(path.read_text())
    except (ValueError, json.JSONDecodeError):
        return 0
    return int(data.get("completed_rows", 0))


def _write_checkpoint(path: Path | None, completed_rows: int, input_path: Path, label: str) -> None:
    """Write atomically (write to a sibling .tmp file, then rename) so
    a crash mid-write never leaves a truncated/corrupt checkpoint file
    that a resume would misread."""
    if path is None:
        return
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(
        json.dumps(
            {
                "completed_rows": completed_rows,
                "input_path": str(input_path),
                "table": label,
            }
        )
    )
    tmp.replace(path)


class _ProgressReporter:
    """Logs row counts / rate / ETA to stderr at a fixed time interval
    (not a fixed row count), so progress stays visible at a steady
    cadence regardless of per-row cost."""

    def __init__(self, total: int, label: str):
        self.total = total
        self.label = label
        self.start = time.time()
        self._last_log = self.start
        self.done = 0

    def update(self, n: int, force: bool = False) -> None:
        self.done += n
        now = time.time()
        if force or now - self._last_log >= PROGRESS_LOG_INTERVAL_SEC or self.done >= self.total:
            elapsed = now - self.start
            rate = self.done / elapsed if elapsed > 0 else 0.0
            remaining = max(self.total - self.done, 0)
            eta = remaining / rate if rate > 0 else float("inf")
            pct = (100.0 * self.done / self.total) if self.total else 100.0
            print(
                f"[migrate:{self.label}] {self.done}/{self.total} rows "
                f"({pct:.1f}%) rate={rate:.1f} rows/s elapsed={elapsed:.1f}s "
                f"eta={eta:.1f}s",
                file=sys.stderr,
            )
            self._last_log = now


# --------------------------------------------------------------------------
# drawers
# --------------------------------------------------------------------------

_DRAWER_COLUMNS = (
    "id",
    "wing",
    "room",
    "title",
    "text",
    "embedding",
    "filed_at",
    "source_file",
    "chunk_index",
    "parent_drawer_id",
    "added_by",
)


def _flush_drawer_batch(cur, batch: list[dict], default_filed_at: str) -> None:
    texts = [(row.get("text") or "") for row in batch]
    embeddings = embed_batch(texts)

    values_sql = ",".join(
        "(%s,%s,%s,%s,%s,string_to_vector(%s),%s,%s,%s,%s,%s)" for _ in batch
    )
    args: list = []
    for row, vec in zip(batch, embeddings):
        if "id" not in row or "wing" not in row or "room" not in row:
            raise ValueError(f"drawers row missing required id/wing/room: {row!r}")
        text = row.get("text") or ""
        title = (row.get("title") or _derive_title(text))[:TITLE_MAX_LEN]
        filed_at = _normalize_dt(row.get("filed_at")) or default_filed_at
        args.extend(
            [
                row["id"],
                row["wing"],
                row["room"],
                title,
                text,
                vector_literal(vec),
                filed_at,
                row.get("source_file"),
                row.get("chunk_index"),
                row.get("parent_drawer_id"),
                row.get("added_by"),
            ]
        )

    update_clause = ", ".join(f"{col}=VALUES({col})" for col in _DRAWER_COLUMNS if col != "id")
    sql = (
        f"INSERT INTO drawers ({', '.join(_DRAWER_COLUMNS)}) VALUES {values_sql} "
        f"ON DUPLICATE KEY UPDATE {update_clause}"
    )
    cur.execute(sql, args)


def migrate_drawers(
    input_path: str | Path,
    batch_size: int = DEFAULT_BATCH_SIZE,
    checkpoint_file: str | Path | None = None,
) -> int:
    """Migrate a drawers-shaped JSONL file into the `drawers` table.
    Returns the total number of input rows accounted for (including
    any skipped-via-checkpoint rows from a prior run)."""
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    def flush(cur, batch):
        _flush_drawer_batch(cur, batch, now_str)

    return _run_migration(input_path, batch_size, checkpoint_file, "drawers", flush)


# --------------------------------------------------------------------------
# kg_triples
# --------------------------------------------------------------------------

_KG_COLUMNS = (
    "id",
    "subject",
    "predicate",
    "object",
    "confidence",
    "valid_from",
    "valid_to",
    "source_closet",
    "current",
    "created_at",
)


def _flush_kg_batch(cur, batch: list[dict], default_created_at: str) -> None:
    values_sql = ",".join("(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)" for _ in batch)
    args: list = []
    for row in batch:
        if "id" not in row or "subject" not in row or "predicate" not in row or "object" not in row:
            raise ValueError(f"kg_triples row missing required id/subject/predicate/object: {row!r}")
        confidence = row.get("confidence", 1.0)
        current = row.get("current", True)
        created_at = _normalize_dt(row.get("created_at")) or default_created_at
        args.extend(
            [
                row["id"],
                row["subject"],
                row["predicate"],
                row["object"],
                confidence,
                _normalize_dt(row.get("valid_from")),
                _normalize_dt(row.get("valid_to")),
                row.get("source_closet"),
                bool(current),
                created_at,
            ]
        )

    # `current` is a MySQL reserved word — backtick it, matching
    # mcp_server/tools/kg.py's convention.
    update_cols = [c for c in _KG_COLUMNS if c != "id"]
    update_clause = ", ".join(
        f"`{c}`=VALUES(`{c}`)" if c == "current" else f"{c}=VALUES({c})" for c in update_cols
    )
    quoted_columns = [f"`{c}`" if c == "current" else c for c in _KG_COLUMNS]
    sql = (
        f"INSERT INTO kg_triples ({', '.join(quoted_columns)}) VALUES {values_sql} "
        f"ON DUPLICATE KEY UPDATE {update_clause}"
    )
    cur.execute(sql, args)


def migrate_kg_triples(
    input_path: str | Path,
    batch_size: int = DEFAULT_BATCH_SIZE,
    checkpoint_file: str | Path | None = None,
) -> int:
    """Migrate a kg_triples-shaped JSONL file into the `kg_triples`
    table. Returns the total number of input rows accounted for
    (including any skipped-via-checkpoint rows from a prior run)."""
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    def flush(cur, batch):
        _flush_kg_batch(cur, batch, now_str)

    return _run_migration(input_path, batch_size, checkpoint_file, "kg", flush)


# --------------------------------------------------------------------------
# shared driver
# --------------------------------------------------------------------------


def _run_migration(
    input_path: str | Path,
    batch_size: int,
    checkpoint_file: str | Path | None,
    label: str,
    flush_fn: Callable[[object, list[dict]], None],
) -> int:
    input_path = Path(input_path)
    checkpoint_path = Path(checkpoint_file) if checkpoint_file else None

    skip = _read_checkpoint(checkpoint_path)
    total = _count_jsonl_lines(input_path)

    if skip and skip >= total:
        print(
            f"[migrate:{label}] checkpoint shows {skip}/{total} rows already "
            "done — nothing to do",
            file=sys.stderr,
        )
        return skip
    if skip:
        print(
            f"[migrate:{label}] resuming from checkpoint: skipping first {skip} "
            "already-processed rows",
            file=sys.stderr,
        )

    progress = _ProgressReporter(total, label)
    progress.done = skip

    processed = skip
    conn = connect()
    try:
        cur = conn.cursor()
        batch: list[dict] = []
        for i, row in enumerate(_iter_jsonl(input_path)):
            if i < skip:
                continue
            batch.append(row)
            if len(batch) >= batch_size:
                flush_fn(cur, batch)
                processed += len(batch)
                progress.update(len(batch))
                _write_checkpoint(checkpoint_path, processed, input_path, label)
                batch = []
        if batch:
            flush_fn(cur, batch)
            processed += len(batch)
            progress.update(len(batch))
            _write_checkpoint(checkpoint_path, processed, input_path, label)
        cur.close()
    finally:
        conn.close()

    progress.update(0, force=True)
    print(f"[migrate:{label}] complete: {processed}/{total} rows", file=sys.stderr)
    return processed


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Migrate a MemPalace-shaped JSONL export into loom's Dolt memory server."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_drawers = sub.add_parser("drawers", help="Migrate a drawers-shaped JSONL into the drawers table")
    p_drawers.add_argument("input", type=Path)
    p_drawers.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    p_drawers.add_argument("--checkpoint-file", type=Path, default=None)

    p_kg = sub.add_parser("kg", help="Migrate a kg_triples-shaped JSONL into the kg_triples table")
    p_kg.add_argument("input", type=Path)
    p_kg.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    p_kg.add_argument("--checkpoint-file", type=Path, default=None)

    args = parser.parse_args(list(argv) if argv is not None else None)

    if args.command == "drawers":
        migrate_drawers(args.input, batch_size=args.batch_size, checkpoint_file=args.checkpoint_file)
    elif args.command == "kg":
        migrate_kg_triples(args.input, batch_size=args.batch_size, checkpoint_file=args.checkpoint_file)
    else:  # pragma: no cover - argparse enforces valid subcommands
        parser.error(f"unknown command {args.command!r}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
