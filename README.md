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
- **Recipes** — activity-shaped skills (`bugfix-a-bead` today;
  `feature-a-bead`, `refactor-a-bead`, `research-a-bead`,
  `cleanup-a-bead`, `docs-a-bead` in flight) that own each activity's
  variable middle, plus the cross-activity `bead-lifecycle-shell` that
  owns claim/isolate/verify/close/capture
- **Subagents** (`bug-family-researcher`, `drawer-author`,
  `kg-relationship-extractor`, `project-onboarder`) — isolated workers
  that handle search/synthesis without bloating main context
- **Slash commands** (`/bugfix-a-bead`, `/working-a-bead` router
  (in flight), `/lineage`, `/wrap-up`, `/audit-project`) —
  user-triggered rituals
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

### Developing loom (dev-only)

Contributing to loom additionally needs **shellcheck** on PATH — it's
the linter behind the `shellcheck --severity=warning hooks/*.sh
lib/*.sh scripts/*` lint gate (declared in
`.claude/project-constitution.md`). It is a dev prerequisite only, not
a runtime dependency: the installed primitives don't need it, but the
lint gate fails loud (non-zero) if it's absent, so install it before
running the lint. No sudo / package manager required — grab the static
binary into `~/.local/bin/`:

```bash
ver=v0.10.0
curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/${ver}/shellcheck-${ver}.linux.x86_64.tar.xz" \
  | tar -xJ
install -m755 "shellcheck-${ver}/shellcheck" ~/.local/bin/shellcheck
shellcheck --version   # confirm ~/.local/bin is on PATH
```

The repo-root `.shellcheckrc` disables only `SC1091` (loom's dynamic
helper sourcing, which shellcheck can't follow statically). Run the
gate with `shellcheck --severity=warning hooks/*.sh lib/*.sh scripts/*`.

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
├── skills/                    # Activity recipes + cold-start ritual + shared lifecycle shell
│   ├── bugfix-a-bead/SKILL.md      # variable middle for bug-shaped beads
│   ├── bead-lifecycle-shell/SKILL.md  # cross-activity scaffolding
│   └── session-startup/SKILL.md    # cold-start ritual
├── agents/                    # Subagents
│   ├── bug-family-researcher.md
│   ├── drawer-author.md
│   ├── kg-relationship-extractor.md
│   └── project-onboarder.md
├── commands/                  # Slash commands
│   ├── bugfix-a-bead.md
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
├── docs/                      # Diataxis-shaped MkDocs site (deployed via GH Pages)
│   ├── tutorials/             # Learning-by-doing: getting-started + walkthroughs
│   ├── how-to/                # Task-oriented guides
│   ├── reference/             # Austere primitive specs (auto-glob over skills/, commands/, agents/, hooks/)
│   └── explanation/           # Design rationale, mental model, provenance
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

Published docs site: https://fkberthold.github.io/loom/ — Diataxis-shaped
across four quadrants:

- [Tutorials](docs/tutorials/) — learning-by-doing: `getting-started.md`
  walks zero → first shipped bead; `bug-walkthrough.md` and
  `feature-walkthrough.md` are deeper narrative walkthroughs.
- [How-to](docs/how-to/) — task-oriented guides: install, daily session
  lifecycle, common scenarios, bypass mechanisms.
- [Reference](docs/reference/) — austere primitive specs (skills, slash
  commands, subagents, hooks auto-discovered from disk), plus glossary,
  decision tables, and path-scoped rules.
- [Explanation](docs/explanation/) — design rationale: mental model,
  recipe family, workflow modes, provenance.

## License

MIT (see [LICENSE](LICENSE)).

## Origin

Forged during the 2026-05-02 deploy-day cleanup of the Hundred Acre
Woods project. Initial design + locked decisions captured in MemPalace
drawer "WORKFLOW INFRASTRUCTURE PLAN" (hundred_acre_woods/decisions
wing of the dreamer-engine palace). Subsequent beads + decisions
tracked here in loom's own `bd`.
