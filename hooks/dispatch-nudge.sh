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
#   - the target file_path is NUDGE-ELIGIBLE: a SOURCE or TEST file,
#     per the shared `loom_is_source_or_test` predicate in
#     lib/loom-hook-helpers.sh (loom-p5ee). That predicate is
#     LANGUAGE-BLIND: it reads `language.runtime` from the project
#     constitution when one is readable, and falls back to a widened
#     built-in glob list covering py/sh/go/js/ts/rb/rs otherwise. NOT
#     *.md, NOT docs/, NOT config. Central editing a test inline is the
#     same test-author==code-author anti-pattern, so test files nudge
#     too.
# The nudge points central at /dispatch-middle (the cheap command —
# one invocation runs the test-author→implementer pipeline).
# Memoized once-per-bead via a sentinel keyed on the bead workflow-state
# records (NOT `bd list --status=in_progress | head -1`, which names the
# wrong bead whenever a project has N>1 concurrent claims), so it isn't
# per-edit spam while dispatch stays unset.
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

# Precedence: explicit LOOM_TEST_LIB_DIR (worktree-shadow discipline) >
# installed copy > repo-relative copy. LOOM_TEST_LIB_DIR must win, or a
# worktree's tests silently exercise MAIN's installed helpers instead of
# the worktree's — the same dishonest-verification shadow
# .claude/rules/dispatched-agents.md documents for Python imports. Every
# other hook already orders it this way; this one did not (loom-p5ee).
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
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
# A nudge-eligible file is a SOURCE file or a TEST file. Central editing
# a test inline is the same test-author==code-author anti-pattern
# dispatch is meant to prevent, so tests nudge too.
#
# The predicate itself lives in lib/loom-hook-helpers.sh
# (`loom_is_source_or_test`, loom-p5ee) and is SHARED with
# hooks/main-checkout-edit-guard.sh (loom-vr6k). It resolves the
# project's source/test globs HYBRID-style: from the constitution's
# `language.runtime` when one is readable, else from a widened built-in
# list covering py/sh/go/js/ts/rb/rs.
#
# This hook used to inline a loom-shaped heuristic (hooks/*.sh,
# scripts/*, lib/*.sh for source; *_test.* / *.test.* for tests). Python
# tests are `test_*.py` — a PREFIX, not a suffix — so in a Python
# project neither sources nor tests matched and the hook was 100% dark.
is_nudge_eligible() {
  loom_is_source_or_test "$1" "$PWD"
}

is_nudge_eligible "$PATH_RAW" || exit 0

# --- Locate the workflow-state lib ----------------------------------
# Same precedence as the helpers ladder above: LOOM_TEST_LIB_DIR (so a
# worktree's tests read the worktree's lib, and so the test runner
# doesn't need install.sh) > installed copy.
WFS_LIB=""
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  WFS_LIB="$LOOM_TEST_LIB_DIR/workflow-state.sh"
elif [ -f "$HOME/.claude/lib/workflow-state.sh" ]; then
  WFS_LIB="$HOME/.claude/lib/workflow-state.sh"
fi
[ -n "$WFS_LIB" ] || exit 0  # can't read state → fail silent

# shellcheck source=../lib/workflow-state.sh
. "$WFS_LIB"

# --- Identify the in_progress bead ----------------------------------
# GATE: some bead must actually be claimed. `bd list --status=in_progress`
# empty → nothing is being worked → silent.
command -v bd >/dev/null 2>&1 || exit 0
IP_LINE=$(bd list --status=in_progress 2>/dev/null | head -1 || true)
[ -n "$IP_LINE" ] || exit 0

# WHICH bead: prefer the `bead` field workflow-state records — that is
# the bead central is actually working. The bd-list scan is only a
# FALLBACK for when the field is unset (loom-p5ee D3). Keying on
# `bd list | head -1` was wrong: a project with N>1 concurrent claims
# always yields the first-listed bead, never the one being worked, so a
# single nudge permanently suppressed the nudge for every other bead.
IP_BEAD=$(workflow_state_get bead "$PWD" 2>/dev/null || true)
case "$IP_BEAD" in null) IP_BEAD="" ;; esac

if [ -z "$IP_BEAD" ]; then
  # Fallback: the first line's leading bead-id token. The character
  # class MUST admit `_` and `-` inside the project prefix — bd prefixes
  # like `liza_base-` and `tla-puzzles-` are real, and a class of
  # `[a-z][a-z0-9]*` silently truncated `liza_base-6r49` to `base-6r49`,
  # naming a bead that does not exist (loom-p5ee D2). The dotted tail
  # keeps child ids (`loom-ig3p.1`) intact.
  IP_BEAD=$(printf '%s' "$IP_LINE" \
    | grep -oE '[a-z][a-z0-9_-]*-[a-z0-9]+(\.[a-z0-9]+)*' | head -1 || true)
fi
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
