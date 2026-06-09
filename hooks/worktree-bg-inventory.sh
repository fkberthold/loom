#!/usr/bin/env bash
# worktree-bg-inventory.sh — PreToolUse hook (Bash matcher). A worktree
# + background-process ORPHAN inventory + cleanup nudge.
#
# Closes loom-z3m.7 (feature). Root cause it addresses: the
# finishing-a-development-branch ritual closes the bead and merges, but
# never enumerates live `git worktree` entries or background bash
# processes. Cleanup falls through unless the user nags, and the same
# gap surfaces after a session crash mid-dispatch — orphan worktrees
# (and the background loops the dead worker started) pile up across
# sessions. Surfaced by loom-z3m.1 f4 (loom) + f2 (liza-base, user
# nagged 3x).
#
# WHAT IT DOES
#   On each PreToolUse (Bash), it enumerates:
#     1. WORKTREES — every linked worktree from
#        `git worktree list --porcelain`. An `.claude/worktrees/agent-*`
#        entry is counted an ORPHAN when its `locked claude agent ...
#        (pid <PID>...)` PID is NOT alive (the dispatching agent process
#        exited / crashed and left the worktree behind). The hook's OWN
#        worktree (the cwd) is never counted — a live worker shouldn't
#        flag itself.
#     2. BG PROCS — long-running background bash processes the session
#        spawned, matched by a tunable name-pattern against descendants
#        of the session process group (`bd-post-rewrite`, suite/loop
#        runners — the orphan classes called out in
#        .claude/rules/dispatched-agents.md's concurrency-caution).
#   It writes the total orphan count into workflow-state
#   (`orphan_pressure`) — which statusline.sh renders as WT:N / BG:M —
#   and, on an ESCALATION (a higher count than last recorded), emits a
#   one-shot "stale worktrees/procs piling up — consider running
#   /cleanup-orphans" nudge via additionalContext.
#
# POSTURE — NUDGE, NEVER BLOCK
#   This is a loom INFO/nudge sensor (mirrors context-budget-sensor.sh).
#   It ALWAYS exits 0. It never blocks a tool call (never exit 2). The
#   nudge surfaces as additionalContext (hookSpecificOutput) — the same
#   mechanism bd-claim-research.sh and context-budget-sensor.sh use.
#
# MEMOIZATION
#   The nudge fires once per ESCALATION (the orphan count rising above
#   the last-recorded value), not per-tool. A re-fire at the
#   same-or-lower count is silent (no spam). Memo is the previously
#   recorded orphan_pressure in workflow-state.
#
# Resolution rules:
#   - not in a git repo / `git worktree list` unavailable → the
#     worktree count is 0 (fail open, never errors).
#   - no transcript needed — this sensor reads the live process table +
#     git worktree state, not the session transcript.
#
# Bypass:
#   LOOM_WORKTREE_BG_INVENTORY_SKIP=1
#
# Env overrides (primarily for tuning + tests):
#   LOOM_WORKTREE_PORCELAIN_CMD  command emitting `git worktree list
#                                --porcelain` output (test seam; default
#                                runs the real git command)
#   LOOM_BG_PROC_CMD             command emitting one orphan-bg-proc PID
#                                per line (test seam; default scans the
#                                process table for the bg-proc pattern)
#   LOOM_BG_PROC_PATTERN         regex matched against bg-proc command
#                                lines (default: bd-post-rewrite|loom-.*loop)

set -uo pipefail

# Lib resolution: an explicitly-set LOOM_TEST_LIB_DIR wins (so a
# worktree's modified libs are what the fixture tests exercise, not
# main's installed copy — the worktree-shadow discipline). Otherwise
# prefer the installed copy, then fall back to the repo-relative copy.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

if loom_env_enabled LOOM_WORKTREE_BG_INVENTORY_SKIP; then
  exit 0
fi

# Drain stdin (the hook payload); we don't need any field off it — the
# sensor reads git + the process table, not the payload. Draining keeps
# the hook well-behaved as a pipe consumer.
cat >/dev/null 2>&1 || true

# --- 1. Enumerate orphan worktrees ----------------------------------
# Read `git worktree list --porcelain`. An agent-* worktree is an orphan
# when its locking agent PID is dead. The cwd's own worktree is never
# counted.
SELF_TOP=""
SELF_TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
SELF_TOP_REAL=""
[ -n "$SELF_TOP" ] && SELF_TOP_REAL=$(realpath "$SELF_TOP" 2>/dev/null || echo "$SELF_TOP")

if [ -n "${LOOM_WORKTREE_PORCELAIN_CMD:-}" ]; then
  PORCELAIN=$(eval "$LOOM_WORKTREE_PORCELAIN_CMD" 2>/dev/null || true)
else
  PORCELAIN=$(git worktree list --porcelain 2>/dev/null || true)
fi

WT_ORPHANS=0
cur_wt=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      cur_wt="${line#worktree }"
      ;;
    "locked "*)
      # Only agent worktrees under .claude/worktrees/agent-* are
      # candidates. Skip the main/normal worktrees.
      case "$cur_wt" in
        *"/.claude/worktrees/agent-"*) : ;;
        *) continue ;;
      esac
      # Never count our own worktree (a live worker mustn't flag itself).
      cur_wt_real=$(realpath "$cur_wt" 2>/dev/null || echo "$cur_wt")
      if [ -n "$SELF_TOP_REAL" ] && [ "$cur_wt_real" = "$SELF_TOP_REAL" ]; then
        continue
      fi
      # Extract the locking agent PID from "...(pid 1234 ...)" or
      # "...(1234 ...)". Grab the first integer inside the parentheses.
      pid=$(printf '%s' "$line" | grep -oE '\(([a-z]+ )?[0-9]+' | grep -oE '[0-9]+' | head -1)
      [ -n "$pid" ] || continue
      # Alive? kill -0 succeeds iff the process exists (and we can see
      # it). A dead pid → orphan.
      if kill -0 "$pid" 2>/dev/null; then
        : # locking agent still alive — not an orphan
      else
        WT_ORPHANS=$((WT_ORPHANS + 1))
      fi
      ;;
  esac
done <<<"$PORCELAIN"

# --- 2. Enumerate orphan background processes -----------------------
# Default scan: descendants of the session whose command matches the
# bg-proc pattern (the orphan classes flagged in dispatched-agents.md).
# The test seam LOOM_BG_PROC_CMD supplies a canned PID-per-line list.
BG_PATTERN="${LOOM_BG_PROC_PATTERN:-bd-post-rewrite|loom-.*loop}"
if [ -n "${LOOM_BG_PROC_CMD:-}" ]; then
  BG_LINES=$(eval "$LOOM_BG_PROC_CMD" 2>/dev/null || true)
else
  # pgrep is the cheap path; fall through to empty if absent.
  if command -v pgrep >/dev/null 2>&1; then
    BG_LINES=$(pgrep -f "$BG_PATTERN" 2>/dev/null || true)
  else
    BG_LINES=""
  fi
fi
BG_ORPHANS=0
if [ -n "$BG_LINES" ]; then
  BG_ORPHANS=$(printf '%s\n' "$BG_LINES" | grep -cE '[0-9]' || true)
fi

TOTAL=$((WT_ORPHANS + BG_ORPHANS))

# --- 3. Locate the workflow-state lib -------------------------------
# Same precedence as above: explicit LOOM_TEST_LIB_DIR wins, then the
# installed copy.
WFS_LIB=""
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  WFS_LIB="$LOOM_TEST_LIB_DIR/workflow-state.sh"
elif [ -f "$HOME/.claude/lib/workflow-state.sh" ]; then
  WFS_LIB="$HOME/.claude/lib/workflow-state.sh"
fi
[ -n "$WFS_LIB" ] || exit 0  # can't record/read state → fail silent

# shellcheck source=../lib/workflow-state.sh
. "$WFS_LIB"

# --- 4. Read the prior count for escalation-memoization -------------
PRIOR=$(workflow_state_get orphan_pressure "$PWD")
case "$PRIOR" in
  ''|*[!0-9]*) PRIOR_N=0 ;;
  *)           PRIOR_N="$PRIOR" ;;
esac

# --- 5. Record the current count ------------------------------------
workflow_state_set --start-dir="$PWD" "orphan_pressure=$TOTAL"

# --- 6. Nudge only on an ESCALATION (count rose above last recorded) -
# 0 orphans never nudges. A same-or-lower count re-fire is silent.
if [ "$TOTAL" -le 0 ] || [ "$TOTAL" -le "$PRIOR_N" ]; then
  exit 0
fi

MSG="Orphan inventory: ${WT_ORPHANS} stale worktree(s) + ${BG_ORPHANS} background process(es) detected (total ${TOTAL}). Stale agent worktrees / leftover background procs are piling up — run /cleanup-orphans to list + prune them. (This is an INFO nudge — it never blocks. Bypass with LOOM_WORKTREE_BG_INVENTORY_SKIP=1.)"

# Emit the nudge as additionalContext (jq-encoded so the message is
# always valid JSON regardless of quoting). Always exit 0. Falls back to
# a bare exit 0 if jq is unavailable (state was still recorded above).
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg msg "$MSG" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $msg}}'
fi
exit 0
