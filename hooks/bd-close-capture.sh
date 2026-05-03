#!/usr/bin/env bash
# PreToolUse hook for `bd close`.
#
# Per locked workflow-infrastructure decision (2026-05-02 #2): block
# until drawer + KG + diary are captured. Bypass via --force flag or
# BD_CLOSE_FORCE=1 env var.
#
# Mode-aware (per workflow-infra v1.5):
#   full   → block unless bypass; on bypass/allow, write state stage=close.
#   light  → never block (informational only); still writes state on close.
#   off    → silent; still writes state on close.
#
# Block strategy: exit 2 with stderr message. Claude Code surfaces stderr
# and blocks the tool call. Agent sees the message and either runs
# /wrap-up or sets BD_CLOSE_FORCE=1.

set -euo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
  TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
  CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
fi

# Only fire on Bash + `bd close` pattern.
[ "$TOOL" = "Bash" ] || exit 0
echo "$CMD" | grep -qE '(^|[;&|]|^&&|\n)[[:space:]]*bd[[:space:]]+close([[:space:]]|$)' || exit 0

# Source state lib.
# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"
MODE=$(workflow_resolve_mode "$PWD")

# Extract bead-ids being closed (best-effort).
# Trailing `|| true` is load-bearing under `set -e`: when grep matches nothing,
# non-zero exit propagates and aborts before we emit the block — yielding
# EXIT=1 (silent fail) instead of EXIT=2 (block). Caught 2026-05-02.
BEAD_IDS=$(echo "$CMD" | grep -oE '[a-z][a-z0-9-]*-[a-z0-9]+\.?[a-z0-9]*' 2>/dev/null \
  | grep -v '^bd$' | tr '\n' ' ' || true)

# Bypass paths: --force flag, BD_CLOSE_FORCE=1 env, OR mode != full.
BYPASS=0
if [ "${BD_CLOSE_FORCE:-0}" = "1" ]; then
  BYPASS=1
elif echo "$CMD" | grep -qE '\-\-force'; then
  BYPASS=1
elif [ "$MODE" != "full" ]; then
  BYPASS=1
fi

if [ "$BYPASS" = "1" ]; then
  # Allow the close to proceed; record it in state.
  workflow_state_set --start-dir="$PWD" activity=idle bead= stage=close \
    >/dev/null 2>&1 || true
  exit 0
fi

# full mode + no bypass → block.
cat >&2 <<EOF
[bd-close-capture hook] Blocking bd close for: ${BEAD_IDS:-<beads>}.

Per the workflow-infrastructure plan (MemPalace drawer 'WORKFLOW
INFRASTRUCTURE PLAN', hundred_acre_woods/decisions; locked decision
#2 on 2026-05-02): bd close should not run until the bead's decision
drawer + KG triples + diary entry have been captured.

Run one of:
  - /wrap-up                  (canonical close ritual; dispatches
                               drawer-author + kg-relationship-extractor
                               subagents and files everything)
  - BD_CLOSE_FORCE=1 bd close <id>  (bypass; use for trivial fixes,
                                     wrong-tracked beads, chore work)
  - bd close <id> --force            (also bypasses)

Workflow-mode bypasses (set in <project>/.claude/workflow.json):
  - mode "light" → never blocks (informational only)
  - mode "off"   → workflow disabled
EOF

exit 2
