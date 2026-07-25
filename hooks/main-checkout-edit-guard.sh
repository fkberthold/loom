#!/usr/bin/env bash
# PreToolUse hook for Edit / Write / MultiEdit. Blocks CENTRAL from
# hand-editing a source/test file directly in the MAIN checkout while a
# bead is in_progress — the work belongs in a worktree.
#
# Closes loom-vr6k.
#
# THE GAP. hooks/edit-write-pwd-guard.sh (loom-ymc) is inert from the
# main checkout BY DESIGN: its own resolution rules say "cwd is NOT in a
# linked worktree -> exit 0". It models the WORKER->MAIN leak — cwd sits
# in a worktree and the target path escapes it. This hook is the exact
# INVERSE: cwd sits in MAIN and the target stays in MAIN, when loom's
# one-bead = one-branch = one-worktree convention says the edit should
# have happened in a worktree. Nothing covered that.
#
# Live instance: 2026-07-24 in liza_base, central wrote a P0 bug's RED
# test directly into the main checkout, caught itself only after the
# fact, and the user had to say "put it on a working tree" on the very
# next bead. Three gates were down; this is one of them.
#
# POSTURE: BLOCK with bypass (gate-don't-advise, loom-wj26.1). The work
# either belongs in a worktree or it does not, so this is a CORRECTNESS
# INVARIANT, not an attended decision a human should weigh in on — which
# is what separates it from nudge-not-block UX (loom-yb5). The bypass env
# var is deliberately PROMINENT in the block message: CLAUDE.md waves
# inline work through when the change is <= ~15 lines AND touches a
# single non-test file AND adds no new test, and that legitimate case
# must have an obvious escape hatch rather than feeling like a wall.
#
# Resolution rules (first match wins, all fail-open):
#   - LOOM_MAIN_CHECKOUT_GUARD_SKIP=1 (literal "1")   -> exit 0
#   - tool not in {Edit, Write, MultiEdit}            -> exit 0
#   - tool_input.file_path empty                      -> exit 0
#   - lib/ helpers unresolvable                       -> exit 0
#   - cwd IS a linked worktree                        -> exit 0
#       (that is edit-write-pwd-guard's domain; never double-block)
#   - cwd is not inside a git repo                    -> exit 0
#   - path is NOT source/test-eligible                -> exit 0
#       (per the shared loom_is_source_or_test predicate, loom-p5ee —
#        which excludes *.md, docs/, *.json outright)
#   - resolved target is OUTSIDE the main checkout    -> exit 0
#   - resolved target is under .worktrees/ or
#     .claude/worktrees/                              -> exit 0
#   - `bd` absent, or no bead in_progress             -> exit 0
#   - otherwise                                       -> exit 2
#
# Bypass:
#   LOOM_MAIN_CHECKOUT_GUARD_SKIP=1
#     Literal "1" only (loom-b1l): =yes / =true / =0 / empty do NOT
#     bypass. For legitimately-inline work per the CLAUDE.md threshold.

set -uo pipefail

# --- lib ladder ------------------------------------------------------
# Precedence: explicit LOOM_TEST_LIB_DIR (worktree-shadow discipline) >
# installed copy > repo-relative copy. LOOM_TEST_LIB_DIR must win, or a
# worktree's tests silently exercise MAIN's installed helpers instead of
# the worktree's — $HOME/.claude/lib/* are install.sh SYMLINKS into MAIN,
# so a HOME-first ladder produces the same dishonest verification
# .claude/rules/dispatched-agents.md documents for Python imports.
# The repo-relative rung resolves through `readlink -f` so it still lands
# on the repo's lib/ when the hook is reached via an installed symlink.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

# Bypass — literal "1" only (loom-b1l convention).
if loom_env_enabled LOOM_MAIN_CHECKOUT_GUARD_SKIP; then
  exit 0
fi

INPUT=$(cat)

TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
PATH_RAW=$(json_get '.tool_input.file_path' 'file_path' "$INPUT")

# Only guard Edit-class tools.
case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

# Empty file_path → let the underlying tool reject.
[ -n "$PATH_RAW" ] || exit 0

# --- worktree detection ----------------------------------------------
# Same ladder as above.
DETECT_LIB=""
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/worktree-detect.sh" ]; then
  DETECT_LIB="$LOOM_TEST_LIB_DIR/worktree-detect.sh"
elif [ -f "$HOME/.claude/lib/worktree-detect.sh" ]; then
  DETECT_LIB="$HOME/.claude/lib/worktree-detect.sh"
elif [ -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/worktree-detect.sh" ]; then
  DETECT_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/worktree-detect.sh"
fi
[ -n "$DETECT_LIB" ] || exit 0  # can't detect → fail open

# shellcheck source=../lib/worktree-detect.sh
. "$DETECT_LIB"

# cwd IS a linked worktree → the work is already isolated. Whatever the
# target, this hook has nothing to say: an in-worktree edit is correct,
# and a worktree→MAIN leak belongs to edit-write-pwd-guard. Never
# double-block.
if loom_is_git_worktree "$PWD"; then
  exit 0
fi

# Main checkout root. Not a git repo → nothing to protect.
MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$MAIN_ROOT" ] || exit 0
MAIN_REAL=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$MAIN_ROOT" 2>/dev/null) || MAIN_REAL="$MAIN_ROOT"

# --- eligibility ------------------------------------------------------
# SOURCE or TEST only. The predicate lives in lib/loom-hook-helpers.sh
# (`loom_is_source_or_test`, loom-p5ee) and is SHARED with
# hooks/dispatch-nudge.sh — language-aware via the constitution's
# `language.runtime`, with a widened built-in fallback covering
# py/sh/go/js/ts/rb/rs. Its EXCLUDE layer is what makes *.md, docs/**
# and *.json pass through: docs and config edits in main are routine and
# must never be gated. Central hand-writing a TEST in main is the exact
# liza_base incident, so tests are eligible alongside sources.
loom_is_source_or_test "$PATH_RAW" "$PWD" || exit 0

# --- target resolution ------------------------------------------------
case "$PATH_RAW" in
  /*) TARGET="$PATH_RAW" ;;
  *)  TARGET="$PWD/$PATH_RAW" ;;
esac

# Canonicalize, tolerating a not-yet-existing leaf (Write creates files).
TARGET_REAL=$(python3 -c "
import os, sys
p = sys.argv[1]
tail = []
cur = p
while cur and not os.path.exists(cur):
    tail.insert(0, os.path.basename(cur))
    cur = os.path.dirname(cur)
if cur:
    real = os.path.realpath(cur)
    if tail:
        real = os.path.join(real, *tail)
else:
    real = p
print(real)
" "$TARGET" 2>/dev/null) || TARGET_REAL="$TARGET"

# Target outside the main checkout → not this hook's domain.
case "$TARGET_REAL/" in
  "$MAIN_REAL/"*) ;;
  *) exit 0 ;;
esac

# Target already inside a worktree directory → the edit IS worktree
# work, just issued with a main-rooted path. Covers both the Agent
# harness's `.claude/worktrees/agent-<id>/` and loom's own
# `.worktrees/<bead-id>/` convention.
case "$TARGET_REAL" in
  */.claude/worktrees/*|*/.worktrees/*) exit 0 ;;
esac

# --- is a bead actually in_progress? ----------------------------------
# GATE: without a claimed bead there is no "the work belongs in a
# worktree" to assert — routine main-checkout maintenance is fine.
command -v bd >/dev/null 2>&1 || exit 0
IP_LINE=$(bd list --status=in_progress 2>/dev/null | head -1 || true)
[ -n "$IP_LINE" ] || exit 0

# WHICH bead: prefer the `bead` field workflow-state records — that is
# the bead central is actually working; the bd-list scan is a FALLBACK
# for when the field is unset (same precedence hooks/dispatch-nudge.sh
# settled on in loom-p5ee D3). workflow-state is OPTIONAL here: if the
# lib is unresolvable we still have the bd-list fallback, so a missing
# lib degrades the message, never the gate.
IP_BEAD=""
WFS_LIB=""
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  WFS_LIB="$LOOM_TEST_LIB_DIR/workflow-state.sh"
elif [ -f "$HOME/.claude/lib/workflow-state.sh" ]; then
  WFS_LIB="$HOME/.claude/lib/workflow-state.sh"
elif [ -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/workflow-state.sh" ]; then
  WFS_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/workflow-state.sh"
fi
if [ -n "$WFS_LIB" ]; then
  # shellcheck source=../lib/workflow-state.sh
  . "$WFS_LIB"
  IP_BEAD=$(workflow_state_get bead "$PWD" 2>/dev/null || true)
  case "$IP_BEAD" in null) IP_BEAD="" ;; esac
fi

if [ -z "$IP_BEAD" ]; then
  # Fallback: the first line's leading bead-id token. The character
  # class MUST admit `_` and `-` inside the project prefix — bd prefixes
  # like `liza_base-` and `tla-puzzles-` are real, and a class of
  # `[a-z][a-z0-9]*` silently truncated `liza_base-6r49` to `base-6r49`
  # (loom-p5ee D2). The dotted tail keeps child ids (`loom-ig3p.1`).
  IP_BEAD=$(printf '%s' "$IP_LINE" \
    | grep -oE '[a-z][a-z0-9_-]*-[a-z0-9]+(\.[a-z0-9]+)*' | head -1 || true)
fi
[ -n "$IP_BEAD" ] || exit 0

# --- block ------------------------------------------------------------
EXPECTED_WT="$MAIN_REAL/.worktrees/$IP_BEAD"

cat >&2 <<EOF
[main-checkout-edit-guard] BLOCKED: $TOOL refused.

  file_path     = $PATH_RAW
  resolves to   = $TARGET_REAL
  main checkout = $MAIN_REAL
  in_progress   = $IP_BEAD

You are editing a source/test file directly in the MAIN checkout while
$IP_BEAD is in_progress. Loom's convention is one bead = one branch
(frank/$IP_BEAD) = one worktree — the work belongs in a worktree, not in
main's working tree. This is the inverse of the worker->MAIN leak
hooks/edit-write-pwd-guard.sh catches, and it is why a P0 bug's RED test
landed in main on 2026-07-24 (loom-vr6k).

Expected worktree:
  $EXPECTED_WT

To recover:
  git worktree add $EXPECTED_WT -b frank/$IP_BEAD
  cd $EXPECTED_WT
  # re-issue the edit against the worktree copy

Or dispatch the middle instead (the cheaper default):
  /dispatch-middle $IP_BEAD

BYPASS — for legitimately-inline work. CLAUDE.md waves inline through
when the change is <= ~15 lines AND touches a single non-test file AND
adds no new test. Set in the session env and retry:

  LOOM_MAIN_CHECKOUT_GUARD_SKIP=1
EOF
exit 2
