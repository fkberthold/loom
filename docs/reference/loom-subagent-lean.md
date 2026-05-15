# `LOOM_SUBAGENT_LEAN` env var

Force loom-owned SessionStart hooks into slim mode regardless of
payload-based subagent detection. Intended for app code wrapping
subprocess Claude Code invocations that want deterministic slim
emission even when transcript markers (`isSidechain` / `parentUuid`)
are absent or misclassified.

Shipped under loom-b1l. Companion to loom-w58 (the
payload-based detector).

## Contract

| State                               | Behavior                                    |
|-------------------------------------|---------------------------------------------|
| `LOOM_SUBAGENT_LEAN=1` (literal `1`)| Force slim — every loom SessionStart hook exits 0 silently |
| `LOOM_SUBAGENT_LEAN` unset          | Payload-based detection (loom-w58) applies as usual |
| `LOOM_SUBAGENT_LEAN=0`              | Treated as unset — no override               |
| `LOOM_SUBAGENT_LEAN=yes` / `=true`  | Treated as unset — only literal `1` triggers |
| `LOOM_SUBAGENT_LEAN=` (empty)       | Treated as unset                             |

The conservative-match rule (only literal `1`) avoids surprise from
shell-style truthy values; the env var is opt-in and intended to be
set explicitly by wrapper code.

## Affected hooks

All loom-owned SessionStart hooks honor the env var:

- `hooks/workflow-mode-onboarding.sh` — onboarding preamble (mode picker)
- `hooks/bd-prime-wrapper.sh` — `bd prime` output

The override lives inside `lib/subagent-detect.sh`'s
`loom_is_subagent_payload` function, so any future SessionStart hook
that sources the detector inherits the env-var contract for free.

## Example: app-code wrapper

```bash
# Wrapping a subprocess Claude Code invocation from app code that
# already supplies its own brief — suppress the onboarding preamble
# and bd-prime memories block to save ~30 KB of SessionStart prefix.
LOOM_SUBAGENT_LEAN=1 claude code --print "..."
```

This mirrors the savings from loom-w58 (~21 KB per detected subagent
spawn) but applies deterministically, regardless of whether Claude
Code populates the transcript markers the heuristic relies on.

## Relationship to loom-w58

loom-w58 (the payload-based detector) ships heuristic detection of
subagent context from the SessionStart hook's stdin JSON: any of
`isSidechain == true`, `parentUuid != null`, or
`source ~= subagent` (case-insensitive) triggers slim emission.

loom-b1l (this env var) adds an out-of-band override for the cases
the heuristic misclassifies. The two compose orthogonally — the env
var short-circuits before payload inspection, so setting both is
harmless.

## Testing

```bash
bash lib/tests/sessionstart-subagent-lean-env.test.sh
```

Fifteen fixture tests cover: env-var force-emit on both affected
hooks, conservative-match for non-`1` values, detector-function
direct invocation, and composition with existing payload signals.

## See also

- [`hooks/index.md`](hooks/index.md) — full hook inventory
- [`bd-prime-wrapper.md`](bd-prime-wrapper.md) — companion SessionStart hook
- `lib/subagent-detect.sh` — detector function source
- `lib/tests/sessionstart-subagent-skip.test.sh` — loom-w58 payload-detector tests
