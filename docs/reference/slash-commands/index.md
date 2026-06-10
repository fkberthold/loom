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
| `/upstream-a-bead [bead-id] [--issue-only\|--issue+pr]` | User-typed | `upstream-a-bead` skill (upstream-contribution recipe) |
| `/dispatch-middle <bead>` | User-typed | `dispatch-middle` skill — runs the bead's RED→GREEN middle as a test-author → implementer (→ optional verify) subagent pipeline |
| `/explore <idea>` | User-typed | `explore` skill — above-bead SUB-design exploration; front-door to `/design-a-cycle` (explore → design → build). No soundness gate, no epic |
| `/design-a-cycle <topic>` | User-typed | `design-a-cycle` skill — above-bead campaign/arc orchestrator over the layered design substrate |
| `/docs-scaffold` | User-typed (manual only) | `docs-scaffold` skill — copies `templates/diataxis/` into the project with per-file approval |
| `/loom-mine-history` | User-typed (manual only) | `loom-mine-history` skill — mines git/PR history for uncaptured decisions behind a two-pass cost gate |
| `/loom-adopt` | User-typed (manual only) | `loom-adopt` skill — one-shot orchestrator composing audit-project + scripts/docs scaffold + history-mine + constitution into a resumable phase machine |
| `/check-loom-upstream` | User-typed | Read-only sweep of the project's `upstream:loom`-labeled beads against loom's closed beads; suggest-only |
| `/check-upstream-prs` | User-typed (schedulable) | Sweeps `upstream:watch` beads, queries `gh` per PR, auto-closes MERGED watch-beads |
| `/loom-guest [on\|off]` | User-typed | Toggles guest mode (no-host-tree-pollution guardrails) for the current repo |
| `/loom-upstream-gc` | User-typed | Interactive prune of stale `~/.loom/upstream/<owner>/<repo>/` clones; never auto-destructive |
| `/cleanup-orphans` | User-typed | Lists + prunes orphan agent worktrees + leftover background bash processes (surfaced by the `worktree-bg-inventory` sensor's `WT/BG:N` statusline chip) |
| `/wrap-up` | User-typed | Close-time ritual; preflight + drawer/KG drafting + close + push |
| `/audit-project [--apply-onboarding]` | User-typed (manual only) | `project-onboarder` subagent + interactive fix loop |
| `/lineage <topic>` | User-typed | `bug-family-researcher` subagent |

Skills `feature-a-bead`, `refactor-a-bead`, `cleanup-a-bead`, and
`docs-a-bead` ship without a direct slash command. They are reached
via the `/working-a-bead` router or via the Skill tool's
description-match auto-discovery.

## Full text

The complete content of every command file is published verbatim at
[all-commands.md](all-commands.md).
