#!/usr/bin/env bash
# Fixture tests for hooks/edit-after-failure-guard.sh.
#
# Closes loom-z3m.6 (introduces hook). Extended by loom-7j5 with
# sections 11-13 covering the three bug-class fixes: tool_use_id
# source-discrimination, tighter failure-marker framing, and hook
# self-reference whitelist.
#
# The recurring TDD-discipline-slip the hook addresses: an agent's
# first move after a test/build failure is to Edit the source file
# (writing the fix before pinning the failure with a RED test).
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

# loom-n1q: tests MUST be hermetic from the user's shell env. If the
# user exports LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1 in .zshenv or
# similar (a common workaround for false positives), it propagates
# into every test invocation and silently bypasses the hook — turning
# every "expected BLOCK" assertion into a false PASS / unexpected
# FAIL. Unset at fixture startup so the bypass-bypass test (case 4)
# is the only path that exercises the env-var bypass.
unset LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP

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
  # $1 = tool name, $2 = file_path (Edit/Write/MultiEdit) or empty,
  # $3 = tool_use id (default "x"). Pass an explicit id when a section
  # needs to pair a tool_use with a non-default tool_use_id on a
  # following tool_result block.
  local tool="$1" fp="${2:-}" id="${3:-x}"
  python3 -c '
import json, sys
tool = sys.argv[1]
fp = sys.argv[2]
id_ = sys.argv[3]
inp = {"file_path": fp} if fp else {}
rec = {
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [
            {"type": "tool_use", "id": id_, "name": tool, "input": inp}
        ],
    },
}
print(json.dumps(rec))
' "$tool" "$fp" "$id"
}

tool_result_block() {
  # $1 = output text (the result body), $2 = tool_use_id (default "x").
  local out="$1" id="${2:-x}"
  python3 -c '
import json, sys
text = sys.argv[1]
id_ = sys.argv[2]
rec = {
    "type": "user",
    "message": {
        "role": "user",
        "content": [
            {"type": "tool_result", "tool_use_id": id_, "content": text}
        ],
    },
}
print(json.dumps(rec))
' "$out" "$id"
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
# 11. Non-Bash tool_result with FAIL substring → allowed (loom-7j5
#     fix #1: source-discriminate via tool_use_id pairing).
#
#     The hook scans only Bash-originated tool_results for failure
#     markers. Reading docs / drawers / source / bead descriptions
#     via Read or MCP tools must not trip the guard, even when the
#     returned text contains "fail" / "failed" / "failure" prose.
# -------------------------------------------------------------------

echo "==> 11. Non-Bash tool_result with FAIL substring → allowed (fix #1)"

# 11a. mempalace_search returning a drawer body with "Failure mode:".
T=$(mk_transcript "$(tool_use_block mcp__plugin_mempalace_mempalace__mempalace_search '' a1)
$(tool_result_block 'Failure mode: arbiter down — partial recovery.' a1)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "mempalace_search FAIL-prose result: allowed"
else
  fail "mempalace_search result tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 11b. Read tool returning source with FAILED identifier.
T=$(mk_transcript "$(tool_use_block Read '' a2)
$(tool_result_block 'TestGroupSetupFailed --> TestGroupTestsDone : remaining tests force-failed' a2)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Read tool result with FAILED identifier: allowed"
else
  fail "Read result with FAILED identifier tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 11c. mempalace_get_drawer with Go source containing log.Fatalf.
T=$(mk_transcript "$(tool_use_block mcp__plugin_mempalace_mempalace__mempalace_get_drawer '' a3)
$(tool_result_block 'log.Fatalf(ctx, err, \"failed to connect to upstream\")' a3)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "mempalace_get_drawer with Go source quote: allowed"
else
  fail "mempalace_get_drawer source quote tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 11d. Positive control — Bash tool_result with real pytest failure
#      still blocks (fix #1 doesn't loosen real detection).
T=$(mk_transcript "$(tool_use_block Bash '' b1)
$(tool_result_block 'Running tests...
test_foo.py::test_bar FAILED
======= 1 failed, 0 passed =======' b1)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "Bash + real pytest failure: still blocks (positive control)"
else
  fail "real Bash failure no longer blocks. rc=$rc" "$out"
fi
rm -f "$T"

# 11e. Mixed — non-Bash FAIL prose + Bash success → allowed.
T=$(mk_transcript "$(tool_use_block Read '' a5)
$(tool_result_block 'Page contains: Failure mode: arbiter down — partial' a5)
$(tool_use_block Bash '' b2)
$(tool_result_block 'OK: all 50 tests passed' b2)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "non-Bash FAIL prose + Bash success: allowed"
else
  fail "mixed transcript blocked. rc=$rc" "$out"
fi
rm -f "$T"

# 11f. Orphaned tool_use_id (tool_result whose preceding tool_use
#      fell outside the tail window) → allowed (fail-safe).
T=$(mk_transcript "$(tool_result_block 'FAILED tests/foo.py::test_bar' orphan)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "orphaned tool_use_id: allowed (fail-safe)"
else
  fail "orphan tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 12. Bash output with prose "fail" only → allowed (loom-7j5 fix #2:
#     tighter failure-marker framing). The lax \bFAIL(?:ED|URE)?\b
#     substring match is replaced with start-of-line and known-framing
#     patterns. Real pytest / go test / panic / npm output still blocks.
# -------------------------------------------------------------------

echo "==> 12. Bash prose 'fail' without test framing → allowed (fix #2)"

# 12a. Bash cat of a doc file containing "Failure mode" prose.
T=$(mk_transcript "$(tool_use_block Bash '' c1)
$(tool_result_block 'NOTES.md content:
This section discusses Failure mode handling for the arbiter.
The component recovers gracefully.' c1)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Bash cat of doc with 'Failure mode' prose: allowed"
else
  fail "Bash doc prose tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 12b. Bash curl response body with "failed to respond" prose.
T=$(mk_transcript "$(tool_use_block Bash '' c2)
$(tool_result_block 'response: {\"message\": \"upstream temporarily failed to respond\"}' c2)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Bash curl 'failed to respond' prose: allowed"
else
  fail "Bash response prose tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 12c. bd show description text containing "Hard-failure detection".
T=$(mk_transcript "$(tool_use_block Bash '' c3)
$(tool_result_block 'DESCRIPTION
Hard-failure detection (mark-failed, do not re-queue) on backend' c3)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd show 'Hard-failure detection' prose: allowed"
else
  fail "bd show prose tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 12d. Positive control — pytest brief "FAILED tests/foo.py::test_bar".
T=$(mk_transcript "$(tool_use_block Bash '' c4)
$(tool_result_block 'FAILED tests/foo.py::test_bar - AssertionError: 1 != 2' c4)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "pytest brief 'FAILED <path>::<test>': blocks (positive control)"
else
  fail "pytest brief no longer blocks. rc=$rc" "$out"
fi
rm -f "$T"

# 12e. Positive control — Go test verbose "--- FAIL: TestFoo".
T=$(mk_transcript "$(tool_use_block Bash '' c5)
$(tool_result_block '=== RUN TestFoo
--- FAIL: TestFoo (0.00s)' c5)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "go test '--- FAIL: TestFoo': blocks (positive control)"
else
  fail "go test verbose no longer blocks. rc=$rc" "$out"
fi
rm -f "$T"

# 12f. Positive control — Go panic "panic: runtime error".
T=$(mk_transcript "$(tool_use_block Bash '' c6)
$(tool_result_block 'panic: runtime error: index out of range
goroutine 1 [running]:' c6)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "go panic 'panic: ...': blocks (positive control)"
else
  fail "go panic no longer blocks. rc=$rc" "$out"
fi
rm -f "$T"

# 12g. Positive control — pytest summary "1 failed, 2 passed".
T=$(mk_transcript "$(tool_use_block Bash '' c7)
$(tool_result_block '===== 1 failed, 2 passed in 0.42s =====' c7)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "pytest summary 'N failed, M passed': blocks (positive control)"
else
  fail "pytest summary no longer blocks. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 13. Bash result containing 'edit-after-failure-guard' → allowed
#     (loom-7j5 fix #3: self-reference whitelist). Prevents the
#     recursive-self-trigger sub-bug where the hook's BLOCKED output
#     becomes a failure marker for the next Edit/Write attempt.
# -------------------------------------------------------------------

echo "==> 13. Bash result with hook self-reference → allowed (fix #3)"

# 13a. Bash cat of the hook source itself (debugging the hook).
T=$(mk_transcript "$(tool_use_block Bash '' d1)
$(tool_result_block '#!/usr/bin/env bash
# PreToolUse hook edit-after-failure-guard.sh
# Detects test/build FAILURE markers in transcript tail.
# Refuses Edit when assertion failed was seen recently.' d1)")
out=$(run_hook Edit "/tmp/proj/hooks/edit-after-failure-guard.sh" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Bash cat of hook source with self-reference: allowed"
else
  fail "hook self-reference tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 13b. Previous hook invocation's own BLOCKED message in transcript.
T=$(mk_transcript "$(tool_use_block Bash '' d2)
$(tool_result_block '[edit-after-failure-guard] BLOCKED: Edit refused.
A test or build failure was observed in recent Bash output' d2)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "previous hook BLOCKED message: allowed (no recursive trigger)"
else
  fail "hook BLOCKED self-message tripped guard. rc=$rc" "$out"
fi
rm -f "$T"

# 13c. Positive control — hook self-ref + later real Bash failure
#      → still blocks (the new failure resets the gate).
T=$(mk_transcript "$(tool_use_block Bash '' d3)
$(tool_result_block '[edit-after-failure-guard] BLOCKED: Edit refused.' d3)
$(tool_use_block Bash '' d4)
$(tool_result_block 'FAILED tests/foo.py::test_bar - AssertionError' d4)")
out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "hook self-ref + later real failure: still blocks (positive control)"
else
  fail "real failure after hook self-ref didn't block. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 14. loom-n1q — git-merge CONFLICT whitelist.
# Pattern: a git merge with conflicts produces output that includes
# "CONFLICT (content):" + "Automatic merge failed; fix conflicts and
# then commit the result." The Bash tool framing then appends
# "Exit code: 1" which trips FAIL_RE. But the user's REQUIRED next
# action is to Edit the conflicting files — exactly what the guard
# refuses. Treat git-merge conflict signals like the self-ref
# whitelist: skip the failure-marker check for that tool_result.
# -------------------------------------------------------------------

echo "==> 14. Git-merge CONFLICT whitelist (loom-n1q)"

# 14a. Conflict text + "Exit code: 1" trailer → allow (would otherwise
#      trip on "Exit code: 1").
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'Auto-merging .beads/issues.jsonl
CONFLICT (content): Merge conflict in .beads/issues.jsonl
Automatic merge failed; fix conflicts and then commit the result.
Exit code: 1')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "git merge CONFLICT + Exit code: 1 → allowed"
else
  fail "merge CONFLICT blocked. rc=$rc" "$out"
fi
rm -f "$T"

# 14b. Just "Automatic merge failed" without CONFLICT line → still
#      whitelisted (defensive — git phrasing might vary).
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'Auto-merging foo.txt
Automatic merge failed; fix conflicts and then commit the result.
Exit code: 1')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Automatic merge failed (no CONFLICT line) → allowed"
else
  fail "Automatic-merge-failed-only blocked. rc=$rc" "$out"
fi
rm -f "$T"

# 14c. Positive control — text with literal word "conflict" but NOT
#      the git-merge framing → still blocks if FAIL_RE matches.
#      ("conflict" alone isn't a discriminator.)
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: tests/test_foo.py - resource conflict detected')")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "word 'conflict' without git framing: still blocks (positive control)"
else
  fail "conflict-word-alone failed to block. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 15. loom-n1q — TTL via "last-Bash-only" semantics.
# Pattern: a Python traceback or test failure appears, then the agent
# runs a NEW Bash command that succeeds (or simply doesn't contain
# failure markers). The latch should clear — the failure was recovered
# from in the very next Bash call. Currently the failure latches for
# the full 80-record tail with no TTL.
# Fix: only consider the MOST RECENT Bash tool_result. If it lacks
# failure markers, ALLOW regardless of any prior Bash failure.
# -------------------------------------------------------------------

echo "==> 15. TTL — last-Bash-only semantics (loom-n1q)"

# 15a. Python traceback followed by clean Bash → allow (recovered).
T=$(mk_transcript "$(tool_use_block Bash '' e1)
$(tool_result_block 'Traceback (most recent call last):
  File \"<string>\", line 1, in <module>
ImportError: No module named foo' e1)
$(tool_use_block Bash '' e2)
$(tool_result_block 'foo bar baz' e2)")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "traceback then clean Bash → allowed (TTL cleared)"
else
  fail "traceback latched past clean Bash. rc=$rc" "$out"
fi
rm -f "$T"

# 15b. Two failures in a row (no clean Bash between) → still blocks.
T=$(mk_transcript "$(tool_use_block Bash '' e3)
$(tool_result_block 'FAIL: test_foo failed' e3)
$(tool_use_block Bash '' e4)
$(tool_result_block 'FAIL: test_bar failed' e4)")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "two failures back-to-back: blocks (positive control)"
else
  fail "back-to-back failures didn't block. rc=$rc" "$out"
fi
rm -f "$T"

# 15c. Failure → clean Bash → failure → block (latest Bash decides).
T=$(mk_transcript "$(tool_use_block Bash '' e5)
$(tool_result_block 'FAIL: old failure' e5)
$(tool_use_block Bash '' e6)
$(tool_result_block 'ok, all good' e6)
$(tool_use_block Bash '' e7)
$(tool_result_block 'FAIL: new failure' e7)")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "fail → clean → fail: blocks on the latest (positive control)"
else
  fail "latest-failure not seen. rc=$rc" "$out"
fi
rm -f "$T"

# 15d. Failure → non-Bash tool_results (Read/MemPalace) → clean Bash
#      → allow. Intervening non-Bash results don't keep the latch.
T=$(mk_transcript "$(tool_use_block Bash '' e8)
$(tool_result_block 'FAIL: test_foo failed' e8)
$(tool_use_block Read /tmp/foo e9)
$(tool_result_block 'file contents' e9)
$(tool_use_block Bash '' e10)
$(tool_result_block 'clean output' e10)")

out=$(run_hook Edit "/tmp/proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "failure → non-Bash → clean Bash → allowed (last Bash wins)"
else
  fail "non-Bash intervening kept latch. rc=$rc" "$out"
fi
rm -f "$T"

# -------------------------------------------------------------------
# 16. loom-n1q — per-project marker file bypass.
# Pattern: the env-var bypass LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1
# must be set before `claude` forks; in-session export is a no-op
# (the agent's exported env doesn't reach the hook spawned by the
# harness). Reachable alternative: a marker file at
# <project>/.claude/no-edit-after-failure-guard that any agent can
# create with one Bash call. When present, hook exits 0.
# -------------------------------------------------------------------

echo "==> 16. Per-project marker-file bypass (loom-n1q)"

# Helper: build a fake project root with .claude/, .git/, and an
# optional marker. Returns the dir.
mk_proj_root() {
  local with_marker="$1"
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.git"
  if [ "$with_marker" = "yes" ]; then
    touch "$d/.claude/no-edit-after-failure-guard"
  fi
  printf '%s' "$d"
}

# 16a. Marker present in project root → allow even with failure.
proj=$(mk_proj_root yes)
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed
1 failed, 0 passed')")

# Run from inside the fake project's src/ subdir; the hook should
# walk up to find the marker.
mkdir -p "$proj/src"
out=$(cd "$proj/src" && run_hook Edit "$proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "marker file at project root → allowed (failure present but bypassed)"
else
  fail "marker file did not bypass. rc=$rc" "$out"
fi
rm -rf "$proj"
rm -f "$T"

# 16b. No marker in project root → still blocks (positive control).
proj=$(mk_proj_root no)
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed
1 failed, 0 passed')")

mkdir -p "$proj/src"
out=$(cd "$proj/src" && run_hook Edit "$proj/src/foo.py" "$T"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "no marker file → still blocks (positive control)"
else
  fail "no-marker did not block. rc=$rc" "$out"
fi
rm -rf "$proj"
rm -f "$T"

# 16c. Marker file works from deeper subdir too.
proj=$(mk_proj_root yes)
mkdir -p "$proj/a/b/c/d"
T=$(mk_transcript "$(tool_use_block Bash)
$(tool_result_block 'FAIL: test_foo failed
1 failed, 0 passed')")

out=$(cd "$proj/a/b/c/d" && run_hook Edit "$proj/a/b/c/d/foo.py" "$T"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "marker found via walk-up from deep subdir → allowed"
else
  fail "walk-up to marker failed. rc=$rc" "$out"
fi
rm -rf "$proj"
rm -f "$T"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
