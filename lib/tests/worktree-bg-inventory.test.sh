#!/usr/bin/env bash
# Fixture tests for hooks/worktree-bg-inventory.sh.
#
# Closes loom-z3m.7 (feature): a worktree + background-process orphan
# inventory + cleanup nudge. A NON-BLOCKING PreToolUse hook (Bash
# matcher) that enumerates live `git worktree list` entries (esp.
# `.claude/worktrees/agent-*`) plus the background bash processes the
# session spawned, classifies them into orphan-pressure, writes an
# `orphan_pressure` count into workflow-state (rendered by statusline.sh
# as WT:N / BG:M), and surfaces a "stale worktrees/procs piling up —
# consider /cleanup-orphans" nudge once per escalation.
#
# Root cause it addresses (bead DESIGN): finishing-a-development-branch
# closes the bead + merges, but never enumerates live worktrees or
# background bash processes. Orphans pile up across sessions / after a
# mid-dispatch crash unless the user nags (surfaced loom-z3m.1 f4 loom +
# f2 liza-base, user nagged 3x).
#
# How orphans are enumerated:
#   - WORKTREES: `git worktree list --porcelain` lists every linked
#     worktree. An `.claude/worktrees/agent-*` entry is counted an
#     ORPHAN when its `locked claude agent ... (pid <PID>...)` PID is
#     NOT alive (the dispatching agent process exited / crashed and left
#     the worktree behind). The hook's OWN worktree (the cwd) is never
#     counted — a live worker shouldn't flag itself.
#   - BG PROCS: descendant background processes spawned from the
#     session's process group that look like long-running loom work
#     (a tunable name-pattern). Counted as BG orphans.
#
# Behavior pinned:
#   - no orphans (clean) → NO nudge, orphan_pressure=0, always exit 0
#   - orphan worktree present → nudge surfaces (WT:N indicator via
#     orphan_pressure>0 + an additionalContext /cleanup-orphans nudge),
#     exit 0
#   - NEVER hard-blocks (never exit 2; always exit 0)
#   - escalation is memoized: re-firing at same-or-lower pressure is
#     silent (no nudge spam); a NEW (higher) orphan count re-nudges
#   - bypass via LOOM_WORKTREE_BG_INVENTORY_SKIP=1
#   - no git / not in a repo → fail open, silent, exit 0
#
# Run:  bash lib/tests/worktree-bg-inventory.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/worktree-bg-inventory.sh"
WS="$LOOM_ROOT/scripts/workflow-state"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# The hook resolves libs via $HOME/.claude/lib/ first, then
# LOOM_TEST_LIB_DIR — point the latter at the repo copy.
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# A long-dead PID we can rely on never being alive in the test sandbox.
DEAD_PID=999999

# Build a project fixture that is its OWN git repo with a controllable
# set of linked worktrees. We can't easily fake `git worktree list`
# output without real worktrees, so the hook reads worktree porcelain
# from a fixture file we inject via LOOM_WORKTREE_PORCELAIN_CMD — the
# hook calls that command instead of `git worktree list --porcelain`
# when it is set (test seam). Same idea for the bg-proc enumerator via
# LOOM_BG_PROC_CMD.
#
#   $1 = path to a file containing canned `git worktree list --porcelain`
#        output (or empty for none)
#   $2 = path to a file containing canned bg-proc lines (one PID per
#        line, or empty for none)
# echoes the project dir
mk_project() {
  local porcelain_file="$1" bgproc_file="$2"
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '{"v":1,"mode":"full","activity":"feature","bead":"loom-z3m.7","stage":"close","updated":"2026-06-08T00:00:00Z"}\n' \
    > "$d/.claude/workflow-state.json"
  # Stash the fixture file paths so run_hook can wire them as env.
  printf '%s' "$porcelain_file" > "$d/.porcelain_file"
  printf '%s' "$bgproc_file" > "$d/.bgproc_file"
  printf '%s' "$d"
}

# Run the hook from inside the project dir with the test seams wired.
#   $1 = project dir   (rest: extra env assignments)
run_hook() {
  local proj="$1"; shift
  local porcelain_file bgproc_file payload
  porcelain_file=$(cat "$proj/.porcelain_file")
  bgproc_file=$(cat "$proj/.bgproc_file")
  payload=$(jq -nc '{tool_name:"Bash", tool_input:{command:"echo hi"}}')
  ( cd "$proj" && env \
      LOOM_WORKTREE_PORCELAIN_CMD="cat ${porcelain_file:-/dev/null}" \
      LOOM_BG_PROC_CMD="cat ${bgproc_file:-/dev/null}" \
      "$@" \
      bash "$HOOK" <<<"$payload" 2>&1 )
}

# Extract the additionalContext string (empty if no JSON emitted).
ctx() { echo "$1" | jq -r 'try .hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# Read orphan_pressure out of the project's workflow-state.
pressure() { bash "$WS" get orphan_pressure "$1" 2>/dev/null; }

# Porcelain fixture writers.
# write_clean <file>  — only the main worktree + cwd's own worktree.
write_porcelain_clean() {
  local f="$1"
  cat > "$f" <<EOF
worktree /home/frank/repos/loom
HEAD aaaa
branch refs/heads/main

EOF
}
# write_orphan <file> <agent-path> <dead-pid> — one orphan agent worktree
# locked to a dead pid.
write_porcelain_orphan() {
  local f="$1" agent_path="$2" pid="$3"
  cat > "$f" <<EOF
worktree /home/frank/repos/loom
HEAD aaaa
branch refs/heads/main

worktree $agent_path
HEAD bbbb
branch refs/heads/frank/loom-dead.1
locked claude agent agent-dead ($pid)

EOF
}

# -------------------------------------------------------------------
# 1. clean (no orphans) → NO nudge, orphan_pressure=0, exit 0
# -------------------------------------------------------------------
echo "==> 1. clean → orphan_pressure=0, no nudge, exit 0"
porc=$(mktemp); write_porcelain_clean "$porc"
bgp=$(mktemp); : > "$bgp"   # no bg procs
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj"); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -z "$c" ] && [ "$p" = "0" ]; then
  pass "clean: no nudge, orphan_pressure=0, exit 0"
else
  fail "expected clean/no-nudge/exit0. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 2. one orphan worktree (dead-pid lock) → nudge, orphan_pressure>=1
# -------------------------------------------------------------------
echo "==> 2. orphan worktree (dead pid) → nudge, orphan_pressure>=1, exit 0"
porc=$(mktemp)
write_porcelain_orphan "$porc" \
  "/home/frank/repos/loom/.claude/worktrees/agent-deadbeef" "$DEAD_PID"
bgp=$(mktemp); : > "$bgp"
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj"); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -n "$c" ] && [ "${p:-0}" -ge 1 ] \
   && echo "$c" | grep -qiE 'orphan|worktree|cleanup'; then
  pass "orphan worktree: nudge surfaces, orphan_pressure>=1, exit 0"
else
  fail "expected orphan nudge + exit0. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 3. live-pid worktree lock → NOT an orphan (the dispatching agent is
#    still alive). Use the test's own $$ as a known-live pid.
# -------------------------------------------------------------------
echo "==> 3. live-pid worktree lock → NOT counted as orphan"
porc=$(mktemp)
write_porcelain_orphan "$porc" \
  "/home/frank/repos/loom/.claude/worktrees/agent-alive" "$$"
bgp=$(mktemp); : > "$bgp"
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj"); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ "$p" = "0" ] && [ -z "$c" ]; then
  pass "live-pid lock: not orphan, orphan_pressure=0, no nudge"
else
  fail "expected live-pid lock to NOT count. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 4. background process present → counted, nudge surfaces
# -------------------------------------------------------------------
echo "==> 4. bg proc present → counted, nudge, exit 0"
porc=$(mktemp); write_porcelain_clean "$porc"
bgp=$(mktemp); printf '12345\n23456\n' > "$bgp"   # two bg procs
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj"); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -n "$c" ] && [ "${p:-0}" -ge 2 ] \
   && echo "$c" | grep -qiE 'process|proc|background|cleanup'; then
  pass "bg procs: counted (>=2), nudge surfaces, exit 0"
else
  fail "expected bg-proc nudge + exit0. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 5. NEVER hard-blocks — exit 0 even with a pile of orphans.
# -------------------------------------------------------------------
echo "==> 5. never hard-blocks (loom posture: nudge, never exit 2)"
porc=$(mktemp)
{
  printf 'worktree /home/frank/repos/loom\nHEAD aaaa\nbranch refs/heads/main\n\n'
  for i in 1 2 3 4 5; do
    printf 'worktree /home/frank/repos/loom/.claude/worktrees/agent-x%s\n' "$i"
    printf 'HEAD bbbb\nbranch refs/heads/frank/dead-%s\n' "$i"
    printf 'locked claude agent agent-x%s (%s)\n\n' "$i" "$DEAD_PID"
  done
} > "$porc"
bgp=$(mktemp); printf '11\n22\n33\n' > "$bgp"
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "pile of orphans still exits 0 (never blocks)"
else
  fail "expected exit 0 even with many orphans. rc=$rc" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 6. escalation memoization: same-or-lower pressure re-fire is silent;
#    a higher count re-nudges.
# -------------------------------------------------------------------
echo "==> 6. escalation memoized (no per-tool nudge spam)"
porc=$(mktemp)
write_porcelain_orphan "$porc" \
  "/home/frank/repos/loom/.claude/worktrees/agent-deadbeef" "$DEAD_PID"
bgp=$(mktemp); : > "$bgp"
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj"); c1=$(ctx "$out")
out=$(run_hook "$proj"); rc=$?; c2=$(ctx "$out")  # same pressure again
if [ -n "$c1" ] && [ "$rc" -eq 0 ] && [ -z "$c2" ]; then
  pass "first orphan nudges; second same-count silent (memoized)"
else
  fail "memoization at same count failed: c1='$c1' c2='$c2' rc=$rc" "$out"
fi
# Now ADD a second orphan worktree — pressure rises → should re-nudge.
{
  cat "$porc"
  printf 'worktree /home/frank/repos/loom/.claude/worktrees/agent-second\n'
  printf 'HEAD cccc\nbranch refs/heads/frank/dead-2\n'
  printf 'locked claude agent agent-second (%s)\n\n' "$DEAD_PID"
} > "$porc.2" && mv "$porc.2" "$porc"
out=$(run_hook "$proj"); c3=$(ctx "$out"); p3=$(pressure "$proj")
if [ -n "$c3" ] && [ "${p3:-0}" -ge 2 ]; then
  pass "rising orphan count re-nudges"
else
  fail "expected re-nudge on rising count. ctx='$c3' pressure='$p3'" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 7. LOOM_WORKTREE_BG_INVENTORY_SKIP=1 bypass → silent, no state write.
# -------------------------------------------------------------------
echo "==> 7. SKIP=1 bypass"
porc=$(mktemp)
write_porcelain_orphan "$porc" \
  "/home/frank/repos/loom/.claude/worktrees/agent-deadbeef" "$DEAD_PID"
bgp=$(mktemp); : > "$bgp"
proj=$(mk_project "$porc" "$bgp")
out=$(run_hook "$proj" LOOM_WORKTREE_BG_INVENTORY_SKIP=1); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -z "$c" ] && [ -z "$p" ]; then
  pass "SKIP=1: silent, no orphan_pressure written, exit 0"
else
  fail "SKIP=1 did not bypass. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 8. statusline renders WT/BG indicator when orphan_pressure > 0.
# -------------------------------------------------------------------
echo "==> 8. statusline shows WT/BG indicator when orphans exist"
porc=$(mktemp)
write_porcelain_orphan "$porc" \
  "/home/frank/repos/loom/.claude/worktrees/agent-deadbeef" "$DEAD_PID"
bgp=$(mktemp); printf '12345\n' > "$bgp"
proj=$(mk_project "$porc" "$bgp")
run_hook "$proj" >/dev/null 2>&1
sl_payload=$(jq -nc --arg cwd "$proj" '{cwd:$cwd}')
sl=$(printf '%s' "$sl_payload" | bash "$LOOM_ROOT/scripts/statusline.sh" 2>&1)
if echo "$sl" | grep -qiE 'WT:|BG:|orphan'; then
  pass "statusline surfaces an orphan indicator (WT:/BG:)"
else
  fail "expected statusline orphan indicator. statusline='$sl'"
fi
rm -rf "$proj" "$porc" "$bgp"

# -------------------------------------------------------------------
# 9. settings.snippet.json wires the hook into the PreToolUse Bash chain
#    (additive — does NOT remove existing registrations).
# -------------------------------------------------------------------
echo "==> 9. settings.snippet.json registers the hook (additive)"
snip="$LOOM_ROOT/settings.snippet.json"
if jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Bash")
  | .hooks[]
  | select(.command | test("worktree-bg-inventory.sh"))
' "$snip" >/dev/null 2>&1 \
   && jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Bash")
  | .hooks[]
  | select(.command | test("context-budget-sensor.sh"))
' "$snip" >/dev/null 2>&1; then
  pass "snippet registers worktree-bg-inventory.sh AND keeps context-budget-sensor.sh"
else
  fail "settings.snippet.json missing worktree-bg-inventory.sh in Bash chain (or dropped context-budget-sensor.sh)"
fi

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
