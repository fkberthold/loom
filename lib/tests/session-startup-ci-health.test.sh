#!/usr/bin/env bash
# Locking-spec test for skills/session-startup/SKILL.md CI-health check.
#
# loom-97q: the skill must surface red CI runs at cold-start so failures
# that landed during a prior session don't sit unnoticed across multiple
# sessions. Surfaced 2026-05-15 after Deploy docs sat red for 2 days
# (loom-59w fixed the underlying broken-link, but the silence was the
# real bug). The fix is a `gh run list` call early in the routine.
#
# Contract (Path A, skill-only):
#   - CI-health step exists and runs `gh run list` (or equivalent)
#   - Placed early in the routine (before "Pick a bead" — i.e., before
#     a recommendation lands), so red CI is visible BEFORE the user
#     commits to the next action.
#   - Tolerant of gh-missing / gh-not-authenticated — degrades to a
#     single skipped-line, never fails the skill.
#   - Light mode still runs the check (cheap, high-signal; explicitly
#     mentioned in the mode block).
#   - Off mode still skips the whole skill (existing behavior; covered
#     by the mode block, no separate assertion needed).
#
# Run:  bash lib/tests/session-startup-ci-health.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/session-startup/SKILL.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qE "$pattern" "$SKILL_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

assert_before() {
  # Assert pattern A appears at a lower line number than pattern B.
  local name="$1" pattern_a="$2" pattern_b="$3"
  local line_a line_b
  line_a=$(grep -nE "$pattern_a" "$SKILL_FILE" | head -1 | cut -d: -f1)
  line_b=$(grep -nE "$pattern_b" "$SKILL_FILE" | head -1 | cut -d: -f1)
  if [ -z "$line_a" ]; then
    fail "$name" "(pattern A not found: $pattern_a)"
  elif [ -z "$line_b" ]; then
    fail "$name" "(pattern B not found: $pattern_b)"
  elif [ "$line_a" -lt "$line_b" ]; then
    pass "$name"
  else
    fail "$name" "(line $line_a >= line $line_b)"
  fi
}

echo "==> CI-health check exists and uses gh run list"
assert_contains "step invokes 'gh run list'" 'gh run list'
assert_contains "step surfaces failure on main" \
  'failure|red|conclusion[: ]+failure'

echo "==> CI-health step placed early — before 'Pick a bead'"
assert_before "gh run list precedes 'Pick a bead'" \
  'gh run list' '^[0-9]+\.[[:space:]]+\*\*Pick a bead'

echo "==> Tolerance: degrade gracefully if gh missing or unauthenticated"
assert_contains "tolerance language present" \
  'not (installed|authenticated|available)|degrade|skip.*gh'

echo "==> Light mode explicitly mentions the CI check is retained"
# The mode block describes light-mode behavior. Either the light bullet
# names the CI check inline, OR a sentence near the mode block clarifies
# the CI step runs in both full and light.
assert_contains "mode block names CI check in light" \
  'light.*CI|CI.*light|ci[- ]health.*light|light.*ci[- ]health'

echo "==> Tolerance contract — explicit 'never fail' clause"
# Without this, future edits could weaken tolerance from "always continue"
# to "exit on error" and silently re-introduce the silent-CI-red gap.
assert_contains "step asserts 'never fail the skill'" \
  '[Nn]ever fail the skill'

echo "==> Off mode regression guard — off-mode still skips the whole skill"
# Negative case: the CI check must not survive into off mode. The skill's
# off-mode bullet handles this by saying the entire skill is skipped.
# This assertion pins that bullet's verbatim language so a future edit
# that re-enables CI-check-but-not-the-rest doesn't pass silently.
assert_contains "off-mode bullet still says skip the skill entirely" \
  'off.*skip the skill entirely|skip the skill entirely'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
