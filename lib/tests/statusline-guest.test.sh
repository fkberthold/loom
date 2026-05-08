#!/usr/bin/env bash
# Tests for scripts/statusline.sh — [GUEST] prefix indicator (loom-b8z).
#
# Verifies:
#   - Inactive guest mode → existing statusline output unchanged.
#   - Active + bd_mode=host     → prefix "[GUEST] "
#   - Active + bd_mode=personal → prefix "[GUEST/personal-bd] "
#   - Active + bd_mode=none     → prefix "[GUEST/no-bd] "
#
# Design: drawer_loom_decisions_12d7f8163e8855be037a007c
#
# Run:  bash lib/tests/statusline-guest.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/statusline.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a minimal beads workspace with a workflow.json. By default, no
# guest block. Caller can write the guest block separately.
mk_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "light"}\n' > "$d/.claude/workflow.json"
  printf '%s' "$d"
}

run_statusline() {
  local cwd="$1"
  printf '{"cwd": "%s"}' "$cwd" | bash "$SCRIPT" 2>/dev/null
}

# ---------------------------------------------------------------------------

# Test 1: no guest block → no prefix (existing behavior preserved)
proj=$(mk_project)
out=$(run_statusline "$proj")
if [ "${out:0:7}" != "[GUEST]" ] && [ "${out:0:6}" != "[GUEST" ] && \
   echo "$out" | grep -q "WORKFLOW:"; then
  pass "inactive: no [GUEST] prefix, statusline unchanged"
else
  fail "inactive: no [GUEST] prefix" "$out"
fi
rm -rf "$proj"

# Test 2: guest.active=false → no prefix
proj=$(mk_project)
jq '. + {guest: {active: false, bd_mode: "host", repo_key: "x-12345678"}}' \
  "$proj/.claude/workflow.json" > "$proj/.claude/workflow.json.tmp"
mv "$proj/.claude/workflow.json.tmp" "$proj/.claude/workflow.json"
out=$(run_statusline "$proj")
if ! echo "$out" | grep -q "^\[GUEST"; then
  pass "active=false: no [GUEST] prefix"
else
  fail "active=false: no [GUEST] prefix" "$out"
fi
rm -rf "$proj"

# Test 3: active + bd_mode=host → "[GUEST] " prefix
proj=$(mk_project)
jq '. + {guest: {active: true, bd_mode: "host", repo_key: "x-12345678"}}' \
  "$proj/.claude/workflow.json" > "$proj/.claude/workflow.json.tmp"
mv "$proj/.claude/workflow.json.tmp" "$proj/.claude/workflow.json"
out=$(run_statusline "$proj")
if echo "$out" | grep -q "^\[GUEST\] WORKFLOW:"; then
  pass "active + bd_mode=host: [GUEST] prefix"
else
  fail "active + bd_mode=host: [GUEST] prefix" "$out"
fi
rm -rf "$proj"

# Test 4: active + bd_mode=personal → "[GUEST/personal-bd] " prefix
proj=$(mk_project)
jq '. + {guest: {active: true, bd_mode: "personal", repo_key: "x-12345678"}}' \
  "$proj/.claude/workflow.json" > "$proj/.claude/workflow.json.tmp"
mv "$proj/.claude/workflow.json.tmp" "$proj/.claude/workflow.json"
out=$(run_statusline "$proj")
if echo "$out" | grep -q "^\[GUEST/personal-bd\] WORKFLOW:"; then
  pass "active + bd_mode=personal: [GUEST/personal-bd] prefix"
else
  fail "active + bd_mode=personal: [GUEST/personal-bd] prefix" "$out"
fi
rm -rf "$proj"

# Test 5: active + bd_mode=none → "[GUEST/no-bd] " prefix
proj=$(mk_project)
jq '. + {guest: {active: true, bd_mode: "none", repo_key: "x-12345678"}}' \
  "$proj/.claude/workflow.json" > "$proj/.claude/workflow.json.tmp"
mv "$proj/.claude/workflow.json.tmp" "$proj/.claude/workflow.json"
out=$(run_statusline "$proj")
if echo "$out" | grep -q "^\[GUEST/no-bd\] WORKFLOW:"; then
  pass "active + bd_mode=none: [GUEST/no-bd] prefix"
else
  fail "active + bd_mode=none: [GUEST/no-bd] prefix" "$out"
fi
rm -rf "$proj"

# Test 6: prefix appears even when project shows non-idle activity (sanity:
# verify prefix is at the START regardless of right-hand content).
proj=$(mk_project)
printf '{"v": 1, "mode": "full", "activity": "bug", "bead": "loom-xyz", "stage": "verify"}\n' \
  > "$proj/.claude/workflow-state.json"
jq '. + {guest: {active: true, bd_mode: "host", repo_key: "x-12345678"}}' \
  "$proj/.claude/workflow.json" > "$proj/.claude/workflow.json.tmp"
mv "$proj/.claude/workflow.json.tmp" "$proj/.claude/workflow.json"
out=$(run_statusline "$proj")
if echo "$out" | grep -q "^\[GUEST\] WORKFLOW:"; then
  pass "active + non-idle state: prefix at very start"
else
  fail "active + non-idle state: prefix at very start" "$out"
fi
rm -rf "$proj"

# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
