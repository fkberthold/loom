# Skills

Source: `skills/*/SKILL.md` in this repository. Each subdirectory of
`skills/` ships one SKILL.md. The list below is generated from the
filesystem at build time via `mkdocs-include-markdown`.

| Field | Value |
|---|---|
| Source glob | `skills/*/SKILL.md` |
| Install target | `~/.claude/skills/<name>/SKILL.md` (symlink) |
| Catalogue page | [all-skills.md](all-skills.md) |

## Invocation

| Skill | Invocation |
|---|---|
| `audit-project` | `/audit-project` (manual-only; never auto-suggested) |
| `bead-lifecycle-shell` | Indirect; cited by activity recipes by phase letter (A/B/C/D) |
| `bugfix-a-bead` | `/bugfix-a-bead [bead-id]`, `/working-a-bead` router, or auto-discovery |
| `feature-a-bead` | `/working-a-bead` router or auto-discovery |
| `refactor-a-bead` | `/working-a-bead` router or auto-discovery |
| `research-a-bead` | `/research-a-bead [bead-id]`, `/working-a-bead` router, or auto-discovery |
| `cleanup-a-bead` | `/working-a-bead` router or auto-discovery |
| `docs-a-bead` | `/working-a-bead` router or auto-discovery |
| `upstream-a-bead` | `/upstream-a-bead [bead-id] [--issue-only\|--issue+pr]`, `/working-a-bead` router, or auto-discovery on `upstream:work`-labeled beads |
| `dispatch-middle` | `/dispatch-middle <bead>`, or auto at a recipe's RED→GREEN middle when the bead is non-trivial |
| `design-a-cycle` | `/design-a-cycle <topic>`; above-bead orchestrator (NOT an activity recipe — iterates, spawns research-a-beads + an epic) |
| `docs-scaffold` | `/docs-scaffold` (manual-only; never auto-suggested) |
| `loom-mine-history` | `/loom-mine-history` (manual-only; two-pass cost gate) |
| `session-startup` | `/session-startup` or session-start auto-load |

## Full text

The complete content of every SKILL.md file is published verbatim at
[all-skills.md](all-skills.md).
