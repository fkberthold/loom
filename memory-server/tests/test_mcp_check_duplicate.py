"""RED-spec test for loom-4cb6 — mempalace_check_duplicate (MCP
corpus-wide near-duplicate detection tool).

check_duplicate is the dedup analog of the existing search() tool: same
embed + VEC_DISTANCE nearest-neighbor path, but UNSCOPED (no wing/room
filter — it dedups across the WHOLE corpus) and wrapped in a
{"is_duplicate": bool, "matches": [...]} verdict keyed off a similarity
threshold (default 0.9). Each match mirrors search()'s per-result shape
(at minimum the matched drawer's id + a distance score).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py defines (imported here rather than
duplicated — this module gets its OWN isolated, module-scoped ephemeral
server instance). Seeds via add_drawer() (the real write path, no
hand-rolled INSERT SQL) and exercises check_duplicate end-to-end
against real embeddings + VEC_DISTANCE. No mocks anywhere in this file.

The module-scoped dolt server is SHARED by every test below, so each
test seeds into a randomized-unique wing and phrases its query around a
distinctive marker, so cross-test seeding can neither satisfy nor
defeat another test's duplicate verdict.
"""
import os

import pytest

from mcp_server.tools.drawers import add_drawer

# The function under test — does not exist yet (loom-4cb6 is RED until
# the implementer adds check_duplicate to mcp_server/tools/search.py).
# Module-level import mirrors the sibling test_mcp_search.py convention;
# while RED it surfaces as an ImportError collection error naming the
# missing symbol.
from mcp_server.tools.search import check_duplicate

# Reuse the existing dolt_server_env fixture rather than re-deriving the
# bring-up boilerplate a second time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401


def test_exact_duplicate_is_flagged(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """A drawer with body C already exists; check_duplicate(C) with the
    default threshold returns is_duplicate=True with the seeded
    drawer's id among non-empty matches, each match carrying at minimum
    an id + a distance score."""
    wing = f"cd_exact_{os.urandom(4).hex()}"
    body = (
        "The Umbral Cartographers Guild ratified bylaw 7 on the third "
        "moon of Threnody, forbidding the mapping of shadows cast by "
        "the ninth lighthouse during a total eclipse."
    )
    seeded_id = add_drawer(wing, "charters", "Umbral bylaw 7", body)

    result = check_duplicate(body)

    assert result["is_duplicate"] is True
    assert result["matches"], "expected non-empty matches for an exact duplicate"
    match_ids = [m["id"] for m in result["matches"]]
    assert seeded_id in match_ids
    # Each match carries at minimum the matched drawer's id + a distance
    # score, mirroring search()'s per-result shape.
    for m in result["matches"]:
        assert {"id", "distance"}.issubset(m.keys())


def test_whitespace_punctuation_variant_is_flagged(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """A copy of an existing drawer's body that differs only in
    whitespace/punctuation still reads as a duplicate at the default
    threshold — this is semantic dedup, not exact-string dedup."""
    wing = f"cd_ws_{os.urandom(4).hex()}"
    body = (
        "Quarterly telemetry from the Borealis buoy array shows a "
        "steady rise in dissolved argon near the northern trench."
    )
    seeded_id = add_drawer(wing, "reports", "Borealis argon", body)

    # Same text, differing ONLY in leading/collapsed whitespace and
    # trailing punctuation.
    variant = (
        "  Quarterly telemetry from the Borealis buoy array shows a "
        "steady rise in dissolved argon near the northern trench!!  "
    )
    result = check_duplicate(variant)

    assert result["is_duplicate"] is True
    assert seeded_id in [m["id"] for m in result["matches"]]


def test_dissimilar_content_is_not_flagged(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Content not similar to anything in the corpus returns
    is_duplicate=False with empty matches at the default threshold. The
    match list holds only qualifying (above-threshold) duplicates, so a
    non-duplicate verdict carries none."""
    wing = f"cd_none_{os.urandom(4).hex()}"
    # Seed a cluster on ONE distinctive topic ...
    for i in range(3):
        add_drawer(
            wing,
            "botany",
            f"Fernback propagation {i}",
            f"Spores of the fernback cultivar {i} germinate in humid "
            f"basalt crevices along the equatorial ridge.",
        )

    # ... then query about a topic with no lexical or semantic overlap
    # with anything seeded by this module.
    unrelated = (
        "Municipal bond yield curves inverted sharply after the central "
        "bank's surprise interest-rate decision on Thursday afternoon."
    )
    result = check_duplicate(unrelated)

    assert result["is_duplicate"] is False
    assert result["matches"] == []


def test_threshold_argument_narrows_what_counts_as_duplicate(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """The threshold parameter is a similarity cutoff: a near-but-not-
    exact duplicate reads as a duplicate under a loose threshold (0.5)
    but NOT under a very strict one (0.999) — demonstrating the argument
    actually gates the verdict. A genuine paraphrase is semantically
    close (clears a loose 0.5 bar) yet not identical (cannot clear a
    0.999 bar, which effectively demands a near-perfect match)."""
    wing = f"cd_thresh_{os.urandom(4).hex()}"
    original = (
        "The archivist logged forty-two vellum scrolls recovered from "
        "the sunken scriptorium, cataloguing each by its wax seal and "
        "the color of its binding thread."
    )
    add_drawer(wing, "archive", "Scriptorium recovery", original)

    # Same facts, reworded — high semantic overlap, not identical.
    near_duplicate = (
        "Forty-two vellum scrolls pulled from the drowned scriptorium "
        "were recorded by the archivist, who noted every wax seal and "
        "each binding thread's hue."
    )

    loose = check_duplicate(near_duplicate, threshold=0.5)
    strict = check_duplicate(near_duplicate, threshold=0.999)

    assert loose["is_duplicate"] is True
    assert strict["is_duplicate"] is False


def test_check_duplicate_registered_on_server():
    """mempalace_check_duplicate is registered on the FastMCP server
    built by create_server() (matching the sibling registration tests
    for the search/status/kg tool groups)."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "mempalace_check_duplicate" in tool_names
