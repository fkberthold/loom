#!/usr/bin/env bash
# PreToolUse hook for `bd update --claim`.
#
# When the agent is about to claim a beads issue:
#   1. Inject a reminder to dispatch the bug-family-researcher subagent
#      BEFORE proceeding to design/code.
#   2. Update <project>/.claude/workflow-state.json with bead + activity
#      (from bd type) + stage=claim.
#
# Mode-aware (per workflow-infra v1.5):
#   full   → fire reminder + write state.
#   light  → silent (no reminder, no state write).
#   off    → silent.
#
# Non-blocking (exit 0) — advisory only.

set -euo pipefail

INPUT=$(cat)

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"
TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
CMD=$(json_get '.tool_input.command' 'command' "$INPUT")

# Only fire on Bash + bd update --claim pattern.
[ "$TOOL" = "Bash" ] || exit 0
echo "$CMD" | grep -qE '(^|[;&|]|\n)[[:space:]]*bd[[:space:]]+update[[:space:]]+.*--claim' || exit 0

# Mode check.
# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"
MODE=$(workflow_resolve_mode "$PWD")
[ "$MODE" = "full" ] || exit 0

# Extract bead-id (best-effort).
BEAD_ID=$(echo "$CMD" | grep -oE '[a-z][a-z0-9-]*-[a-z0-9]+\.?[a-z0-9]*' 2>/dev/null | head -1 || true)

# Update state file: best-effort activity from bd type, plus bead + stage=claim.
if [ -n "${BEAD_ID:-}" ]; then
  ACTIVITY=task
  if command -v bd >/dev/null 2>&1; then
    BD_TYPE=$(bd show "$BEAD_ID" 2>/dev/null \
      | grep -oE 'Type:[[:space:]]+[a-z]+' \
      | head -1 \
      | sed -E 's/Type:[[:space:]]+//' || true)
    case "$BD_TYPE" in
      bug|feature|task|epic) ACTIVITY="$BD_TYPE" ;;
    esac
  fi
  workflow_state_set --start-dir="$PWD" "activity=$ACTIVITY" "bead=$BEAD_ID" "stage=claim" \
    >/dev/null 2>&1 || true
fi

# Output a system-reminder (lands in agent context).
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "About to claim ${BEAD_ID:-<bead>}. Per the workflow-infrastructure plan (MemPalace drawer 'WORKFLOW INFRASTRUCTURE PLAN', hundred_acre_woods/decisions): BEFORE designing the fix, dispatch the bug-family-researcher subagent (~/.claude/agents/bug-family-researcher.md) to surface prior art for this bead's bug family. Mid-design MemPalace search caught the 0qw → huu.15.2 lineage on 2026-05-02 and reshaped the fix from defensive coercion to convention alignment. Skip this only if the bug is truly novel territory."
  }
}
EOF

exit 0
