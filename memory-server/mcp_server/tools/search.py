"""mcp_server/tools/search.py — semantic search tool (loom-40ec.4.2)
plus corpus-wide near-duplicate detection (loom-4cb6).

  mempalace_search(query, wing=None, room=None, limit=10) -> list[dict]
  mempalace_check_duplicate(content, threshold=0.9) -> dict

The highest-value read path: embeds `query` (same all-MiniLM-L6-v2
model as add_drawer/update_drawer, via mcp_server/embeddings.py) and
runs a `VEC_DISTANCE` nearest-neighbor query against `drawers`,
optionally scoped by `wing`/`room`. Mirrors tools/drawers.py's style:
a plain, directly-callable, independently-testable function, plus a
`register_search_tools(mcp)` registration function following the same
`mcp.tool(name=...)` pattern as register_drawer_tools.

Conditional-WHERE-building mirrors list_drawers() in tools/drawers.py
exactly (wing then room, each optional, AND-joined) — this is also
what lets the query use the `(wing, room)` B-tree index from
schema.sql to narrow the candidate set before the VEC_DISTANCE/TopN
sort runs (see that index's inline comment). An unscoped call (no
wing/room) falls back to the documented full-table-scan behavior —
see docs/vector-index-scaling.md: ADEQUATE at real scale under a
sub-second latency bar, not something this bead attempts to fix.

`snippet` is the returned CONTEXT for a hit. For a chunked drawer it is
the neighbour-chunk STITCH (loom-rpsf.5): the best-matching chunk plus
its +/-1 neighbours, joined and capped (see `_stitch_window`). For a
standalone (unchunked) drawer it stays a simple first-~300-chars
truncation of `text` (see `_snippet()` for why that nice-to-have of
centering on the best-matching span was skipped there).

`check_duplicate` (loom-4cb6) is registered as `mempalace_check_duplicate`,
matching every other tool in this server under the `mempalace_*` prefix
(loom-40ec.6.4 cutover). It reuses `search()`'s embed + VEC_DISTANCE
query shape but is deliberately UNSCOPED (no wing/room filter) since
dedup checks the whole corpus, not a sub-tree of it.

Distance-to-similarity conversion for the threshold check: `VEC_DISTANCE`
here resolves to Dolt's `VEC_DISTANCE_L2_SQUARED` (confirmed via
`EXPLAIN FORMAT=TREE` in docs/vector-index-scaling.md's query-plan
dump), and `embeddings.py`'s all-MiniLM-L6-v2 model emits L2-unit-
normalized vectors (empirically verified: `norm(embed(x)) ~= 1.0` for
arbitrary x — this model ships a built-in Normalize pooling layer).
For unit vectors a and b, `||a-b||^2 = ||a||^2 + ||b||^2 - 2*a.b
= 2 - 2*cos_sim(a, b)`, so `cos_sim = 1 - (L2_squared / 2)`. This is
the standard identity, not a fit to any specific test input — it holds
for any pair of unit vectors in this embedding space, which is why the
threshold test (loose 0.5 vs strict 0.999 against the SAME near-
duplicate pair) calibrates correctly without special-casing.
"""
from __future__ import annotations

from typing import Any

from mcp_server import bm25
from mcp_server.chunking import canonical_id
from mcp_server.db import connect
from mcp_server.embeddings import embed, vector_literal

SNIPPET_LENGTH = 300

# Reciprocal Rank Fusion constant (loom-rpsf.4, D5). RRF fuses the two
# lanes as score(d) = Σ_lane 1/(RRF_K + rank_lane(d)), rank 1-based. The
# k=60 default is the value from Cormack et al.'s original RRF paper; a
# larger k flattens the contribution of top ranks, a smaller k sharpens
# it. 60 is the well-established default and is what D5 specifies.
RRF_K = 60

# Over-fetch multiplier for the chunk-rollup pass (loom-rpsf.2). A long
# drawer is stored as a parent + N child chunk rows, so a raw
# nearest-neighbor scan can return several rows that all roll up to the
# SAME logical drawer. To still hand back `limit` DISTINCT drawers after
# dedup, fetch `limit * _ROLLUP_OVERFETCH` candidate rows before rolling
# them up. 10x is generous at any realistic chunk fan-out (a drawer
# would need >10x `limit` chunks ranked above the true limit-th drawer
# to under-fill) while staying a bounded TopN at the DB.
_ROLLUP_OVERFETCH = 10

# Neighbour-chunk stitch ceiling (loom-rpsf.5, design D4-stitch). The stitched
# +/-1 neighbour window is hard-capped at this many characters. Ported from
# MemPalace searcher.py:1281-1289 (`MAX_HYDRATION_CHARS = 10000`). At
# CHUNK_SIZE=800 a 3-chunk window is at most ~2404 chars, so this is a safety
# ceiling that never fires under the current chunk size — it exists so the cap
# holds no matter how CHUNK_SIZE (chunking.py) is later tuned.
MAX_HYDRATION_CHARS = 10000


def _stitch_window(chunk_texts: dict[int, str], best_idx: int) -> str:
    """Neighbour-chunk stitch (loom-rpsf.5, design D4-stitch). Join the
    best-matching chunk with its immediate neighbours — chunk_index in
    [best-1, best, best+1] — in ascending index order, separated by a blank
    line (`"\\n\\n"`), hard-capped at MAX_HYDRATION_CHARS.

    `chunk_texts` maps a canonical drawer's child chunk_index -> that chunk's
    text; `best_idx` is the chunk_index of the best-matching chunk (min vector
    distance). Out-of-range neighbours (best-1 < 0 at the first chunk, best+1
    past the last) are simply dropped — the window clamps rather than
    fabricating a neighbour. Ported from MemPalace searcher.py:1281-1289
    (N=+/-1 window, 10k cap).
    """
    window = [
        chunk_texts[i]
        for i in (best_idx - 1, best_idx, best_idx + 1)
        if i in chunk_texts
    ]
    return "\n\n".join(window)[:MAX_HYDRATION_CHARS]


def _snippet(text: str) -> str:
    """A simple truncation of `text` to the first SNIPPET_LENGTH
    characters, per the bead brief's explicit "simple truncation is
    fine" allowance. NOT an excerpt centered on the best-matching
    span — that "nice-to-have" was skipped here: doing it well
    requires either (a) a second text-similarity pass per row (token
    overlap / substring search against the query) beyond the vector
    distance already computed, or (b) surfacing span offsets from the
    embedding model, neither of which this bead's scope asked for.
    Plain truncation is honest or "relevance-anchored" in the loose
    sense that the FULL `text` column always at least contains the
    real match (VEC_DISTANCE already selected it) even when the
    displayed excerpt doesn't start exactly at the matching phrase.
    """
    return text[:SNIPPET_LENGTH]


def _vector_ranked(
    vec_literal: str,
    wing: str | None,
    room: str | None,
    tag_filter: list[str] | None,
    limit: int,
) -> list[str]:
    """Vector lane: the existing VEC_DISTANCE nearest-neighbor scan,
    scoped by wing/room/tag_filter exactly as before, rolled up to
    canonical (logical-drawer) ids. Returns the canonical ids in
    ascending-distance order, deduped (S1 rollup, loom-rpsf.2) — a chunk
    hit surfaces its parent, best distance first. This is the vector lane
    of the hybrid fusion; distances for display are recomputed
    authoritatively in _build_results.
    """
    conditions: list[str] = []
    params: list[Any] = []
    if wing is not None:
        conditions.append("wing = %s")
        params.append(wing)
    if room is not None:
        conditions.append("room = %s")
        params.append(room)
    if tag_filter:
        placeholders = ", ".join(["%s"] * len(tag_filter))
        conditions.append(
            "id IN (SELECT drawer_id FROM drawer_tags "
            f"WHERE tag IN ({placeholders}) "
            "GROUP BY drawer_id HAVING COUNT(DISTINCT tag) = %s)"
        )
        params.extend(tag_filter)
        params.append(len(tag_filter))
    where_clause = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    # Over-fetch so the chunk rollup can still yield `limit` distinct
    # logical drawers (see _ROLLUP_OVERFETCH).
    fetch_limit = max(int(limit), 1) * _ROLLUP_OVERFETCH

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, parent_drawer_id, "
                f"VEC_DISTANCE(embedding, string_to_vector('{vec_literal}')) AS dist "
                f"FROM drawers {where_clause} "
                "ORDER BY dist ASC LIMIT %s",
                [*params, int(fetch_limit)],
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    ranked: list[str] = []
    seen: set[str] = set()
    for row in rows:
        cid = canonical_id(row.get("parent_drawer_id"), row["id"])
        if cid in seen:
            continue
        seen.add(cid)
        ranked.append(cid)
    return ranked


def _canonicals_with_tags(tag_filter: list[str]) -> set[str]:
    """The set of logical-drawer ids carrying ALL of `tag_filter` — the
    BM25-lane equivalent of the vector lane's `tag_filter` subquery, used
    to scope BM25 hits by tag (AND semantics)."""
    placeholders = ", ".join(["%s"] * len(tag_filter))
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT drawer_id FROM drawer_tags "
                f"WHERE tag IN ({placeholders}) "
                "GROUP BY drawer_id HAVING COUNT(DISTINCT tag) = %s",
                [*tag_filter, len(tag_filter)],
            )
            return {row["drawer_id"] for row in cur.fetchall()}
    finally:
        conn.close()


def _bm25_ranked(
    index: bm25.Bm25Index,
    query: str,
    wing: str | None,
    room: str | None,
    tag_filter: list[str] | None,
) -> list[str]:
    """BM25 lane: the full-corpus keyword ranking (loom-rpsf.4), scoped to
    the SAME wing/room/tag_filter as the vector lane so the two lanes fuse
    over a comparable candidate space. The index is full-corpus (D5), so
    scoping is applied here, after ranking, via the per-drawer metadata.
    Returns canonical ids in descending BM25-score order.
    """
    allowed_by_tag = _canonicals_with_tags(tag_filter) if tag_filter else None
    ranked: list[str] = []
    for cid, _score in index.ranked_canonicals(query):
        meta = index.meta.get(cid)
        if meta is None:
            continue
        if wing is not None and meta.wing != wing:
            continue
        if room is not None and meta.room != room:
            continue
        if allowed_by_tag is not None and cid not in allowed_by_tag:
            continue
        ranked.append(cid)
    return ranked


def _recency_sort_key(meta: bm25.DrawerMeta | None) -> float:
    """Sort key placing NEWER drawers first under Python's ascending sort:
    the negated POSIX timestamp (newer => more negative => sorts earlier).
    A missing/NULL filed_at sorts last (float('inf'))."""
    if meta is None or meta.filed_at is None:
        return float("inf")
    return -meta.filed_at.timestamp()


def _build_results(vec_literal: str, canonicals: list[str]) -> list[dict]:
    """Build the {id, wing, room, title, snippet, distance} result dicts
    for the fused top-`limit` canonical drawer ids, in the given order.

    Display fields and the `distance` are read authoritatively from the
    live DB (not the cached BM25 metadata) in one query: for each drawer
    the logical-drawer row (id == canonical) supplies wing/room/title/
    text, and the MINIMUM VEC_DISTANCE across all of that drawer's rows
    (its best chunk or its title/body) supplies `distance` — so a
    BM25-surfaced drawer that never appeared in the vector over-fetch
    still gets a real distance.

    `snippet` carries the neighbour-chunk STITCH (loom-rpsf.5, design
    D4-stitch): for a CHUNKED drawer, it is the best-matching chunk plus its
    +/-1 neighbours (chunk_index IN [best-1, best, best+1]) joined with a
    blank line and capped at MAX_HYDRATION_CHARS — a richer, less-fragmentary
    context than any single chunk. The stitch is ADDITIVE over the S1 rollup
    + S2 RRF fusion: `canonicals` is already the rolled-up, fused order; this
    only enriches each result's returned context. "Best-matching chunk" is the
    child chunk with the minimum VEC_DISTANCE (the chunk the vector lane landed
    on), read from the same per-row distances this query already computes. A
    STANDALONE (unchunked) drawer has no child chunks, so its snippet stays the
    plain truncation of its body (nothing to stitch).
    """
    if not canonicals:
        return []
    placeholders = ", ".join(["%s"] * len(canonicals))
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title, text, chunk_index, parent_drawer_id, "
                f"VEC_DISTANCE(embedding, string_to_vector('{vec_literal}')) AS dist "
                f"FROM drawers WHERE id IN ({placeholders}) "
                f"OR parent_drawer_id IN ({placeholders})",
                [*canonicals, *canonicals],
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    display: dict[str, dict] = {}
    best_dist: dict[str, float] = {}
    # Per canonical, the child chunk_index -> text map + the best-matching
    # child chunk_index (min VEC_DISTANCE) — the inputs to _stitch_window.
    chunk_texts: dict[str, dict[int, str]] = {}
    best_chunk: dict[str, tuple[float, int]] = {}
    for row in rows:
        cid = canonical_id(row.get("parent_drawer_id"), row["id"])
        dist = float(row["dist"])
        if cid not in best_dist or dist < best_dist[cid]:
            best_dist[cid] = dist
        if row["id"] == cid:  # the logical-drawer row supplies display fields
            display[cid] = row
        chunk_index = row.get("chunk_index")
        if chunk_index is not None:  # a child chunk row of a chunked drawer
            ci = int(chunk_index)
            chunk_texts.setdefault(cid, {})[ci] = row.get("text") or ""
            if cid not in best_chunk or dist < best_chunk[cid][0]:
                best_chunk[cid] = (dist, ci)

    results: list[dict] = []
    for cid in canonicals:
        row = display.get(cid)
        if row is None:  # drawer vanished between fusion and this fetch (rare)
            continue
        children = chunk_texts.get(cid)
        if children:  # chunked drawer -> stitch the +/-1 neighbour window
            snippet = _stitch_window(children, best_chunk[cid][1])
        else:  # standalone drawer -> plain body truncation (nothing to stitch)
            snippet = _snippet(row.get("text") or "")
        results.append(
            {
                # The canonical (logical-drawer) id, never a raw `_chunk_`
                # fragment id — a child hit surfaces its parent so callers
                # get a stable, get_drawer-able id.
                "id": cid,
                "wing": row["wing"],
                "room": row["room"],
                "title": row["title"],
                "snippet": snippet,
                # Explicit float() cast for the same JSON-serialization
                # reason as the pre-hybrid code: VEC_DISTANCE may come back
                # as Decimal depending on the driver's numeric-type mapping.
                "distance": float(best_dist.get(cid, 0.0)),
            }
        )
    return results


def search(
    query: str,
    wing: str | None = None,
    room: str | None = None,
    tag_filter: list[str] | None = None,
    limit: int = 10,
) -> list[dict]:
    """Hybrid search over `drawers` (loom-rpsf.4): fuses a semantic
    (vector) lane and a keyword (BM25) lane by Reciprocal Rank Fusion, so
    an exact token a drawer contains verbatim — a bead-id, error string,
    identifier — surfaces even when that drawer is semantically about
    something else and the vector lane ranks it low.

    Both lanes are scoped by `wing`/`room`/`tag_filter` (all optional;
    wing+room AND-joined; tag_filter requires ALL listed tags), rolled up
    to canonical (logical-drawer) ids (S1 rollup, loom-rpsf.2 — a chunk
    hit surfaces its parent, deduped), and fused as
    score(d) = Σ_lane 1/(RRF_K + rank_lane(d)) (rank 1-based). Ties break
    on recency (filed_at, newest first) then id. Returns up to `limit`
    {id, wing, room, title, snippet, distance} dicts in descending fused
    score. `distance` is the drawer's best vector distance (see
    _build_results); with the BM25 lane added, results are no longer
    ordered by ascending distance.
    """
    limit = max(int(limit), 1)
    vec_literal = vector_literal(embed(query))

    vector_lane = _vector_ranked(vec_literal, wing, room, tag_filter, limit)
    index = bm25.get_index()
    bm25_lane = _bm25_ranked(index, query, wing, room, tag_filter)

    # Reciprocal Rank Fusion: each lane contributes 1/(RRF_K + rank) for
    # every canonical drawer it ranks (rank 1-based). A drawer that ranks
    # in BOTH lanes accumulates both contributions.
    fused: dict[str, float] = {}
    for rank, cid in enumerate(vector_lane, start=1):
        fused[cid] = fused.get(cid, 0.0) + 1.0 / (RRF_K + rank)
    for rank, cid in enumerate(bm25_lane, start=1):
        fused[cid] = fused.get(cid, 0.0) + 1.0 / (RRF_K + rank)
    if not fused:
        return []

    meta = index.meta
    ordered = sorted(
        fused,
        key=lambda cid: (-fused[cid], _recency_sort_key(meta.get(cid)), cid),
    )
    return _build_results(vec_literal, ordered[:limit])



# Candidate pool size for check_duplicate's underlying VEC_DISTANCE
# query: pulled BEFORE the threshold filter is applied, since (unlike
# search()'s top-K "best few matches") we need every row that clears
# the similarity bar, not just the single nearest one. 50 is a
# generous cap for the "duplicate cluster" case (genuine near-dupes
# of one drawer are realistically a handful, not hundreds) while
# still bounding the Python-side filtering work.
_DUPLICATE_CANDIDATE_LIMIT = 50


def check_duplicate(content: str, threshold: float = 0.9) -> dict:
    """Corpus-wide near-duplicate check. Embeds `content`, runs the
    same embed + VEC_DISTANCE nearest-neighbor query as search() but
    UNSCOPED (no wing/room filter — dedup spans the whole `drawers`
    table), converts each candidate's distance to a cosine similarity
    (see module docstring for the derivation), and keeps only
    candidates whose similarity clears `threshold` (higher threshold
    = stricter = fewer/no duplicates flagged).

    Returns {"is_duplicate": bool, "matches": [...]}: `is_duplicate`
    is True iff at least one candidate clears the threshold; `matches`
    holds ONLY the qualifying (above-threshold) candidates, each a
    dict mirroring search()'s per-result shape
    ({id, wing, room, title, snippet, distance}), ordered by ascending
    distance (closest/most-similar first).
    """
    vec_literal = vector_literal(embed(content))

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, wing, room, title, text, "
                f"VEC_DISTANCE(embedding, string_to_vector('{vec_literal}')) AS dist "
                "FROM drawers "
                # Dedup compares against LOGICAL drawers only, never the
                # child chunk fragments a long drawer is split into
                # (loom-rpsf.2) — a fragment is not itself a drawer, so
                # it must not surface as a near-duplicate match.
                "WHERE parent_drawer_id IS NULL "
                "ORDER BY dist ASC LIMIT %s",
                [_DUPLICATE_CANDIDATE_LIMIT],
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    matches = []
    for row in rows:
        dist = float(row["dist"])
        similarity = 1.0 - (dist / 2.0)
        if similarity < threshold:
            continue
        text = row.get("text") or ""
        matches.append(
            {
                "id": row["id"],
                "wing": row["wing"],
                "room": row["room"],
                "title": row["title"],
                "snippet": _snippet(text),
                "distance": dist,
            }
        )

    return {"is_duplicate": len(matches) > 0, "matches": matches}


def register_search_tools(mcp) -> None:
    """Register the semantic-search + duplicate-check tools on a
    FastMCP server instance. `search` keeps the `mempalace_` prefix
    (matching register_drawer_tools's convention); `check_duplicate`
    is registered under the final `mempalace_` name directly (see
    module docstring — new tools in this mid-rename window land under
    the final name rather than being renamed later)."""
    mcp.tool(name="mempalace_search")(search)
    mcp.tool(name="mempalace_check_duplicate")(check_duplicate)
