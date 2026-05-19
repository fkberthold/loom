#!/usr/bin/env bash
# Locking-spec test for skills/session-startup/SKILL.md since-last-session
# digest (loom-z3m.4, Step 1b).
#
# Surfaced by loom-z3m.1 f2 (HAW): user away >1 week said "I've been away from
# this for over a week, get me up to speed on where we're at." — the agent
# then probed each bead one-by-one (wasteful tokens, slow ramp).
#
# Contract:
#   - A step detects "long time since last session" (>3 day gap) and emits a
#     "Since you were last here:" digest block.
#   - The digest combines: closed-since beads (bd list --status=closed
#     --since=...), recent diary entries (mempalace_diary_read), and recent
#     main commits (git log --since=...).
#   - Threshold is 3 days — codified in the skill so the agent doesn't pick
#     an ad-hoc cutoff.
#   - Negative case: when the gap is <=3 days, the digest is skipped entirely
#     (no empty "Since you were last here:" header). The skill text must
#     explicitly say so.
#
# Run:  bash lib/tests/session-startup-since-last-session.test.sh

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

echo "==> Since-last-session digest step exists"
assert_contains "digest header label" \
  'Since you were last here|since[- ]last[- ]session|since-you-were-last-here'

echo "==> 3-day threshold codified"
assert_contains "3-day gap threshold present" \
  '3[- ]day|3 days|three[- ]day'

echo "==> Digest combines closed beads + diary + git log"
assert_contains "closed-since bd query" \
  'bd list[^`]*--status[= ]closed|closed.*--since|--since.*closed'
assert_contains "diary read in digest" \
  'mempalace_diary_read|diary'
assert_contains "git log in digest" \
  'git log'

echo "==> Digest placed before 'Pick a bead'"
assert_before "digest precedes Pick a bead" \
  'Since you were last here|since[- ]last[- ]session' \
  '^[0-9]+\.[[:space:]]+\*\*Pick a bead'

echo "==> Negative case: skip when gap is short"
# Without an explicit skip-when-short-gap clause, the agent could emit an
# empty digest on every cold-start. Pin the textual escape hatch.
assert_contains "skip-when-short-gap clause" \
  '<=[ ]?3 day|less than 3|gap.*short|short.*gap|recent.*skip|skip.*recent|otherwise.*skip|skip.*digest'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
