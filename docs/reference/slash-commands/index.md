# Slash commands

Source: `commands/*.md` in this repository. Each `.md` file is one
slash command. All loom-shipped commands carry
`disable-model-invocation: true` in their frontmatter; only an
explicit user `/...` invocation triggers them.

| Field | Value |
|---|---|
| Source glob | `commands/*.md` |
| Install target | `~/.claude/commands/<name>.md` (symlink) |
| Catalogue page | [all-commands.md](all-commands.md) |

## Inventory

| Command | Trigger | Routes to |
|---|---|---|
| `/working-a-bead [bead-id] [--recipe=<name>]` | User-typed | Activity recipe selected by `bead.type` + description heuristics |
| `/bugfix-a-bead [bead-id]` | User-typed | `bugfix-a-bead` skill |
| `/research-a-bead [bead-id]` | User-typed | `research-a-bead` skill |
| `/wrap-up` | User-typed | Close-time ritual; preflight + drawer/KG drafting + close + push |
| `/audit-project` | User-typed (manual only) | `project-onboarder` subagent + interactive fix loop |
| `/lineage <topic>` | User-typed | `bug-family-researcher` subagent |

Skills `feature-a-bead`, `refactor-a-bead`, `cleanup-a-bead`, and
`docs-a-bead` ship without a direct slash command. They are reached
via the `/working-a-bead` router or via the Skill tool's
description-match auto-discovery.

## Full text

The complete content of every command file is published verbatim at
[all-commands.md](all-commands.md).
