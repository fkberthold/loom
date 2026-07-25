#!/usr/bin/env bash
# Fixture tests for hooks/main-checkout-edit-guard.sh (loom-vr6k).
#
# THE GAP THIS CLOSES. hooks/edit-write-pwd-guard.sh (loom-ymc) is inert
# from the main checkout BY DESIGN — its own resolution rules say "cwd is
# NOT in a linked worktree -> exit 0". It models the WORKER->MAIN leak:
# cwd sits in a worktree and the target path escapes it. The INVERSE —
# central sitting in the MAIN checkout, hand-editing main, when the work
# belongs in a worktree — was covered by nothing.
#
# Live instance: 2026-07-24 in liza_base, central wrote a P0 bug's RED
# test directly into the main checkout, caught itself only after the
# fact, and the user had to say "put it on a working tree" on the very
# next bead. Three gates were down; this hook is one of them.
#
# RED contract (verbatim from the bead):
#   INVARIANT: an Edit/Write/MultiEdit whose target resolves inside the
#   MAIN checkout (not a linked worktree) while at least one bead is
#   in_progress AND whose path is source/test-eligible exits 2 with a
#   message naming the expected worktree path and the recovery command;
#   LOOM_MAIN_CHECKOUT_GUARD_SKIP=1 (literal "1" only) passes through;
#   *.md / docs/ / *.json targets pass through; no in_progress bead
#   passes through.
#
# POSTURE: BLOCK with bypass (gate-don't-advise, loom-wj26.1). The work
# either belongs in a worktree or it does not — a correctness invariant,
# not an attended decision. The bypass env var is deliberately PROMINENT
# in the block message: CLAUDE.md waves inline work through for a change
# that is <= ~15 lines AND touches a single non-test file AND adds no new
# test, and that legitimate case needs an obvious escape hatch.
#
# Run:  bash lib/tests/main-checkout-edit-guard.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/main-checkout-edit-guard.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# The hook must read the WORKTREE's libs, not MAIN's installed symlinks
# ($HOME/.claude/lib/* are install.sh symlinks into MAIN, so a
# HOME-first ladder would make a worktree's tests silently exercise
# MAIN's helpers — the same dishonest-verification shadow
# .claude/rules/dispatched-agents.md documents for Python imports).
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# --------------------------------------------------------------------
# Fixture: a plain git repo (the "main checkout") plus a linked
# worktree, and a stub `bd` on PATH whose `list --status=in_progress`
# output is controlled per-case.
#
# mk_fixture <in_progress_line>
#   echoes "main_dir<TAB>worktree_dir<TAB>bin_dir"
#   An EMPTY in_progress_line makes the stub print nothing (= no bead
#   claimed).
# --------------------------------------------------------------------
mk_fixture() {
  local ip_line="${1:-}"
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt="$root/wt"
  local bin="$root/bin"

  mkdir -p "$main" "$bin"
  (cd "$main" && git init -q -b main && git config user.email t@t && git config user.name t)
  mkdir -p "$main/lib" "$main/lib/tests" "$main/docs" "$main/hooks"
  echo "seed" > "$main/seed.txt"
  (cd "$main" && git add seed.txt && git commit -q -m seed)
  (cd "$main" && git worktree add -q "$wt" -b worker >/dev/null 2>&1)

  # `bd` stub. Only `list --status=in_progress` matters to the hook.
  {
    echo '#!/usr/bin/env bash'
    printf 'IP_LINE=%q\n' "$ip_line"
    echo 'case "$*" in'
    echo '  *"--status=in_progress"*) [ -n "$IP_LINE" ] && printf "%s\\n" "$IP_LINE"; exit 0 ;;'
    echo 'esac'
    echo 'exit 0'
  } > "$bin/bd"
  chmod +x "$bin/bd"

  printf '%s\t%s\t%s\n' "$main" "$wt" "$bin"
}

# run_hook <cwd> <bin_dir> <tool> <file_path> [ENV=VAL ...]
run_hook() {
  local cwd="$1" bin="$2" tool="$3" path="$4"; shift 4
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"file_path": sys.argv[2]}}))
' "$tool" "$path")
  (cd "$cwd" && env PATH="$bin:$PATH" "$@" bash "$HOOK" <<<"$payload" 2>&1)
}

IP="◐ loom-vr6k ● P1 [bug] main-checkout edit guard"

# ====================================================================
echo "==> 1. MAIN checkout + in_progress bead + SOURCE file -> BLOCK"
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

out=$(run_hook "$MAIN" "$BIN" Edit "lib/foo.sh"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "Edit on a source file in main checkout: exit 2"
else
  fail "expected exit 2, got rc=$rc" "$out"
fi

if echo "$out" | grep -q '\.worktrees/loom-vr6k'; then
  pass "message names the EXPECTED WORKTREE PATH"
else
  fail "message does not name the expected worktree path" "$out"
fi

if echo "$out" | grep -q 'git worktree add'; then
  pass "message names the RECOVERY COMMAND"
else
  fail "message does not name a recovery command" "$out"
fi

if echo "$out" | grep -q 'LOOM_MAIN_CHECKOUT_GUARD_SKIP=1'; then
  pass "message names the bypass env var prominently"
else
  fail "message does not name LOOM_MAIN_CHECKOUT_GUARD_SKIP=1" "$out"
fi

if echo "$out" | grep -q 'loom-vr6k'; then
  pass "message names the in_progress bead"
else
  fail "message does not name the in_progress bead" "$out"
fi

# Write + MultiEdit are the same tool class.
out=$(run_hook "$MAIN" "$BIN" Write "lib/new.sh"); rc=$?
[ "$rc" -eq 2 ] && pass "Write also blocked" || fail "Write not blocked. rc=$rc" "$out"

out=$(run_hook "$MAIN" "$BIN" MultiEdit "lib/foo.sh"); rc=$?
[ "$rc" -eq 2 ] && pass "MultiEdit also blocked" || fail "MultiEdit not blocked. rc=$rc" "$out"

# Absolute in-main path resolves the same way.
out=$(run_hook "$MAIN" "$BIN" Edit "$MAIN/lib/foo.sh"); rc=$?
[ "$rc" -eq 2 ] && pass "absolute in-main source path blocked" || fail "absolute path not blocked. rc=$rc" "$out"

# TEST files are eligible too — central hand-writing the RED test in
# main is the exact liza_base incident.
out=$(run_hook "$MAIN" "$BIN" Write "lib/tests/foo.test.sh"); rc=$?
[ "$rc" -eq 2 ] && pass "test file also blocked (the liza_base shape)" || fail "test file not blocked. rc=$rc" "$out"

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 2. Non-source/test targets pass through (*.md, docs/, *.json)"
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

for p in "README.md" "docs/reference/foo.md" "docs/anything.txt" "settings.snippet.json" "notes.md"; do
  out=$(run_hook "$MAIN" "$BIN" Edit "$p"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "non-eligible target '$p' passes through"
  else
    fail "non-eligible target '$p' blocked. rc=$rc" "$out"
  fi
done

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 3. No in_progress bead -> pass through"
# ====================================================================

FX=$(mk_fixture "")   # stub prints nothing
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

out=$(run_hook "$MAIN" "$BIN" Edit "lib/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "no bead in_progress: hook is silent"
else
  fail "hook fired with no in_progress bead. rc=$rc" "$out"
fi

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 4. cwd inside a linked worktree -> pass through"
#         (that is edit-write-pwd-guard's domain, not this hook's)
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

out=$(run_hook "$WT" "$BIN" Edit "lib/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "worktree cwd + in-worktree source: silent"
else
  fail "hook fired from a worktree cwd. rc=$rc" "$out"
fi

# A worker leaking INTO main is still edit-write-pwd-guard's job, not
# this hook's — this hook must stay silent rather than double-block.
out=$(run_hook "$WT" "$BIN" Edit "$MAIN/lib/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "worktree cwd + main-path leak: silent (edit-write-pwd-guard owns it)"
else
  fail "hook double-blocked a worker leak. rc=$rc" "$out"
fi

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 5. Target already inside a worktree dir -> pass through"
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

mkdir -p "$MAIN/.claude/worktrees/agent-abc/lib" "$MAIN/.worktrees/loom-vr6k/lib"

out=$(run_hook "$MAIN" "$BIN" Edit ".claude/worktrees/agent-abc/lib/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "target under .claude/worktrees/ passes through"
else
  fail "target under .claude/worktrees/ blocked. rc=$rc" "$out"
fi

out=$(run_hook "$MAIN" "$BIN" Edit ".worktrees/loom-vr6k/lib/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "target under .worktrees/ passes through"
else
  fail "target under .worktrees/ blocked. rc=$rc" "$out"
fi

# A target entirely OUTSIDE the main checkout is not this hook's domain.
OUTSIDE=$(mktemp -d)
out=$(run_hook "$MAIN" "$BIN" Edit "$OUTSIDE/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "target outside the main checkout passes through"
else
  fail "target outside main checkout blocked. rc=$rc" "$out"
fi
rm -rf "$OUTSIDE"

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 6. LOOM_MAIN_CHECKOUT_GUARD_SKIP — literal \"1\" only (loom-b1l)"
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

out=$(run_hook "$MAIN" "$BIN" Edit "lib/foo.sh" LOOM_MAIN_CHECKOUT_GUARD_SKIP=1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "SKIP=1 bypasses"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi

for v in yes true 0 "" 10 TRUE; do
  out=$(run_hook "$MAIN" "$BIN" Edit "lib/foo.sh" "LOOM_MAIN_CHECKOUT_GUARD_SKIP=$v"); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "SKIP='$v' does NOT bypass (still blocked)"
  else
    fail "SKIP='$v' wrongly bypassed. rc=$rc" "$out"
  fi
done

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 7. Out-of-scope inputs -> pass through"
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

for tool in Read Bash Glob Grep NotebookEdit; do
  out=$(run_hook "$MAIN" "$BIN" "$tool" "lib/foo.sh"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$tool passes through (not an Edit-class tool)"
  else
    fail "$tool blocked. rc=$rc" "$out"
  fi
done

out=$(run_hook "$MAIN" "$BIN" Edit ""); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty file_path passes through (tool will reject)"
else
  fail "empty file_path blocked. rc=$rc" "$out"
fi

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 8. Fail-open paths: no bd on PATH, and a non-git cwd"
# ====================================================================

FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)

# bd absent -> cannot know whether a bead is claimed -> stay silent.
EMPTY_BIN=$(mktemp -d)
payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "lib/foo.sh"}}))
')
out=$(cd "$MAIN" && env PATH="$EMPTY_BIN:/usr/bin:/bin" bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd absent: hook fails open"
else
  fail "bd absent: hook did not fail open. rc=$rc" "$out"
fi
rm -rf "$EMPTY_BIN"

# Non-git cwd -> no main checkout to protect -> stay silent.
NOGIT=$(mktemp -d)
out=$(run_hook "$NOGIT" "$BIN" Edit "lib/foo.sh"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "non-git cwd: hook fails open"
else
  fail "non-git cwd: hook did not fail open. rc=$rc" "$out"
fi
rm -rf "$NOGIT"

rm -rf "$(dirname "$MAIN")"

# ====================================================================
echo "==> 9. Source ladder: LOOM_TEST_LIB_DIR is consulted FIRST"
#         ($HOME/.claude/lib/* are install.sh symlinks into MAIN, so a
#          HOME-first ladder makes a worktree's tests verify MAIN.)
# ====================================================================

if grep -n 'LOOM_TEST_LIB_DIR' "$HOOK" >/dev/null 2>&1; then
  pass "hook references LOOM_TEST_LIB_DIR"
else
  fail "hook never consults LOOM_TEST_LIB_DIR"
fi

# The FIRST loom-hook-helpers.sh source line reached must be the
# LOOM_TEST_LIB_DIR branch, not the $HOME one.
first_helper_ladder=$(grep -nE 'LOOM_TEST_LIB_DIR|HOME/\.claude/lib' "$HOOK" \
  | grep -vE '^[0-9]+:[[:space:]]*#' | head -1)
case "$first_helper_ladder" in
  *LOOM_TEST_LIB_DIR*) pass "LOOM_TEST_LIB_DIR precedes \$HOME/.claude/lib in the ladder" ;;
  *) fail "ladder consults \$HOME/.claude/lib before LOOM_TEST_LIB_DIR" "$first_helper_ladder" ;;
esac

# And the sourcing must actually WORK with HOME pointed somewhere empty
# (proving the repo-relative rung exists and resolves through symlinks).
FX=$(mk_fixture "$IP")
MAIN=$(echo "$FX" | cut -f1); WT=$(echo "$FX" | cut -f2); BIN=$(echo "$FX" | cut -f3)
EMPTY_HOME=$(mktemp -d)
out=$(cd "$MAIN" && env PATH="$BIN:$PATH" HOME="$EMPTY_HOME" LOOM_TEST_LIB_DIR= \
        bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 127 ]; then
  fail "empty HOME + no LOOM_TEST_LIB_DIR: hook not invocable" "$out"
elif echo "$out" | grep -qiE "command not found|No such file or directory"; then
  fail "empty HOME + no LOOM_TEST_LIB_DIR: helper never sourced" "$out"
else
  pass "empty HOME + no LOOM_TEST_LIB_DIR: repo-relative rung resolves"
fi
rm -rf "$EMPTY_HOME" "$(dirname "$MAIN")"

# --------------------------------------------------------------------
echo ""
echo "Total: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
