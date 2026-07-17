"""mcp_server/chunking.py — document chunking for long drawers
(loom-rpsf.2, epic loom-rpsf S1 — the single largest recall lever).

Problem this solves (F12). all-MiniLM-L6-v2 truncates its input at 256
tokens, so a long drawer used to embed as ONE 256-token-truncated
whole-drawer vector — everything past the truncation point was
invisible to semantic search. This module splits an oversized drawer's
body into bounded, non-overlapping character slices so each slice
embeds in full, and search can find a match anywhere in the body.

Storage shape (locked by the loom-rpsf.2 RED invariant):

  len(text) <= CHUNK_SIZE
    ONE row: parent_drawer_id NULL, chunk_index NULL,
    embedding = embed(full text). (Unchanged from the pre-chunking
    single-row behavior.)

  len(text) > CHUNK_SIZE
    ONE parent row: text = the FULL body (so get_drawer returns the
    whole thing), embedding = embed(title), parent_drawer_id NULL,
    chunk_index NULL;
    PLUS ceil(len / CHUNK_SIZE) CHILD rows: id =
    f"{parent}_chunk_{i:06d}", text = the i-th non-overlapping
    CHUNK_SIZE-char slice, embedding = embed(slice), chunk_index = i,
    parent_drawer_id = parent.

This differs from the MemPalace/chroma reference chunker
(mempalace mcp_server.py:2648) in one deliberate way: MemPalace stored
ONLY chunk rows (the logical drawer was a metadata group over them),
whereas here a real PARENT ROW holds the full body. That keeps
get_drawer(parent) a single-row read of the whole document and gives
the title its own searchable vector, while the non-overlapping
`content[i:i+chunk_size]` slicing is ported verbatim.

This module is deliberately PURE — no DB, no embedding-model imports.
It emits a structural plan (`plan_rows`) describing each row to write
and WHICH string that row's embedding should be derived from; the
caller (tools/drawers.py) maps the embedding model over the plan and
performs the INSERT/UPDATE. Search-side rollup uses `canonical_id`.
"""
from __future__ import annotations

from typing import NamedTuple

# Character-count chunk size. Chosen to keep each slice comfortably
# under all-MiniLM-L6-v2's 256-token truncation ceiling (English prose
# averages ~4 chars/token, so 800 chars ~= 200 tokens, leaving
# headroom). Ported from the MemPalace reference chunker's
# `_config.chunk_size` default of 800 (mcp_server.py:3259).
CHUNK_SIZE = 800


class RowSpec(NamedTuple):
    """One row to write for a drawer, plus the source string its
    embedding is derived from (so the caller — which owns the embedding
    model — can compute the vector without this module importing it).

    row_id            the drawer/chunk primary key
    text              the value stored in the `text` column
    embed_source      the string to embed for this row's vector
    chunk_index       INT for a child row, None for parent/standalone
    parent_drawer_id  the parent's id for a child row, None otherwise
    is_parent         True for the logical drawer row (standalone OR
                      the container parent); False for child chunks.
                      Lets the caller UPDATE the existing parent row vs
                      INSERT fresh children on the update path.
    """

    row_id: str
    text: str
    embed_source: str
    chunk_index: int | None
    parent_drawer_id: str | None
    is_parent: bool


def should_chunk(text: str, chunk_size: int = CHUNK_SIZE) -> bool:
    """A body is chunked iff it is STRICTLY longer than chunk_size.
    len == chunk_size stays a single standalone row (matches the
    `len(text) <= CHUNK_SIZE => one row` half of the RED invariant)."""
    return len(text) > chunk_size


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE) -> list[str]:
    """Split `text` into non-overlapping `chunk_size`-char slices.
    Ported verbatim from the MemPalace reference chunker
    (mcp_server.py:2648, `content[i:i+chunk_size]` over
    `range(0, len(content), chunk_size)`).

    A 2000-char body with chunk_size=800 yields three slices of
    800 / 800 / 400 chars. An empty string yields [] (the empty body
    never reaches here — it is <= chunk_size and stays a single row)."""
    return [text[i : i + chunk_size] for i in range(0, len(text), chunk_size)]


def chunk_id(parent_drawer_id: str, chunk_index: int) -> str:
    """Deterministic child-chunk id: `{parent}_chunk_{i:06d}`. The
    zero-padded 6-digit index matches the MemPalace reference id shape
    (mcp_server.py:2650) so a re-chunk of the live corpus (loom-rpsf.3)
    produces the same ids it would have there."""
    return f"{parent_drawer_id}_chunk_{chunk_index:06d}"


def canonical_id(parent_drawer_id: str | None, own_id: str) -> str:
    """Roll a search hit up to its logical drawer: a child row rolls up
    to its parent (`parent_drawer_id`), a parent/standalone row is its
    own canonical id. This is the `canonical_id = parent_drawer_id or
    id` rule the search rollup dedups on (loom-rpsf.2 RED invariant)."""
    return parent_drawer_id or own_id


def plan_rows(
    drawer_id: str,
    title: str,
    content: str,
    chunk_size: int = CHUNK_SIZE,
) -> list[RowSpec]:
    """Return the full set of rows to persist for one logical drawer,
    as a list of RowSpec (pure structure — no embeddings computed here).

    Short body (<= chunk_size): a single standalone RowSpec whose
    embedding derives from the full text.

    Long body (> chunk_size): a parent RowSpec (text = full body,
    embedding derived from the TITLE) followed by one child RowSpec per
    non-overlapping slice (embedding derived from that slice), in
    chunk-index order.
    """
    if not should_chunk(content, chunk_size):
        return [
            RowSpec(
                row_id=drawer_id,
                text=content,
                embed_source=content,
                chunk_index=None,
                parent_drawer_id=None,
                is_parent=True,
            )
        ]

    specs: list[RowSpec] = [
        RowSpec(
            row_id=drawer_id,
            text=content,
            embed_source=title,
            chunk_index=None,
            parent_drawer_id=None,
            is_parent=True,
        )
    ]
    for index, slice_text in enumerate(chunk_text(content, chunk_size)):
        specs.append(
            RowSpec(
                row_id=chunk_id(drawer_id, index),
                text=slice_text,
                embed_source=slice_text,
                chunk_index=index,
                parent_drawer_id=drawer_id,
                is_parent=False,
            )
        )
    return specs
