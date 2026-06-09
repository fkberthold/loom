#!/usr/bin/env bash
# PreToolUse hook: pre-seed bd state when running a write-class `bd`
# command inside a fresh git worktree.
#
# Closes loom-x4m (+ superseded loom-14w): a worktree created via
# `git worktree add` gets a tree copy that includes .beads/, but the
# bd embedded-dolt DB under .beads/embeddeddolt/ is local-not-checked-
# in — so the dolt is EMPTY in the worktree. When the agent runs
# `bd update --claim`, bd writes one-issue state to the empty dolt
# AND auto-exports it to .beads/issues.jsonl, overwriting the
# worktree's full checked-in copy. On merge to main, all other issues
# are LOST.
#
# Fix shape (three layers, applied once per worktree, memoized via
# .beads/.loom-preseeded sentinel):
#   1. `bd import .beads/issues.jsonl` — populate the worktree's
#      local dolt DB from its own checked-in jsonl. After this, bd
#      writes go to the worktree's dolt; subsequent auto-exports to
#      issues.jsonl reflect the full state.
#   2. `bd config set export.git-add false` — tell bd not to auto-
#      stage issues.jsonl during commits. Worktree-local bd state
#      stays out of merge.
#   3. Append `.beads/issues.jsonl` to <worktree>/.git/info/exclude
#      — belt-and-suspenders defense if config layer fails.
#
# Mode-aware: the SKIP env var bypasses entirely. Non-blocking
# (exit 0 always). Read-only bd commands skip pre-seed since they
# don't risk wiping state.
#
# See lib/tests/bd-worktree-preseed.test.sh for fixture coverage.

set -uo pipefail

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"

if loom_env_enabled LOOM_BD_WORKTREE_PRESEED_SKIP; then
  exit 0
fi

INPUT=$(cat)

# Parse tool name + command (jq if available, else grep).
TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
CMD=$(json_get '.tool_input.command' 'command' "$INPUT")

# Bash-only.
[ "$TOOL" = "Bash" ] || exit 0

# Match write-class bd subcommands. Read-only bd commands (show,
# list, ready, stats, blocked, search, memories, etc.) don't risk
# wiping state — skip pre-seed for them so first session-startup
# `bd stats` doesn't churn.
echo "$CMD" | grep -qE '(^|[;&|]|\n)[[:space:]]*bd[[:space:]]+(update|close|create|reopen|dep|delete|defer|supersede|epic|label|comment|remember|forget|import|export)\b' || exit 0

# Resolve git context.
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
if [ "${COMMON_DIR#/}" = "$COMMON_DIR" ]; then
  COMMON_DIR=$(cd "$COMMON_DIR" 2>/dev/null && pwd) || exit 0
fi
MAIN_DIR=$(dirname "$COMMON_DIR")

# Not a linked worktree → no-op.
[ "$TOPLEVEL" != "$MAIN_DIR" ] || exit 0

# Sentinel: pre-seed once per worktree — UNLESS dolt has been wiped
# since the sentinel was created (loom-8vc: stash+rebase can wipe the
# embedded-dolt blob while leaving the untracked sentinel in place).
# Self-heal by re-preseeding when sentinel exists but dolt is empty.
SENTINEL="$TOPLEVEL/.beads/.loom-preseeded"
DOLT_DIR="$TOPLEVEL/.beads/embeddeddolt"
if [ -e "$SENTINEL" ]; then
  # Sentinel present. Skip only if dolt is non-empty (has any files).
  if [ -d "$DOLT_DIR" ] && [ -n "$(find "$DOLT_DIR" -mindepth 1 -type f -print -quit 2>/dev/null)" ]; then
    exit 0
  fi
fi

# Require a checked-in issues.jsonl to seed from.
JSONL="$TOPLEVEL/.beads/issues.jsonl"
[ -f "$JSONL" ] || exit 0

BD_BIN="${BD_BIN:-bd}"

# Layer 1: pre-seed dolt from worktree's own checked-in jsonl.
(cd "$TOPLEVEL" && "$BD_BIN" import "$JSONL" >/dev/null 2>&1) || true

# Layer 2: stop bd from auto-staging issues.jsonl in this worktree.
(cd "$TOPLEVEL" && "$BD_BIN" config set export.git-add false >/dev/null 2>&1) || true

# Layer 3: belt-and-suspenders — info/exclude defense.
GIT_DIR=$(cd "$TOPLEVEL" && git rev-parse --git-dir 2>/dev/null) || GIT_DIR=""
if [ -n "$GIT_DIR" ]; then
  if [ "${GIT_DIR#/}" = "$GIT_DIR" ]; then
    GIT_DIR=$(cd "$TOPLEVEL" && cd "$GIT_DIR" 2>/dev/null && pwd) || GIT_DIR=""
  fi
  if [ -n "$GIT_DIR" ]; then
    EXCLUDE_PATH="$GIT_DIR/info/exclude"
    mkdir -p "$(dirname "$EXCLUDE_PATH")"
    touch "$EXCLUDE_PATH"
    if ! grep -qxF ".beads/issues.jsonl" "$EXCLUDE_PATH"; then
      # Append within a managed block (mirrors lib/info-exclude.sh
      # convention) if no LOOM block exists; otherwise just append
      # the line.
      if ! grep -q '^# BEGIN LOOM' "$EXCLUDE_PATH"; then
        printf '# BEGIN LOOM (managed by loom worktree pre-seed — do not edit)\n.beads/issues.jsonl\n# END LOOM\n' >> "$EXCLUDE_PATH"
      else
        # Insert the pattern inside the existing LOOM block.
        tmp=$(mktemp)
        awk '
          /^# BEGIN LOOM/ { print; print ".beads/issues.jsonl"; next }
          { print }
        ' "$EXCLUDE_PATH" > "$tmp"
        mv "$tmp" "$EXCLUDE_PATH"
      fi
    fi
  fi
fi

# Drop the sentinel last (so a failure mid-setup retries next call).
mkdir -p "$(dirname "$SENTINEL")"
touch "$SENTINEL"

exit 0
