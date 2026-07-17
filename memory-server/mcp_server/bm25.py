"""mcp_server/bm25.py — full-corpus Okapi-BM25 keyword-retrieval lane
(loom-rpsf.4, epic loom-rpsf S2).

Problem this solves (D5, FORK-A). The vector lane (tools/search.py's
VEC_DISTANCE scan) ranks by SEMANTIC similarity, so an exact token that
carries little semantic weight — a bead-id (`loom-40ec.7`), an error
string, a dotted/underscored identifier — can rank LOW even when it
appears verbatim in a drawer. MemPalace's answer was rerank-over-
overfetch (re-score the vector over-fetch by keyword); this DIVERGES
from that: a bead-id sitting in a semantically-unrelated drawer is NOT
in the vector over-fetch at all, so re-scoring it can never surface it.
Instead this module runs an INDEPENDENT full-corpus BM25 lane; the
caller (tools/search.py) fuses the two lanes by Reciprocal Rank Fusion.

Corpus of SEARCHABLE UNITS (matches the S1 chunking storage shape in
chunking.py):

  - a short (<= CHUNK_SIZE) drawer stores as ONE standalone row — that
    row is one unit;
  - a long drawer stores as a PARENT row holding the full body plus N
    CHILD chunk rows — each CHILD chunk is one unit, and the parent
    full-body row is EXCLUDED (it would double-count the body and, being
    long, would be unfairly penalized by BM25's length normalization).

Every unit rolls up to its logical drawer via
chunking.canonical_id(parent_drawer_id, id) — the SAME rollup the vector
lane uses (loom-rpsf.2) — so a BM25 hit on any chunk surfaces its parent
drawer, never a raw `_chunk_` fragment id.

Tokenizer (D5): lowercase + split on whitespace/punctuation, but
dotted/hyphenated/underscored identifiers (`loom-40ec.7`, `foo_bar`,
`a.b.c`) are preserved as ATOMIC tokens AND expanded into their
separator-split sub-parts and progressive prefixes — so `loom-40ec.7`
emits `loom-40ec.7` (atomic, the loom-rpsf.4 invariant), `loom-40ec`
(prefix), and `loom`/`40ec`/`7` (parts). Emitting the prefix lets a
query for a parent id (`loom-40ec`) also match a child id
(`loom-40ec.7`).

Cache (D5: "built at startup + refreshed on write"). The index is built
lazily and cached at module scope, keyed on the target dolt server
(host/port/db) so a switch to a different server never returns a stale
index. The drawers write path (tools/drawers.py add/update/delete) calls
invalidate() after a successful mutation, so the next search rebuilds
against the current corpus.
"""
from __future__ import annotations

import re
from datetime import datetime
from typing import NamedTuple

from rank_bm25 import BM25Okapi

from mcp_server.chunking import canonical_id
from mcp_server.db import connect, connection_config

# Okapi-BM25 parameters (D5): the standard k1=1.5, b=0.75 defaults.
BM25_K1 = 1.5
BM25_B = 0.75

# An identifier is an alphanumeric run joined to at least one more run by
# `.`, `_`, or `-` (e.g. loom-40ec.7, foo_bar, a.b.c). The alternation
# lists the identifier form FIRST so `re` prefers the longest match and a
# dotted/hyphenated id is captured whole rather than split at its
# separators. A bare alphanumeric run is the plain-word fallback.
_IDENTIFIER = r"[a-z0-9]+(?:[._-][a-z0-9]+)+"
_TOKEN_RE = re.compile(_IDENTIFIER + r"|[a-z0-9]+")
_SEP_RE = re.compile(r"[._-]")


def _expand_identifier(ident: str) -> list[str]:
    """Expand one (already-lowercased) identifier into the tokens it
    contributes: the ATOMIC identifier, its separator-split sub-parts,
    and its progressive prefixes. `loom-40ec.7` ->
    [loom-40ec.7, loom, 40ec, 7, loom-40ec].

    Emitting BOTH the atomic token AND `loom-40ec` (a prefix) is what
    satisfies the loom-rpsf.4 invariant that `loom-40ec.7` is an atomic
    token DISTINCT from `loom-40ec`; the prefix also lets a query for a
    parent id match a child id. De-duplicated within the one
    identifier's expansion so a repeated component (e.g. `loom` as both a
    part and the first prefix) counts once for this occurrence.
    """
    out: list[str] = [ident]  # atomic
    out.extend(_SEP_RE.split(ident))  # separator-split sub-parts
    for match in _SEP_RE.finditer(ident):  # progressive prefixes
        out.append(ident[: match.start()])
    return list(dict.fromkeys(out))


def tokenize(text: str) -> list[str]:
    """Identifier-preserving tokenizer (D5). Lowercase; split on
    whitespace/punctuation; dotted/hyphenated/underscored identifiers are
    preserved as ATOMIC tokens and additionally expanded into their
    sub-parts and prefixes (see _expand_identifier). Plain alphanumeric
    words pass through as single tokens.
    """
    tokens: list[str] = []
    for match in _TOKEN_RE.finditer(text.lower()):
        tok = match.group(0)
        if _SEP_RE.search(tok):
            tokens.extend(_expand_identifier(tok))
        else:
            tokens.append(tok)
    return tokens


class DrawerMeta(NamedTuple):
    """Per-logical-drawer metadata carried on the index for scope
    filtering (wing/room), recency tie-break (filed_at), and a fallback
    display source. Keyed by canonical (logical-drawer) id."""

    wing: str
    room: str
    title: str
    text: str
    filed_at: datetime | None


class Bm25Index:
    """A full-corpus BM25 index over searchable units, plus the
    per-logical-drawer metadata needed to scope and roll up results."""

    def __init__(
        self,
        unit_canonicals: list[str],
        unit_docs: list[list[str]],
        meta: dict[str, DrawerMeta],
    ) -> None:
        self._unit_canonicals = unit_canonicals
        self._meta = meta
        # BM25Okapi requires a non-empty corpus (it divides by the average
        # document length); an empty corpus yields a None engine whose
        # ranked_canonicals() returns [].
        self._bm25 = (
            BM25Okapi(unit_docs, k1=BM25_K1, b=BM25_B) if unit_docs else None
        )

    @property
    def meta(self) -> dict[str, DrawerMeta]:
        return self._meta

    def ranked_canonicals(self, query: str) -> list[tuple[str, float]]:
        """Rank logical drawers by BM25 over the full corpus. Scores every
        unit for `query`, rolls each unit up to its canonical drawer id
        (best-scoring unit wins per drawer), drops zero/negative-score
        units, and returns [(canonical_id, score), ...] in descending
        score order. The rollup mirrors the vector lane's S1 dedup so a
        chunk hit surfaces its parent, never a `_chunk_` id.
        """
        if self._bm25 is None:
            return []
        query_tokens = tokenize(query)
        if not query_tokens:
            return []
        scores = self._bm25.get_scores(query_tokens)
        order = sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)

        ranked: list[tuple[str, float]] = []
        seen: set[str] = set()
        for i in order:
            score = float(scores[i])
            # `order` is score-descending, so the first non-positive score
            # means every remaining unit is also non-positive — stop.
            if score <= 0.0:
                break
            cid = self._unit_canonicals[i]
            if cid in seen:
                continue
            seen.add(cid)
            ranked.append((cid, score))
        return ranked


# One full-table read builds the whole corpus. `text` is a LONGTEXT body;
# this is the same table the vector lane scans, read once per (re)build
# rather than per search.
_BUILD_SQL = (
    "SELECT id, wing, room, title, text, parent_drawer_id, filed_at FROM drawers"
)


def build_index() -> Bm25Index:
    """Read the whole `drawers` table and build a fresh Bm25Index. A
    chunked drawer's PARENT full-body row is skipped (its children are the
    units); standalone rows and child chunk rows are the searchable units.
    Each unit's document is `title + text` so title terms are also
    keyword-searchable.
    """
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(_BUILD_SQL)
            rows = cur.fetchall()
    finally:
        conn.close()

    # Parent ids that actually HAVE children — their full-body parent row
    # is redundant with the children and is excluded from the unit corpus.
    parents_with_children = {
        row["parent_drawer_id"]
        for row in rows
        if row["parent_drawer_id"] is not None
    }

    unit_canonicals: list[str] = []
    unit_docs: list[list[str]] = []
    meta: dict[str, DrawerMeta] = {}
    for row in rows:
        parent_id = row["parent_drawer_id"]
        own_id = row["id"]
        title = row["title"] or ""
        text = row["text"] or ""

        # A logical drawer (standalone row OR chunked parent) — its
        # parent_drawer_id is NULL. Record display/scope/recency metadata
        # keyed by its canonical id.
        if parent_id is None:
            meta[own_id] = DrawerMeta(
                wing=row["wing"],
                room=row["room"],
                title=title,
                text=text,
                filed_at=row["filed_at"],
            )

        # Skip the redundant full-body row of a chunked drawer.
        if parent_id is None and own_id in parents_with_children:
            continue

        # Searchable unit: a child chunk (parent_id not NULL) or a
        # standalone short drawer (parent_id NULL, no children).
        unit_canonicals.append(canonical_id(parent_id, own_id))
        unit_docs.append(tokenize(title + "\n" + text))

    return Bm25Index(unit_canonicals, unit_docs, meta)


# --- Process-level cache (D5: built once, refreshed on write) ---------------
# Keyed on the target dolt server so pointing db.py at a different server
# (tests do this via LOOM_MEMORY_* env vars) never returns a stale index.
_INDEX: Bm25Index | None = None
_INDEX_KEY: tuple | None = None


def _current_key() -> tuple:
    cfg = connection_config()
    return (cfg["host"], cfg["port"], cfg["database"])


def get_index() -> Bm25Index:
    """Return the cached full-corpus index, rebuilding it if it was
    invalidated by a write or if the target server changed since it was
    built."""
    global _INDEX, _INDEX_KEY
    key = _current_key()
    if _INDEX is None or _INDEX_KEY != key:
        _INDEX = build_index()
        _INDEX_KEY = key
    return _INDEX


def invalidate() -> None:
    """Drop the cached index so the next get_index() rebuilds — the
    'refreshed on write' half of D5. Called by the drawers write path
    (add/update/delete) after a successful mutation."""
    global _INDEX, _INDEX_KEY
    _INDEX = None
    _INDEX_KEY = None
