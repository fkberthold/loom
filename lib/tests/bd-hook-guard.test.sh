#!/usr/bin/env bash
# Fixture tests for the bd-fail-open guard on PURELY-bd-dependent hooks
# (loom-svcj).
#
# INVARIANT: a purely-bd-dependent loom hook exits 0 (no-op) when `bd`
# is not on PATH, WITHOUT disabling any non-bd hook's protection.
#
# Motivation: in an apartment / non-loom session where bd is not
# installed, hooks whose ENTIRE job is bd-state work should fail open —
# exit 0, do nothing — rather than error or do partial work. The fix is
# a top-of-file guard:
#
#     command -v bd >/dev/null 2>&1 || exit 0
#
# placed after the shebang + comment block + any existing skip/bypass
# env-var check, before the first bd-touching logic.
#
# SAFETY: only the PURELY-bd subset gets the guard. Hooks that also do
# non-bd work (pre-push-mkdocs-strict, bd-preflight-docs-strict,
# edit-after-failure-guard, cwd-drift-guard) must NOT carry it — a
# top-level fail-open would disable their non-bd protection when bd is
# absent. Part B below is the guard-rail that pins this.
#
# The four purely-bd hooks under test:
#   hooks/bd-prime-wrapper.sh      (SessionStart: shells `bd prime`)
#   hooks/post-rewrite.sh          (post-rewrite: re-export from dolt)
#   hooks/bd-worktree-preseed.sh   (PreToolUse bd matcher: seed dolt)
#   hooks/git-push-bd-sync.sh      (PreToolUse git push: bd-state nudge)
#
# Run:  bash lib/tests/bd-hook-guard.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="$LOOM_ROOT/hooks"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# A PATH that deliberately EXCLUDES any directory carrying `bd`. We
# build it from the standard system dirs, then defensively prune any
# entry that contains a `bd` executable (covers a `bd` installed under
# /usr/local/bin or similar).
build_bdless_path() {
  local candidate dir kept=""
  for dir in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$dir" ] || continue
    if [ -x "$dir/bd" ]; then continue; fi
    kept="${kept:+$kept:}$dir"
  done
  echo "$kept"
}

BDLESS_PATH=$(build_bdless_path)

# Sanity: `bd` must NOT be resolvable under BDLESS_PATH, or the test
# proves nothing.
if PATH="$BDLESS_PATH" command -v bd >/dev/null 2>&1; then
  echo "SETUP ERROR: bd is still resolvable under the stripped PATH ($BDLESS_PATH)" >&2
  echo "             cannot prove fail-open; aborting." >&2
  exit 1
fi

# Run a hook with bd stripped from PATH, feeding it STDIN, capturing
# rc + combined output. We preserve a clean environment but force the
# bd-less PATH. BD_BIN is unset so the hooks fall back to the literal
# `bd`, which is what `command -v bd` then fails to find.
run_bdless() {
  local hook="$1" stdin="$2"; shift 2
  printf '%s' "$stdin" | env -u BD_BIN PATH="$BDLESS_PATH" bash "$hook" "$@" 2>&1
}

# =====================================================================
# Part A — each purely-bd hook fails open (exit 0, no-op) without bd
# =====================================================================

echo "==> Part A: purely-bd hooks exit 0 (no-op) when bd is absent"

# --- A1. bd-prime-wrapper.sh -----------------------------------------
# SessionStart payload. With no bd, the guard must short-circuit BEFORE
# the `bd prime` shell-out — exit 0 and emit NOTHING (no python
# post-processing of absent output).
out=$(run_bdless "$HOOKS/bd-prime-wrapper.sh" '{"hook_event_name":"SessionStart"}'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd-prime-wrapper: exits 0 without bd"
else
  fail "bd-prime-wrapper: rc=$rc (expected 0)" "$out"
fi
if [ -z "$out" ]; then
  pass "bd-prime-wrapper: no-op (empty output) without bd"
else
  fail "bd-prime-wrapper: emitted output without bd" "$out"
fi

# --- A2. post-rewrite.sh ---------------------------------------------
# Build a tiny git repo with .beads/ so the hook gets PAST the
# git-worktree + .beads checks and would otherwise reach bd work. With
# the top-of-file guard it must exit 0 WITHOUT creating a commit and
# WITHOUT touching .beads/issues.jsonl.
WORK=$(mktemp -d)
REPO="$WORK/repo"
mkdir -p "$REPO/.beads"
printf '%s' '{"id":"loom-aaa","status":"in_progress"}' > "$REPO/.beads/issues.jsonl"
( cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t )
( cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m seed )
orig_head=$( cd "$REPO" && git rev-parse HEAD )
orig_jsonl=$( cat "$REPO/.beads/issues.jsonl" )

out=$( cd "$REPO" && printf '' | env -u BD_BIN PATH="$BDLESS_PATH" bash "$HOOKS/post-rewrite.sh" rebase 2>&1 ); rc=$?
new_head=$( cd "$REPO" && git rev-parse HEAD )
new_jsonl=$( cat "$REPO/.beads/issues.jsonl" )

if [ "$rc" -eq 0 ]; then
  pass "post-rewrite: exits 0 without bd"
else
  fail "post-rewrite: rc=$rc (expected 0)" "$out"
fi
if [ "$orig_head" = "$new_head" ] && [ "$orig_jsonl" = "$new_jsonl" ]; then
  pass "post-rewrite: no-op (no commit, jsonl untouched) without bd"
else
  fail "post-rewrite: mutated state without bd (head $orig_head->$new_head)" "$out"
fi
rm -rf "$WORK"

# --- A3. bd-worktree-preseed.sh --------------------------------------
# PreToolUse payload for a write-class bd command. Without bd on PATH
# the guard must short-circuit (exit 0) before any import/config work.
PRESEED_INPUT='{"tool_name":"Bash","tool_input":{"command":"bd update loom-x --claim"}}'
out=$(run_bdless "$HOOKS/bd-worktree-preseed.sh" "$PRESEED_INPUT"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd-worktree-preseed: exits 0 without bd"
else
  fail "bd-worktree-preseed: rc=$rc (expected 0)" "$out"
fi

# --- A4. git-push-bd-sync.sh -----------------------------------------
# PreToolUse payload for a git push. Without bd there is nothing to
# sync; the guard must short-circuit (exit 0) and emit NO advisory.
PUSH_INPUT='{"tool_name":"Bash","tool_input":{"command":"git push"}}'
out=$(run_bdless "$HOOKS/git-push-bd-sync.sh" "$PUSH_INPUT"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "git-push-bd-sync: exits 0 without bd"
else
  fail "git-push-bd-sync: rc=$rc (expected 0)" "$out"
fi
if ! echo "$out" | grep -q 'git-push-bd-sync hook'; then
  pass "git-push-bd-sync: no advisory emitted without bd"
else
  fail "git-push-bd-sync: emitted bd-sync advisory without bd" "$out"
fi

# =====================================================================
# Part A' — the guard is PRESENT, near top-of-file, in each hook
# =====================================================================
#
# Behavioral checks above are necessary but the guard could in
# principle pass them via late checks; pin that the canonical
# top-of-file guard line actually exists in each of the four hooks.

echo "==> Part A': canonical 'command -v bd' guard present in each purely-bd hook"
for h in bd-prime-wrapper post-rewrite bd-worktree-preseed git-push-bd-sync; do
  if grep -qE 'command -v (bd|"\$\{?BD_BIN)' "$HOOKS/$h.sh"; then
    pass "$h.sh carries a command -v bd fail-open guard"
  else
    fail "$h.sh missing command -v bd fail-open guard"
  fi
done

# =====================================================================
# Part B — GUARD-RAIL: non-bd hooks are NOT disabled by this change
# =====================================================================
#
# A naive top-of-file sweep would also guard hooks that do non-bd work,
# silently disabling that protection when bd is absent. Pin that the
# two canonical non-bd guards do NOT carry a top-level
# `command -v bd || exit 0`, and still perform their own guarding.

echo "==> Part B: non-bd hooks NOT disabled (guard-rail)"

# B1. cwd-drift-guard.sh guards git merge/push too — must NOT fail-open
#     on bd absence (that would disable its git-side protection).
if grep -qE 'command -v (bd|"\$\{?BD_BIN)[^|]*\|\| *exit 0' "$HOOKS/cwd-drift-guard.sh"; then
  fail "cwd-drift-guard.sh has a top-level command-v-bd fail-open (would disable git-merge/push protection)"
else
  pass "cwd-drift-guard.sh has NO command-v-bd fail-open"
fi
# It still performs its central-op guard (refuses from a worktree cwd).
if grep -qE 'exit 2' "$HOOKS/cwd-drift-guard.sh"; then
  pass "cwd-drift-guard.sh still performs its exit-2 refusal guard"
else
  fail "cwd-drift-guard.sh no longer refuses (exit 2 gone) — protection lost"
fi

# B2. edit-after-failure-guard.sh is the TDD RED-before-source guard —
#     pure non-bd. Must NOT carry a command-v-bd fail-open.
if grep -qE 'command -v (bd|"\$\{?BD_BIN)' "$HOOKS/edit-after-failure-guard.sh"; then
  fail "edit-after-failure-guard.sh carries a command-v-bd guard (it has no bd dependency)"
else
  pass "edit-after-failure-guard.sh has NO command-v-bd guard"
fi

# B3. Functional guard-rail: cwd-drift-guard still REFUSES a central op
#     (git merge) from inside a worktree cwd even with bd absent. If a
#     fail-open guard had been added, this refusal would vanish.
WORK=$(mktemp -d)
# Construct a path that looks like a linked worktree under
# .claude/worktrees/agent-*/ so the hook's cwd heuristic fires.
WT="$WORK/.claude/worktrees/agent-deadbeef"
mkdir -p "$WT"
DRIFT_INPUT='{"tool_name":"Bash","tool_input":{"command":"git merge --no-ff frank/loom-x"}}'
out=$( cd "$WT" && printf '%s' "$DRIFT_INPUT" | env -u BD_BIN PATH="$BDLESS_PATH" \
        bash "$HOOKS/cwd-drift-guard.sh" 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "cwd-drift-guard: still refuses git merge from worktree cwd (rc=2) even without bd"
else
  fail "cwd-drift-guard: did NOT refuse (rc=$rc) — git-side protection disabled without bd" "$out"
fi
rm -rf "$WORK"

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
