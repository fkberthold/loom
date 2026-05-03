#!/usr/bin/env bash
# statusline.sh — Claude Code statusLine command target.
#
# Reads <project>/.claude/workflow.json + workflow-state.json from the
# current working directory and prints a one-line status:
#   WORKFLOW: <mode> | <activity>:<stage> | bead:<short-id> | <updated-age>
# Or, when uninitialized:
#   WORKFLOW: <mode> | unconfigured
# Or, when not in a beads workspace or mode=off:
#   (nothing)

set -u

INPUT=""
if [ -t 0 ]; then
  : # no stdin in interactive smoke; fall back to PWD below
else
  INPUT=$(cat 2>/dev/null || true)
fi

CWD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .workspace.current_dir // ""' 2>/dev/null || true)
fi
CWD="${CWD:-$PWD}"

# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"

ROOT=$(workflow_project_root "$CWD")

# Not a beads workspace? Nothing to show.
[ -d "$ROOT/.beads" ] || exit 0

MODE=$(workflow_resolve_mode "$CWD")

# off mode: silent.
[ "$MODE" = "off" ] && exit 0

STATE_PATH=$(workflow_state_path "$CWD")
if [ ! -f "$STATE_PATH" ]; then
  printf 'WORKFLOW: %s | unconfigured' "$MODE"
  exit 0
fi

ACTIVITY=$(workflow_state_get activity "$CWD")
BEAD=$(workflow_state_get bead "$CWD")
STAGE=$(workflow_state_get stage "$CWD")
UPDATED=$(workflow_state_get updated "$CWD")
ACTIVITY="${ACTIVITY:-idle}"
STAGE="${STAGE:-idle}"

# Compact bead chip — strip <project>- prefix when it matches the workspace.
BEAD_CHIP="bead:none"
if [ -n "$BEAD" ] && [ "$BEAD" != "null" ]; then
  PROJECT_PREFIX=$(basename "$ROOT")
  SHORT_BEAD="${BEAD#${PROJECT_PREFIX}-}"
  BEAD_CHIP="bead:$SHORT_BEAD"
fi

# Updated-age (best-effort; GNU date).
AGE=""
if [ -n "$UPDATED" ]; then
  UPDATED_TS=$(date -d "$UPDATED" +%s 2>/dev/null || true)
  if [ -n "$UPDATED_TS" ] && [ "$UPDATED_TS" -gt 0 ]; then
    NOW_TS=$(date -u +%s)
    DIFF=$((NOW_TS - UPDATED_TS))
    if   [ "$DIFF" -lt 60 ];    then AGE="${DIFF}s"
    elif [ "$DIFF" -lt 3600 ];  then AGE="$((DIFF / 60))m"
    elif [ "$DIFF" -lt 86400 ]; then AGE="$((DIFF / 3600))h"
    else                              AGE="$((DIFF / 86400))d"
    fi
  fi
fi

if [ "$ACTIVITY" = "idle" ] && [ "$STAGE" = "idle" ]; then
  printf 'WORKFLOW: %s | idle' "$MODE"
else
  printf 'WORKFLOW: %s | %s:%s | %s' "$MODE" "$ACTIVITY" "$STAGE" "$BEAD_CHIP"
fi

[ -n "$AGE" ] && printf ' | %s' "$AGE"

printf '\n'
