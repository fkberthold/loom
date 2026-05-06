#!/usr/bin/env bash
# Tests for the guest-mode block in .claude/workflow.json.
#
# Schema (loom-4re):
#   {
#     "v": 1,
#     "mode": "...",
#     "guest": {
#       "active":   true | false,
#       "bd_mode":  "host" | "personal" | "none",
#       "repo_key": "<basename>-<sha8>"
#     }
#   }
#
# Verifies:
#   - workflow_config_guest_active   reads .guest.active honestly
#   - workflow_config_guest_get      reads .guest.<field>
#   - workflow_config_guest_on       writes guest block, leaves other fields
#   - workflow_config_guest_off      clears guest block, leaves other fields
#   - workflow-state CLI:
#       guest-status, guest-on, guest-off
#       get guest.active, get guest.bd_mode, get guest.repo_key
#   - All operations idempotent
#
# Run:  bash lib/tests/workflow-config-guest.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WS_BIN="$LOOM_ROOT/scripts/workflow-state"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

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

# ---------------------------------------------------------------------------
# Library tests — source the lib directly
# ---------------------------------------------------------------------------

echo "== workflow-config.sh library =="

# Test 1: workflow_config_path resolves correctly
proj=$(mk_project)
. "$LOOM_ROOT/lib/workflow-config.sh"
got=$(workflow_config_path "$proj")
expected="$proj/.claude/workflow.json"
if [ "$got" = "$expected" ]; then
  pass "workflow_config_path returns expected path"
else
  fail "workflow_config_path" "expected: $expected\ngot: $got"
fi
rm -rf "$proj"

# Test 2: guest_active is false on a fresh workflow.json
proj=$(mk_project)
if workflow_config_guest_active "$proj"; then
  fail "guest_active false by default" "exit 0 (active) on fresh project"
else
  pass "guest_active false by default (exit nonzero)"
fi
rm -rf "$proj"

# Test 3: guest_get returns empty for missing field
proj=$(mk_project)
got=$(workflow_config_guest_get bd_mode "$proj")
if [ -z "$got" ]; then
  pass "guest_get empty when block missing"
else
  fail "guest_get empty when block missing" "got: '$got'"
fi
rm -rf "$proj"

# Test 4: guest_on writes the guest block
proj=$(mk_project)
workflow_config_guest_on host atlas-a3f8b2c1 "$proj"
got_active=$(read_field "$proj/.claude/workflow.json" .guest.active)
got_bd=$(read_field "$proj/.claude/workflow.json" .guest.bd_mode)
got_key=$(read_field "$proj/.claude/workflow.json" .guest.repo_key)
got_mode=$(read_field "$proj/.claude/workflow.json" .mode)
if [ "$got_active" = "true" ] && [ "$got_bd" = "host" ] && \
   [ "$got_key" = "atlas-a3f8b2c1" ] && [ "$got_mode" = "light" ]; then
  pass "guest_on writes block, preserves mode"
else
  fail "guest_on writes block, preserves mode" \
    "active=$got_active bd_mode=$got_bd repo_key=$got_key mode=$got_mode"
fi

# Test 5: guest_active is true after guest_on
if workflow_config_guest_active "$proj"; then
  pass "guest_active true after guest_on"
else
  fail "guest_active true after guest_on"
fi

# Test 6: guest_get reads the right values
got_bd=$(workflow_config_guest_get bd_mode "$proj")
got_key=$(workflow_config_guest_get repo_key "$proj")
if [ "$got_bd" = "host" ] && [ "$got_key" = "atlas-a3f8b2c1" ]; then
  pass "guest_get returns written values"
else
  fail "guest_get returns written values" "bd_mode=$got_bd repo_key=$got_key"
fi

# Test 7: guest_on idempotent (run twice, same result)
workflow_config_guest_on host atlas-a3f8b2c1 "$proj"
got_active=$(read_field "$proj/.claude/workflow.json" .guest.active)
if [ "$got_active" = "true" ]; then
  pass "guest_on idempotent"
else
  fail "guest_on idempotent" "active=$got_active"
fi

# Test 8: guest_off clears the block, preserves other fields
workflow_config_guest_off "$proj"
got_active=$(read_field "$proj/.claude/workflow.json" '.guest.active // empty')
got_mode=$(read_field "$proj/.claude/workflow.json" .mode)
if [ -z "$got_active" ] && [ "$got_mode" = "light" ]; then
  pass "guest_off clears block, preserves mode"
else
  fail "guest_off clears block, preserves mode" \
    "active='$got_active' mode='$got_mode'"
fi
rm -rf "$proj"

# Test 9: guest_off idempotent on never-active project
proj=$(mk_project)
workflow_config_guest_off "$proj"
got_mode=$(read_field "$proj/.claude/workflow.json" .mode)
if [ "$got_mode" = "light" ]; then
  pass "guest_off idempotent when never active"
else
  fail "guest_off idempotent when never active" "mode=$got_mode"
fi
rm -rf "$proj"

# Test 10: guest_on with bd_mode=personal works
proj=$(mk_project)
workflow_config_guest_on personal myrepo-deadbeef "$proj"
got_bd=$(workflow_config_guest_get bd_mode "$proj")
if [ "$got_bd" = "personal" ]; then
  pass "guest_on bd_mode=personal"
else
  fail "guest_on bd_mode=personal" "bd_mode=$got_bd"
fi
rm -rf "$proj"

# Test 11: guest_on with bd_mode=none works
proj=$(mk_project)
workflow_config_guest_on none repo-cafe1234 "$proj"
got_bd=$(workflow_config_guest_get bd_mode "$proj")
if [ "$got_bd" = "none" ]; then
  pass "guest_on bd_mode=none"
else
  fail "guest_on bd_mode=none" "bd_mode=$got_bd"
fi
rm -rf "$proj"

# Test 12: invalid bd_mode rejected
proj=$(mk_project)
if workflow_config_guest_on bogus_mode foo "$proj" 2>/dev/null; then
  fail "guest_on rejects invalid bd_mode" "exit 0 on bogus_mode"
else
  pass "guest_on rejects invalid bd_mode"
fi
rm -rf "$proj"

# ---------------------------------------------------------------------------
# CLI tests — exercise scripts/workflow-state subcommands
# ---------------------------------------------------------------------------

echo "== workflow-state CLI =="

# Test 13: get guest.active returns "false" on fresh project
proj=$(mk_project)
got=$("$WS_BIN" get guest.active "$proj" 2>/dev/null)
if [ "$got" = "false" ] || [ -z "$got" ]; then
  pass "CLI: get guest.active false/empty by default"
else
  fail "CLI: get guest.active false/empty by default" "got: '$got'"
fi
rm -rf "$proj"

# Test 14: guest-on subcommand activates
proj=$(mk_project)
"$WS_BIN" guest-on host atlas-a3f8b2c1 "$proj" >/dev/null 2>&1
got=$("$WS_BIN" get guest.active "$proj" 2>/dev/null)
if [ "$got" = "true" ]; then
  pass "CLI: guest-on activates"
else
  fail "CLI: guest-on activates" "got: '$got'"
fi

# Test 15: get guest.bd_mode after guest-on
got=$("$WS_BIN" get guest.bd_mode "$proj" 2>/dev/null)
if [ "$got" = "host" ]; then
  pass "CLI: get guest.bd_mode after guest-on"
else
  fail "CLI: get guest.bd_mode after guest-on" "got: '$got'"
fi

# Test 16: get guest.repo_key after guest-on
got=$("$WS_BIN" get guest.repo_key "$proj" 2>/dev/null)
if [ "$got" = "atlas-a3f8b2c1" ]; then
  pass "CLI: get guest.repo_key after guest-on"
else
  fail "CLI: get guest.repo_key after guest-on" "got: '$got'"
fi

# Test 17: guest-status reports active state
out=$("$WS_BIN" guest-status "$proj" 2>&1)
if echo "$out" | grep -qi "active" && echo "$out" | grep -q "host"; then
  pass "CLI: guest-status reports active + bd_mode"
else
  fail "CLI: guest-status reports active + bd_mode" "$out"
fi

# Test 18: guest-off deactivates
"$WS_BIN" guest-off "$proj" >/dev/null 2>&1
got=$("$WS_BIN" get guest.active "$proj" 2>/dev/null)
if [ "$got" = "false" ] || [ -z "$got" ]; then
  pass "CLI: guest-off deactivates"
else
  fail "CLI: guest-off deactivates" "got: '$got'"
fi

# Test 19: guest-status reports inactive after guest-off
out=$("$WS_BIN" guest-status "$proj" 2>&1)
if echo "$out" | grep -qi "inactive\|not.active"; then
  pass "CLI: guest-status reports inactive after guest-off"
else
  fail "CLI: guest-status reports inactive after guest-off" "$out"
fi
rm -rf "$proj"

# Test 20: existing get/set/path/mode still work (regression)
# `mode` reads workflow.json (config), not workflow-state.json (ephemera);
# verify both: live mode resolution, and a state set+get round-trip.
proj=$(mk_project)
got_mode=$("$WS_BIN" mode "$proj" 2>/dev/null)
"$WS_BIN" set --start-dir="$proj" stage=verify >/dev/null 2>&1
got_stage=$("$WS_BIN" get stage "$proj" 2>/dev/null)
got_path=$("$WS_BIN" path "$proj" 2>/dev/null)
if [ "$got_mode" = "light" ] && [ "$got_stage" = "verify" ] && \
   [ "$got_path" = "$proj/.claude/workflow-state.json" ]; then
  pass "regression: existing CLI subcommands still work"
else
  fail "regression: existing CLI subcommands still work" \
    "mode=$got_mode stage=$got_stage path=$got_path"
fi
rm -rf "$proj"

# Test 21: guest-on without arguments shows usage and exits non-zero
proj=$(mk_project)
if "$WS_BIN" guest-on "$proj" 2>/dev/null; then
  fail "CLI: guest-on without args exits non-zero" "exit 0 with no args"
else
  pass "CLI: guest-on without args exits non-zero"
fi
rm -rf "$proj"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
