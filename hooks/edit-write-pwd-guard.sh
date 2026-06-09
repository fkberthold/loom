#!/usr/bin/env bash
# PreToolUse hook for Edit / Write / MultiEdit. Blocks the recurring
# loom-path-leak where a worker dispatched into an isolated worktree
# Edit/Write/MultiEdit's a path that resolves OUTSIDE the worktree
# (landing in the parent repo / MAIN instead).
#
# Closes loom-ymc. Hits 5x in the 2026-05-13 PM session alone.
# Failure modes covered:
#   Mode 1 — absolute-path-in-brief leak (worker uses /home/frank/...)
#   Mode 2 — cwd-drift intentional main-side work (catches when cwd
#            stays in worktree but absolute path targets main)
#   Mode 4 — relative-path resolution surprise (relative path
#            resolves to MAIN via ../ or symlink)
# Out of scope: Mode 3 (bd-state regression — covered by loom-x4m + 8vc).
#
# Resolution rules:
#   - tool not in {Edit, Write, MultiEdit} → exit 0
#   - cwd is NOT in a linked worktree → exit 0
#   - tool_input.file_path is empty → exit 0 (tool will reject)
#   - resolved (realpath'd) target is under worktree root → exit 0
#   - otherwise → exit 2 with explanatory message
#
# Bypass:
#   LOOM_EDIT_WRITE_GUARD_SKIP=1
#     For intentional cross-tree ops (e.g. merge prep from worktree).

set -uo pipefail

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"

if loom_env_enabled LOOM_EDIT_WRITE_GUARD_SKIP; then
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

# Locate worktree-detect.sh: prefer install path, fall back to repo-relative
# (so the test runner doesn't depend on install.sh having run).
DETECT_LIB=""
if [ -f "$HOME/.claude/lib/worktree-detect.sh" ]; then
  DETECT_LIB="$HOME/.claude/lib/worktree-detect.sh"
elif [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/worktree-detect.sh" ]; then
  DETECT_LIB="$LOOM_TEST_LIB_DIR/worktree-detect.sh"
fi
[ -n "$DETECT_LIB" ] || exit 0  # can't detect → fail open

# shellcheck source=../lib/worktree-detect.sh
. "$DETECT_LIB"

# Not in a linked worktree → no guard needed.
loom_is_git_worktree "$PWD" || exit 0

# Worktree root (real path).
WT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
WT_REAL=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$WT_ROOT" 2>/dev/null) || WT_REAL="$WT_ROOT"

# Target: absolute → as-is; relative → against $PWD.
case "$PATH_RAW" in
  /*) TARGET="$PATH_RAW" ;;
  *)  TARGET="$PWD/$PATH_RAW" ;;
esac

# Canonicalize (resolves .., symlinks, etc.) BUT allow nonexistent
# targets (Write may create new files). Use python's os.path.realpath
# which canonicalizes the existing parent chain and leaves the leaf.
TARGET_REAL=$(python3 -c "
import os, sys
p = sys.argv[1]
# Resolve the parent that exists, then re-append the unresolved tail.
parts = p.split('/')
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

# Allow if target is inside (or equal to) the worktree root.
case "$TARGET_REAL/" in
  "$WT_REAL/"*) exit 0 ;;
esac

# Leak detected.
cat >&2 <<EOF
[edit-write-pwd-guard] BLOCKED: $TOOL refused.

  file_path = $PATH_RAW
  resolves to = $TARGET_REAL
  worktree root = $WT_REAL

The target is OUTSIDE the current worktree. This is the recurring
loom-path-leak (loom-ymc): a worker in an isolated worktree about
to write into the parent repo / MAIN.

To fix: recast the path relative to the worktree root, OR use an
absolute path under $WT_REAL.

To bypass intentionally (e.g. cross-tree merge prep), set
LOOM_EDIT_WRITE_GUARD_SKIP=1 in the worker env and retry.
EOF
exit 2
