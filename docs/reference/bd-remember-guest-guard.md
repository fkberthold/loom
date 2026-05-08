# `bd-remember-guest-guard` hook

PreToolUse hook that refuses `bd remember` when [loom-guest](../how-to/loom-guest.md)
is active against a **host** project's bd workspace. Without it, a stray
`bd remember` from inside a guest session would write to the host's
`.beads/issues.jsonl` — exactly the contamination loom-guest exists to
prevent.

Design lineage: `drawer_loom_decisions_12d7f8163e8855be037a007c` (loom-n7x,
case A only — the host-bd case).

## Behavior

| guest active | `bd_mode` | command            | result                  |
|--------------|-----------|--------------------|-------------------------|
| no           | n/a       | anything           | passthrough             |
| yes          | `host`    | `bd remember ...`  | **block** (exit 2)      |
| yes          | `host`    | other bd command   | passthrough             |
| yes          | `personal`| `bd remember ...`  | passthrough (own bd ok) |
| yes          | `none`    | `bd remember ...`  | passthrough (bd errors) |

The matcher is word-boundary anchored: `gbd remember`,
`bd remember-not-this`, and `bd-remember-foo` all pass through. The hook
prefers false-allow over false-deny.

## Block message

```
[bd-remember-guest-guard hook] Guest mode + host bd. Refusing `bd remember`
(would commit to host's issues.jsonl). Use a MemPalace drawer instead:

  mempalace_add_drawer wing=<project> room=notes ...

Bypass (rarely correct — implies you actually do want this in the host's bd):
  /loom-guest off
```

## Installation

Add to `~/.claude/settings.json` (per-user — not committed). Append to the
existing PreToolUse Bash matcher block, or create one:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/bd-remember-guest-guard.sh"
          }
        ]
      }
    ]
  }
}
```

The hook source lives at `hooks/bd-remember-guest-guard.sh` in this repo;
`install.sh` symlinks it into `~/.claude/hooks/`.

## Testing

```bash
bash lib/tests/bd-remember-guard.test.sh
```

Nine fixture tests cover the full behavior matrix plus false-positive
avoidance and compound commands.
