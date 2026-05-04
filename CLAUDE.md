# loom — project instructions for Claude Code

> This file is read at session start when working in `~/repos/loom`.
> Loom is the workflow-infrastructure repo (the meta-project). It's
> not a deploy target; it's a collection of skills, hooks, agents,
> commands, and helpers that get installed into `~/.claude/` to shape
> how Claude Code itself works.

## What this repo is

A package of Claude Code primitives that integrates beads + MemPalace
+ superpowers + beadpowers into one disciplined workflow. See
[README.md](README.md) for the user-facing description and the
published docs site (https://fkberthold.github.io/loom/) for the
Diataxis-shaped reference, how-to guides, tutorials, and design
explanation.

**Not a code project**. Loom is mostly markdown (skills, agent
definitions, slash commands) + bash (hooks, helpers, scripts) + JSON
(settings snippets). No Python, no application code.

## Working on loom

### Recipe applies — but lighter

The activity recipes (today: `bugfix-a-bead`; in flight:
`feature-a-bead`, `refactor-a-bead`, `research-a-bead`,
`cleanup-a-bead`, `docs-a-bead`) apply to loom work too — pick the
recipe matching the bead's shape, or invoke `/working-a-bead <id>`
once the router lands. With these adjustments:

- **TDD scales differently for bash.** Use `bats` or shell-fixture
  tests under `lib/tests/`. The `light` workflow mode is appropriate
  for many loom changes (skill text edits, hook tweaks, doc updates).
- **Bug-family search is meta**: prior loom decisions live in this
  repo's beads + the original `hundred_acre_woods/decisions`
  MemPalace wing (where the design was locked 2026-05-02). Search
  both.
- **Capture in MemPalace** — loom decisions go in a new
  `loom/decisions` MemPalace wing (created on first use). Cross-
  reference back to `hundred_acre_woods/decisions` via tunnels when
  the lineage is HAW-rooted.

### Editing primitives

After install, `~/.claude/...` files are SYMLINKS into this repo.
Edit them either in `~/.claude/...` or here in `~/repos/loom/...` —
both paths point at the same underlying files. Changes take effect
immediately for the current session (settings.json file watcher
reloads hook config; skills load fresh per session).

### Beads tracker

This repo has its own `bd` workspace under `.beads/`. Active workflow
infrastructure beads live HERE, not in HAW. The original epic `2st`
(v1) and `bng` (v2) remain in HAW as historical record; new loom-side
work goes in loom's beads.

### MemPalace conventions

Loom decisions go in `loom/decisions` wing (or `loom/<topic>` rooms).
Diary entries can stay in `wing_claude-opus` (per-agent personal
wing). Cross-project tunnels:

- `loom/decisions ↔ hundred_acre_woods/decisions` for lineage to the
  v1/v1.5/v2 design drawers
- `loom/decisions ↔ <other_project>/decisions` when loom work was
  driven by experience in another project

### Testing changes

Most loom changes affect Claude Code's behavior live (hooks +
settings.json hot-reload). To smoke-test:

```bash
# Hook output JSON validation
echo '{"tool_name":"Bash","tool_input":{"command":"bd close foo"}}' | \
  bash hooks/bd-close-capture.sh; echo "EXIT: $?"

# State + statusline round-trip
~/.claude/scripts/workflow-state set stage=verify
bash ~/.claude/scripts/statusline.sh < /dev/null

# Mode resolution
~/.claude/scripts/workflow-state mode
```

For full lifecycle testing (hooks firing on real Claude Code tool
calls), open a fresh session in this repo and exercise the relevant
slash commands.

## Conventions

- **Use loom's own bead tracker for loom work.** Don't file loom
  beads in HAW or any other project.
- **One bead = one branch (`frank/<bead-id>`) = one worktree** when
  the change is non-trivial. Skip worktree for ≤1-line tweaks.
- **Capture decisions** in MemPalace drawers (`loom/decisions`
  room). The drawer is the design source-of-truth; this repo is the
  implementation source-of-truth. When they diverge, the drawer
  wins on intent, the repo wins on what currently works.
- **Status drawers** for incremental delivery — append-only updates
  to the master plan drawer (mirrors the `WORKFLOW INFRASTRUCTURE
  PLAN` pattern from HAW).

## Tools

The `bd`, MemPalace MCP tools, and superpowers/beadpowers skills all
work normally here. The hooks + statusline are loom-installed (this
repo's own files) — meta-recursion is fine, the hooks operate on bd
commands regardless of which project you're in.

## Don't

- Don't commit `~/.claude/settings.json` — it's user-machine-specific
  and contains stuff outside loom's scope.
- Don't commit symlinks — install.sh creates them on a per-machine
  basis. The repo holds the canonical files; symlinks are
  per-installation.
- Don't add HAW-specific content to `docs/` — pages there are
  project-agnostic. HAW-specific examples should mention HAW as one
  example, not as the only example.
- Prefer committing from the main repo path
  (`~/repos/loom/`) over committing from inside a worktree
  (`.worktrees/<bead>/`). The bd pre-commit hook in worktree mode
  has been observed exporting `issues.jsonl` to the worktree root
  instead of (or in addition to) `.beads/issues.jsonl` (loom-22h).
  `/issues.jsonl` is gitignored as a defense, but commits from the
  worktree may still produce surprising state. Workflow: do the
  bead's work in the worktree, then `cd ~/repos/loom && git merge
  --no-ff frank/<bead>` from main.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
