# Install loom

To install loom into `~/.claude/` so its skills, slash commands,
hooks, agents, and helpers are picked up by Claude Code, follow
these steps.

## Precondition

- [Claude Code](https://claude.com/code) installed.
- [`bd` (beads)](https://github.com/steveyegge/beads) installed and
  on `PATH`.
- Loom's Dolt-backed memory server set up (`memory-server/`) and
  registered as the `mempalace` MCP server in `~/.claude/settings.json`
  (see `memory-server/mcp_server/server.py`). This replaces the
  upstream [MemPalace](https://github.com/MemPalace/mempalace) server
  as of loom-40ec.6.4; the `mempalace_*` tool names are unchanged.
- Plugins enabled: `beads`, `mempalace`, `superpowers`, `beadpowers`,
  `context7-plugin`.
- `jq` on `PATH` (used by hooks for JSON parsing).

## Steps

1. **Clone the repo and run the installer.**
   ```bash
   cd ~/repos/loom
   ./install.sh
   ```

2. **Let the installer back up, symlink, and merge.** It performs
   three actions in order:
   - Backs up any existing
     `~/.claude/{skills,agents,commands,hooks,lib,scripts}/<file>`
     that loom owns, suffixing `.pre-loom.bak`.
   - Symlinks loom's files into `~/.claude/...` so edits in this
     repo take effect immediately for the current session.
   - Merges `settings.snippet.json` into `~/.claude/settings.json`
     additively (existing keys preserved).

3. **Verify the symlinks resolved.**
   ```bash
   ls -la ~/.claude/skills/session-startup
   # Expect a symlink pointing into ~/repos/loom/skills/session-startup/
   ```

4. **Verify the workflow-state CLI works.**
   ```bash
   ~/.claude/scripts/workflow-state mode
   # Expect a single word: full / light / off
   ```

5. **Open a fresh Claude Code session in any beads workspace.** The
   `SessionStart` hook fires `bd prime` and (for unconfigured beads
   workspaces) the workflow-mode onboarding prompt.

## Outcome

Loom's primitives are live in `~/.claude/`. Skills, hooks, slash
commands, and agents are available in any new session. Edits to
files under `~/repos/loom/` propagate immediately via the symlinks.

## Uninstall

To reverse the install:

```bash
cd ~/repos/loom
./uninstall.sh
```

Removes the symlinks and restores any `.pre-loom.bak` backups.

## Troubleshooting

- **Symlink target missing.** `install.sh` requires `mkdir -p` for
  any new skill subdirectory under `~/.claude/skills/`. If a fresh
  install fails for a skill that did not exist before, run
  `mkdir -p ~/.claude/skills/<name>` and re-run the installer.
- **Settings merge clobbered a key.** `install.sh` is additive but
  not a deep-merge for arrays; review your `~/.claude/settings.json`
  diff after install.

## Related

- For the layout of files inside `~/.claude/` after install, see
  [reference: architecture](../reference/installed-files.md).
- For why loom uses symlinks rather than copies, see
  [explanation: mental model](../explanation/mental-model.md).
