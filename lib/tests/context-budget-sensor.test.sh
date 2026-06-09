#!/usr/bin/env bash
# Fixture tests for hooks/context-budget-sensor.sh.
#
# Closes loom-z3m.9 (feature): a proactive context-budget wrap-up
# sensor. A NON-BLOCKING PreToolUse hook (Bash matcher) that reads
# the session's accumulated-context high-water mark off the live
# transcript — reusing the SAME `.message.usage` telemetry the
# proven central-side reader scripts/loom-stage-spend reads
# (cache_read_input_tokens + cache_creation_input_tokens on the last
# assistant record) — classifies it green|yellow|red against tunable
# thresholds, writes `context_pressure` into workflow-state, and
# surfaces a "context is getting heavy — consider wrapping up /
# checkpointing" nudge once per tier-escalation.
#
# Design constraint (loom-0ahj D7): Stop/SessionEnd hooks do NOT
# reliably fire on sidechains for token measurement, so the actual
# MEASUREMENT rides the proven central-side reader path (the
# transcript .message.usage block), NOT a Stop-hook. This sensor
# TRIGGERS on a PreToolUse and reads telemetry via that proven path.
#
# Behavior pinned:
#   - below-threshold (green) → NO nudge, context_pressure=green,
#     always exit 0
#   - yellow threshold crossed → nudge surfaces (statusline-bound
#     context_pressure=yellow + an additionalContext recipe nudge),
#     exit 0
#   - red threshold crossed → stronger nudge surfaces,
#     context_pressure=red, exit 0
#   - NEVER hard-blocks (never exit 2; always exit 0)
#   - tier escalation is memoized: re-firing at the same tier is
#     silent (no nudge spam); a NEW tier escalation re-nudges
#   - thresholds tunable via env (LOOM_CONTEXT_BUDGET_YELLOW /
#     LOOM_CONTEXT_BUDGET_RED)
#   - bypass via LOOM_CONTEXT_BUDGET_SENSOR_SKIP=1
#   - no transcript / unreadable transcript → fail open, silent,
#     exit 0
#
# Run:  bash lib/tests/context-budget-sensor.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/context-budget-sensor.sh"
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

# Build a project fixture with a transcript JSONL whose last assistant
# record carries a controllable usage block.
#   $1 = cache_read_input_tokens for the last assistant record
#   $2 = cache_creation_input_tokens for the last assistant record
# echoes the project dir
mk_project() {
  local cache_read="$1" cache_creation="$2"
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '{"v":1,"mode":"full","activity":"feature","bead":"loom-z3m.9","stage":"tdd-green","updated":"2026-06-08T00:00:00Z"}\n' \
    > "$d/.claude/workflow-state.json"

  # A minimal session transcript: a couple of assistant records, the
  # LAST of which carries the high-water-mark usage block. Mirrors the
  # Anthropic transcript shape loom-stage-spend reads
  # (.message.usage.cache_read_input_tokens etc).
  {
    printf '{"type":"assistant","message":{"role":"assistant","usage":{"cache_read_input_tokens":1000,"cache_creation_input_tokens":500,"output_tokens":100}}}\n'
    printf '{"type":"user","message":{"role":"user","content":"hi"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","usage":{"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":200}}}\n' \
      "$cache_read" "$cache_creation"
  } > "$d/transcript.jsonl"

  printf '%s' "$d"
}

# Run the hook with a payload carrying tool_name + transcript_path,
# from inside the project dir.
#   $1 = project dir   $2 = tool   (rest: env assignments)
run_hook() {
  local proj="$1" tool="$2"; shift 2
  local payload
  payload=$(jq -nc --arg t "$tool" --arg tp "$proj/transcript.jsonl" \
    '{tool_name:$t, transcript_path:$tp, tool_input:{command:"echo hi"}}')
  (cd "$proj" && env "$@" bash "$HOOK" <<<"$payload" 2>&1)
}

# Extract the additionalContext string (empty if no JSON emitted).
ctx() { echo "$1" | jq -r 'try .hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# Read the context_pressure field out of the project's workflow-state.
pressure() { bash "$WS" get context_pressure "$1" 2>/dev/null; }

# -------------------------------------------------------------------
# 1. below-threshold (green) → NO nudge, context_pressure=green, exit 0
# -------------------------------------------------------------------
echo "==> 1. below-threshold → green, no nudge, exit 0"
proj=$(mk_project 100000 10000)   # 110k total — well under 400k yellow
out=$(run_hook "$proj" Bash); rc=$?
c=$(ctx "$out")
p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -z "$c" ] && [ "$p" = "green" ]; then
  pass "green: no nudge, context_pressure=green, exit 0"
else
  fail "expected green/no-nudge/exit0. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 2. at/above yellow threshold → nudge surfaces, context_pressure=yellow
# -------------------------------------------------------------------
echo "==> 2. yellow threshold → nudge, context_pressure=yellow, exit 0"
proj=$(mk_project 450000 20000)   # 470k total — over 400k yellow
out=$(run_hook "$proj" Bash); rc=$?
c=$(ctx "$out")
p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -n "$c" ] && [ "$p" = "yellow" ] \
   && echo "$c" | grep -qiE 'wrap|checkpoint|context'; then
  pass "yellow: nudge surfaces, context_pressure=yellow, exit 0"
else
  fail "expected yellow nudge + exit0. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 3. at/above red threshold → stronger nudge, context_pressure=red
# -------------------------------------------------------------------
echo "==> 3. red threshold → nudge, context_pressure=red, exit 0"
proj=$(mk_project 720000 30000)   # 750k total — over 700k red
out=$(run_hook "$proj" Bash); rc=$?
c=$(ctx "$out")
p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -n "$c" ] && [ "$p" = "red" ] \
   && echo "$c" | grep -qiE 'wrap|checkpoint'; then
  pass "red: nudge surfaces, context_pressure=red, exit 0"
else
  fail "expected red nudge + exit0. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 4. NEVER hard-blocks — exit 0 even at extreme pressure.
# -------------------------------------------------------------------
echo "==> 4. never hard-blocks (loom posture: nudge, never exit 2)"
proj=$(mk_project 5000000 100000)   # absurdly high
out=$(run_hook "$proj" Bash); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "extreme pressure still exits 0 (never blocks)"
else
  fail "expected exit 0 even at extreme pressure. rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 5. tier-escalation memoization: same tier re-fire is silent; a NEW
#    tier escalation re-nudges.
# -------------------------------------------------------------------
echo "==> 5. tier escalation memoized (no per-tool nudge spam)"
proj=$(mk_project 450000 0)   # yellow
out=$(run_hook "$proj" Bash); c1=$(ctx "$out")
out=$(run_hook "$proj" Bash); rc=$?; c2=$(ctx "$out")  # same tier again
if [ -n "$c1" ] && [ "$rc" -eq 0 ] && [ -z "$c2" ]; then
  pass "first yellow nudges; second same-tier silent (memoized)"
else
  fail "memoization at same tier failed: c1='$c1' c2='$c2' rc=$rc" "$out"
fi
# Now escalate the SAME project to red — should re-nudge.
{
  printf '{"type":"assistant","message":{"role":"assistant","usage":{"cache_read_input_tokens":720000,"cache_creation_input_tokens":30000,"output_tokens":200}}}\n'
} > "$proj/transcript.jsonl"
out=$(run_hook "$proj" Bash); c3=$(ctx "$out"); p3=$(pressure "$proj")
if [ -n "$c3" ] && [ "$p3" = "red" ]; then
  pass "escalation yellow→red re-nudges"
else
  fail "expected re-nudge on yellow→red escalation. ctx='$c3' pressure='$p3'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 6. thresholds tunable via env.
# -------------------------------------------------------------------
echo "==> 6. thresholds tunable via env"
proj=$(mk_project 50000 0)   # 50k — green under defaults
# Lower the yellow threshold to 40k so 50k now reads yellow.
out=$(run_hook "$proj" Bash LOOM_CONTEXT_BUDGET_YELLOW=40000); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ "$p" = "yellow" ] && [ -n "$c" ]; then
  pass "LOOM_CONTEXT_BUDGET_YELLOW lowers the yellow threshold"
else
  fail "expected env-tuned yellow. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 7. LOOM_CONTEXT_BUDGET_SENSOR_SKIP=1 bypass → silent, no state write.
# -------------------------------------------------------------------
echo "==> 7. SKIP=1 bypass"
proj=$(mk_project 720000 30000)   # would be red
out=$(run_hook "$proj" Bash LOOM_CONTEXT_BUDGET_SENSOR_SKIP=1); rc=$?
c=$(ctx "$out"); p=$(pressure "$proj")
if [ "$rc" -eq 0 ] && [ -z "$c" ] && [ -z "$p" ]; then
  pass "SKIP=1: silent, no context_pressure written, exit 0"
else
  fail "SKIP=1 did not bypass. rc=$rc pressure='$p' ctx='$c'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 8. no transcript / unreadable transcript → fail open, silent, exit 0.
# -------------------------------------------------------------------
echo "==> 8. missing transcript → fail open, silent"
proj=$(mk_project 720000 30000)
rm -f "$proj/transcript.jsonl"   # remove it
out=$(run_hook "$proj" Bash); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && [ -z "$c" ]; then
  pass "missing transcript: fail open, silent, exit 0"
else
  fail "expected fail-open silent on missing transcript. rc=$rc ctx='$c'" "$out"
fi
rm -rf "$proj"
# Empty transcript_path in payload → also silent.
proj=$(mk_project 720000 30000)
payload=$(jq -nc '{tool_name:"Bash", transcript_path:"", tool_input:{}}')
out=$( (cd "$proj" && bash "$HOOK" <<<"$payload" 2>&1) ); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && [ -z "$c" ]; then
  pass "empty transcript_path: fail open, silent, exit 0"
else
  fail "expected silent on empty transcript_path. rc=$rc ctx='$c'" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
