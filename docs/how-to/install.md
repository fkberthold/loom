# Install loom

This guide installs loom into `~/.claude/` so its skills, slash
commands, hooks, agents, and helpers are picked up by Claude Code.

## Prerequisites

- [Claude Code](https://claude.com/code) installed
- [`bd` (beads)](https://github.com/steveyegge/beads) installed and on `PATH`
- [MemPalace](https://github.com/MemPalace/mempalace) installed and configured
- Plugins enabled: `beads`, `mempalace`, `superpowers`, `beadpowers`,
  `context7-plugin`
- `jq` on `PATH` (used by hooks for JSON parsing)

## Install

```bash
cd ~/repos/loom
./install.sh
```

The installer:

1. Backs up any existing `~/.claude/{skills,agents,commands,hooks,lib,scripts}/<file>`
   that loom owns, suffixing `.pre-loom.bak`
2. Symlinks loom's files into `~/.claude/...` so edits in this repo
   take effect immediately for the current session
3. Merges `settings.snippet.json` into `~/.claude/settings.json`
   (additive — preserves your existing keys)

## Verify

```bash
ls -la ~/.claude/skills/session-startup
# Expect a symlink pointing into ~/repos/loom/skills/session-startup/

~/.claude/scripts/workflow-state mode
# Expect a single word: full / light / off
```

Open a new Claude Code session in any beads workspace; the
`SessionStart` hook fires `bd prime` and (for unconfigured beads
workspaces) the workflow-mode onboarding prompt.

## Uninstall

```bash
cd ~/repos/loom
./uninstall.sh
```

Removes the symlinks and restores any `.pre-loom.bak` backups.

## Troubleshooting

- **Symlink target missing** — `install.sh` requires `mkdir -p` for
  any new skill subdirectory under `~/.claude/skills/`. If a fresh
  install fails for a skill that didn't exist before, `mkdir -p
  ~/.claude/skills/<name>` and re-run the installer. (Tracked under
  the `install.sh-rename-deploy-gaps` MemPalace drawer.)
- **Settings merge clobbered a key** — `install.sh` is additive but
  not a deep-merge for arrays; review your `~/.claude/settings.json`
  diff after install.
