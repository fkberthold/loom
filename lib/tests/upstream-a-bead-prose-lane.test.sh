#!/usr/bin/env bash
# Locking-spec test for skills/upstream-a-bead/SKILL.md prose-only handling.
#
# loom-bqz (loom-7bn canary friction, drawer ffd73e9e + the loom-k2g.7
# closeout): the recipe's M3/M4 (RED/GREEN) assume the upstream has a
# native test command. The two real canary targets — beadpowers AND
# superpowers (loom-ki5's target) — are pure-prose skill plugins with NO
# test harness, so recipe step Q4 ("AGNOSTIC — run upstream's native test
# command") presumes something that does not exist. The canary also showed
# worker-dispatch is overkill for a 6-line prose PR (inline-central was
# right, per the loom-csu within-bead threshold).
#
# Contract (three coupled refinements; shared file -> one bead):
#   1. PROSE-ONLY SUB-LANE — explicit handling for an upstream with no
#      test harness: M3/M4 collapse to a documented doc-presence
#      before/after grep on a single doc commit, and the PR body's
#      Verification section states that before/after grep INSTEAD OF a
#      test command + pass count.
#   2. TRIVIAL-PR INLINE ESCAPE — a named escape in the "variable middle
#      is worker territory" framing: a small prose PR with no loom-side
#      code is inline-central, mirroring the within-bead nudge and citing
#      the loom-csu threshold.
#   3. SMOKE-BATTERY CLONE CAVEAT — a sub-note that the dispatched-agents
#      pre-flight smoke battery assumes a loom-side .claude/worktrees
#      worktree, NOT an external ~/.loom/upstream/<owner>/<repo> clone, so
#      a dispatched M3/M4 has no equivalent pre-flight for the clone.
#
# Run:  bash lib/tests/upstream-a-bead-prose-lane.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/upstream-a-bead/SKILL.md"

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
  if grep -qiE "$pattern" "$SKILL_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

assert_before() {
  # Assert pattern A appears at a lower line number than pattern B.
  local name="$1" pattern_a="$2" pattern_b="$3"
  local line_a line_b
  line_a=$(grep -niE "$pattern_a" "$SKILL_FILE" | head -1 | cut -d: -f1)
  line_b=$(grep -niE "$pattern_b" "$SKILL_FILE" | head -1 | cut -d: -f1)
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

echo "==> Refinement 1: prose-only sub-lane is named + conditioned on no test harness"
assert_contains "prose-only sub-lane named" \
  'prose-only'
assert_contains "no-test-harness condition documented" \
  'no (native )?test (harness|command)|without a (native )?test (harness|command)|no test framework'
assert_contains "M3/M4 collapse to doc-presence before/after grep" \
  'doc-presence|before/after grep|before.?and.?after grep|before.?after (doc )?grep'
assert_contains "on a single doc commit" \
  'single doc commit|one doc commit|a single (documentation|doc) commit'

echo "==> Refinement 1: PR Verification section states the grep, not a pass count"
assert_contains "Verification section names the doc-presence before/after" \
  'Verification section'
assert_before "prose-only handling precedes M5 PR-body draft" \
  'prose-only' '#### M5\.'

echo "==> Refinement 2: trivial-PR inline escape, citing loom-csu, mirroring within-bead nudge"
assert_contains "trivial-PR inline escape named" \
  'trivial.{0,6}(prose )?PR|trivial[- ].{0,18}inline|inline escape'
assert_contains "small prose PR with no loom-side code is inline-central" \
  'inline.?central|inline (the )?central|central edits inline'
# NOTE: the bead's hypothesis cited loom-csu's "<=5-line" number, but that
# is superseded. The live canonical inline threshold is bead-lifecycle-
# shell's Dispatch discipline (loom-yb5): <=15 lines, single non-test file,
# no new test, and "pure docs/config/prose edits qualify." Pin the CURRENT
# rule (prose-qualifies), not csu's stale line.
assert_contains "cites the current within-bead inline threshold (prose qualifies)" \
  'prose.{0,18}qualif|adds no new test|no new test|loom-yb5'
assert_contains "mirrors the within-bead nudge" \
  'within-bead'
assert_before "inline escape sits in the worker-territory framing (before M2)" \
  'inline escape|trivial.{0,6}(prose )?PR' '#### M2\.'

echo "==> Refinement 3: smoke-battery clone caveat cross-references dispatched-agents rule"
assert_contains "smoke battery / pre-flight named" \
  'smoke battery|pre-flight'
assert_contains "caveat: external upstream clone, not a loom worktree" \
  'no equivalent pre-flight|not a loom-side worktree|assumes a loom-side|rather than (an? )?external'
assert_contains "cross-references the dispatched-agents rule" \
  'dispatched-agents'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
