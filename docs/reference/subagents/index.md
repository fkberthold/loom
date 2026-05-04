# Subagents

Source: `agents/*.md` in this repository. Each file defines one
subagent with frontmatter and prompt. Subagents inherit the main
session's model and run in isolated context, returning a reviewable
artifact rather than writing directly to MemPalace or beads.

| Field | Value |
|---|---|
| Source glob | `agents/*.md` |
| Install target | `~/.claude/agents/<name>.md` (symlink) |
| Catalogue page | [all-subagents.md](all-subagents.md) |

## Inventory

| Subagent | Dispatched by | Output |
|---|---|---|
| `bug-family-researcher` | `bd update --claim` hook reminder, `/lineage`, recipe phase A1 | ≤400-word prior-art markdown report |
| `drawer-author` | `/wrap-up`, recipe phase D3 | 300–600 word decision drawer in HAW house style |
| `kg-relationship-extractor` | `/wrap-up`, recipe phase D3 | ≤5 KG triples with valid_from + rationale |
| `project-onboarder` | `/audit-project` | ≤250-line PASS/WARN/MISS checklist |

Latency: 5–15 seconds per dispatch.

## Full text

The complete content of every agent file is published verbatim at
[all-subagents.md](all-subagents.md).
