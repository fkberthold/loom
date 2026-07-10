"""RED-spec test for loom-40ec.4.4 — mempalace_diary_write /
mempalace_diary_read (MCP diary tools, the mempalace_diary_write /
mempalace_diary_read equivalent).

Boots a REAL dolt sql-server via the SAME `dolt_server_env` fixture
tests/test_mcp_drawers.py already defines (imported here rather than
duplicated -- pytest re-instantiates a module-scoped fixture per
requesting module, so this file gets its OWN isolated ephemeral
server instance; see test_mcp_search.py's identical import for
precedent).

Diary entries are stored AS drawers (wing=`wing_<agent_name>` by
default, room="diary") -- mempalace_diary_write/mempalace_diary_read are
thin wrappers, exercised here end-to-end against real dolt SQL (no
mocks).
"""
import time

from mcp_server.tools.diary import diary_read, diary_write

# Reuse the existing dolt_server_env fixture from test_mcp_drawers.py
# rather than re-deriving the same bring-up boilerplate a second time.
from tests.test_mcp_drawers import dolt_server_env  # noqa: F401

# drawers.filed_at is a DATETIME column with SECOND-level precision
# (verified empirically against a live dolt 2.1.10 server: two
# inserts ~50ms apart landed with an IDENTICAL filed_at value) --
# diary_read's ORDER BY filed_at DESC recency ordering is only
# deterministic across writes spaced further apart than that
# granularity. Tests asserting relative recency sleep just over one
# second between writes to guarantee distinct timestamps -- matching
# how an actual diary is written (real gaps between entries), not a
# throughput/stress scenario.
_RECENCY_GAP_SECONDS = 1.1


def test_diary_write_returns_drawer_id(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    drawer_id = diary_write("test-agent", "test entry", topic="smoke-test")
    assert isinstance(drawer_id, str) and drawer_id


def test_diary_read_includes_written_entry(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    drawer_id = diary_write("test-agent-read", "hello diary", topic="smoke-test")
    entries = diary_read("test-agent-read", 3)
    matching = next(e for e in entries if e["id"] == drawer_id)
    assert matching["entry"] == "hello diary"
    assert matching["topic"] == "smoke-test"
    assert "filed_at" in matching


def test_diary_read_returns_n_most_recent_in_order(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """Write 3 entries for the same agent (spaced past the
    second-granularity boundary), then diary_read(agent, 2) must
    return exactly the 2 most recent, most-recent-first, verified by
    topic (not just count)."""
    agent = "test-agent-order"
    diary_write(agent, "first entry body", topic="topic-one")
    time.sleep(_RECENCY_GAP_SECONDS)
    diary_write(agent, "second entry body", topic="topic-two")
    time.sleep(_RECENCY_GAP_SECONDS)
    diary_write(agent, "third entry body", topic="topic-three")

    entries = diary_read(agent, 2)
    assert len(entries) == 2
    assert entries[0]["topic"] == "topic-three"
    assert entries[1]["topic"] == "topic-two"
    assert all(e["topic"] != "topic-one" for e in entries)


def test_diary_write_isolates_by_agent_wing(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    """A diary_write for a DIFFERENT agent must not show up in the
    first agent's diary_read -- confirms the wing_<agent_name>
    default actually isolates."""
    diary_write("agent-alpha", "alpha's private entry", topic="alpha-topic")
    diary_write("agent-beta", "beta's private entry", topic="beta-topic")

    alpha_entries = diary_read("agent-alpha", 10)
    beta_entries = diary_read("agent-beta", 10)

    assert any(e["topic"] == "alpha-topic" for e in alpha_entries)
    assert all(e["topic"] != "beta-topic" for e in alpha_entries)
    assert any(e["topic"] == "beta-topic" for e in beta_entries)
    assert all(e["topic"] != "alpha-topic" for e in beta_entries)


def test_diary_write_respects_wing_override(dolt_server_env):  # noqa: F811 - pytest fixture param, not a redefinition
    drawer_id = diary_write(
        "agent-gamma", "override entry", topic="override-topic", wing="custom_wing"
    )
    from mcp_server.tools.drawers import get_drawer

    fetched = get_drawer(drawer_id)
    assert fetched["wing"] == "custom_wing"
    assert fetched["room"] == "diary"

    # Default-wing diary_read for the same agent name does NOT see it
    # (the override wing isn't wing_agent-gamma).
    default_entries = diary_read("agent-gamma", 10)
    assert all(e["id"] != drawer_id for e in default_entries)

    # Reading with the SAME wing override finds it.
    override_entries = diary_read("agent-gamma", 10, wing="custom_wing")
    assert any(e["id"] == drawer_id for e in override_entries)


def test_diary_tools_registered_on_server():
    """mempalace_diary_write/mempalace_diary_read are registered on the
    FastMCP server built by create_server(), alongside the other tool
    groups."""
    from mcp_server.server import create_server

    server = create_server()
    tool_names = {t.name for t in server._tool_manager.list_tools()}
    assert "mempalace_diary_write" in tool_names
    assert "mempalace_diary_read" in tool_names
