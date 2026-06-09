#!/usr/bin/env bash
# Tests for the .deploy field in .claude/workflow.json.
#
# Schema (loom-0k0 / loom-1tq):
#   {
#     "v": 1,
#     "mode": "...",
#     "deploy": "<shell command string>"   # optional, three-state:
#                                          #   "<cmd>" set      → PASS
#                                          #   ""      opt-out  → PASS (no re-prompt)
#                                          #   absent  undecided → MISS (prompt)
#   }
#
# Two halves:
#   READ path (loom-0k0): workflow_resolve_deploy + scripts/loom-print-deploy-hint
#     - returns empty when .deploy is absent / null / "" / malformed / missing file
#     - returns the command string verbatim when set
#   WRITE path (loom-1tq): the /audit-project Item-21 schema-write helpers
#     - workflow_config_deploy_state    distinguishes absent / empty / set
#     - workflow_config_deploy_present  exit 0 iff .deploy is a non-empty string
#     - workflow_config_deploy_set      writes .deploy, preserves other fields
#     - the audit lifecycle: MISS→write→PASS, MISS→opt-out→PASS(no re-prompt), N/A
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
echo "== workflow-config.sh .deploy WRITE helpers (loom-1tq) =="

# Helper producing a fresh project with a minimal workflow.json (mode=light).
mk_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "light"}\n' > "$d/.claude/workflow.json"
  printf '%s' "$d"
}
read_field() {
  local file="$1" path="$2"
  jq -r "$path" "$file" 2>/dev/null
}

# Test 12: deploy_state reports "absent" on a fresh workflow.json (MISS case)
proj=$(mk_project)
got=$(workflow_config_deploy_state "$proj")
if [ "$got" = "absent" ]; then
  pass "deploy_state absent on fresh project (MISS)"
else
  fail "deploy_state absent on fresh project (MISS)" "got: '$got'"
fi
rm -rf "$proj"

# Test 13: deploy_present is false (non-zero) when .deploy absent
proj=$(mk_project)
if workflow_config_deploy_present "$proj"; then
  fail "deploy_present false when absent" "exit 0 (present) on fresh project"
else
  pass "deploy_present false when absent (exit nonzero)"
fi
rm -rf "$proj"

# Test 14: deploy_set writes a non-empty command, preserves mode + v
proj=$(mk_project)
workflow_config_deploy_set './install.sh' "$proj"
got_deploy=$(read_field "$proj/.claude/workflow.json" .deploy)
got_mode=$(read_field "$proj/.claude/workflow.json" .mode)
got_v=$(read_field "$proj/.claude/workflow.json" .v)
if [ "$got_deploy" = "./install.sh" ] && [ "$got_mode" = "light" ] && [ "$got_v" = "1" ]; then
  pass "deploy_set writes command, preserves mode + v"
else
  fail "deploy_set writes command, preserves mode + v" \
    "deploy='$got_deploy' mode='$got_mode' v='$got_v'"
fi
rm -rf "$proj"

# Test 15: deploy_present true after a non-empty deploy_set (PASS case)
proj=$(mk_project)
workflow_config_deploy_set 'make deploy' "$proj"
if workflow_config_deploy_present "$proj"; then
  pass "deploy_present true after non-empty set (PASS)"
else
  fail "deploy_present true after non-empty set (PASS)"
fi
rm -rf "$proj"

# Test 16: deploy_state reports "set" after a non-empty deploy_set
proj=$(mk_project)
workflow_config_deploy_set 'make deploy' "$proj"
got=$(workflow_config_deploy_state "$proj")
if [ "$got" = "set" ]; then
  pass "deploy_state set after non-empty write"
else
  fail "deploy_state set after non-empty write" "got: '$got'"
fi
rm -rf "$proj"

# Test 17: workflow_resolve_deploy reads back the written command (read↔write)
proj=$(mk_project)
workflow_config_deploy_set './scripts/build' "$proj"
got=$(workflow_resolve_deploy "$proj")
if [ "$got" = "./scripts/build" ]; then
  pass "resolve_deploy reads back written command"
else
  fail "resolve_deploy reads back written command" "got: '$got'"
fi
rm -rf "$proj"

# Test 18: opt-out — deploy_set "" writes an EXPLICIT empty .deploy key.
# The crux: the key must be PRESENT and empty, NOT absent. has("deploy")
# is what distinguishes "explicitly chose nothing" from "never decided".
proj=$(mk_project)
workflow_config_deploy_set '' "$proj"
has_key=$(read_field "$proj/.claude/workflow.json" 'has("deploy")')
got_deploy=$(read_field "$proj/.claude/workflow.json" '.deploy')
if [ "$has_key" = "true" ] && [ "$got_deploy" = "" ]; then
  pass "opt-out writes explicit empty .deploy key (present, empty)"
else
  fail "opt-out writes explicit empty .deploy key (present, empty)" \
    "has_key='$has_key' deploy='$got_deploy'"
fi
rm -rf "$proj"

# Test 19: opt-out — deploy_state reports "empty" (distinct from "absent")
proj=$(mk_project)
workflow_config_deploy_set '' "$proj"
got=$(workflow_config_deploy_state "$proj")
if [ "$got" = "empty" ]; then
  pass "deploy_state empty after opt-out (distinct from absent)"
else
  fail "deploy_state empty after opt-out (distinct from absent)" "got: '$got'"
fi
rm -rf "$proj"

# Test 20: opt-out — deploy_present is FALSE on empty (no live hint to surface).
# Audit PASS is computed from state ∈ {set, empty}; deploy_present tracks
# whether there is a live command — empty has none, but the audit still PASSes.
proj=$(mk_project)
workflow_config_deploy_set '' "$proj"
if workflow_config_deploy_present "$proj"; then
  fail "deploy_present false on opt-out" "exit 0 on empty deploy"
else
  pass "deploy_present false on opt-out (no live hint; audit-PASS via state)"
fi
rm -rf "$proj"

# Test 21: idempotence — set the same non-empty command twice
proj=$(mk_project)
workflow_config_deploy_set './install.sh' "$proj"
workflow_config_deploy_set './install.sh' "$proj"
got=$(read_field "$proj/.claude/workflow.json" .deploy)
if [ "$got" = "./install.sh" ]; then
  pass "deploy_set idempotent (same non-empty command twice)"
else
  fail "deploy_set idempotent (same non-empty command twice)" "got: '$got'"
fi
rm -rf "$proj"

# Test 22: idempotence — opt-out twice stays empty (no re-prompt drift)
proj=$(mk_project)
workflow_config_deploy_set '' "$proj"
workflow_config_deploy_set '' "$proj"
got=$(workflow_config_deploy_state "$proj")
if [ "$got" = "empty" ]; then
  pass "deploy_set idempotent on opt-out (state stays empty)"
else
  fail "deploy_set idempotent on opt-out (state stays empty)" "got: '$got'"
fi
rm -rf "$proj"

# Test 23: re-setting a real command after opt-out works (user changed mind)
proj=$(mk_project)
workflow_config_deploy_set '' "$proj"
workflow_config_deploy_set 'kubectl apply -k .' "$proj"
got=$(workflow_resolve_deploy "$proj")
if [ "$got" = "kubectl apply -k ." ]; then
  pass "deploy_set overwrites a prior opt-out with a real command"
else
  fail "deploy_set overwrites a prior opt-out with a real command" "got: '$got'"
fi
rm -rf "$proj"

# Test 24: deploy_set preserves a pre-existing .guest block (no clobber)
proj=$(mk_project)
workflow_config_guest_on host repo-deadbeef "$proj"
workflow_config_deploy_set './install.sh' "$proj"
got_deploy=$(read_field "$proj/.claude/workflow.json" .deploy)
got_guest=$(read_field "$proj/.claude/workflow.json" .guest.active)
got_bd=$(read_field "$proj/.claude/workflow.json" .guest.bd_mode)
if [ "$got_deploy" = "./install.sh" ] && [ "$got_guest" = "true" ] && [ "$got_bd" = "host" ]; then
  pass "deploy_set preserves a pre-existing .guest block"
else
  fail "deploy_set preserves a pre-existing .guest block" \
    "deploy='$got_deploy' guest.active='$got_guest' bd_mode='$got_bd'"
fi
rm -rf "$proj"

# Test 25: deploy_set self-bootstraps workflow.json when .claude/ is absent
proj=$(mktemp -d)
mkdir -p "$proj/.beads"  # no .claude/, no workflow.json
workflow_config_deploy_set './deploy.sh' "$proj"
got=$(workflow_resolve_deploy "$proj")
if [ "$got" = "./deploy.sh" ]; then
  pass "deploy_set self-bootstraps workflow.json when absent"
else
  fail "deploy_set self-bootstraps workflow.json when absent" "got: '$got'"
fi
rm -rf "$proj"

echo
echo "== audit-flow lifecycle (Item 21 verdict shape) =="

# audit_verdict mirrors the /audit-project Item 21 verdict logic:
#   set | empty → PASS ; absent → MISS ; (no workflow.json) → N/A
audit_verdict() {
  local p="$1"
  [ -f "$p/.claude/workflow.json" ] || { echo "N/A"; return; }
  case "$(workflow_config_deploy_state "$p")" in
    set|empty) echo "PASS" ;;
    *)         echo "MISS" ;;
  esac
}

# Test 26: MISS → write command → PASS on rerun
proj=$(mk_project)
v1=$(audit_verdict "$proj")
workflow_config_deploy_set './install.sh' "$proj"   # simulate "user typed command"
v2=$(audit_verdict "$proj")
if [ "$v1" = "MISS" ] && [ "$v2" = "PASS" ]; then
  pass "lifecycle: MISS → write command → PASS on rerun"
else
  fail "lifecycle: MISS → write command → PASS on rerun" "v1=$v1 v2=$v2"
fi
rm -rf "$proj"

# Test 27: MISS → opt-out (empty) → PASS on rerun, and stays PASS (no re-prompt)
proj=$(mk_project)
v1=$(audit_verdict "$proj")
workflow_config_deploy_set '' "$proj"               # simulate "user left blank"
v2=$(audit_verdict "$proj")
v3=$(audit_verdict "$proj")                          # third audit must still PASS
if [ "$v1" = "MISS" ] && [ "$v2" = "PASS" ] && [ "$v3" = "PASS" ]; then
  pass "lifecycle: MISS → opt-out → PASS (no re-prompt on subsequent audits)"
else
  fail "lifecycle: MISS → opt-out → PASS (no re-prompt)" "v1=$v1 v2=$v2 v3=$v3"
fi
rm -rf "$proj"

# Test 28: N/A when workflow.json doesn't exist (other audit items cover that)
proj=$(mktemp -d)
mkdir -p "$proj/.beads"  # no .claude/workflow.json at all
v=$(audit_verdict "$proj")
if [ "$v" = "N/A" ]; then
  pass "lifecycle: N/A when workflow.json absent"
else
  fail "lifecycle: N/A when workflow.json absent" "got: $v"
fi
rm -rf "$proj"

echo
echo "Passed: $passed  Failed: $failed"
[ "$failed" = "0" ]
