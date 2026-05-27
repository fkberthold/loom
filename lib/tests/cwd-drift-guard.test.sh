#!/usr/bin/env bash
# Fixture tests for hooks/cwd-drift-guard.sh.
#
# Closes loom-d2o (P3 bug): central-side cwd-drift under parallel
# dispatch. When central's persistent-bash cwd silently resolves
# into a `.claude/worktrees/agent-*/` after a worker dispatch
# returns, central-context ops (git merge, git push, bd close,
# bd update, bd dolt push) mis-route — observed 2026-05-27 during
# loom-7p6/cuk parallel completion.
#
# Hook is PreToolUse on Bash. It:
#   1. Parses tool_input.command from stdin JSON.
#   2. Skips unless tool_name == "Bash".
#   3. Resolves cwd via realpath.
#   4. Checks if cwd is under any .claude/worktrees/agent-*/ path.
#   5. Matches command against the central-op allowlist regex:
#      git merge, git push, bd close, bd update, bd dolt push.
#   6. Refuses (exit 2) with recovery message when BOTH match.
#   7. Bypass: LOOM_CWD_DRIFT_GUARD_SKIP=1 (literal "1" match).
#
# Run:  bash lib/tests/cwd-drift-guard.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/cwd-drift-guard.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook in a controlled env.
#   $1 = cwd
#   $2 = tool name (Bash / Edit / etc.)
#   $3 = command string
#   $4 = optional extra env (string like "FOO=bar BAZ=qux")
run_hook() {
  local cwd="$1" tool="$2" cmd="$3" extra="${4:-}"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))
' "$tool" "$cmd")
  if [ -n "$extra" ]; then
    (cd "$cwd" && env $extra bash "$HOOK" <<<"$payload" 2>&1)
  else
    (cd "$cwd" && bash "$HOOK" <<<"$payload" 2>&1)
  fi
}

# Build a main + worktree fixture.
# Note: the worktree path must contain ".claude/worktrees/agent-<id>"
# because the hook keys off that path pattern.
#   echoes "main_dir worktree_dir"
mk_main_plus_worktree() {
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt_parent="$main/.claude/worktrees"
  local wt="$wt_parent/agent-test123"
  mkdir -p "$main" "$wt_parent"
  (cd "$main" && git init -q && git config user.email t@t && git config user.name t)
  echo "seed" > "$main/seed.txt"
  (cd "$main" && git add seed.txt && git commit -q -m "seed")
  (cd "$main" && git worktree add -q "$wt" -b worker-test 2>&1 >/dev/null)
  printf '%s\t%s\n' "$main" "$wt"
}

export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# -------------------------------------------------------------------
# 1. Worktree cwd + `git merge --no-ff frank/foo` → refuse.
# -------------------------------------------------------------------

echo "==> 1. Worktree cwd + git merge → refuse (exit 2)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(run_hook "$WT" Bash "git merge --no-ff frank/foo"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "worktree" && echo "$out" | grep -qi "cd "; then
  pass "git merge from worktree: blocked with recovery hint"
else
  fail "git merge not blocked or missing hint. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 2. Worktree cwd + `git push` → refuse.
# -------------------------------------------------------------------

echo "==> 2. Worktree cwd + git push → refuse"

out=$(run_hook "$WT" Bash "git push"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "git push from worktree: blocked"
else
  fail "git push not blocked. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 3. Worktree cwd + `bd close` → refuse.
# -------------------------------------------------------------------

echo "==> 3. Worktree cwd + bd close → refuse"

out=$(run_hook "$WT" Bash "bd close loom-foo"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "bd close from worktree: blocked"
else
  fail "bd close not blocked. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 4. Worktree cwd + `bd update` → refuse.
# -------------------------------------------------------------------

echo "==> 4. Worktree cwd + bd update → refuse"

out=$(run_hook "$WT" Bash "bd update loom-foo --notes=\"x\""); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "bd update from worktree: blocked"
else
  fail "bd update not blocked. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 5. Worktree cwd + `bd dolt push` → refuse.
# -------------------------------------------------------------------

echo "==> 5. Worktree cwd + bd dolt push → refuse"

out=$(run_hook "$WT" Bash "bd dolt push"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "bd dolt push from worktree: blocked"
else
  fail "bd dolt push not blocked. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 6. Main cwd + central ops → allow (hook is no-op outside worktree).
# -------------------------------------------------------------------

echo "==> 6. Main cwd + central ops → allow"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

for cmd in "git merge --no-ff frank/foo" "git push" "bd close loom-foo" "bd update loom-foo --notes=x" "bd dolt push"; do
  out=$(run_hook "$MAIN" Bash "$cmd"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "main cwd + '$cmd': allowed"
  else
    fail "main cwd hook fired. rc=$rc cmd=$cmd" "$out"
  fi
done

# -------------------------------------------------------------------
# 7. Worktree cwd + read-only git → allow.
# -------------------------------------------------------------------

echo "==> 7. Worktree cwd + read-only ops → allow"

for cmd in "git status" "git log" "git diff" "git branch --show-current"; do
  out=$(run_hook "$WT" Bash "$cmd"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "worktree cwd + '$cmd': allowed"
  else
    fail "read-only blocked. rc=$rc cmd=$cmd" "$out"
  fi
done

# -------------------------------------------------------------------
# 8. LOOM_CWD_DRIFT_GUARD_SKIP=1 bypass.
# -------------------------------------------------------------------

echo "==> 8. SKIP=1 bypass"

out=$(run_hook "$WT" Bash "git merge --no-ff frank/foo" "LOOM_CWD_DRIFT_GUARD_SKIP=1"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "SKIP=1 bypass: hook silent"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 9. SKIP=yes / SKIP=true / SKIP=0 / SKIP= → still refuses (literal-1 match).
# -------------------------------------------------------------------

echo "==> 9. SKIP non-1 values still refuse (literal-1 convention)"

for val in yes true 0 ""; do
  out=$(run_hook "$WT" Bash "git merge --no-ff frank/foo" "LOOM_CWD_DRIFT_GUARD_SKIP=$val"); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "SKIP='$val' (non-literal-1): refuses"
  else
    fail "SKIP='$val' incorrectly bypassed. rc=$rc" "$out"
  fi
done

# -------------------------------------------------------------------
# 10. Worktree cwd + `bd list` (read-class bd) → allow.
# -------------------------------------------------------------------

echo "==> 10. Worktree cwd + bd list (read-only) → allow"

out=$(run_hook "$WT" Bash "bd list"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd list from worktree: allowed (not in allowlist)"
else
  fail "bd list incorrectly blocked. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 11. Class shape — whitespace variants must still match.
# -------------------------------------------------------------------

echo "==> 11. Whitespace variants — git  merge (double space), bd  close"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(run_hook "$WT" Bash "git  merge --no-ff frank/foo"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "git<spaces>merge: blocked (whitespace-tolerant)"
else
  fail "git<spaces>merge not blocked. rc=$rc" "$out"
fi

out=$(run_hook "$WT" Bash "bd  close loom-foo"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "bd<spaces>close: blocked (whitespace-tolerant)"
else
  fail "bd<spaces>close not blocked. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 12. Class shape — git --no-pager merge should still match
#     (git options between git and the subcommand).
# -------------------------------------------------------------------

echo "==> 12. git --no-pager merge variant"

out=$(run_hook "$WT" Bash "git --no-pager merge --no-ff frank/foo"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "git --no-pager merge: blocked (option-tolerant)"
else
  fail "git --no-pager merge not blocked. rc=$rc" "$out"
fi

# -------------------------------------------------------------------
# 13. Tool-name guard — Edit/Read/Write tool payloads must be ignored.
# -------------------------------------------------------------------

echo "==> 13. Non-Bash tool payloads → no-op"

for tool in Edit Read Write MultiEdit Glob Grep; do
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"file_path": "/tmp/foo"}}))
' "$tool")
  out=$(cd "$WT" && bash "$HOOK" <<<"$payload" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$tool tool payload: ignored"
  else
    fail "$tool blocked. rc=$rc" "$out"
  fi
done
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 14. Empty command → no-op.
# -------------------------------------------------------------------

echo "==> 14. Empty command → no-op"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(run_hook "$WT" Bash ""); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty command: hook silent"
else
  fail "empty command triggered hook. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
