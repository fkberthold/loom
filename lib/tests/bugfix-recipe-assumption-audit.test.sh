#!/usr/bin/env bash
# Locking-spec test for skills/bugfix-a-bead/SKILL.md.
#
# loom-z3m.10: the bugfix recipe must include a bead-assumption-audit
# step that fires AFTER systematic-debugging lands a root-cause
# hypothesis and BEFORE the RED test. Surfaced by HAW bead yho — filed
# as "validator gap" but diagnosis was "tighten observe-NPC prompt";
# bead description stayed stale until manually corrected. Recipe now
# mandates `bd update --description` (preferred) or `bd comment` when
# diagnosed root cause materially diverges from filed framing.
#
# Doc-presence test. Prose-only assertions on the recipe SKILL.md.
#
# Run:  bash lib/tests/bugfix-recipe-assumption-audit.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECIPE="$LOOM_ROOT/skills/bugfix-a-bead/SKILL.md"

passed=0
failed=0

assert_grep() {
  local name="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file"; then
    echo "PASS: $name"
    passed=$((passed + 1))
  else
    echo "FAIL: $name — pattern not found: $pattern"
    failed=$((failed + 1))
  fi
}

[ -f "$RECIPE" ] || { echo "FAIL: recipe file missing at $RECIPE"; exit 1; }

# The new step must exist as a named middle-step header.
assert_grep "M2 bead-assumption-audit step header present" \
  "M2\.\s+Bead-assumption audit" "$RECIPE"

# The step must cite the trigger condition (after diagnosis, before RED).
assert_grep "audit step cites before-RED placement" \
  "before.+(RED|writing.+test)" "$RECIPE"

# The step must name the corrective bd commands.
assert_grep "audit step references bd update --description" \
  "bd update.+--description" "$RECIPE"
assert_grep "audit step references bd comment fallback" \
  "bd comment" "$RECIPE"

# HAW yho lineage must be cited (provenance).
assert_grep "audit step cites HAW yho lineage" \
  "yho" "$RECIPE"

# Stage table must include the new stage.
assert_grep "stage table includes assumption-audit" \
  "assumption-audit" "$RECIPE"

# Subsequent steps must be renumbered M3..M6 (RED, GREEN, bug-class, sweep).
assert_grep "M3 RED step renumbered" "M3\.\s+TDD.+RED" "$RECIPE"
assert_grep "M4 GREEN step renumbered" "M4\.\s+GREEN" "$RECIPE"
assert_grep "M5 bug-class step renumbered" "M5\.\s+Bug-class" "$RECIPE"
assert_grep "M6 enshrined-sweep step renumbered" \
  "M6\.\s+Full suite" "$RECIPE"

# Failure-mode section should mention the new skip risk.
assert_grep "failure-mode entry for skipping audit" \
  "Skip M2.+(assumption|audit)" "$RECIPE"

echo
echo "=== bugfix-recipe-assumption-audit test results ==="
echo "Passed: $passed"
echo "Failed: $failed"

[ "$failed" -eq 0 ]
