#!/usr/bin/env bash
# Tests for the .deploy field in .claude/workflow.json (loom-0k0).
#
# Schema (loom-0k0):
#   {
#     "v": 1,
#     "mode": "...",
#     "deploy": "<shell command string>"   # optional
#   }
#
# Verifies:
#   - workflow_resolve_deploy returns empty when .deploy is absent
#   - workflow_resolve_deploy returns the command string when set
#   - workflow_resolve_deploy returns empty on malformed JSON (no crash)
#   - workflow_resolve_deploy returns empty when workflow.json is missing
#   - workflow_resolve_deploy returns empty when .deploy is null or ""
#
# Run:  bash lib/tests/workflow-config-deploy.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

mk_project_with_workflow() {
  local body="$1"
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '%s\n' "$body" > "$d/.claude/workflow.json"
  printf '%s' "$d"
}

mk_project_no_workflow() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.beads"
  printf '%s' "$d"
}

echo "== workflow_resolve_deploy =="

# Source the lib. The function does not exist yet → expect a load-time pass
# but every test below to fail until M4 lands the implementation.
. "$LOOM_ROOT/lib/workflow-mode.sh"
. "$LOOM_ROOT/lib/workflow-config.sh"

# Test 1: .deploy absent → empty output, exit 0
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full"}')
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
rc=$?
if [ "$rc" = "0" ] && [ -z "$got" ]; then
  pass ".deploy absent returns empty (exit 0)"
else
  fail ".deploy absent returns empty (exit 0)" "rc=$rc got='$got'"
fi
rm -rf "$proj"

# Test 2: .deploy present → command string echoed verbatim
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full", "deploy": "./install.sh"}')
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
if [ "$got" = "./install.sh" ]; then
  pass ".deploy present returns the command verbatim"
else
  fail ".deploy present returns the command verbatim" "got='$got'"
fi
rm -rf "$proj"

# Test 3: .deploy present with shell-shape command (args + redirects ok)
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full", "deploy": "make deploy && ./scripts/post-deploy.sh"}')
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
if [ "$got" = "make deploy && ./scripts/post-deploy.sh" ]; then
  pass ".deploy with shell operators returns verbatim"
else
  fail ".deploy with shell operators returns verbatim" "got='$got'"
fi
rm -rf "$proj"

# Test 4: malformed JSON → empty (no crash, non-zero from jq tolerated)
proj=$(mk_project_with_workflow '{this is not json')
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
rc=$?
if [ "$rc" = "0" ] && [ -z "$got" ]; then
  pass "malformed workflow.json returns empty (exit 0)"
else
  fail "malformed workflow.json returns empty (exit 0)" "rc=$rc got='$got'"
fi
rm -rf "$proj"

# Test 5: workflow.json missing → empty
proj=$(mk_project_no_workflow)
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
rc=$?
if [ "$rc" = "0" ] && [ -z "$got" ]; then
  pass "missing workflow.json returns empty (exit 0)"
else
  fail "missing workflow.json returns empty (exit 0)" "rc=$rc got='$got'"
fi
rm -rf "$proj"

# Test 6: .deploy: null → empty (jq -r yields "null", caller must filter)
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full", "deploy": null}')
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
if [ -z "$got" ]; then
  pass ".deploy: null returns empty (not literal 'null')"
else
  fail ".deploy: null returns empty (not literal 'null')" "got='$got'"
fi
rm -rf "$proj"

# Test 7: .deploy: "" → empty
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full", "deploy": ""}')
got=$(workflow_resolve_deploy "$proj" 2>/dev/null)
if [ -z "$got" ]; then
  pass ".deploy: empty string returns empty"
else
  fail ".deploy: empty string returns empty" "got='$got'"
fi
rm -rf "$proj"

echo
echo "== scripts/loom-print-deploy-hint =="

# The wrap-up section 6 snippet must work regardless of which shell the
# Bash tool invokes it from. Claude Code's Bash tool runs commands in zsh
# (or any user-configured shell) — the snippet cannot rely on bash-specific
# features like BASH_SOURCE leaking out of the sourced lib. The
# `scripts/loom-print-deploy-hint` script wraps the resolver in a
# bash-shebanged executable so the wrap-up snippet just calls it.

HINT_SCRIPT="$LOOM_ROOT/scripts/loom-print-deploy-hint"

# Test 8: the wrapper script exists and is executable
if [ -x "$HINT_SCRIPT" ]; then
  pass "loom-print-deploy-hint script exists + executable"
else
  fail "loom-print-deploy-hint script exists + executable" "not at $HINT_SCRIPT"
fi

# Test 9: script invoked from zsh prints the Next-step hint when .deploy is set
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full", "deploy": "./install.sh"}')
got=$(cd "$proj" && zsh -c "$HINT_SCRIPT" 2>/dev/null)
if [ "$got" = "Next step (project deploy): ./install.sh" ]; then
  pass "script under zsh prints hint with .deploy set"
else
  fail "script under zsh prints hint with .deploy set" "got='$got'"
fi
rm -rf "$proj"

# Test 10: script invoked from zsh prints nothing when .deploy is absent
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full"}')
got=$(cd "$proj" && zsh -c "$HINT_SCRIPT" 2>/dev/null)
if [ -z "$got" ]; then
  pass "script under zsh prints nothing without .deploy"
else
  fail "script under zsh prints nothing without .deploy" "got='$got'"
fi
rm -rf "$proj"

# Test 11: script invoked from bash also works (parity check)
proj=$(mk_project_with_workflow '{"v": 1, "mode": "full", "deploy": "make deploy"}')
got=$(cd "$proj" && bash -c "$HINT_SCRIPT" 2>/dev/null)
if [ "$got" = "Next step (project deploy): make deploy" ]; then
  pass "script under bash prints hint (parity)"
else
  fail "script under bash prints hint (parity)" "got='$got'"
fi
rm -rf "$proj"

echo
echo "Passed: $passed  Failed: $failed"
[ "$failed" = "0" ]
