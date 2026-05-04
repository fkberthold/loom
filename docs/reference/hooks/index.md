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
| `git-push-bd-sync.sh` | PreToolUse | `Bash` cmd matches `git push` (excludes `--dry-run`) | Non-blocking (exit 0); advisory | Mode `off` silences |
| `workflow-mode-onboarding.sh` | SessionStart | n/a | Non-blocking (exit 0) | Skipped silently outside beads workspaces |

All hooks are mode-aware. Mode resolution is documented in
[Installed files](../installed-files.md).

## Full text

The complete content of every hook script is published verbatim at
[all-hooks.md](all-hooks.md).
