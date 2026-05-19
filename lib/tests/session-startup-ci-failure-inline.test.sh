#!/usr/bin/env bash
# Locking-spec test for skills/session-startup/SKILL.md CI failure inline
# detail (loom-z3m.4, Step 1c — extension of loom-97q's Step 1a).
#
# Surfaced by loom-z3m.1 f1: user said "Ok, we have an ongoing issue, the build
# keeps failing in GHA. Building docs I believe." — the existing count-only CI
# health step (loom-97q) told the user N failures, but not WHICH job or WHY,
# forcing a follow-up roundtrip. Extend with inline job name + summary.
#
# Contract:
#   - When the CI-health step finds a failure, it ALSO runs `gh run view <id>
#     --json conclusion,jobs` (or equivalent) to pull the failing job's name.
#   - The output includes the failing job name plus a one-line failure summary
#     (failure line / step name).
#   - Negative case: when CI is green, the inline-detail call is skipped (no
#     extraneous `gh run view`). Pinned by a "skip when green" / "only when
#     failure" textual clause.
#   - The tolerance contract (gh missing / unauthenticated → continue) from
#     loom-97q must still apply — extends, does not weaken.
#
# Run:  bash lib/tests/session-startup-ci-failure-inline.test.sh

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

echo "==> Inline failure detail via gh run view"
assert_contains "gh run view invocation" 'gh run view'
assert_contains "jobs field requested" 'jobs|job name|failing job'

echo "==> Inline detail includes a 1-line failure summary"
assert_contains "summary / failure line mentioned" \
  'summary|failure line|first.*failure|fail.*line|one[- ]line'

echo "==> Negative case: skip inline call when CI is green"
# Without a green-skip clause, the agent might `gh run view` on every cold
# start. Pin the textual gate.
assert_contains "only-on-failure clause" \
  'only.*failure|when.*failure|if.*failure.*detected|when.*red|skip.*green|green.*skip'

echo "==> Tolerance contract preserved (gh-missing degrades cleanly)"
# loom-97q's "never fail the skill" must still cover the extended call.
assert_contains "'never fail' still present (loom-97q invariant)" \
  '[Nn]ever fail the skill'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
