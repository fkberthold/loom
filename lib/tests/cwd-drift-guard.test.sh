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

# Like run_hook but injects extra top-level keys into the JSON payload
# (e.g. `agent_id`, `agent_type`) to simulate Claude Code's PreToolUse
# payload shape inside a subagent. Per
# https://code.claude.com/docs/en/hooks the PreToolUse payload carries
# optional `agent_id` / `agent_type` when fired inside a subagent —
# the worker-context signal we use to suppress this hook.
#   $1 = cwd
#   $2 = tool name
#   $3 = command string
#   $4 = JSON snippet inserted at top level (e.g. '"agent_id":"abc"')
run_hook_with_extra_payload() {
  local cwd="$1" tool="$2" cmd="$3" extra_json="$4"
  local payload
  payload=$(python3 -c '
import json, sys
d = {"tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2]}}
extra = json.loads("{" + sys.argv[3] + "}")
d.update(extra)
print(json.dumps(d))
' "$tool" "$cmd" "$extra_json")
  (cd "$cwd" && bash "$HOOK" <<<"$payload" 2>&1)
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
# 15. loom-ehv — worker-context payload should be allowed.
# Claude Code's PreToolUse payload carries optional top-level
# `agent_id` / `agent_type` fields when the hook fires inside a
# subagent (Task-tool spawn). Workers legitimately operate from
# their own `.claude/worktrees/agent-*/` worktree — the central-
# drift assumption does not apply to them. With either marker
# present, the hook must short-circuit (exit 0) even when cwd is
# a worktree and the command is in the central-op allowlist.
# -------------------------------------------------------------------

echo "==> 15. Worker-context payload (agent_id / agent_type) → allow"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# 15a. agent_id present alone → allow.
out=$(run_hook_with_extra_payload "$WT" Bash "bd update loom-foo --claim" '"agent_id":"worker-abc"'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "agent_id present + bd update --claim from worktree: allowed (worker context)"
else
  fail "agent_id-present payload still blocked. rc=$rc" "$out"
fi

# 15b. agent_type present alone → allow.
out=$(run_hook_with_extra_payload "$WT" Bash "git merge --no-ff frank/foo" '"agent_type":"general-purpose"'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "agent_type present + git merge from worktree: allowed (worker context)"
else
  fail "agent_type-present payload still blocked. rc=$rc" "$out"
fi

# 15c. both markers present → allow.
out=$(run_hook_with_extra_payload "$WT" Bash "bd close loom-foo" '"agent_id":"x","agent_type":"y"'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "agent_id + agent_type both present + bd close from worktree: allowed"
else
  fail "both markers payload still blocked. rc=$rc" "$out"
fi

# 15d. empty-string agent_id → treat as ABSENT (central context),
# so the central-drift block still fires. Defensive: only non-empty
# string values count as a subagent marker.
out=$(run_hook_with_extra_payload "$WT" Bash "bd update loom-foo --claim" '"agent_id":""'); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "empty-string agent_id treated as absent: central-drift still blocks"
else
  fail "empty agent_id incorrectly bypassed. rc=$rc" "$out"
fi

# 15e. agent_id present + main cwd → allow (hook is no-op outside
# worktree anyway; documents that the new check composes harmlessly).
out=$(run_hook_with_extra_payload "$MAIN" Bash "bd update loom-foo --claim" '"agent_id":"worker-abc"'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "agent_id present + main cwd: allowed (no-op anyway)"
else
  fail "agent_id-present + main cwd unexpectedly blocked. rc=$rc" "$out"
fi

# 15f. agent_id present + worktree cwd + read-only op → allow
# (would be allowed anyway; documents marker doesn't change anything).
out=$(run_hook_with_extra_payload "$WT" Bash "git status" '"agent_id":"worker-abc"'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "agent_id present + read-only op: allowed (already-allowed path)"
else
  fail "agent_id-present + read-only blocked. rc=$rc" "$out"
fi

# 15g. Regression guard for loom-d2o's original behavior:
# NO agent markers + worktree cwd + central op → still blocks. This
# is the central-drift case the original hook was built for; the
# worker-context exemption must not weaken it.
out=$(run_hook "$WT" Bash "bd update loom-foo --claim"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "no agent markers + central op + worktree cwd: still blocks (loom-d2o regression guard)"
else
  fail "central-drift case incorrectly allowed. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 16. SUBSTRING OVER-MATCH guard (loom-s9ko). The central-op allowlist
# anchors each refused verb on `(\s|$)`, so a `-`-suffixed LONGER word
# that merely STARTS with the verb must NOT trip the guard. This pins
# the substring-over-match bug class (siblings loom-2y6x AUTOFAN-EXCLUDE
# self-exclude + loom-skxj `pytest`-in-`pytest-of-*`) for this detector.
#
# The lead case is `git merge-base` — run in EVERY dispatched-worker
# smoke battery (.claude/rules/dispatched-agents.md step 4) and by
# central. If the guard fired on it from a worktree cwd, it would BLOCK
# a legitimate read-only op (live false-positive). The guard was AUDITED
# already-safe (the `merge(\s|$)` anchor rejects the `-` in `merge-base`);
# these tests are the regression pin that keeps it that way.
# -------------------------------------------------------------------

echo "==> 16. Substring over-match — verb-prefixed LONGER words must NOT block (loom-s9ko)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# 16a. git merge-base — the smoke-battery read-only op — must NOT block.
out=$(run_hook "$WT" Bash "git merge-base HEAD main"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "git merge-base from worktree: allowed (does NOT over-match 'git merge')"
else
  fail "git merge-base incorrectly blocked — substring over-match on 'merge'. rc=$rc" "$out"
fi

# 16b. git merge-base inside a command-substitution (the literal smoke
# battery form: mb=\$(git merge-base HEAD main)) — must NOT block.
out=$(run_hook "$WT" Bash "mb=\$(git merge-base HEAD main); echo \$mb"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "mb=\$(git merge-base ...) from worktree: allowed (smoke-battery form)"
else
  fail "smoke-battery 'git merge-base' subshell incorrectly blocked. rc=$rc" "$out"
fi

# 16c. git push-cache (hypothetical `-`-suffixed push subcommand) must NOT
# over-match the `push` arm.
out=$(run_hook "$WT" Bash "git push-cache foo"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "git push-cache from worktree: allowed (does NOT over-match 'git push')"
else
  fail "git push-cache incorrectly blocked — substring over-match on 'push'. rc=$rc" "$out"
fi

# 16d. bd update-config (a `-`-suffixed longer subcommand) must NOT
# over-match the `bd update` arm.
out=$(run_hook "$WT" Bash "bd update-config foo"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd update-config from worktree: allowed (does NOT over-match 'bd update')"
else
  fail "bd update-config incorrectly blocked — substring over-match on 'update'. rc=$rc" "$out"
fi

# 16e. bd close-all (hypothetical `-`-suffixed close subcommand) must NOT
# over-match the `bd close` arm.
out=$(run_hook "$WT" Bash "bd close-all"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd close-all from worktree: allowed (does NOT over-match 'bd close')"
else
  fail "bd close-all incorrectly blocked — substring over-match on 'close'. rc=$rc" "$out"
fi

# 16f. bd dolt push-mirror (a `-`-suffixed longer push subcommand) must
# NOT over-match the `bd dolt push` arm.
out=$(run_hook "$WT" Bash "bd dolt push-mirror"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bd dolt push-mirror from worktree: allowed (does NOT over-match 'bd dolt push')"
else
  fail "bd dolt push-mirror incorrectly blocked — substring over-match. rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
