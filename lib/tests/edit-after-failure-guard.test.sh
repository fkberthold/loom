#!/usr/bin/env bash
# Fixture tests for hooks/edit-after-failure-guard.sh.
#
# Closes loom-z3m.6: the recurring TDD-discipline-slip where the
# agent's first move after a test/build failure is to Edit the
# source file (writing the fix before pinning the failure with a
# RED test).
#
# Hook is PreToolUse on Edit/Write/MultiEdit. It:
#   1. Tails the session transcript JSONL.
#   2. Looks for a recent Bash tool_result with test-failure markers.
#   3. Tracks whether ANY Edit/Write/MultiEdit on a test file
#      happened AFTER the failure (clears the guard).
#   4. Refuses (exit 2) when failure is recent AND no test edit
#      since AND target is not itself a test file.
#   5. No-op when transcript_path is missing/empty (fail open).
#   6. Bypass via LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1.
#
# Run:  bash lib/tests/edit-after-failure-guard.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/edit-after-failure-guard.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a transcript file with given JSONL entries.
mk_transcript() {
  local content="$1"
  local f; f=$(mktemp --suffix=.jsonl)
  printf '%s' "$content" > "$f"
  echo "$f"
}

# Run the hook with a synthesized PreToolUse payload.
#   $1 = tool name
#   $2 = file_path
#   $3 = transcript_path
run_hook() {
  local tool="$1" path="$2" transcript="$3"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({
    "tool_name": sys.argv[1],
    "tool_input": {"file_path": sys.argv[2]},
    "transcript_path": sys.argv[3],
}))
' "$tool" "$path" "$transcript")
  bash "$HOOK" <<<"$payload" 2>&1
}

# Transcript helpers — produce JSONL lines matching Anthropic shape.
tool_use_block() {
  # $1 = tool name, $2 = file_path (Edit/Write/MultiEdit) or empty
  local tool="$1" fp="${2:-}"
  python3 -c '
import json, sys
tool = sys.argv[1]
fp = sys.argv[2]
inp = {"file_path": fp} if fp else {}
rec = {
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [
            {"type": "tool_use", "id": "x", "name": tool, "input": inp}
        ],
    },
}
print(json.dumps(rec))
' "$tool" "$fp"
}

tool_result_block() {
  # $1 = output text (the bash result body)
  local out="$1"
  python3 -c '
import json, sys
text = sys.argv[1]
rec = {
    "type": "user",
    "message": {
        "role": "user",
        "content": [
            {"type": "tool_result", "tool_use_id": "x", "content": text}
        ],
    },
}
print(json.dumps(rec))
' "$out"
}

# -------------------------------------------------------------------
# 1. Failure marker + source-file Edit → blocked.
# -------------------------------------------------------------------

echo "==> 1. Failure marker + source-file Edit → blocked"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'Running tests...
test_foo.py::test_bar FAILED
======= 1 failed, 0 passed =======')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "discipline slip\|TDD\|test-driven"; then
  pass "FAIL marker + source Edit: blocked with TDD reminder"
else
  fail "expected exit 2 + TDD msg. rc=$rc" "$out"
fi
rm -f "$T"

# Also Write and MultiEdit.
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'AssertionError: expected 1 got 2
FAILED tests/test_bar.py::test_thing')")

out=$(run_hook Write "/tmp/proj/src/bar.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "Write also blocked"
else
  fail "Write not blocked. rc=$rc" "$out"
fi

out=$(run_hook MultiEdit "/tmp/proj/src/bar.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "MultiEdit also blocked"
else
  fail "MultiEdit not blocked. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 2. Failure marker + test-file Edit → allowed (this IS the TDD move).
# -------------------------------------------------------------------

echo "==> 2. Failure marker + test-file Edit → allowed (target is test)"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed
exit code: 1')")

out=$(run_hook Edit "/tmp/proj/tests/test_foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "target IS test file (tests/...): allowed"
else
  fail "test-file target blocked. rc=$rc" "$out"
fi

out=$(run_hook Edit "/tmp/proj/lib/tests/foo.test.sh" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "target IS test file (.test.sh): allowed"
else
  fail "test-file target blocked. rc=$rc" "$out"
fi

out=$(run_hook Edit "/tmp/proj/internal/foo_test.go" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "target IS test file (_test.go): allowed"
else
  fail "test-file target blocked. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 3. No failure marker → allowed.
# -------------------------------------------------------------------

echo "==> 3. No failure marker in transcript → allowed"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'All tests passed.
ok    proj/foo    0.012s')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "clean transcript: source Edit allowed"
else
  fail "clean transcript blocked. rc=$rc" "$out"
fi
rm -f "$T"

# Empty transcript also fine.
T=$(mk_transcript "")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty transcript: allowed"
else
  fail "empty transcript blocked. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 4. LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1 bypass.
# -------------------------------------------------------------------

echo "==> 4. SKIP=1 bypass"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAILED: tests/test_foo.py::test_bar — assertion failed')")

payload=$(python3 -c '
import json, sys
print(json.dumps({
    "tool_name": "Edit",
    "tool_input": {"file_path": "/tmp/proj/src/foo.py"},
    "transcript_path": sys.argv[1],
}))
' "$T")
out=$(LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1 bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "SKIP=1 bypass: hook silent"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 5. Failure + test-file Edit SINCE + source-file Edit → allowed.
# -------------------------------------------------------------------

echo "==> 5. Failure → test edit (RED captured) → source Edit allowed"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed')
$(tool_use_block Edit /tmp/proj/tests/test_foo.py)
$(tool_result_block 'edit ok')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "test edit after failure clears guard: source Edit allowed"
else
  fail "guard did not clear after test edit. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 6. Missing/empty transcript_path → no-op (fail open).
# -------------------------------------------------------------------

echo "==> 6. Missing transcript_path → no-op"

payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/proj/src/foo.py"}}'
out=$(bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "missing transcript_path: hook silent (fail open)"
else
  fail "missing transcript_path triggered hook. rc=$rc" "$out"
fi

payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/proj/src/foo.py"},"transcript_path":""}'
out=$(bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty transcript_path: hook silent"
else
  fail "empty transcript_path triggered hook. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 7. Non-Edit tools → no-op.
# -------------------------------------------------------------------

echo "==> 7. Non-Edit tools → no-op"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed')")

for tool in Read Bash Glob Grep; do
  out=$(run_hook "$tool" "/tmp/proj/src/foo.py" "$T"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$tool: allowed (out of scope)"
  else
    fail "$tool blocked. rc=$rc" "$out"
  fi
done
rm -f "$T"

# -------------------------------------------------------------------
# 8. Empty file_path on Edit → no-op (let tool reject).
# -------------------------------------------------------------------

echo "==> 8. Empty file_path → no-op"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed')")

out=$(run_hook Edit "" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty file_path: hook silent"
else
  fail "empty file_path triggered hook. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 9. Multiple failure markers — only most recent wins; test edit
#    after most-recent clears.
# -------------------------------------------------------------------

echo "==> 9. Test edit after most-recent failure clears guard"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: old failure')
$(tool_use_block Bash)
$(tool_result_block 'FAIL: newer failure')
$(tool_use_block Edit /tmp/proj/tests/test_new.py)
$(tool_result_block 'edit ok')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "test edit after most-recent failure: source Edit allowed"
else
  fail "guard incorrectly fired. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 10. Failure followed by source edit followed by NEW failure →
#     blocked (the new failure resets the gate, no test edit since).
# -------------------------------------------------------------------

echo "==> 10. Failure → test edit → new failure → source Edit blocked"

T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: original failure')
$(tool_use_block Edit /tmp/proj/tests/test_foo.py)
$(tool_result_block 'edit ok')
$(tool_use_block Bash)
$(tool_result_block 'FAIL: a NEW failure after the test edit')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "new failure after test edit resets guard: source Edit blocked"
else
  fail "guard did not re-fire on new failure. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
