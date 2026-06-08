# Loom env vars

> The two Claude Code env vars loom sets at the project level to
> disable harness defaults that compete with loom's bd + MemPalace
> conventions.

## Summary

Loom configures **two** environment variables in
`<project_root>/.claude/settings.json` — not user-global. Both
disable Claude Code harness defaults that would otherwise spawn
state stores loom already owns (bd for tasks, bd remember +
MemPalace for memory).

| Variable                             | Value     | Disables                                  |
| ------------------------------------ | --------- | ----------------------------------------- |
| `CLAUDE_CODE_ENABLE_TASKS`           | `"false"` | Harness TaskCreate / TodoWrite nudges      |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY`    | `"1"`     | Auto-spawned `MEMORY.md` surrogate         |

The block lives at the JSON top level under `"env"`:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TASKS": "false",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
  }
}
```

## `CLAUDE_CODE_ENABLE_TASKS=false`

### What it disables

The harness's built-in `TaskCreate` / `TaskUpdate` / `TaskList`
tools and the periodic "consider using TaskCreate" reminders that
appear in the conversation as system messages.

### Which loom rule this replaces

Loom's project instructions (`CLAUDE.md`) say:

> Use `bd` for ALL task tracking — do NOT use TodoWrite,
> TaskCreate, or markdown TODO lists

The harness's reminders pull agents toward TaskCreate at the same
moment loom's instructions say "use bd." With the env var unset,
agents see contradictory signals and the in-context reminder
(higher recency) often wins. Setting `CLAUDE_CODE_ENABLE_TASKS=false`
removes the contradiction at the source — TaskCreate isn't an option
to be tempted by because the harness no longer surfaces it.

### Upstream issues

- [anthropics/claude-code#26038](https://github.com/anthropics/claude-code/issues/26038)
  — request to disable Task tools project-by-project.
- [anthropics/claude-code#45986](https://github.com/anthropics/claude-code/issues/45986)
  — discoverability of `CLAUDE_CODE_ENABLE_TASKS` (the env var name is
  not widely documented; this issue is the canonical reference).

## `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`

### What it disables

The harness's auto-spawned `MEMORY.md` file at the project root and
the "I'll remember this in MEMORY.md" surrogate behavior that fires
when the model decides something is worth retaining across sessions.

### Which loom rule this replaces

Loom's project instructions (`CLAUDE.md`) say:

> Use `bd remember` for persistent knowledge — do NOT use MEMORY.md
> files

Loom's design has two layers of persistent memory:

- **`bd remember`** — short, tribal-fact lines pinned to the project
  via the beads tracker. Surfaces via `bd memories <keyword>`.
- **MemPalace drawers** — long-form decisions, status updates, and
  diary entries via MCP-backed semantic search.

`MEMORY.md` would be a third surrogate that bypasses both — an
unsearched markdown file at the project root, drift-prone and
invisible to `bd memories` and to `mempalace_search`. Disabling the
auto-memory feature is what keeps loom's two-layer scheme the only
in-play option.

### Upstream issues

- [anthropics/claude-code#23544](https://github.com/anthropics/claude-code/issues/23544)
  — `CLAUDE_CODE_DISABLE_AUTO_MEMORY` discoverability.
- [anthropics/claude-code#23750](https://github.com/anthropics/claude-code/issues/23750)
  — request for project-level toggle for the auto-memory feature.

## Loom bypass env vars (`LOOM_*_SKIP`)

Separate from the two harness vars above: each loom hook (and a few
scripts) ships an opt-out environment variable. Setting it to the
literal `1` disables that one guard, leaving every other loom guard
in force. These are escape hatches, not configuration — prefer the
narrower per-target bypasses (marker files, `--force` flags) where a
hook offers one.

> Most `LOOM_*_SKIP` vars match the **literal string `1`** only
> (`=yes` / `=true` / `=0` / empty are all rejected, per loom-b1l).
> Hook-installed PreToolUse guards read the env at `claude` fork
> time, so an in-session `export` does NOT take effect — set the var
> before launching `claude`, or use the hook's marker-file bypass
> where one exists.

| Env var | Disables | Reference |
|---|---|---|
| `LOOM_CWD_DRIFT_GUARD_SKIP` | `cwd-drift-guard.sh` — central-op refusal when cwd is inside a worktree | [cwd-drift-guard](cwd-drift-guard.md) |
| `LOOM_BD_WORKTREE_PRESEED_SKIP` | `bd-worktree-preseed.sh` — fresh-worktree dolt preseed | [bd-worktree-preseed](bd-worktree-preseed.md) |
| `LOOM_DISPATCH_NUDGE_SKIP` | `dispatch-nudge.sh` — inline-vs-dispatch nudge (non-blocking) | [Hooks](hooks/index.md) |
| `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP` | `edit-after-failure-guard.sh` — post-failure source-edit block | [edit-after-failure-guard](hooks/edit-after-failure-guard.md) |
| `LOOM_EDIT_WRITE_GUARD_SKIP` | `edit-write-pwd-guard.sh` — out-of-worktree write block | [edit-write-pwd-guard](edit-write-pwd-guard.md) |
| `LOOM_BD_PRECLOSE_STRICT_SKIP` | `bd-preflight-docs-strict.sh` — `mkdocs build --strict` at `bd close`/`bd preflight` | [bd-preflight-docs-strict](hooks/bd-preflight-docs-strict.md) |
| `LOOM_BD_POST_REWRITE_SKIP` | `post-rewrite.sh` — re-export jsonl from dolt after rebase/amend (full no-op) | [bd-state integrity](bd-state-integrity.md) |
| `LOOM_BD_POST_REWRITE_NO_COMMIT` | `post-rewrite.sh` — re-export the working tree but skip the auto-commit | [bd-state integrity](bd-state-integrity.md) |
| `LOOM_PRE_PUSH_MKDOCS_SKIP` | `pre-push-mkdocs-strict.sh` — `mkdocs build --strict` at `git push` (WARN-only anyway) | [Hooks](hooks/index.md) |
| `LOOM_SKILL_REDIRECT_SKIP` | `skill-redirect.sh` — `superpowers:brainstorming` → `beadpowers:brainstorming` redirect | [Hooks](hooks/index.md) |
| `LOOM_SUBAGENT_LEAN` | `bd-prime-wrapper.sh` + `workflow-mode-onboarding.sh` SessionStart hooks (lean subagent payloads, loom-b1l/w58) | [loom-subagent-lean](loom-subagent-lean.md) |

## How `install.sh` wires it

When run from the main loom checkout, `install.sh` deep-merges the
canonical env block into `<loom_root>/.claude/settings.json`. The
merge step lives after the user-global settings.json merge and
before the bd-merge-driver wiring section.

Behavior:

- **Fresh file** — creates `<loom_root>/.claude/settings.json` with
  the env block as its only content.
- **Existing file without `env`** — adds the `env` block; preserves
  every other top-level key.
- **Existing `env` block missing one loom key** — inserts the
  missing key, preserves the present one, preserves every other
  `env.*` key.
- **Existing `env` block with both canonical values** — idempotent
  no-op. No write, no backup.
- **Existing `env` block with a conflicting value for a loom key
  (e.g. `CLAUDE_CODE_ENABLE_TASKS=true`)** — overwrites with loom's
  canonical value. Logs the overwrite to stdout so the user can
  audit. Loom owns these two keys.
- **First overwrite** — writes `.claude/settings.json.pre-loom.bak`
  before mutating. Mirrors the user-global backup pattern at
  `install.sh:230` (loom-7ro). Idempotent runs after the first
  overwrite do NOT re-create the backup; the first backup is the
  authoritative pre-loom state.

The deep merge is performed in python (same shape as the user-global
settings merge — `json.load` + targeted key replacement + `json.dump`
with `indent=2`). Re-running `install.sh` against a canonical state
exits the python step without writing.

## How `/audit-project --apply-onboarding` propagates it

Downstream loom-managed projects (any project that has run
`/audit-project`) get the same env block via item 16 of the
project-onboarder checklist:

1. The `project-onboarder` subagent reads
   `<project_root>/.claude/settings.json` and reports PASS /
   WARN / MISS:
   - **PASS** — both keys present with canonical values.
   - **WARN** — file exists but one or both keys are missing /
     non-canonical.
   - **MISS** — `<project_root>/.claude/settings.json` absent.
2. WARN / MISS suggested-fix lines are tagged with
   `[AUTOFIX:loom-env-block]`.
3. When the user runs `/audit-project --apply-onboarding`, the
   `audit-project` skill walks the report, picks up the
   `[AUTOFIX:loom-env-block]` tag, gates on guest-mode (refuses
   under guest), and applies the same python deep-merge as
   `install.sh` uses against `<loom_root>/.claude/settings.json`.

The two paths are intentionally redundant: `install.sh` covers
loom's own checkout; `/audit-project --apply-onboarding` covers
every other loom-managed project. Both use the same merge shape and
the same backup convention so the file ends up identical regardless
of which path wrote it.

## Verifying

```bash
python3 -c '
import json
d = json.load(open(".claude/settings.json"))
env = d.get("env", {})
print("CLAUDE_CODE_ENABLE_TASKS       =", env.get("CLAUDE_CODE_ENABLE_TASKS", "<MISSING>"))
print("CLAUDE_CODE_DISABLE_AUTO_MEMORY =", env.get("CLAUDE_CODE_DISABLE_AUTO_MEMORY", "<MISSING>"))
'
```

Expected output:

```
CLAUDE_CODE_ENABLE_TASKS       = false
CLAUDE_CODE_DISABLE_AUTO_MEMORY = 1
```

If either prints `<MISSING>` or a non-canonical value, run
`./install.sh` (in the loom repo) or `/audit-project
--apply-onboarding` (in a downstream loom-managed project).

## Lineage

loom-7ro (2026-05-27). Brainstormed after observing that the harness
defaults silently fight loom's bd + MemPalace conventions even when
the project's `CLAUDE.md` says otherwise — agents follow the
higher-recency in-context reminder over the lower-recency project
rule. The env vars remove the contradiction at the configuration
layer instead of relying on agents to resolve it case-by-case.
