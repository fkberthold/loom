#!/usr/bin/env bash
# PreToolUse hook for Edit / Write / MultiEdit. Nudges the central
# session toward worker-dispatch as the DEFAULT for a RED→GREEN bead.
#
# Component A of epic loom-yb5 (closes loom-h5s). Builds on the
# per-bead `dispatch` field added in T1 (loom-0zr): central records
# how the current bead is being worked via
#   workflow-state set dispatch=worker        # dispatched to a worker
#   workflow-state set dispatch=inline:<reason>  # worked inline, why
# This hook fires while that field is still UNSET and central is about
# to hand-edit a source file — i.e. about to silently default into
# inline work without having made the dispatch-vs-inline call.
#
# Fires (emits additionalContext, ALWAYS exit 0) ONLY when ALL hold:
#   - tool is Edit / Write / MultiEdit
#   - a bead is in_progress (bd list --status=in_progress non-empty)
#   - workflow-state get dispatch is EMPTY
#   - the target file_path is NUDGE-ELIGIBLE: a SOURCE file
#     (hooks/*.sh, scripts/*, lib/*.sh) OR a TEST file
#     (lib/tests/*.test.sh, *_test.*, *.test.*). NOT *.md, NOT
#     docs/, NOT config. Central editing a test inline is the same
#     test-author==code-author anti-pattern, so test files nudge too.
# The nudge points central at /dispatch-middle (the cheap command —
# one invocation runs the test-author→implementer pipeline).
# Memoized once-per-bead via a sentinel keyed on the in_progress id,
# so it isn't per-edit spam while dispatch stays unset.
#
# If dispatch=worker but central is editing a nudge-eligible file (the
# central session doing the worker's job), emit a softer one-line
# reminder instead — not the full nudge, and not memoized (it's a
# live mismatch worth flagging each time it's still unresolved... but
# we keep it light by also memoizing on the same sentinel).
#
# NON-BLOCKING: this hook NEVER blocks. It always exits 0. The
# reminder surfaces as additionalContext (hookSpecificOutput), the
# same mechanism bd-claim-research.sh uses.
#
# Bypass:
#   LOOM_DISPATCH_NUDGE_SKIP=1

set -uo pipefail

# shellcheck source=../lib/loom-hook-helpers.sh
if [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
elif [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
else
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"
fi

if loom_env_enabled LOOM_DISPATCH_NUDGE_SKIP; then
  exit 0
fi

INPUT=$(cat)

TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
PATH_RAW=$(json_get '.tool_input.file_path' 'file_path' "$INPUT")

# Only nudge on Edit-class tools.
case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

# Empty file_path → nothing to classify.
[ -n "$PATH_RAW" ] || exit 0

# --- Nudge-eligible-file heuristic ----------------------------------
# A nudge-eligible file is a SOURCE file or a TEST file:
#   SOURCE: hooks/*.sh, scripts/* (any), lib/*.sh.
#   TEST:   lib/tests/*.test.sh, *_test.* (e.g. bar_test.go),
#           *.test.* (e.g. foo.test.js).
# Central editing a test inline is the same test-author==code-author
# anti-pattern dispatch is meant to prevent, so tests nudge too.
# EXCLUDE: *.md (docs/markdown), docs/* (docs), *.json / config.
# Match on the path's tail so absolute, relative, and worktree-
# prefixed paths all classify identically.
is_nudge_eligible() {
  local p="$1"
  # Excludes apply to everything, including would-be test docs.
  case "$p" in
    *.md|*.json) return 1 ;;
    */docs/*|docs/*) return 1 ;;
  esac
  # Test files — the issue-#2 anti-pattern case.
  case "$p" in
    */lib/tests/*.test.sh|lib/tests/*.test.sh) return 0 ;;
    *_test.*) return 0 ;;
    *.test.*) return 0 ;;
  esac
  # Source files.
  case "$p" in
    */hooks/*.sh|hooks/*.sh) return 0 ;;
    */scripts/*|scripts/*) return 0 ;;
    */lib/*.sh|lib/*.sh) return 0 ;;
  esac
  return 1
}

is_nudge_eligible "$PATH_RAW" || exit 0

# --- Locate the workflow-state lib ----------------------------------
# Prefer the installed copy, fall back to the repo-relative copy via
# LOOM_TEST_LIB_DIR (so the test runner doesn't need install.sh).
WFS_LIB=""
if [ -f "$HOME/.claude/lib/workflow-state.sh" ]; then
  WFS_LIB="$HOME/.claude/lib/workflow-state.sh"
elif [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  WFS_LIB="$LOOM_TEST_LIB_DIR/workflow-state.sh"
fi
[ -n "$WFS_LIB" ] || exit 0  # can't read state → fail silent

# shellcheck source=../lib/workflow-state.sh
. "$WFS_LIB"

# --- Identify the in_progress bead ----------------------------------
# Best-effort: bd list --status=in_progress, take the first line's
# leading bead-id token. Empty output → no claimed bead → silent.
command -v bd >/dev/null 2>&1 || exit 0
IP_LINE=$(bd list --status=in_progress 2>/dev/null | head -1 || true)
[ -n "$IP_LINE" ] || exit 0
IP_BEAD=$(echo "$IP_LINE" | grep -oE '[a-z][a-z0-9]*-[a-z0-9]+(\.[a-z0-9]+)*' | head -1 || true)
[ -n "$IP_BEAD" ] || exit 0

# --- Memoization sentinel -------------------------------------------
# Once per in_progress bead, keyed on the bead id, under the project's
# .claude/. Prevents per-edit spam while dispatch stays unset.
STATE_PATH=$(workflow_state_path "$PWD")
STATE_DIR=$(dirname "$STATE_PATH")
SENTINEL="$STATE_DIR/.loom-dispatch-nudged-$IP_BEAD"
[ -e "$SENTINEL" ] && exit 0

# --- Read the dispatch field ----------------------------------------
DISPATCH=$(workflow_state_get dispatch "$PWD")

case "$DISPATCH" in
  worker)
    # Central editing a nudge-eligible file while the bead is flagged
    # worker-dispatch: the central session is doing the worker's job.
    # Softer reminder.
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    : > "$SENTINEL" 2>/dev/null || true
    MSG="Heads up: ${IP_BEAD} is flagged dispatch=worker, but you are hand-editing a test/source file in the central session. Run \`/dispatch-middle ${IP_BEAD}\` instead, or set \`workflow-state set dispatch=inline:<reason>\` if you meant to work it inline."
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "$MSG"
  }
}
EOF
    exit 0
    ;;
  inline:*)
    # Opt-out already recorded — silent.
    exit 0
    ;;
  ""|null)
    # The nudge case: dispatch undecided + about to hand-edit a
    # test/source file. Point at /dispatch-middle (the cheap command).
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    : > "$SENTINEL" 2>/dev/null || true
    MSG="Default for a RED→GREEN bead is to dispatch the test-author→implementer pipeline via \`/dispatch-middle ${IP_BEAD}\`, or set \`workflow-state set dispatch=inline:<reason>\` to opt out. See bead-lifecycle-shell Dispatch discipline."
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "$MSG"
  }
}
EOF
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
