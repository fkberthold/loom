# Installed files

What loom installs and where it lives. Paths are absolute. After
install, files under `~/.claude/...` are symlinks into a clone of this
repository; the canonical content lives in the clone.

## Plugins enabled

Configured in `~/.claude/settings.json`.

```
superpowers@superpowers-marketplace      # original 14-skill set
superpowers@claude-plugins-official      # newer 5.x; both versions coexist
beads@beads-marketplace                  # bd CLI + 19 skill wrappers
beadpowers@beadpowers-dev                # 3 skills (brainstorming, create-beads, using-beadpowers)
mempalace@mempalace                      # 29-tool MCP server + skills + hooks
context7-plugin@context7-marketplace     # docs lookup for libraries
```

## `~/.claude/` tree (loom-owned files)

```
~/.claude/
├── settings.json                 # permissions, plugins, hooks, statusLine
├── lib/
│   ├── workflow-mode.sh          # mode resolver (sourceable lib)
│   └── workflow-state.sh         # state-file r/w (sourceable lib)
├── scripts/
│   ├── workflow-state            # CLI wrapper for skills/agents
│   └── statusline.sh             # Claude Code statusLine target
├── skills/
│   ├── session-startup/SKILL.md
│   ├── bead-lifecycle-shell/SKILL.md
│   ├── bugfix-a-bead/SKILL.md
│   ├── feature-a-bead/SKILL.md
│   ├── refactor-a-bead/SKILL.md
│   ├── research-a-bead/SKILL.md
│   ├── cleanup-a-bead/SKILL.md
│   ├── docs-a-bead/SKILL.md
│   └── audit-project/SKILL.md
├── agents/
│   ├── bug-family-researcher.md
│   ├── drawer-author.md
│   ├── kg-relationship-extractor.md
│   └── project-onboarder.md
├── commands/
│   ├── working-a-bead.md
│   ├── bugfix-a-bead.md
│   ├── research-a-bead.md
│   ├── audit-project.md
│   ├── lineage.md
│   └── wrap-up.md
└── hooks/
    ├── bd-claim-research.sh
    ├── bd-close-capture.sh
    ├── git-push-bd-sync.sh
    └── workflow-mode-onboarding.sh
```

The full list of skills, commands, agents, and hooks shipped at any
given commit is auto-included on the catalogue pages
([Skills](skills/index.md), [Slash commands](slash-commands/index.md),
[Subagents](subagents/index.md), [Hooks](hooks/index.md)).

## Per-project files

```
<project>/
├── CLAUDE.md                     # always-loaded conventions
├── .claude/
│   ├── workflow.json             # committed; {"v":1, "mode":"full|light|off"}
│   ├── workflow-state.json       # gitignored; per-session state
│   └── rules/                    # path-scoped guidance, auto-loads on file match
│       ├── tests.md              # paths: tests/**/*.py
│       ├── engine.md             # paths: engine/**/*.py
│       └── prompts.md            # paths: prompts/**/*.md
└── .beads/                       # bd state (committed)
    ├── issues.jsonl
    └── interactions.jsonl
```

`.claude/workflow-state.json` is per-session ephemera and must be
gitignored. `.claude/workflow.json` is per-project policy and is
committed.

The `.claude/rules/` set above is HAW-specific. Other projects
configure their own rules; see [Path-scoped rules](path-scoped-rules.md).

## Workflow modes

Resolved against `<project>/.claude/workflow.json` and the
`CLAUDE_WORKFLOW_OFF` environment variable.

| Mode | Hooks | Skills | Status line |
|---|---|---|---|
| `full` | All fire | Recipe runs | Populated |
| `light` | Informational only (close-capture never blocks) | Recipe runs with reduced ceremony + warning | Populated |
| `off` | Silent | Recipe refuses; `session-startup` skipped | Empty |

Resolution priority (first match wins):

1. `CLAUDE_WORKFLOW_OFF=1` → `off`
2. `<project>/.claude/workflow.json` `.mode` field → that value
3. Default → `full`

## State file + status line

State file at `<project>/.claude/workflow-state.json`:

```json
{
  "v": 1,
  "mode": "full",
  "activity": "feature",
  "bead": "loom-1ab",
  "stage": "tdd-green",
  "updated": "2026-05-03T06:30:00Z"
}
```

| Field | Domain |
|---|---|
| `activity` | `bug` / `feature` / `refactor` / `research` / `cleanup` / `docs` / `task` / `epic` / `idle` |
| `stage` | `idle` / `claim` / `research` / `tdd-red` / `tdd-green` / `verify` / `review` / `commit` / `wrap-up` / `close` |
| `updated` | ISO-8601 UTC timestamp |

Status line (configured in `~/.claude/settings.json` `statusLine`):

```
WORKFLOW: full | feature:tdd-green | bead:1ab | 14m
```

Empty string outside beads workspaces or when mode is `off`.

## Workflow state CLI

```bash
~/.claude/scripts/workflow-state mode               # show resolved mode
~/.claude/scripts/workflow-state show               # full state JSON
~/.claude/scripts/workflow-state set stage=verify   # update stage
echo '{"v":1,"mode":"light"}' > .claude/workflow.json   # change mode
```

## MemPalace location

- One palace per project at `~/.mempalace/<project-name>/`.
- Chroma DB + KG SQLite + diary all under that root.

## Cross-references

- Bypass mechanisms: [bd CLI](bd-cli.md#bypass-and-escape-hatches) and
  [How-to: switch workflow modes](xref:how-to/switch-workflow-modes.md).
- Rationale for the four-axis split: [Mental model](xref:explanation/mental-model.md).
