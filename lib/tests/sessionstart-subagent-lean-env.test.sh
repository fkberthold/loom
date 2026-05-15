#!/usr/bin/env bash
# Fixture tests for LOOM_SUBAGENT_LEAN env-var override (loom-b1l).
#
# Companion to loom-w58 (sessionstart-subagent-skip): w58 introduced
# transcript-payload-based subagent detection (isSidechain=true /
# parentUuid != null) that short-circuits loom-owned SessionStart hooks
# to slim mode. b1l adds an explicit env-var override for cases where
# the heuristic misclassifies, so app code wrapping subprocess Claude
# Code invocations can force-emit slim deterministically:
#
#   LOOM_SUBAGENT_LEAN=1 claude code ...
#
# Tests verify:
#   - LOOM_SUBAGENT_LEAN=1 + orchestrator-shaped payload → slim emission
#     (workflow-mode-onboarding emits nothing, exits 0)
#   - LOOM_SUBAGENT_LEAN=1 + bd-prime-wrapper SessionStart hook also
#     short-circuits to slim (exits 0 with no output)
#   - LOOM_SUBAGENT_LEAN unset / =0 / =yes → no behavior change (only
#     literal "1" triggers; conservative match to avoid surprise)
#   - LOOM_SUBAGENT_LEAN=1 detector returns success even on empty / null
#     payloads (the env var is sufficient on its own)
#
# Run:  bash lib/tests/sessionstart-subagent-lean-env.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ONBOARDING_HOOK="$LOOM_ROOT/hooks/workflow-mode-onboarding.sh"
PRIME_HOOK="$LOOM_ROOT/hooks/bd-prime-wrapper.sh"
DETECT_LIB="$LOOM_ROOT/lib/subagent-detect.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a beads-workspace project dir without a workflow.json — this is
# the configuration that triggers the onboarding output. Without the
# env-var guard, the hook would emit additionalContext.
mk_beads_project_no_cfg() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.beads" "$dir/.claude"
  echo "$dir"
}

PROJ=$(mk_beads_project_no_cfg)

# HOME override: the hook's source-chain (`. $HOME/.claude/lib/... ||
# . $(dirname BASH_SOURCE)/../lib/...`) prefers a host-installed lib
# symlink over the worktree-local copy. The host's symlink may point
# at MAIN's lib/, not this worktree's modified copy — so tests would
# silently exercise main's code rather than the change under test.
# For tests we point HOME at a scratch dir whose `.claude/lib` symlinks
# to THIS worktree's `lib/`, guaranteeing the hook sources the
# code-under-test.
TEST_HOME=$(mktemp -d)
mkdir -p "$TEST_HOME/.claude"
ln -s "$LOOM_ROOT/lib" "$TEST_HOME/.claude/lib"
trap 'rm -rf "$PROJ" "$TEST_HOME"' EXIT

run_hook_with_payload_env() {
  # Args: env_var_assignment payload
  local env_assign="$1" payload="$2"
  if [ -n "$env_assign" ]; then
    (cd "$PROJ" && env HOME="$TEST_HOME" "$env_assign" bash "$ONBOARDING_HOOK" <<<"$payload" 2>/dev/null)
  else
    (cd "$PROJ" && env -u LOOM_SUBAGENT_LEAN HOME="$TEST_HOME" bash "$ONBOARDING_HOOK" <<<"$payload" 2>/dev/null)
  fi
}

mk_payload() {
  python3 -c '
import json, sys
d = {"cwd": sys.argv[1]}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    d[k] = json.loads(v)
print(json.dumps(d))
' "$PROJ" "$@"
}

# ---------------------------------------------------------------------------
# 1. LOOM_SUBAGENT_LEAN=1 forces slim emission on workflow-mode-onboarding
# ---------------------------------------------------------------------------

echo "==> 1. LOOM_SUBAGENT_LEAN=1 + orchestrator payload → workflow-mode-onboarding slim"

# Orchestrator-shaped payload: no subagent markers. Without env var
# this would emit the preamble. With env var, must skip.
out=$(run_hook_with_payload_env "LOOM_SUBAGENT_LEAN=1" "$(mk_payload 'hook_event_name="SessionStart"' 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "LOOM_SUBAGENT_LEAN=1 + orchestrator → empty output, rc=0"
else
  fail "LOOM_SUBAGENT_LEAN=1 did not force slim (rc=$rc)" "$out"
fi

# Minimal payload (just cwd) — env var still short-circuits.
out=$(run_hook_with_payload_env "LOOM_SUBAGENT_LEAN=1" "$(mk_payload)"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "LOOM_SUBAGENT_LEAN=1 + minimal payload → empty output, rc=0"
else
  fail "LOOM_SUBAGENT_LEAN=1 minimal payload did not skip (rc=$rc)" "$out"
fi

# Empty stdin — env var alone is sufficient.
out=$(cd "$PROJ" && env HOME="$TEST_HOME" LOOM_SUBAGENT_LEAN=1 bash "$ONBOARDING_HOOK" </dev/null 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "LOOM_SUBAGENT_LEAN=1 + empty stdin → empty output, rc=0"
else
  fail "LOOM_SUBAGENT_LEAN=1 empty stdin did not skip (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 2. LOOM_SUBAGENT_LEAN unset / non-"1" values do NOT force slim
# ---------------------------------------------------------------------------

echo "==> 2. LOOM_SUBAGENT_LEAN unset / other values → no behavior change"

# Unset → orchestrator payload emits preamble as usual.
out=$(run_hook_with_payload_env "" "$(mk_payload 'hook_event_name="SessionStart"' 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "unset → orchestrator payload still emits preamble"
else
  fail "unset env var unexpectedly skipped (rc=$rc)" "$out"
fi

# =0 → still emits (conservative: only literal "1" triggers).
out=$(run_hook_with_payload_env "LOOM_SUBAGENT_LEAN=0" "$(mk_payload 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "LOOM_SUBAGENT_LEAN=0 → orchestrator payload still emits preamble"
else
  fail "LOOM_SUBAGENT_LEAN=0 unexpectedly skipped (rc=$rc)" "$out"
fi

# =yes (any non-"1" truthy-looking string) → still emits.
out=$(run_hook_with_payload_env "LOOM_SUBAGENT_LEAN=yes" "$(mk_payload 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "LOOM_SUBAGENT_LEAN=yes → orchestrator payload still emits preamble"
else
  fail "LOOM_SUBAGENT_LEAN=yes unexpectedly skipped (rc=$rc)" "$out"
fi

# Empty string → still emits.
out=$(run_hook_with_payload_env "LOOM_SUBAGENT_LEAN=" "$(mk_payload 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "LOOM_SUBAGENT_LEAN= (empty) → orchestrator payload still emits preamble"
else
  fail "LOOM_SUBAGENT_LEAN empty unexpectedly skipped (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 3. LOOM_SUBAGENT_LEAN=1 composes with existing signals (still skips)
# ---------------------------------------------------------------------------

echo "==> 3. LOOM_SUBAGENT_LEAN=1 + isSidechain=true → still skip (compose)"

out=$(run_hook_with_payload_env "LOOM_SUBAGENT_LEAN=1" "$(mk_payload 'isSidechain=true')"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "LOOM_SUBAGENT_LEAN=1 + isSidechain=true → empty output, rc=0"
else
  fail "compose case failed (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 4. detector function: env var directly tested
# ---------------------------------------------------------------------------

echo "==> 4. loom_is_subagent_payload honors LOOM_SUBAGENT_LEAN=1"

# Source the detector and exercise it with various payloads + env state.
test_detector() {
  local env_assign="$1" payload="$2" expected_rc="$3" label="$4"
  if [ -n "$env_assign" ]; then
    rc=$(env "$env_assign" bash -c ". '$DETECT_LIB'; loom_is_subagent_payload '$payload'; echo \$?")
  else
    rc=$(env -u LOOM_SUBAGENT_LEAN bash -c ". '$DETECT_LIB'; loom_is_subagent_payload '$payload'; echo \$?")
  fi
  if [ "$rc" = "$expected_rc" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label (expected rc=$expected_rc, got rc=$rc)"
  fi
}

# Env var set → returns 0 (match) regardless of payload contents.
test_detector "LOOM_SUBAGENT_LEAN=1" '{"cwd":"/tmp"}' 0 "LOOM_SUBAGENT_LEAN=1 + orchestrator payload → match"
test_detector "LOOM_SUBAGENT_LEAN=1" '' 0 "LOOM_SUBAGENT_LEAN=1 + empty payload → match"
test_detector "LOOM_SUBAGENT_LEAN=1" 'not-json' 0 "LOOM_SUBAGENT_LEAN=1 + malformed JSON → match"

# Env var unset → only payload signals matter (preserve w58 behavior).
test_detector "" '{"cwd":"/tmp"}' 1 "unset + orchestrator payload → no match (w58 baseline)"
test_detector "" '{"isSidechain":true}' 0 "unset + isSidechain=true → match (w58 baseline)"

# Env var =0 → does NOT match (only literal "1" triggers).
test_detector "LOOM_SUBAGENT_LEAN=0" '{"cwd":"/tmp"}' 1 "LOOM_SUBAGENT_LEAN=0 → no match"

# ---------------------------------------------------------------------------
# 5. bd-prime-wrapper SessionStart hook also honors the env var
# ---------------------------------------------------------------------------

echo "==> 5. LOOM_SUBAGENT_LEAN=1 short-circuits bd-prime-wrapper"

# Without the env var, bd-prime-wrapper would call `bd prime` and emit
# its output. With the env var set, it should exit 0 silently.
out=$(cd "$PROJ" && env HOME="$TEST_HOME" LOOM_SUBAGENT_LEAN=1 bash "$PRIME_HOOK" </dev/null 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "LOOM_SUBAGENT_LEAN=1 + bd-prime-wrapper → empty output, rc=0"
else
  fail "LOOM_SUBAGENT_LEAN=1 did not short-circuit bd-prime-wrapper (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
