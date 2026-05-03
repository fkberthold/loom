# loom

> Workflow infrastructure for Claude Code that weaves together
> **beads** (issue tracker), **MemPalace** (memory), **superpowers**
> (skills), and **beadpowers** (design→bead pipeline) into a single
> coherent end-to-end developer workflow.
>
> Status: v1.5 (workflow modes + state file + status line shipped
> 2026-05-03). v2 activity-shaped recipes in flight under epics
> tracked in this repo's own `bd`.

## What it is

A collection of skills, slash commands, hooks, subagents, and helper
libraries — installed into `~/.claude/` — that turn Claude Code into
a disciplined development partner. The discipline is enforced by
primitives (hooks fire on lifecycle events, slash commands invoke
recipes, subagents handle isolated work) so it can't be skipped under
pressure.

The four-axis memory model:

| Axis | Tool | Surfaces at |
|---|---|---|
| Task state + tribal knowledge | `bd` (beads) | `bd prime`, explicit query |
| Verbatim decisions + lineage | MemPalace drawers | manual queries |
| Structured entity relationships | MemPalace KG | `kg_query` / `kg_timeline` |
| Per-agent introspective continuity | MemPalace diary | `diary_read` |

loom layers onto these:
- **Recipes** (skills like `working-a-bead`) — the canonical 14-step
  bead-execution sequence
- **Subagents** (`bug-family-researcher`, `drawer-author`,
  `kg-relationship-extractor`, `project-onboarder`) — isolated workers
  that handle search/synthesis without bloating main context
- **Slash commands** (`/working-a-bead`, `/lineage`, `/wrap-up`,
  `/audit-project`) — user-triggered rituals
- **Hooks** (PreToolUse on `bd update --claim`, `bd close`, `git push`;
  SessionStart for mode onboarding) — automation that fires without
  agent intervention
- **Modes** (`full` / `light` / `off` per `<project>/.claude/workflow.json`)
  — opt-out for projects where the workflow doesn't fit
- **Status line** — surfaces current mode + activity + recipe stage +
  bead in the Claude Code TUI

## Prerequisites

- [Claude Code](https://claude.com/code) installed
- [`bd` (beads)](https://github.com/steveyegge/beads) installed and on PATH
- [MemPalace](https://github.com/MemPalace/mempalace) installed and configured
- Plugins enabled: `beads`, `mempalace`, `superpowers`, `beadpowers`,
  `context7-plugin`
- `jq` on PATH (used by hooks for JSON parsing)

## Install

```bash
cd ~/repos/loom
./install.sh
```

The installer:
1. Backs up any existing `~/.claude/{skills,agents,commands,hooks,lib,scripts}/<file>`
   that loom owns, suffixing `.pre-loom.bak`
2. Symlinks loom's files into `~/.claude/...` so edits in this repo take
   effect immediately
3. Merges `settings.snippet.json` into `~/.claude/settings.json`
   (additive — preserves your existing keys)

To uninstall:

```bash
./uninstall.sh
```

Removes the symlinks and restores any `.pre-loom.bak` backups.

## Layout

```
loom/
├── skills/                    # 14-step recipe + cold-start ritual + shared lifecycle shell
│   ├── working-a-bead/SKILL.md
│   ├── bead-lifecycle-shell/SKILL.md
│   └── session-startup/SKILL.md
├── agents/                    # Subagents
│   ├── bug-family-researcher.md
│   ├── drawer-author.md
│   ├── kg-relationship-extractor.md
│   └── project-onboarder.md
├── commands/                  # Slash commands
│   ├── working-a-bead.md
│   ├── lineage.md
│   ├── wrap-up.md
│   └── audit-project.md
├── hooks/                     # PreToolUse + SessionStart hooks
│   ├── bd-claim-research.sh
│   ├── bd-close-capture.sh
│   ├── git-push-bd-sync.sh
│   └── workflow-mode-onboarding.sh
├── lib/                       # Sourceable bash helpers
│   ├── workflow-mode.sh
│   ├── workflow-state.sh
│   └── tests/                 # bash unit tests
├── scripts/                   # Executable scripts
│   ├── statusline.sh          # Claude Code statusLine target
│   └── workflow-state         # CLI wrapper for skills/agents
├── docs/                      # Reference material
│   ├── manual.md              # The Claude Workflow Manual (16 sections)
│   └── walkthrough.md         # Narrative session walkthrough
├── settings.snippet.json      # The stanzas install.sh merges into ~/.claude/settings.json
├── install.sh                 # Symlink installer
├── uninstall.sh               # Restore .pre-loom.bak backups
├── README.md                  # This file
├── CLAUDE.md                  # Project instructions for Claude Code working on loom
└── .beads/                    # loom's own beads tracker (initialized by `bd init`)
```

## Workflow modes

Per-project `<project>/.claude/workflow.json`:

```json
{"v": 1, "mode": "full"}
```

| Mode | Hooks | Skills | Status line |
|---|---|---|---|
| `full` | all fire | recipe runs | populated |
| `light` | informational only (close-capture never blocks) | recipe runs with reduced ceremony + warning | populated |
| `off` | silent | recipe refuses; session-startup skipped | empty |

Hard escape hatch: `CLAUDE_WORKFLOW_OFF=1 claude` forces `off` mode.

First cold-start in a beads workspace without `workflow.json` triggers
the SessionStart onboarding hook, which asks Claude to ask you to pick
a mode. The answer is written to `workflow.json` and remembered.

## Documentation

- [`docs/manual.md`](docs/manual.md) — full reference (16 sections):
  mental model, what's installed where, daily session lifecycle, the
  recipe, decision tables, bypass mechanisms, cookbook, glossary.
- [`docs/walkthrough.md`](docs/walkthrough.md) — narrative end-to-end
  session walkthrough with `[v1.5]` annotations.

## License

MIT (see [LICENSE](LICENSE)).

## Origin

Forged during the 2026-05-02 deploy-day cleanup of the Hundred Acre
Woods project. Initial design + locked decisions captured in MemPalace
drawer "WORKFLOW INFRASTRUCTURE PLAN" (hundred_acre_woods/decisions
wing of the dreamer-engine palace). Subsequent beads + decisions
tracked here in loom's own `bd`.
