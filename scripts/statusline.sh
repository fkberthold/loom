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

# Resolve script's lib dir relative to this script (works for symlinked
# install at ~/.claude/scripts/ AND in-repo / worktree paths).
__SL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__SL_LIB_DIR="$__SL_SCRIPT_DIR/../lib"
# shellcheck source=../lib/workflow-state.sh
. "$__SL_LIB_DIR/workflow-state.sh"
# shellcheck source=../lib/workflow-config.sh
. "$__SL_LIB_DIR/workflow-config.sh"

# Build the [GUEST] prefix when guest mode is active. Empty when inactive.
# bd_mode=host     → "[GUEST] "
# bd_mode=personal → "[GUEST/personal-bd] "
# bd_mode=none     → "[GUEST/no-bd] "
__sl_guest_prefix() {
  local cwd="$1"
  workflow_config_guest_active "$cwd" || return 0
  local bd_mode
  bd_mode=$(workflow_config_guest_get bd_mode "$cwd")
  case "$bd_mode" in
    personal) printf '[GUEST/personal-bd] ' ;;
    none)     printf '[GUEST/no-bd] ' ;;
    *)        printf '[GUEST] ' ;;
  esac
}

ROOT=$(workflow_project_root "$CWD")

# Not a beads workspace? Nothing to show.
[ -d "$ROOT/.beads" ] || exit 0

MODE=$(workflow_resolve_mode "$CWD")

# off mode: silent.
[ "$MODE" = "off" ] && exit 0

GUEST_PREFIX=$(__sl_guest_prefix "$CWD")

STATE_PATH=$(workflow_state_path "$CWD")
if [ ! -f "$STATE_PATH" ]; then
  printf '%sWORKFLOW: %s | unconfigured' "$GUEST_PREFIX" "$MODE"
  exit 0
fi

ACTIVITY=$(workflow_state_get activity "$CWD")
BEAD=$(workflow_state_get bead "$CWD")
STAGE=$(workflow_state_get stage "$CWD")
UPDATED=$(workflow_state_get updated "$CWD")
PAR=$(workflow_state_get parallel_candidates "$CWD")
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
  printf '%sWORKFLOW: %s | idle' "$GUEST_PREFIX" "$MODE"
else
  printf '%sWORKFLOW: %s | %s:%s | %s' "$GUEST_PREFIX" "$MODE" "$ACTIVITY" "$STAGE" "$BEAD_CHIP"
fi

[ -n "$AGE" ] && printf ' | %s' "$AGE"

# Parallel-dispatch cue (loom-z3m.5): surface "PAR:N" when seam-scan
# found N>0 parallelizable siblings at claim time.
if [ -n "$PAR" ] && [ "$PAR" != "0" ] && [ "$PAR" != "null" ]; then
  printf ' | PAR:%s' "$PAR"
fi

printf '\n'
