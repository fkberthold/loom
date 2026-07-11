"""mcp_server/tools/checkpoint.py — checkpoint convenience wrapper
(loom-40ec.4.5.4).

One tool, prefixed `mempalace_` (matching every other tool in this
server under the `mempalace_*` prefix, loom-40ec.6.4 cutover):

  mempalace_checkpoint(items, diary=None, dedup_threshold=0.9) -> dict

`checkpoint` is a PURE COMPOSITION of three existing tools — no new
schema, no new query logic. For each item in `items` (a
{wing, room, title, content} dict; `title` is required) it runs
check_duplicate() (tools/search.py) and, if the item is not already a
near-duplicate, runs add_drawer() (tools/drawers.py). An optional
`diary` argument ({agent_name, topic, entry}) finally runs
diary_write() (tools/diary.py) once for the whole batch.

Per-item failures (a malformed item missing a required key, or any
other exception raised while processing one item) are caught and land
in the returned `errors` list rather than aborting the whole batch —
so a batch of N items where one is malformed still processes the
other N-1.

Return shape: {added: [...], duplicates: [...], errors: [...],
diary: {...} or None}. Each `added` entry is {item, drawer_id}; each
`duplicates` entry is {item, matches} (matches per check_duplicate's
own shape); each `errors` entry is {item, error}; `diary` is
{drawer_id} when a diary was written, else None.

Same plain-function-is-the-registered-tool pattern as every sibling
tool module (mcp.tool()(fn) returns the same function object it
decorates — see tools/drawers.py's module docstring).
"""
from __future__ import annotations

from typing import Any

from mcp_server.tools.diary import diary_write
from mcp_server.tools.drawers import add_drawer
from mcp_server.tools.search import check_duplicate


def checkpoint(
    items: list[dict],
    diary: dict | None = None,
    dedup_threshold: float = 0.9,
) -> dict:
    """Dedupe-then-add each item in `items`, then optionally write a
    diary entry for the batch. See module docstring for the full
    contract."""
    added: list[dict[str, Any]] = []
    duplicates: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    for item in items:
        try:
            wing = item["wing"]
            room = item["room"]
            title = item["title"]
            content = item["content"]
        except KeyError as exc:
            errors.append({"item": item, "error": f"missing required key: {exc}"})
            continue

        try:
            dup_check = check_duplicate(content, threshold=dedup_threshold)
            if dup_check["is_duplicate"]:
                duplicates.append({"item": item, "matches": dup_check["matches"]})
                continue
            drawer_id = add_drawer(wing, room, title, content)
            added.append({"item": item, "drawer_id": drawer_id})
        except Exception as exc:  # noqa: BLE001 - per-item isolation is the contract
            errors.append({"item": item, "error": str(exc)})

    diary_result: dict[str, Any] | None = None
    if diary is not None:
        diary_id = diary_write(
            agent_name=diary["agent_name"],
            entry=diary["entry"],
            topic=diary.get("topic", "general"),
        )
        diary_result = {"drawer_id": diary_id}

    return {
        "added": added,
        "duplicates": duplicates,
        "errors": errors,
        "diary": diary_result,
    }


def register_checkpoint_tools(mcp) -> None:
    """Register the checkpoint tool on a FastMCP server instance,
    prefixed `mempalace_`."""
    mcp.tool(name="mempalace_checkpoint")(checkpoint)
