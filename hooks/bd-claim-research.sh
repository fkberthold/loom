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

# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR > installed copy > repo-
# relative fallback (readlink -f so it resolves through an installed
# .git/hooks symlink, loom-fxad). TESTLIB must win, or a worktree's tests
# silently load MAIN's lib/ — ~/.claude/lib/* are symlinks into the main
# checkout, the bash flavor of the loom-rsk Python-import shadow.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi
TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
CMD=$(json_get '.tool_input.command' 'command' "$INPUT")

# Only fire on Bash + bd update --claim pattern.
[ "$TOOL" = "Bash" ] || exit 0
echo "$CMD" | grep -qE '(^|[;&|]|\n)[[:space:]]*bd[[:space:]]+update[[:space:]]+.*--claim' || exit 0

# Mode check.
# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR wins so a worktree's tests
# load the WORKTREE's lib, not MAIN's. No repo-relative rung — that
# preserves this hook's original hard-fail-if-absent posture exactly.
# shellcheck source=../lib/workflow-state.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/workflow-state.sh"
else
  . "$HOME/.claude/lib/workflow-state.sh"
fi
MODE=$(workflow_resolve_mode "$PWD")
[ "$MODE" = "full" ] || exit 0

# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR first, as everywhere. This
# rung is fail-open — if lib/bd-id-extract.sh cannot be found the hook
# falls back to the generic pattern below rather than dying, since it is
# advisory and must never block a claim.
# shellcheck source=../lib/bd-id-extract.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/bd-id-extract.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/bd-id-extract.sh"
elif [ -f "$HOME/.claude/lib/bd-id-extract.sh" ]; then
  . "$HOME/.claude/lib/bd-id-extract.sh"
elif [ -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/bd-id-extract.sh" ]; then
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/bd-id-extract.sh"
fi

# Extract bead-id (best-effort).
#
# Preferred path (loom-6mf7): anchor the scan on the project's LITERAL
# bd prefix via lib/bd-id-extract.sh. A literal prefix is immune by
# construction to the shape question that broke every hand-rolled class
# before it — `liza_base-6r49` no longer truncates to `base-6r49`, and
# `loom-z3m.1.4` keeps its full dotted tail.
#
# Fallback (prefix undetectable — no .beads/issues.jsonl and no usable
# `bd list`): a generic pattern that is underscore-aware AND carries the
# {3,} suffix minimum, so a `[a-z]` grep literal sitting in the command
# no longer parses as the bead ID "a-z" (observed live, loom-bbq7).
BEAD_ID=""
if command -v bd_id_detect_prefix >/dev/null 2>&1; then
  BD_PREFIX=$(bd_id_detect_prefix "$PWD" 2>/dev/null || true)
  if [ -n "$BD_PREFIX" ]; then
    BEAD_ID=$(printf '%s' "$CMD" | bd_id_scan "$BD_PREFIX" 2>/dev/null | head -1 || true)
  fi
fi
if [ -z "$BEAD_ID" ]; then
  BEAD_ID=$(printf '%s' "$CMD" \
    | grep -oE '[a-z][a-z0-9_-]*-[a-z0-9]{3,}(\.[a-z0-9]+)*' 2>/dev/null \
    | head -1 || true)
fi

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
