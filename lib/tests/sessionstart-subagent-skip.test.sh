#!/usr/bin/env bash
# Fixture tests for SessionStart subagent skip (loom-w58).
#
# Loom-owned SessionStart hooks should detect subagent context in the
# stdin JSON payload and exit 0 silently — subagents don't structurally
# use the preamble, the brief carries the intent. This shaves ~21 KB of
# preamble per subagent spawn (top-leverage finding from loom-nsb).
#
# Detection signals (checked in priority order):
#   1. isSidechain == true        (transcript-level marker)
#   2. parentUuid is non-null     (transcript-level marker)
#   3. source matches subagent    (defensive — for future CC versions)
#
# Tests verify:
#   - Subagent markers in stdin → hook emits nothing and exits 0
#   - Normal SessionStart payload → hook emits its preamble as usual
#
# Run:  bash lib/tests/sessionstart-subagent-skip.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/workflow-mode-onboarding.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a beads-workspace project dir without a workflow.json — this is
# the configuration that triggers the onboarding output. Without the
# subagent guard, the hook would emit additionalContext.
mk_beads_project_no_cfg() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.beads" "$dir/.claude"
  # No workflow.json on purpose — the hook injects when absent.
  echo "$dir"
}

PROJ=$(mk_beads_project_no_cfg)
trap 'rm -rf "$PROJ"' EXIT

# Helper: run hook with a JSON payload, return stdout (stderr discarded
# to keep assertion noise low). Exit code captured via $?.
run_hook_with_payload() {
  local proj="$1" payload="$2"
  (cd "$proj" && bash "$HOOK" <<<"$payload" 2>/dev/null)
}

mk_payload() {
  # Args: key1=value1 key2=value2 ... — values must be valid JSON
  # fragments (strings need their own quotes embedded).
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
# 1. Baseline — orchestrator session (no subagent markers) → emits preamble
# ---------------------------------------------------------------------------

echo "==> 1. Orchestrator session emits onboarding preamble"

# Plain SessionStart payload — no subagent markers. Hook should emit
# its additionalContext block.
out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'hook_event_name="SessionStart"' 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "baseline orchestrator → emits preamble (rc=0, contains marker)"
else
  fail "baseline orchestrator did not emit preamble (rc=$rc)" "$out"
fi

# Even more minimal payload (just cwd) — still emits.
out=$(run_hook_with_payload "$PROJ" "$(mk_payload)"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "minimal payload (cwd only) → still emits preamble"
else
  fail "minimal payload did not emit preamble (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 2. isSidechain=true → skip
# ---------------------------------------------------------------------------

echo "==> 2. isSidechain=true skips emission"

out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'isSidechain=true')"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "isSidechain=true → empty output, rc=0"
else
  fail "isSidechain=true did not skip (rc=$rc, output non-empty)" "$out"
fi

# isSidechain=false should NOT skip.
out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'isSidechain=false')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "isSidechain=false → still emits"
else
  fail "isSidechain=false incorrectly skipped (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 3. parentUuid non-null → skip
# ---------------------------------------------------------------------------

echo "==> 3. parentUuid non-null skips emission"

out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'parentUuid="33226626-4660-4ee6-be8c-2e4717232054"')"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "parentUuid=<uuid> → empty output, rc=0"
else
  fail "parentUuid non-null did not skip (rc=$rc)" "$out"
fi

# parentUuid=null should NOT skip.
out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'parentUuid=null')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "parentUuid=null → still emits"
else
  fail "parentUuid=null incorrectly skipped (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 4. source=subagent (defensive, future-proof) → skip
# ---------------------------------------------------------------------------

echo "==> 4. source=subagent skips emission (defensive)"

out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'source="subagent"')"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "source=subagent → empty output, rc=0"
else
  fail "source=subagent did not skip (rc=$rc)" "$out"
fi

# source=startup should NOT skip.
out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'source="startup"')"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "source=startup → still emits"
else
  fail "source=startup incorrectly skipped (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 5. Edge — combined markers, malformed JSON, missing fields
# ---------------------------------------------------------------------------

echo "==> 5. Edge cases"

# Multiple markers — still skips cleanly.
out=$(run_hook_with_payload "$PROJ" "$(mk_payload 'isSidechain=true' 'parentUuid="abc"' 'source="subagent"')"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "all subagent markers set → skip"
else
  fail "combined markers did not skip (rc=$rc)" "$out"
fi

# Empty stdin — hook reads "" and falls through; should NOT crash.
out=$(cd "$PROJ" && bash "$HOOK" </dev/null 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty stdin → rc=0 (no crash)"
else
  fail "empty stdin crashed (rc=$rc)" "$out"
fi

# Malformed JSON — fall through to normal emission rather than fail.
# (Defensive: subagent detection failure shouldn't break orchestrator flow.)
out=$(run_hook_with_payload "$PROJ" "not-json-at-all"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'workflow-mode-onboarding'; then
  pass "malformed JSON → falls through to normal emission"
else
  fail "malformed JSON broke hook (rc=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
