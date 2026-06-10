# Hooks

Source: `hooks/*.sh` in this repository. Each `.sh` file is one hook
script. Most are wired into Claude Code via `~/.claude/settings.json`
— `hooks.PreToolUse` with a `Bash`, `Edit|Write|MultiEdit`, or
`Skill` matcher, and `hooks.SessionStart` for
`workflow-mode-onboarding.sh`. Two (`post-rewrite.sh`,
`pre-push-mkdocs-strict.sh`) are git-native hooks installed into
`.git/hooks/` rather than registered through settings.json. Header
comments at the top of each script document the trigger, mode
behaviour, and block strategy.

| Field | Value |
|---|---|
| Source glob | `hooks/*.sh` |
| Install target | `~/.claude/hooks/<name>.sh` (symlink) |
| Registration file | `~/.claude/settings.json` |
| Catalogue page | [all-hooks.md](all-hooks.md) |

## Inventory

| Hook | Event | Matcher | Block strategy | Bypass |
|---|---|---|---|---|
| `bd-claim-research.sh` | PreToolUse | `Bash` cmd matches `bd update.*--claim` | Non-blocking (exit 0); advisory | Mode `light`/`off` silences |
| `bd-close-capture.sh` | PreToolUse | `Bash` cmd matches `bd close` | Blocks (exit 2) in mode `full` unless bypass | `--force` flag, `BD_CLOSE_FORCE=1`, mode `light`/`off` |
| `bd-preflight-docs-strict.sh` | PreToolUse | `Bash` cmd starts with `bd close` or `bd preflight`, cwd has `mkdocs.yml`, branch diff touches docs-relevant paths | Blocks (exit 2) in mode `full` with first WARNING/ERROR + hint; `light` → exit 0 with WARN | `LOOM_BD_PRECLOSE_STRICT_SKIP=1`; no `mkdocs.yml`; mode `off`; mkdocs absent |
| `bd-prime-wrapper.sh` | SessionStart | n/a | Non-blocking (exit 0); trims `bd prime` memories bloat | Silent on `bd prime` failure; `LOOM_SUBAGENT_LEAN=1` skips entirely |
| `bd-remember-guest-guard.sh` | PreToolUse | `Bash` cmd matches `bd remember` | Blocks (exit 2) when guest mode + host bd | `/loom-guest off` |
| `bd-worktree-preseed.sh` | PreToolUse | `Bash` cmd matches write-class `bd` in a linked worktree | Non-blocking (exit 0); pre-seeds dolt + applies info/exclude defense | `LOOM_BD_WORKTREE_PRESEED_SKIP=1`, sentinel `.beads/.loom-preseeded` |
| `constitution-enforce.sh` | PreToolUse | `Bash` (any cmd) when `.claude/project-constitution.md` exists in the cwd ancestry | Blocks (exit 2) on a positive `forbidden:` / competing-package-manager match with a suggestion; exit 0 on no constitution, missing `yq`, parse error, or no match | `LOOM_CONSTITUTION_SKIP=1` (literal "1"); the constitution's `bypass_patterns:` allow-list (checked first) |
| `context-budget-sensor.sh` | PreToolUse | `Bash` (any cmd) | Non-blocking (always exit 0); classifies context high-water into green/yellow/red → writes `context_pressure` (statusline `CTX:Y`/`CTX:R`) + one-shot wrap-up nudge on tier escalation | `LOOM_CONTEXT_BUDGET_SENSOR_SKIP=1`; `jq` absent / no live transcript → silent exit 0 |
| `cwd-drift-guard.sh` | PreToolUse | `Bash` cmd matches central-op allowlist (`git merge`, `git push`, `bd close`, `bd update`, `bd dolt push`) when cwd is inside `.claude/worktrees/agent-*/` | Blocks (exit 2) with recovery hint | `LOOM_CWD_DRIFT_GUARD_SKIP=1` (literal-1 match) |
| `dispatch-nudge.sh` | PreToolUse | `Edit\|Write\|MultiEdit` on a NUDGE-ELIGIBLE source/test file while a bead is in_progress and `workflow-state get dispatch` is empty | Non-blocking (always exit 0); emits `additionalContext` pointing at `/dispatch-middle`; memoized once-per-bead | `LOOM_DISPATCH_NUDGE_SKIP=1` |
| `edit-after-failure-guard.sh` | PreToolUse | `Edit\|Write\|MultiEdit` when the LAST Bash result in the transcript tail showed a test/build failure and no test file has been edited since (loom-n1q: last-Bash-only TTL) | Blocks (exit 2) with TDD reminder when target is a non-test file | `<project>/.claude/no-edit-after-failure-guard` marker file (loom-n1q); `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1` env var (must be set before `claude` forks); target is itself a test file (auto-allow); git-merge CONFLICT output whitelisted (loom-n1q) |
| `edit-write-pwd-guard.sh` | PreToolUse | `Edit\|Write\|MultiEdit` from a worktree-isolated cwd | Blocks (exit 2) when target resolves outside worktree root | `LOOM_EDIT_WRITE_GUARD_SKIP=1` |
| `git-push-bd-sync.sh` | PreToolUse | `Bash` cmd matches `git push` (excludes `--dry-run`) | Non-blocking (exit 0); advisory | Mode `off` silences |
| `post-rewrite.sh` | git `post-rewrite` (rebase/amend) | n/a — invoked by git, not a tool matcher | Re-exports `.beads/issues.jsonl` from dolt + auto-commits to align jsonl to dolt (loom-yjo) | `LOOM_BD_POST_REWRITE_SKIP=1` (no-op); `LOOM_BD_POST_REWRITE_NO_COMMIT=1` (re-export, skip commit); detached HEAD / staged-changes / no `.beads/` all skip |
| `pre-push-mkdocs-strict.sh` | git `pre-push` | push range touches `docs/`, `mkdocs.yml`, or `skills/` | WARN-only — never blocks; rc=0 even on strict failure (loom-kbo) | `LOOM_PRE_PUSH_MKDOCS_SKIP=1`; mkdocs absent (graceful skip) |
| `pytest-tempdir-prune.sh` | SessionStart | n/a | Non-blocking (exit 0); prunes stale `./tmp/pytest-of-*` dirs older than 24h (project-scoped, `maxdepth 1`) | `LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1` (literal "1"); no `./tmp/` → no-op |
| `skill-redirect.sh` | PreToolUse | `Skill` call whose `tool_input.skill` is a mapped key (e.g. `superpowers:brainstorming`) in a `.beads/`-tracked project | Blocks (exit 2) naming the loom replacement (`beadpowers:brainstorming`) so the model re-picks | `LOOM_SKILL_REDIRECT_SKIP=1` (literal "1"); no `.beads/` dir |
| `workflow-mode-onboarding.sh` | SessionStart | n/a | Non-blocking (exit 0) | Skipped silently outside beads workspaces; subagent payloads (loom-w58) and `LOOM_SUBAGENT_LEAN=1` (loom-b1l) also skip |
| `worktree-bg-inventory.sh` | PreToolUse | `Bash` (any cmd) | Non-blocking (always exit 0); inventories orphan agent worktrees + leftover background procs → statusline `WT/BG:N` chip + nudge to `/cleanup-orphans` | `LOOM_WORKTREE_BG_INVENTORY_SKIP=1` |

> **Not a PreToolUse hook, but related:** `scripts/bd-merge-driver.sh`
> is a git **merge driver** (registered via `.gitattributes`
> `.beads/issues.jsonl merge=bd-export`, wired by `install.sh`), not
> a `hooks/*.sh` script. It regenerates `.beads/issues.jsonl` from
> the authoritative dolt store on every `git merge` (loom-4um). It
> composes with `post-rewrite.sh` (rebase/amend path) and
> `bd-worktree-preseed.sh` (worktree path) — dolt is the source of
> truth across all three. See [bd-state integrity](../bd-state-integrity.md).

All hooks are mode-aware. Mode resolution is documented in
[Installed files](../installed-files.md).

## Full text

The complete content of every hook script is published verbatim at
[all-hooks.md](all-hooks.md).
