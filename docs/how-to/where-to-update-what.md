# Where to update what

To change a piece of loom's behavior, edit the file listed below
for that surface.

## Precondition

- You have already decided what you want to change (the *what*).
- This page tells you the *where* — the canonical edit surface.

## Lookup table

| You want to update | Edit this |
|---|---|
| The bug-shaped variable middle | `~/.claude/skills/bugfix-a-bead/SKILL.md` |
| Any other activity-shaped variable middle | `~/.claude/skills/<shape>-a-bead/SKILL.md` |
| Cross-activity lifecycle phases (A/B/C/D) | `~/.claude/skills/bead-lifecycle-shell/SKILL.md` |
| Cold-start ritual | `~/.claude/skills/session-startup/SKILL.md` |
| Slash command behavior | `~/.claude/commands/<name>.md` |
| Subagent prompt | `~/.claude/agents/<name>.md` |
| Hook behavior (the script) | `~/.claude/hooks/<name>.sh` |
| Hook registration | `~/.claude/settings.json` (`hooks.PreToolUse[matcher=Bash]`) |
| Mode resolution / state-file lib | `~/.claude/lib/workflow-mode.sh`, `~/.claude/lib/workflow-state.sh` |
| Status line script | `~/.claude/scripts/statusline.sh` |
| State-file CLI | `~/.claude/scripts/workflow-state` |
| Permission allowlist | `~/.claude/settings.json` `permissions.allow` |
| Project workflow mode | `<project>/.claude/workflow.json` `.mode` |
| Project conventions (always-on) | `<project>/CLAUDE.md` |
| Path-scoped conventions | `<project>/.claude/rules/<area>.md` |
| Project tribal one-liners | `bd remember "<insight>"` |
| Multi-paragraph decision | `mempalace_add_drawer` |
| Entity relationship | `mempalace_kg_add` |
| Personal session note | `mempalace_diary_write` |

## Edit-in-place

Files under `~/.claude/...` that loom owns are symlinks into
`~/repos/loom/`. Editing either path changes the underlying file.
Settings hot-reload picks up hook-registration changes mid-session;
skill content reloads fresh per session.

## Outcome

The edit lands at the canonical surface. The change takes effect
on the next event that loads the surface (next hook fire, next
skill load, next session, etc.).

## Related

- For the surfaces themselves and what they do, see
  [reference: skills](../reference/skills/index.md),
  [reference: commands](../reference/slash-commands/index.md),
  [reference: hooks](../reference/hooks/index.md).
- For why surfaces are split this way (skill vs hook vs command),
  see [explanation: mental model](../explanation/mental-model.md).
