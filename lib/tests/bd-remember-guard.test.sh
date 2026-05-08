#!/usr/bin/env bash
# Fixture tests for hooks/bd-remember-guest-guard.sh.
#
# Behavior matrix (loom-n7x, design drawer
# drawer_loom_decisions_12d7f8163e8855be037a007c):
#
#   guest active | bd_mode    | command           | result
#   no           | n/a        | n/a               | passthrough (exit 0)
#   yes          | host       | bd remember ...   | block (exit 2) + hint
#   yes          | host       | not bd remember   | passthrough
#   yes          | personal   | bd remember ...   | passthrough
#   yes          | none       | bd remember ...   | passthrough
#
# Plus false-positive avoidance: `gbd remember`, `bd remember-not-this`,
# and `bd-remember-foo` must not trip the guard.
#
# Run:  bash lib/tests/bd-remember-guard.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-remember-guest-guard.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a minimal project root with .beads/ (so workflow_project_root finds it)
# and a workflow.json with the requested mode + guest block.
mk_repo() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.beads" "$d/.claude"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '%s' "$d"
}

# Activate guest mode in a project's workflow.json with a chosen bd_mode.
set_guest() {
  local proj="$1" bd_mode="$2"
  local cfg="$proj/.claude/workflow.json"
  if command -v jq >/dev/null 2>&1; then
    jq --arg bd "$bd_mode" \
      '.guest = {active: true, bd_mode: $bd, repo_key: "fixture-12345678"}' \
      "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  else
    printf '{"v": 1, "mode": "full", "guest": {"active": true, "bd_mode": "%s", "repo_key": "fixture-12345678"}}\n' \
      "$bd_mode" > "$cfg"
  fi
}

# Run the hook with the given tool_name + command. Echoes combined output;
# exit code is left in $? for the caller via a wrapper variable.
run_hook() {
  local proj="$1" tool="$2" cmd="$3"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))
' "$tool" "$cmd")
  (cd "$proj" && bash "$HOOK" <<<"$payload" 2>&1)
}

# ---------------------------------------------------------------------------
# Row 1: guest INACTIVE → passthrough regardless of command
# ---------------------------------------------------------------------------

repo=$(mk_repo)
out=$(run_hook "$repo" "Bash" "bd remember loom-foo bar")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "guest inactive: passthrough on bd remember"
else
  fail "guest inactive: passthrough on bd remember" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Row 2: guest active + host bd + bd remember → BLOCK
# ---------------------------------------------------------------------------

repo=$(mk_repo)
set_guest "$repo" "host"
out=$(run_hook "$repo" "Bash" "bd remember loom-foo \"some note\"")
rc=$?
if [ "$rc" -eq 2 ] && \
   echo "$out" | grep -q "Guest mode + host bd" && \
   echo "$out" | grep -q "MemPalace" && \
   echo "$out" | grep -q "mempalace_add_drawer"; then
  pass "guest+host+bd remember: blocks with hint"
else
  fail "guest+host+bd remember: blocks with hint" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Row 3: guest active + host bd + non-remember command → passthrough
# ---------------------------------------------------------------------------

repo=$(mk_repo)
set_guest "$repo" "host"
out=$(run_hook "$repo" "Bash" "bd ready")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "guest+host+bd ready: passthrough"
else
  fail "guest+host+bd ready: passthrough" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Row 4: guest active + personal bd + bd remember → passthrough
# ---------------------------------------------------------------------------

repo=$(mk_repo)
set_guest "$repo" "personal"
out=$(run_hook "$repo" "Bash" "bd remember loom-foo bar")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "guest+personal+bd remember: passthrough"
else
  fail "guest+personal+bd remember: passthrough" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Row 5: guest active + none + bd remember → passthrough (let bd error)
# ---------------------------------------------------------------------------

repo=$(mk_repo)
set_guest "$repo" "none"
out=$(run_hook "$repo" "Bash" "bd remember loom-foo bar")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "guest+none+bd remember: passthrough"
else
  fail "guest+none+bd remember: passthrough" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# False-positive avoidance: word-boundary regex
# ---------------------------------------------------------------------------

# 6a: `gbd remember` (different binary) must NOT block
repo=$(mk_repo)
set_guest "$repo" "host"
out=$(run_hook "$repo" "Bash" "gbd remember foo bar")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "false-positive: gbd remember not blocked"
else
  fail "false-positive: gbd remember not blocked" "rc=$rc out=$out"
fi
rm -rf "$repo"

# 6b: `bd remember-not-this` (suffix on remember) must NOT block
repo=$(mk_repo)
set_guest "$repo" "host"
out=$(run_hook "$repo" "Bash" "bd remember-not-this foo")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "false-positive: bd remember-not-this not blocked"
else
  fail "false-positive: bd remember-not-this not blocked" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Non-Bash tool: passthrough regardless
# ---------------------------------------------------------------------------

repo=$(mk_repo)
set_guest "$repo" "host"
out=$(run_hook "$repo" "Read" "bd remember foo bar")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "non-Bash tool: passthrough"
else
  fail "non-Bash tool: passthrough" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Compound command: && bd remember should also block under guest+host
# ---------------------------------------------------------------------------

repo=$(mk_repo)
set_guest "$repo" "host"
out=$(run_hook "$repo" "Bash" "echo hi && bd remember loom-foo bar")
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "compound (&& bd remember): blocked"
else
  fail "compound (&& bd remember): blocked" "rc=$rc out=$out"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
