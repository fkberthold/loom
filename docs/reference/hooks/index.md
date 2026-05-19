# Hooks

Source: `hooks/*.sh` in this repository. Each `.sh` file is one hook
script. The hook is wired into Claude Code via `~/.claude/settings.json`
(`hooks.PreToolUse[matcher=Bash]` for the bd hooks, `hooks.SessionStart`
for `workflow-mode-onboarding.sh`). Header comments at the top of
each script document the trigger, mode behaviour, and block strategy.

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
| `bd-prime-wrapper.sh` | SessionStart | n/a | Non-blocking (exit 0); trims `bd prime` memories bloat | Silent on `bd prime` failure; `LOOM_SUBAGENT_LEAN=1` skips entirely |
| `bd-remember-guest-guard.sh` | PreToolUse | `Bash` cmd matches `bd remember` | Blocks (exit 2) when guest mode + host bd | `/loom-guest off` |
| `bd-worktree-preseed.sh` | PreToolUse | `Bash` cmd matches write-class `bd` in a linked worktree | Non-blocking (exit 0); pre-seeds dolt + applies info/exclude defense | `LOOM_BD_WORKTREE_PRESEED_SKIP=1`, sentinel `.beads/.loom-preseeded` |
| `edit-after-failure-guard.sh` | PreToolUse | `Edit\|Write\|MultiEdit` when transcript tail shows a recent test/build failure and no test file has been edited since | Blocks (exit 2) with TDD reminder when target is a non-test file | `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1`; target is itself a test file (auto-allow) |
| `edit-write-pwd-guard.sh` | PreToolUse | `Edit\|Write\|MultiEdit` from a worktree-isolated cwd | Blocks (exit 2) when target resolves outside worktree root | `LOOM_EDIT_WRITE_GUARD_SKIP=1` |
| `git-push-bd-sync.sh` | PreToolUse | `Bash` cmd matches `git push` (excludes `--dry-run`) | Non-blocking (exit 0); advisory | Mode `off` silences |
| `workflow-mode-onboarding.sh` | SessionStart | n/a | Non-blocking (exit 0) | Skipped silently outside beads workspaces; subagent payloads (loom-w58) and `LOOM_SUBAGENT_LEAN=1` (loom-b1l) also skip |

All hooks are mode-aware. Mode resolution is documented in
[Installed files](../installed-files.md).

## Full text

The complete content of every hook script is published verbatim at
[all-hooks.md](all-hooks.md).
