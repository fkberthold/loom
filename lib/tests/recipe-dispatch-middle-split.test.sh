#!/usr/bin/env bash
# Locking-spec test for the RED-author/GREEN-implementer split in the
# bugfix-a-bead and feature-a-bead activity recipes.
#
# loom-8crd (T4 of epic loom-5m94, dispatch architecture v2): the
# activity-recipe variable middles must run RED and GREEN as TWO
# SEPARATE dispatched agents via /dispatch-middle (test-author then
# implementer), not ONE worker doing both. Independence of test-author
# from implementer is the anti-tautology guarantee — issue #2 from the
# dispatch-v2 brainstorm (drawer_loom_decisions_fe831554f7a62b9c6ea4bf18),
# solved by construction: the implementer inherits the RED test as an
# ARTIFACT, never the test-author's reasoning.
#
# Doc-presence test. Prose-only assertions on the two recipe SKILL.md
# files. If the prose evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/recipe-dispatch-middle-split.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUGFIX="$LOOM_ROOT/skills/bugfix-a-bead/SKILL.md"
FEATURE="$LOOM_ROOT/skills/feature-a-bead/SKILL.md"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert a (case-insensitive, extended) pattern is present in a file.
assert_in() {
  local file="$1" name="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qiE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

# =====================================================================
# 0. Both recipe files exist
# =====================================================================
echo "==> Files exist"
[ -f "$BUGFIX" ] && pass "bugfix-a-bead/SKILL.md exists" \
  || fail "bugfix-a-bead/SKILL.md exists" "(missing: $BUGFIX)"
[ -f "$FEATURE" ] && pass "feature-a-bead/SKILL.md exists" \
  || fail "feature-a-bead/SKILL.md exists" "(missing: $FEATURE)"

# =====================================================================
# 1. bugfix-a-bead: RED and GREEN are SEPARATE dispatched agents
# =====================================================================
echo "==> bugfix-a-bead: RED (test-author) / GREEN (implementer) split"
assert_in "$BUGFIX" "bugfix references /dispatch-middle" \
  '/dispatch-middle|dispatch-middle'
assert_in "$BUGFIX" "bugfix names the test-author role" \
  'test[- ]author'
assert_in "$BUGFIX" "bugfix names the implementer role" \
  'implementer'
# The M3 (RED) step must say a test-author is dispatched.
assert_in "$BUGFIX" "bugfix M3 (RED) dispatches the test-author" \
  'M3\.\s+TDD.+RED'
# The split must be explicit: two agents, not one worker doing both.
assert_in "$BUGFIX" "bugfix states RED and GREEN are separate agents" \
  '(separate|two|independent|different).*(agent|dispatch)'
# The implementer must NOT be the test-author (independence).
assert_in "$BUGFIX" "bugfix implementer independent of test-author" \
  '(independent|never sees|does not see|without seeing).*(test[- ]author|author|reasoning)|implementer.*independent'

# =====================================================================
# 2. feature-a-bead: RED and GREEN are SEPARATE dispatched agents
# =====================================================================
echo "==> feature-a-bead: RED (test-author) / GREEN (implementer) split"
assert_in "$FEATURE" "feature references /dispatch-middle" \
  '/dispatch-middle|dispatch-middle'
assert_in "$FEATURE" "feature names the test-author role" \
  'test[- ]author'
assert_in "$FEATURE" "feature names the implementer role" \
  'implementer'
# The M3 (RED) step must pin the contract via a dispatched test-author.
assert_in "$FEATURE" "feature M3 (RED) pins the contract" \
  'M3\.\s+RED'
# Test-author writes from the M1 contract; implementer from the RED test.
assert_in "$FEATURE" "feature test-author writes from the M1 contract" \
  'test[- ]author.*(contract|M1)|contract.*test[- ]author'
assert_in "$FEATURE" "feature implementer works from the RED test" \
  'implementer.*(RED|red test)|red test.*implementer'
# The split must be explicit: two agents.
assert_in "$FEATURE" "feature states RED and GREEN are separate agents" \
  '(separate|two|independent|different).*(agent|dispatch)'

# =====================================================================
# 3. Cross-ref to /dispatch-middle + bead-lifecycle-shell in BOTH
# =====================================================================
echo "==> Cross-refs present"
assert_in "$BUGFIX" "bugfix cross-refs bead-lifecycle-shell" \
  'bead-lifecycle-shell'
assert_in "$FEATURE" "feature cross-refs bead-lifecycle-shell" \
  'bead-lifecycle-shell'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
