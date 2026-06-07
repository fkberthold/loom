#!/usr/bin/env bash
# Fixture tests for hooks/skill-redirect.sh.
#
# Closes loom-i8t: when the model spontaneously invokes the Skill
# tool with superpowers:brainstorming in a beads-tracked project,
# redirect it to beadpowers:brainstorming (design lands as beads).
# The two skills have WORD-FOR-WORD identical descriptions, so on
# auto-trigger the model defaults to superpowers; loom wants
# beadpowers. We do NOT control the plugin descriptions, so a
# loom-owned PreToolUse hook is the robust fix.
#
# Hook is PreToolUse on Skill. It:
#   1. Bypasses on LOOM_SKILL_REDIRECT_SKIP=1 (literal 1).
#   2. No-ops for non-Skill tools.
#   3. Gates on a .beads/ dir present (walk up from cwd).
#   4. Redirects mapped skills (superpowers:brainstorming ->
#      beadpowers:brainstorming) with exit 2 + naming stderr.
#   5. No-op for unmapped skills / non-beads projects.
#
# Run:  bash lib/tests/skill-redirect.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/skill-redirect.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook in a controlled env.
#   $1 = cwd
#   $2 = tool name (Skill / Bash / etc.)
#   $3 = skill name
run_hook() {
  local cwd="$1" tool="$2" skill="$3"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"skill": sys.argv[2], "args": ""}}))
' "$tool" "$skill")
  (cd "$cwd" && bash "$HOOK" <<<"$payload" 2>&1)
}

# Build a temp project dir.
#   $1 = "beads" → create a .beads/ dir inside; anything else → no .beads/
mk_project() {
  local with_beads="${1:-}"
  local d; d=$(mktemp -d)
  if [ "$with_beads" = "beads" ]; then
    mkdir -p "$d/.beads"
  fi
  printf '%s\n' "$d"
}

# -------------------------------------------------------------------
# (a) superpowers:brainstorming + .beads present → exit 2 + stderr
#     names beadpowers.
# -------------------------------------------------------------------

echo "==> (a) superpowers:brainstorming + .beads present → block"

PROJ=$(mk_project beads)
out=$(run_hook "$PROJ" Skill "superpowers:brainstorming"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "beadpowers"; then
  pass "mapped skill in beads project: blocked + stderr names beadpowers"
else
  fail "expected exit 2 + 'beadpowers' msg. rc=$rc" "$out"
fi
rm -rf "$PROJ"

# -------------------------------------------------------------------
# (b) beadpowers:brainstorming → exit 0 (no redirect loop).
# -------------------------------------------------------------------

echo "==> (b) beadpowers:brainstorming → no loop"

PROJ=$(mk_project beads)
out=$(run_hook "$PROJ" Skill "beadpowers:brainstorming"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "beadpowers (the destination) passes through: no loop"
else
  fail "beadpowers:brainstorming blocked. rc=$rc" "$out"
fi
rm -rf "$PROJ"

# -------------------------------------------------------------------
# (c) unmapped skill (feature-a-bead) → exit 0.
# -------------------------------------------------------------------

echo "==> (c) unmapped skill → passthrough"

PROJ=$(mk_project beads)
out=$(run_hook "$PROJ" Skill "feature-a-bead"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "unmapped skill: allowed"
else
  fail "unmapped skill blocked. rc=$rc" "$out"
fi
rm -rf "$PROJ"

# -------------------------------------------------------------------
# (d) superpowers:brainstorming but NO .beads → exit 0 (gate).
# -------------------------------------------------------------------

echo "==> (d) mapped skill but NO .beads → gate allows"

PROJ=$(mk_project nobeads)
out=$(run_hook "$PROJ" Skill "superpowers:brainstorming"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "non-beads project: gate passes through"
else
  fail "non-beads project blocked. rc=$rc" "$out"
fi
rm -rf "$PROJ"

# -------------------------------------------------------------------
# (e) LOOM_SKILL_REDIRECT_SKIP=1 → exit 0 (bypass).
# -------------------------------------------------------------------

echo "==> (e) LOOM_SKILL_REDIRECT_SKIP=1 bypass"

PROJ=$(mk_project beads)
payload=$(python3 -c '
import json
print(json.dumps({"tool_name": "Skill", "tool_input": {"skill": "superpowers:brainstorming", "args": ""}}))
')
out=$(cd "$PROJ" && LOOM_SKILL_REDIRECT_SKIP=1 bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "SKIP=1 bypass: hook silent even on mapped skill in beads project"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi
# Non-literal bypass value must NOT bypass (loom-b1l literal-1 convention).
out=$(cd "$PROJ" && LOOM_SKILL_REDIRECT_SKIP=yes bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "SKIP=yes (non-literal) does NOT bypass: still blocks"
else
  fail "SKIP=yes wrongly bypassed. rc=$rc" "$out"
fi
rm -rf "$PROJ"

# -------------------------------------------------------------------
# (f) non-Skill tool (Bash) → exit 0 (passthrough).
# -------------------------------------------------------------------

echo "==> (f) non-Skill tool → passthrough"

PROJ=$(mk_project beads)
payload=$(python3 -c '
import json
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": "echo superpowers:brainstorming"}}))
')
out=$(cd "$PROJ" && bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Bash tool: allowed (out of scope)"
else
  fail "Bash tool blocked. rc=$rc" "$out"
fi
rm -rf "$PROJ"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
