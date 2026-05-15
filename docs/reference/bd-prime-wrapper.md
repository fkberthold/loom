# `bd-prime-wrapper` hook

SessionStart wrapper around `bd prime` that caps the verbose
`## Persistent Memories` section so the SessionStart prefix stays small.

`bd prime` output in projects with many `bd remember` entries balloons
to ~150 KB because the memories section dumps full drawer-narrative
bodies. That output is pinned into the SessionStart prefix and re-bills
every turn until `/clear`, so a 6-fire session can burn ~900 KB before
dedup. The wrapper trims each entry body to ~200 chars and caps the
whole memories block at ~10 KB; the workflow primer (~5 KB) and any
non-memory sections pass through verbatim.

Design lineage: `drawer_loom_decisions_3eec30046461f0766ac92eec`
(nsb dynamic-phase research — identified bd-prime memories bloat as
the bd-side bloat surface). Shipped under loom-nc2.

## Behavior

| Input shape                                  | Result                                          |
|----------------------------------------------|-------------------------------------------------|
| No `## Persistent Memories` section          | Passthrough verbatim                            |
| Memories block within byte cap, entries short | Passthrough verbatim                            |
| Memories block exceeds byte cap              | Truncate entries + elide overflow + add footer |
| Individual entry body exceeds char cap       | Truncate to char cap, append `...`              |
| `bd prime` exits non-zero                    | Silent exit 0 (never blocks SessionStart)       |

The wrapper always exits 0 — it is informational scaffolding and must
not block session startup.

### Section detection

The memories block opens with a line matching
`^## Persistent Memories\b` and ends at the next top-level `^## ` line
or EOF. Individual entries are detected as `^### <key>` blocks. Any
content outside the memories block (preamble, trailing sections) is
emitted verbatim.

### Truncation footer

When entries are elided or bodies truncated, the wrapper appends a
short note so the agent knows to fetch full bodies on demand:

```
*(... N memory entries elided to keep SessionStart prefix small;
   run `bd memories <keyword>` to fetch full bodies on demand.)*
```

## Configuration

Tuning knobs (env vars; sensible defaults):

| Variable                          | Default | Meaning                                    |
|-----------------------------------|---------|--------------------------------------------|
| `BD_BIN`                          | `bd`    | `bd` binary path (matches the convention used by `bd-close-capture.sh`) |
| `BD_PRIME_ENTRY_TRUNCATE_CHARS`   | `200`   | Per-entry body cap; longer bodies get `...` suffix |
| `BD_PRIME_MEMORIES_MAX_BYTES`     | `10000` | Whole-memories-block cap; overflow entries are elided |
| `LOOM_SUBAGENT_LEAN`              | unset   | When set to `1`, short-circuits the wrapper to silent slim emission (loom-b1l). See [LOOM_SUBAGENT_LEAN](loom-subagent-lean.md). |

The wrapper also honors loom-w58's payload-based subagent detection:
when the stdin JSON carries `isSidechain=true`, `parentUuid != null`,
or `source ~= subagent`, the wrapper exits 0 silently.

## Installation

Wired by `install.sh` into `~/.claude/settings.json` under
`hooks.SessionStart`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOK_DIR/bd-prime-wrapper.sh"
          }
        ]
      }
    ]
  }
}
```

The hook source lives at `hooks/bd-prime-wrapper.sh` in this repo;
`install.sh` symlinks it into `~/.claude/hooks/`.

## Testing

```bash
bash lib/tests/bd-prime-wrapper.test.sh
```

Fourteen fixture tests cover: verbose-input capping, per-entry
truncation, passthrough when no memories section is present,
short-block idempotence, env-var override of both thresholds, and
section-boundary robustness against trailing `## ` sections.

A real-world smoke check against a project with ~100 stored memories
shows the wrapper trimming `bd prime` output from ~150 KB to ~15 KB
(10× reduction) — small enough to fit comfortably in the SessionStart
prefix without dominating context.

## See also

- `hooks/bd-prime-wrapper.sh` — wrapper source
- `lib/tests/bd-prime-wrapper.test.sh` — fixture tests
- [Hooks index](hooks/index.md)
