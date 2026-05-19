#!/usr/bin/env bash
# Locking-spec test for skills/session-startup/SKILL.md in-progress RESUME header
# (loom-z3m.4, Step 1a).
#
# Surfaced by loom-z3m.1 f4 (liza_base): user said "Ah, I didn't know we hadn't
# finished liza_base-n7pb, let's get that done." — in_progress beads were not
# foregrounded on resume; the user was surprised work was incomplete.
#
# Contract:
#   - A dedicated step prints a "RESUME?" header listing in_progress beads with
#     id, title, and a recency cue (last_touched / last diary entry).
#   - The step runs `bd list --status=in_progress` with JSON output so the agent
#     can format the header (vs. a generic list dump).
#   - The step is placed BEFORE the "Pick a bead" step — resume cues outrank
#     fresh-ready-bead selection.
#   - Negative case: if no in_progress beads, the step emits nothing (no empty
#     "RESUME?" header). This is asserted via a textual "skip when empty" / "if
#     none" clause in the skill.
#
# Run:  bash lib/tests/session-startup-in-progress-resume.test.sh

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

echo "==> RESUME header step exists with in_progress JSON query"
assert_contains "RESUME header label appears in skill" 'RESUME\?|RESUME[: ]'
assert_contains "in_progress JSON query specified" \
  'bd list[^`]*--status[= ]in_progress[^`]*--json|bd list[^`]*--json[^`]*--status[= ]in_progress'

echo "==> RESUME header includes recency cue (last_touched / diary)"
assert_contains "recency cue mentioned" \
  'last_touched|last diary|recent diary|last-touched'

echo "==> RESUME step placed before 'Pick a bead'"
assert_before "RESUME header precedes Pick a bead" \
  'RESUME\?|RESUME[: ]' '^[0-9]+\.[[:space:]]+\*\*Pick a bead'

echo "==> Empty-case: skill explicitly says skip header when no in_progress"
# Negative case discipline — without this, the agent might emit an empty
# RESUME? header on every cold-start even when there's nothing to resume.
assert_contains "skip-when-empty clause" \
  'no in_progress|in_progress.*empty|empty.*in_progress|if none|skip.*header|nothing to resume'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
