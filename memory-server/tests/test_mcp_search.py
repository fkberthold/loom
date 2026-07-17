"""RED-spec test for loom-40ec.4.2 — mempalace_search (MCP semantic
search tool, the mempalace_search equivalent).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py already defines (imported here rather than
duplicated — see that fixture's docstring in test_mcp_drawers.py for
the full bring-up mechanics: ephemeral tmp data dir + free port via
scripts/start-server.sh, LOOM_MEMORY_* env vars pointed at it for the
duration of THIS test module too, since pytest re-instantiates a
module-scoped fixture per requesting module).

Seeds a small multi-wing/multi-room corpus via add_drawer() (the real
write path — no hand-rolled INSERT SQL, per the bead brief) and
exercises mempalace_search's wing/room scoping end-to-end against real
VEC_DISTANCE queries. No mocks anywhere in this file.
"""
import os

import pytest

from mcp_server.tools import drawers as drawers_mod
from mcp_server.tools.search import search

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py
# rather than re-deriving the same bring-up boilerplate a second time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401

# Randomized wing names so this module's corpus can never collide with
# rows any other test module (or a prior run) may have left behind in
# the (ephemeral, per-module) dolt server.
ALPHA_WING = f"loomtest_search_alpha_{os.urandom(4).hex()}"
BETA_WING = f"loomtest_search_beta_{os.urandom(4).hex()}"
KITTENS_ROOM = "kittens"
PUPPIES_ROOM = "puppies"
WIDGETS_ROOM = "widgets"

# A phrase distinctive enough that a real embedding model's
# nearest-neighbor search reliably surfaces its owning drawer at the
# very top when the SAME phrase is used as the query — this is a
# semantic-search test, not an exact-string-match test, but copying
# the phrase verbatim (per the bead's RED spec) gives the strongest,
# least-flaky signal.
UNIQUE_PHRASE = (
    "The zorbleflax nebula emits chartreuse photons in irregular "
    "bursts every third Tuesday, according to the observatory log."
)

# Appended to every seeded drawer's body so an UNSCOPED search on this
# marker phrase deterministically has a "closest match" in each wing
# (used by the cross-wing + narrowing tests below).
SHARED_MARKER = (
    "Cross-project calibration marker sentence for the unscoped "
    "search regression test."
)


@pytest.fixture(scope="module")
def seeded_corpus(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Seeds >=20 drawers spanning 2 distinct wings via add_drawer()
    (the real write path): ALPHA_WING has two rooms (kittens: 6 rows,
    puppies: 6 rows), BETA_WING has one room (widgets: 10 rows) —
    22 rows total. Returns a dict of drawer_ids grouped by
    wing/room so tests can assert on specific ids."""
    ids = {"alpha_kittens": [], "alpha_puppies": [], "beta_widgets": []}

    # alpha/kittens: one drawer carries UNIQUE_PHRASE, the rest are a
    # topically-distinct filler cluster (photosynthesis).
    ids["alpha_kittens"].append(
        drawers_mod.add_drawer(
            ALPHA_WING,
            KITTENS_ROOM,
            "Zorbleflax nebula observation",
            f"{UNIQUE_PHRASE} {SHARED_MARKER}",
        )
    )
    for i in range(5):
        ids["alpha_kittens"].append(
            drawers_mod.add_drawer(
                ALPHA_WING,
                KITTENS_ROOM,
                f"Kitten photosynthesis note {i}",
                f"Chlorophyll absorbs sunlight in leaf cell {i}. {SHARED_MARKER}",
            )
        )

    # alpha/puppies: same wing, DIFFERENT room, unrelated topic (urban
    # beekeeping) — exercises the "room narrows further than wing
    # alone" RED-spec item.
    for i in range(6):
        ids["alpha_puppies"].append(
            drawers_mod.add_drawer(
                ALPHA_WING,
                PUPPIES_ROOM,
                f"Urban beekeeping note {i}",
                f"Beekeepers inspect hive frame {i} for larvae. {SHARED_MARKER}",
            )
        )

    # beta/widgets: entirely different wing, unrelated topic
    # (quarterly financial reporting).
    for i in range(10):
        ids["beta_widgets"].append(
            drawers_mod.add_drawer(
                BETA_WING,
                WIDGETS_ROOM,
                f"Quarterly compliance memo {i}",
                f"Finance reviewed ledger reconciliation item {i}. {SHARED_MARKER}",
            )
        )

    return ids


def test_search_scoped_to_wing_returns_seeded_drawer(seeded_corpus):
    """search(<phrase copied from a seeded drawer's text>,
    wing=<that drawer's wing>) returns that drawer's id in the top
    results (and, given how distinctive UNIQUE_PHRASE is against the
    filler corpus, as the single closest match)."""
    target_id = seeded_corpus["alpha_kittens"][0]
    results = search(UNIQUE_PHRASE, wing=ALPHA_WING, limit=5)
    result_ids = [r["id"] for r in results]
    assert target_id in result_ids
    assert results[0]["id"] == target_id


def test_search_scoped_to_other_wing_excludes_it(seeded_corpus):
    """The SAME query with wing=<the OTHER wing> does NOT return the
    alpha drawer — confirms wing scoping actually FILTERS via the
    WHERE clause (+ the (wing, room) index), not just re-ranks."""
    target_id = seeded_corpus["alpha_kittens"][0]
    results = search(UNIQUE_PHRASE, wing=BETA_WING, limit=10)
    result_ids = [r["id"] for r in results]
    assert target_id not in result_ids
    assert all(r["wing"] == BETA_WING for r in results)


def test_search_unscoped_spans_both_wings(seeded_corpus):
    """An UNSCOPED search (no wing/room) still returns results across
    both wings — cross-project search still works."""
    total_seeded = sum(len(v) for v in seeded_corpus.values())
    results = search(SHARED_MARKER, limit=total_seeded)
    wings_seen = {r["wing"] for r in results}
    assert ALPHA_WING in wings_seen
    assert BETA_WING in wings_seen


def test_search_wing_and_room_narrows_further_than_wing_alone(seeded_corpus):
    """search(query, wing=X, room=Y) narrows further than wing=X
    alone (ALPHA_WING has 2 distinct rooms: kittens, puppies)."""
    wing_only = search(SHARED_MARKER, wing=ALPHA_WING, limit=100)
    wing_and_room = search(
        SHARED_MARKER, wing=ALPHA_WING, room=KITTENS_ROOM, limit=100
    )

    assert len(wing_and_room) < len(wing_only)
    assert all(r["room"] == KITTENS_ROOM for r in wing_and_room)
    assert {r["id"] for r in wing_and_room} <= {r["id"] for r in wing_only}


def test_search_result_shape(seeded_corpus):
    """Result dicts carry exactly the documented shape:
    {id, wing, room, title, snippet, distance}."""
    results = search(UNIQUE_PHRASE, wing=ALPHA_WING, limit=1)
    assert len(results) == 1
    row = results[0]
    assert set(row.keys()) == {"id", "wing", "room", "title", "snippet", "distance"}
    assert isinstance(row["snippet"], str)
    assert isinstance(row["distance"], float)


# ---------------------------------------------------------------------------
# loom-rpsf.2 — search rollup (S1). A long (>800-char) drawer is stored
# as a parent row + N child chunk rows. A semantic hit on ANY child must
# roll up to the parent's canonical id (canonical_id = parent_drawer_id
# or id) and appear exactly ONCE, best-distance-wins — search must never
# surface a raw `_chunk_` fragment id or the same drawer twice.
# ---------------------------------------------------------------------------

ROLLUP_WING = f"loomtest_rollup_{os.urandom(4).hex()}"

# A phrase distinctive enough to reliably be the nearest neighbor, placed
# deep enough in the body that it lands in the SECOND chunk (offset > 800)
# — so the hit is genuinely a child-chunk hit, not the parent row.
ROLLUP_PHRASE = (
    "The quintavium resonator hums in glissando whenever the "
    "aurora-tuned flywheel crosses its ninth harmonic node."
)


@pytest.fixture(scope="module")
def rollup_drawer(dolt_server_env):  # noqa: F811 - pytest fixture param
    """Seed ONE long (>1600-char) drawer whose distinctive phrase lands
    in the second chunk, so a search for that phrase hits a CHILD row
    that must be rolled up to the parent id."""
    # ~900 chars of filler, then the phrase => phrase starts past offset
    # 800, i.e. inside chunk index 1 (the second 800-char slice).
    filler = "Filler sentence about ordinary sedimentary geology. " * 18
    assert len(filler) > 800  # phrase starts past offset 800 => chunk index 1
    body = filler + " " + ROLLUP_PHRASE + " " + ("trailing padding. " * 10)
    assert len(body) > 800  # > CHUNK_SIZE guarantees the drawer is chunked
    parent_id = drawers_mod.add_drawer(
        ROLLUP_WING, "resonators", "Quintavium field notes", body
    )
    return parent_id


def test_search_rolls_chunk_hits_up_to_parent(rollup_drawer):
    """search(<phrase in a child chunk>) returns the PARENT id, never a
    `_chunk_` id, and never the same logical drawer twice."""
    results = search(ROLLUP_PHRASE, wing=ROLLUP_WING, limit=10)
    result_ids = [r["id"] for r in results]

    # the parent id is surfaced ...
    assert rollup_drawer in result_ids
    # ... exactly once (deduped) ...
    assert result_ids.count(rollup_drawer) == 1
    # ... and no raw chunk-fragment id leaks through the rollup.
    assert not any("_chunk_" in i for i in result_ids)
    # top hit is the drawer we seeded (its chunk was the closest match)
    assert results[0]["id"] == rollup_drawer


def test_search_result_id_is_canonical_not_chunk(rollup_drawer):
    """Every returned id must be a canonical (logical-drawer) id: no
    result may carry a parent_drawer_id-derived chunk id."""
    results = search(ROLLUP_PHRASE, wing=ROLLUP_WING, limit=10)
    for r in results:
        assert "_chunk_" not in r["id"]
    # shape is preserved through the rollup
    assert set(results[0].keys()) == {
        "id",
        "wing",
        "room",
        "title",
        "snippet",
        "distance",
    }


def test_search_registered_on_server():
    """mempalace_search is registered on the FastMCP server built by
    create_server(), alongside the drawer tools."""
    from mcp_server.server import create_server

    server = create_server()
    # FastMCP.list_tools() is async (it's an MCP-protocol handler);
    # the underlying ToolManager.list_tools() is sync and gives the
    # same registered-tools view, so this test stays a plain sync
    # test rather than needing asyncio machinery.
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "mempalace_search" in tool_names


# ---------------------------------------------------------------------------
# loom-rpsf.4 — hybrid BM25 + RRF keyword lane (S2). An exact token a
# drawer contains verbatim (a bead-id, error string, identifier) must
# surface even when that drawer is SEMANTICALLY about something else and
# the vector lane therefore ranks it low. An independent full-corpus BM25
# lane surfaces it; the two lanes are fused by Reciprocal Rank Fusion.
# ---------------------------------------------------------------------------

from mcp_server.bm25 import tokenize  # noqa: E402 — grouped with its tests

# The bead-id the RED spec queries for. It appears verbatim in exactly
# one seeded drawer, whose body is otherwise about deep-sea geology — a
# topic the vector lane places far from a bead-id-shaped query.
BEAD_ID_QUERY = "loom-40ec.7"

HYBRID_WING = f"loomtest_hybrid_{os.urandom(4).hex()}"
HYBRID_ROOM = "identifiers"

# Twelve short drawers whose bodies are ABOUT software/version-control —
# semantically nearer a code-identifier query than deep-sea geology is —
# but which contain NONE of the query's tokens (no `loom`, no `40ec`, no
# digits) and none of the SHARED_MARKER vocabulary. So the BM25 lane
# scores them exactly zero for BEAD_ID_QUERY, while the vector lane still
# ranks them above the (marine) target. That gap is what makes the
# scenario a genuine RED against a vector-only search.
HYBRID_DISTRACTOR_BODIES = [
    "Distributed version control tracks branches and merges across cloned repositories.",
    "Continuous integration pipelines compile artifacts and publish container images.",
    "The build orchestrator schedules parallel jobs onto ephemeral worker nodes.",
    "A rebase replays local commits atop the upstream head to keep history linear.",
    "Static analysis flags unused imports and shadowed variables before merge.",
    "The dependency resolver pins transitive package versions in a lockfile.",
    "Feature flags gate unfinished code paths behind runtime configuration toggles.",
    "The scheduler drains a node before rolling out the next deployment revision.",
    "Structured logging emits key value pairs consumed by the aggregation backend.",
    "The formatter enforces import ordering and consistent whitespace conventions.",
    "Containers mount a read only root filesystem with a writable overlay layer.",
    "The message broker buffers events and replays them to lagging consumers.",
]

# The target: body semantically about marine geology (FAR from a
# bead-id-shaped query) with the exact bead-id appended verbatim. Only
# this drawer contains the query token, so BM25 surfaces it at rank 1
# even though the vector lane ranks it low.
HYBRID_TARGET_BODY = (
    "Deep sea hydrothermal vents precipitate towering sulfide chimneys that "
    "shelter tube worms and blind shrimp along the mid ocean spreading ridge. "
    f"{BEAD_ID_QUERY}"
)


@pytest.fixture(scope="module")
def hybrid_corpus(dolt_server_env):  # noqa: F811 - pytest fixture param
    """Seed 12 software distractors + 1 marine-geology target that alone
    contains the bead-id BEAD_ID_QUERY. The target is seeded LAST so it
    also carries the latest filed_at (belt-and-suspenders for the recency
    tie-break, though the RRF math already ranks it first)."""
    distractor_ids = []
    for i, body in enumerate(HYBRID_DISTRACTOR_BODIES):
        distractor_ids.append(
            drawers_mod.add_drawer(
                HYBRID_WING, HYBRID_ROOM, f"Engineering note {chr(ord('a') + i)}", body
            )
        )
    target_id = drawers_mod.add_drawer(
        HYBRID_WING, HYBRID_ROOM, "Ridge survey field notes", HYBRID_TARGET_BODY
    )
    return {"target": target_id, "distractors": distractor_ids}


def test_tokenizer_emits_bead_id_as_atomic_token():
    """INVARIANT (loom-rpsf.4 RED): the tokenizer emits `loom-40ec.7` as
    an ATOMIC token, distinct from `loom-40ec`. Both are present and are
    different strings — the atomic bead-id is never silently truncated to
    its parent id."""
    toks = tokenize("see loom-40ec.7 in the drawer for the resonator finding")
    assert "loom-40ec.7" in toks  # atomic token present
    assert "loom-40ec" in toks  # the parent-id prefix is also emitted
    assert "loom-40ec.7" != "loom-40ec"  # ... and they are distinct tokens
    # the separator-split sub-parts are emitted too (keyword recall)
    assert "loom" in toks
    assert "40ec" in toks
    assert "7" in toks
    # a plain word stays a single token, not split into characters
    assert "resonator" in toks


def test_bm25_lane_surfaces_bead_id_in_unrelated_drawer(hybrid_corpus):
    """The BM25 lane ranks the drawer that verbatim-contains the bead-id
    at rank 1 — even though its body is semantically about deep-sea
    geology. It is the sole corpus-wide match for the token, so it leads
    the lane."""
    from mcp_server.bm25 import get_index

    ranked = get_index().ranked_canonicals(BEAD_ID_QUERY)
    ranked_ids = [cid for cid, _ in ranked]
    assert hybrid_corpus["target"] in ranked_ids
    assert ranked_ids[0] == hybrid_corpus["target"]


def test_hybrid_search_surfaces_bead_id_in_semantically_unrelated_drawer(hybrid_corpus):
    """RED spec (loom-rpsf.4): query `loom-40ec.7` against a corpus where
    one drawer contains that bead-id verbatim but is semantically about
    something else. Hybrid search returns that drawer in the top-k — the
    BM25 lane surfaces it though the vector lane ranks it low. A
    vector-only search does NOT (the marine-geology target is not the
    nearest neighbor of a bead-id query), which is what makes this RED
    before the BM25 lane is fused in."""
    results = search(BEAD_ID_QUERY, wing=HYBRID_WING, limit=5)
    result_ids = [r["id"] for r in results]

    assert hybrid_corpus["target"] in result_ids
    # the bead-id match is the single best hybrid result: it is rank 1 in
    # the BM25 lane AND present in the vector lane, so RRF ranks it above
    # every distractor (which contributes to the vector lane only).
    assert results[0]["id"] == hybrid_corpus["target"]
    # result shape is preserved through fusion + rollup
    assert set(results[0].keys()) == {
        "id",
        "wing",
        "room",
        "title",
        "snippet",
        "distance",
    }


# ---------------------------------------------------------------------------
# loom-rpsf.5 — neighbour-chunk stitching + recency (S3, design D4-stitch).
# For the best-matching chunk of a canonical hit, the returned context is the
# +/-1 neighbour window (chunk_index IN [best-1, best, best+1]) joined with a
# blank line and capped at MAX_HYDRATION_CHARS (10000). The stitch is ADDITIVE
# over the S1 rollup + S2 RRF fusion: it enriches the `snippet` (returned
# context) of each already-rolled-up, already-fused canonical result — the
# parent id still surfaces exactly once, never a raw `_chunk_` fragment.
# Ported from MemPalace searcher.py:1281-1289 (N=+/-1 window, 10k cap).
# ---------------------------------------------------------------------------

from datetime import datetime  # noqa: E402 — grouped with its tests

from mcp_server.bm25 import DrawerMeta  # noqa: E402
from mcp_server.chunking import CHUNK_SIZE  # noqa: E402
from mcp_server.tools.search import (  # noqa: E402
    MAX_HYDRATION_CHARS,
    _recency_sort_key,
    _stitch_window,
)

# A run-unique marker suffix so this module's per-chunk sentinels can never
# collide with rows any other test (or a prior run) left behind.
STITCH_RUN = os.urandom(4).hex()
STITCH_WING = f"loomtest_stitch_{os.urandom(4).hex()}"

# Ten vividly-distinct topical sentences, one dominating each 800-char chunk,
# so the vector lane deterministically picks the chunk whose topic matches the
# query. Chunk index 5's topic is the query below, so the best-matching chunk
# is 5 and the +/-1 stitch window is chunks 4, 5, 6.
_STITCH_TOPICS = [
    "Glacial moraines deposit unsorted till across the alpine valley floor.",
    "The pipe organ's diapason reeds resonate through the cathedral nave.",
    "Mycorrhizal fungi exchange phosphorus with pine roots underground.",
    "Sailmakers reinforce the clew with triple-stitched dacron webbing.",
    "Neutron stars spin down as magnetic dipole radiation drains their spin.",
    "The quintavium resonator hums in glissando across its ninth harmonic node.",
    "Beekeepers smoke the hive before lifting the honey-laden brood frames.",
    "Ledger reconciliation flags the unmatched quarterly settlement entry.",
    "Tectonic subduction melts the slab and feeds the arc volcano's magma.",
    "The lexicographer annotates each headword with its etymological root.",
]


def _stitch_chunk(i: int) -> str:
    """Build one exactly-CHUNK_SIZE-char segment dominated by topic `i`, with
    a run-unique `STITCHMARK_<i>_<run>` sentinel near the front so the test can
    assert exactly which chunks landed in the stitched window."""
    marker = f"STITCHMARK_{i}_{STITCH_RUN}"
    base = f"{marker}. " + (_STITCH_TOPICS[i] + " ") * 40
    # [:CHUNK_SIZE] then .ljust(CHUNK_SIZE): guarantees EXACTLY 800 chars so
    # the non-overlapping 800-char slicing aligns each stored chunk with one
    # segment (chunk_index i == segment i).
    return base[:CHUNK_SIZE].ljust(CHUNK_SIZE)


@pytest.fixture(scope="module")
def stitch_drawer(dolt_server_env):  # noqa: F811 - pytest fixture param
    """Seed ONE drawer whose body is exactly ten 800-char chunks (chunk_index
    0..9), each dominated by a distinct topic. Returns the parent drawer id."""
    body = "".join(_stitch_chunk(i) for i in range(10))
    assert len(body) == 10 * CHUNK_SIZE  # exactly ten 800-char chunks
    parent_id = drawers_mod.add_drawer(
        STITCH_WING, "chunks", "Ten-chunk stitch fixture", body
    )
    return parent_id


def test_search_stitches_neighbour_chunks_into_context(stitch_drawer):
    """RED (loom-rpsf.5): a query matching chunk 5 of a 10-chunk drawer returns
    context stitched from chunks 4, 5, 6 joined with a blank line, capped at
    10000 chars, and the parent id appears exactly once (never a `_chunk_`)."""
    results = search(_STITCH_TOPICS[5], wing=STITCH_WING, limit=5)
    result_ids = [r["id"] for r in results]

    # S1 rollup preserved: parent surfaces once, no raw chunk fragment id.
    assert stitch_drawer in result_ids
    assert result_ids.count(stitch_drawer) == 1
    assert not any("_chunk_" in i for i in result_ids)
    # chunk 5's topic is unique to this wing's sole drawer, so it leads.
    assert results[0]["id"] == stitch_drawer

    snippet = results[0]["snippet"]
    # the +/-1 window around the best-matching chunk (5): chunks 4, 5, 6 ...
    assert f"STITCHMARK_4_{STITCH_RUN}" in snippet
    assert f"STITCHMARK_5_{STITCH_RUN}" in snippet
    assert f"STITCHMARK_6_{STITCH_RUN}" in snippet
    # ... and NOT chunks 3 or 7 (window is strictly +/-1, not wider).
    assert f"STITCHMARK_3_{STITCH_RUN}" not in snippet
    assert f"STITCHMARK_7_{STITCH_RUN}" not in snippet
    # joined with a blank line between the three chunks ...
    assert "\n\n" in snippet
    # ... and capped at MAX_HYDRATION_CHARS.
    assert len(snippet) <= MAX_HYDRATION_CHARS
    # result shape is preserved through the stitch (snippet enriched in place).
    assert set(results[0].keys()) == {
        "id",
        "wing",
        "room",
        "title",
        "snippet",
        "distance",
    }


def test_stitch_window_selects_pm1_neighbours():
    """_stitch_window joins chunk_index [best-1, best, best+1] in ascending
    order, separated by a blank line."""
    texts = {i: f"chunk{i}" for i in range(10)}
    assert _stitch_window(texts, 5) == "chunk4\n\nchunk5\n\nchunk6"


def test_stitch_window_clamps_at_boundaries():
    """At the first/last chunk the window clamps — no out-of-range neighbour
    is fabricated (best-1 < 0 or best+1 > max is simply dropped)."""
    texts = {i: f"chunk{i}" for i in range(10)}
    assert _stitch_window(texts, 0) == "chunk0\n\nchunk1"
    assert _stitch_window(texts, 9) == "chunk8\n\nchunk9"


def test_stitch_window_caps_at_max_hydration_chars():
    """A window whose joined text exceeds MAX_HYDRATION_CHARS is hard-capped
    to exactly MAX_HYDRATION_CHARS (the 10k ceiling ported from MemPalace)."""
    big = {4: "a" * 6000, 5: "b" * 6000, 6: "c" * 6000}
    out = _stitch_window(big, 5)
    assert len(out) == MAX_HYDRATION_CHARS


def test_recency_sort_key_orders_newer_first():
    """Recency reconciliation (S3 step 3): the S2 fusion tie-break already
    breaks exact-score ties toward the newer filed_at. This pins that
    contract — newer filed_at yields a smaller sort key (sorts earlier under
    Python's ascending sort), and a missing filed_at sorts last."""
    older = DrawerMeta("w", "r", "t", "x", datetime(2020, 1, 1))
    newer = DrawerMeta("w", "r", "t", "x", datetime(2026, 1, 1))
    assert _recency_sort_key(newer) < _recency_sort_key(older)
    assert _recency_sort_key(None) == float("inf")
    assert _recency_sort_key(DrawerMeta("w", "r", "t", "x", None)) == float("inf")
