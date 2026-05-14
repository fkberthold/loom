#!/usr/bin/env bash
# Fixture tests for hooks/edit-write-pwd-guard.sh.
#
# Closes loom-ymc (P1 bug): the recurring loom-path-leak where
# workers in isolated worktrees Edit/Write/MultiEdit a path that
# resolves OUTSIDE the worktree (into the parent repo / MAIN).
# Hits 5x in 2026-05-13 PM session.
#
# Hook is PreToolUse on Edit/Write/MultiEdit. It:
#   1. Detects worktree-ness via lib/worktree-detect.sh.
#   2. Resolves tool_input.file_path against cwd (relative) or
#      treats as-is (absolute).
#   3. Canonicalizes via realpath.
#   4. Rejects (exit 2) if resolved path is outside the worktree.
#   5. No-op outside worktrees, no-op for non-Edit tools.
#
# Run:  bash lib/tests/edit-write-pwd-guard.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/edit-write-pwd-guard.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook in a controlled env.
#   $1 = cwd
#   $2 = tool name (Edit / Write / MultiEdit / Read / Bash / etc.)
#   $3 = file_path arg
run_hook() {
  local cwd="$1" tool="$2" path="$3"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"file_path": sys.argv[2]}}))
' "$tool" "$path")
  (cd "$cwd" && bash "$HOOK" <<<"$payload" 2>&1)
}

# Build a main + worktree fixture.
#   echoes "main_dir worktree_dir"
mk_main_plus_worktree() {
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt="$root/wt"
  mkdir -p "$main"
  (cd "$main" && git init -q && git config user.email t@t && git config user.name t)
  echo "seed" > "$main/seed.txt"
  (cd "$main" && git add seed.txt && git commit -q -m "seed")
  (cd "$main" && git worktree add -q "$wt" -b worker 2>&1 >/dev/null)
  printf '%s\t%s\n' "$main" "$wt"
}

# Source the LOOM_ROOT's worktree-detect.sh (the hook will use the
# installed one via $HOME/.claude/lib/, but for tests we need the
# repo-local copy reachable).
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# -------------------------------------------------------------------
# 1. Worktree cwd + Edit on path INSIDE worktree → allow.
# -------------------------------------------------------------------

echo "==> 1. Worktree cwd + Edit on in-worktree path → allow"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# Absolute path inside worktree.
out=$(run_hook "$WT" Edit "$WT/some-file.txt"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "absolute path inside worktree: allowed"
else
  fail "absolute in-worktree path blocked. rc=$rc" "$out"
fi

# Relative path that resolves to worktree.
out=$(run_hook "$WT" Edit "some-file.txt"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "relative path inside worktree: allowed"
else
  fail "relative in-worktree path blocked. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 2. Worktree cwd + Edit on absolute path in MAIN → reject.
# -------------------------------------------------------------------

echo "==> 2. Worktree cwd + Edit on absolute MAIN path → reject (Mode 1)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(run_hook "$WT" Edit "$MAIN/seed.txt"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "outside"; then
  pass "absolute main path from worktree: blocked with explanation"
else
  fail "expected exit 2 + 'outside' msg. rc=$rc" "$out"
fi

# Write tool too.
out=$(run_hook "$WT" Write "$MAIN/new-file.txt"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "Write tool also blocked"
else
  fail "Write not blocked. rc=$rc" "$out"
fi

# MultiEdit too.
out=$(run_hook "$WT" MultiEdit "$MAIN/seed.txt"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "MultiEdit tool also blocked"
else
  fail "MultiEdit not blocked. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 3. Worktree cwd + relative path with .. escape → reject (Mode 4).
# -------------------------------------------------------------------

echo "==> 3. Worktree cwd + relative ../escape → reject (Mode 4)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# The relative path "../../main/seed.txt" from WT resolves OUT of worktree.
# WT is at ${root}/wt; ../../main/seed.txt from there hits ${root}/main/seed.txt → MAIN.
out=$(run_hook "$WT" Edit "../main/seed.txt"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "outside"; then
  pass "relative escape (../) blocked"
else
  fail "relative escape allowed. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 4. Main cwd + Edit on anything → allow (hook is no-op).
# -------------------------------------------------------------------

echo "==> 4. Main cwd → no-op (allow everything)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(run_hook "$MAIN" Edit "$MAIN/seed.txt"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "main cwd + main path: allowed"
else
  fail "main cwd hook fired. rc=$rc" "$out"
fi

# Even Edit on a worktree path from main is fine — outside the bug's domain.
out=$(run_hook "$MAIN" Edit "$WT/some.txt"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "main cwd + worktree path: allowed (out of scope)"
else
  fail "main cwd + worktree path blocked. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 5. Non-Edit tools → no-op.
# -------------------------------------------------------------------

echo "==> 5. Non-Edit tools → no-op"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

for tool in Read Bash Glob Grep; do
  out=$(run_hook "$WT" "$tool" "$MAIN/seed.txt"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$tool from worktree on main path: allowed (out of scope)"
  else
    fail "$tool blocked. rc=$rc" "$out"
  fi
done
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 6. Missing file_path → no-op (let the tool handle it).
# -------------------------------------------------------------------

echo "==> 6. Edit with empty file_path → no-op"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(run_hook "$WT" Edit ""); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty file_path: hook is silent (tool will reject)"
else
  fail "empty file_path triggered hook. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 7. LOOM_EDIT_WRITE_GUARD_SKIP=1 bypass for intentional cross-tree ops.
# -------------------------------------------------------------------

echo "==> 7. LOOM_EDIT_WRITE_GUARD_SKIP=1 bypass"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": sys.argv[1]}}))
' "$MAIN/seed.txt")
out=$(cd "$WT" && LOOM_EDIT_WRITE_GUARD_SKIP=1 bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "SKIP=1 bypass: hook silent"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
