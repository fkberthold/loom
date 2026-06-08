#!/usr/bin/env bash
# Locking-spec test for the /dispatch-middle command + skill.
#
# loom-0k68 (T1 of epic loom-5m94, dispatch architecture v2): the
# foundation primitive that orchestrates a bead's variable middle as a
# test-author → implementer (→ optional verify) pipeline of INDEPENDENT
# subagents, so central invokes once and writes nothing. The
# friction-inversion lever — make dispatch CHEAPER than inline.
#
# Architecture locked in
# drawer_loom_decisions_fe831554f7a62b9c6ea4bf18 (dispatch-v2
# brainstorm, 2026-06-07). Kills the 3 in-thread-work failure modes:
#   #1 central eats planning context  → central orchestration-only
#   #2 test-author == code-author     → two INDEPENDENT agents
#   #3 central accumulates junk ctx   → minimal slice per brief
#
# The skill + command are prose, not code. These tests are
# doc-presence guards: the SKILL.md must NAME each piece of the
# pipeline, and the command must be a pass-through user door. If the
# prose evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/dispatch-middle-contract.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/dispatch-middle/SKILL.md"
CMD_FILE="$LOOM_ROOT/commands/dispatch-middle.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert a pattern is present in a given file.
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
# 0. The two files exist
# =====================================================================
echo "==> Files exist"
[ -f "$SKILL_FILE" ] && pass "skills/dispatch-middle/SKILL.md exists" \
  || fail "skills/dispatch-middle/SKILL.md exists" "(missing: $SKILL_FILE)"
[ -f "$CMD_FILE" ] && pass "commands/dispatch-middle.md exists" \
  || fail "commands/dispatch-middle.md exists" "(missing: $CMD_FILE)"

# =====================================================================
# 1. The test-author → implementer sequence is documented
# =====================================================================
echo "==> Pipeline: test-author → implementer sequence"
assert_in "$SKILL_FILE" "names the test-author agent" \
  'test[- ]author'
assert_in "$SKILL_FILE" "names the implementer agent" \
  'implementer'
assert_in "$SKILL_FILE" "documents the ordered author→implementer sequence" \
  'test[- ]author.*(→|->|then|first).*implementer|implementer.*after.*test[- ]author'
assert_in "$SKILL_FILE" "test-author dispatched via Agent isolation:worktree" \
  'isolation.*worktree|worktree.*isolation'
assert_in "$SKILL_FILE" "implementer runs in the SAME worktree" \
  'same worktree'

# =====================================================================
# 2. Independence rule: implementer does NOT author/modify the test
# =====================================================================
echo "==> Independence rule (issue #2 solved by construction)"
assert_in "$SKILL_FILE" "implementer must NOT modify/weaken the test" \
  '(do not|don.t|never|must not).*(modify|weaken|change|edit|touch).*test'
assert_in "$SKILL_FILE" "implementer inherits the test as an artifact, not a mind" \
  'artifact'
assert_in "$SKILL_FILE" "implementer never sees the test-author's reasoning" \
  '(never|does not|doesn.t).*(see|inherit).*(reasoning|mind|history)'
assert_in "$SKILL_FILE" "stop-and-report if the test looks wrong" \
  '(stop|halt).*(report|escalate)|if the test (looks|seems) wrong'

# =====================================================================
# 3. Context-scoping discipline (issue #3)
# =====================================================================
echo "==> Context-scoping discipline (minimal slice per brief)"
assert_in "$SKILL_FILE" "central extracts the minimal slice per brief" \
  'minimal slice|minimal.*context|only its slice'
assert_in "$SKILL_FILE" "no session-history dump into worker briefs" \
  'session[- ]history|no.*dump|do not dump'

# =====================================================================
# 4. Central-writes-nothing posture in the middle
# =====================================================================
echo "==> Central-writes-nothing posture"
assert_in "$SKILL_FILE" "central writes nothing in the middle" \
  'writes nothing|central.*never writes|never writes a (test|line)'

# =====================================================================
# 5. Hand-back-for-merge step (central integrates)
# =====================================================================
echo "==> Hand-back-for-merge (central integrates)"
assert_in "$SKILL_FILE" "hands back to central for merge/close/capture" \
  'hand[- ]?back|hands? back.*central|central.*(verify|merge|close|capture)'
assert_in "$SKILL_FILE" "central does verify + merge + close + capture" \
  'merge'

# =====================================================================
# 6. The TWO brief templates (test-author + implementer)
# =====================================================================
echo "==> Two concrete brief templates present"
assert_in "$SKILL_FILE" "test-author brief template present" \
  'test[- ]author brief|brief.*test[- ]author'
assert_in "$SKILL_FILE" "implementer brief template present" \
  'implementer brief|brief.*implementer'
assert_in "$SKILL_FILE" "brief has a CONTRACT slot" \
  'contract.*(slot|here|<|\{)|<contract|\{contract'
assert_in "$SKILL_FILE" "brief has a RED-test slot" \
  'red[- ]test.*(slot|path|<|\{)|<red[- ]test|\{red[- ]test|red test file path'

# =====================================================================
# 7. loom-tdua interlock: contract slot = the bead's RED: line
# =====================================================================
echo "==> loom-tdua interlock (design emits contracts → dispatch consumes)"
assert_in "$SKILL_FILE" "cites loom-tdua interlock" \
  'loom-tdua'
assert_in "$SKILL_FILE" "contract slot = the bead's RED: line" \
  'RED:.*line|red: line'

# =====================================================================
# 8. Compose note: within-bead vs across-bead (loom-yb5 fan-out)
# =====================================================================
echo "==> Compose note: within-bead split vs across-bead fan-out"
assert_in "$SKILL_FILE" "names within-bead split" \
  'within[- ]bead'
assert_in "$SKILL_FILE" "names across-bead fan-out (loom-yb5)" \
  'across[- ]bead'
assert_in "$SKILL_FILE" "cites loom-yb5 fan-out detector" \
  'loom-yb5|fan[- ]out'

# =====================================================================
# 9. The command file is a disable-model-invocation pass-through door
# =====================================================================
echo "==> Command file: disable-model-invocation pass-through door"
assert_in "$CMD_FILE" "command sets disable-model-invocation: true" \
  '^disable-model-invocation:[[:space:]]*true'
assert_in "$CMD_FILE" "command has a description frontmatter key" \
  '^description:'
assert_in "$CMD_FILE" "command passes through the <bead> argument" \
  '<bead>'
assert_in "$CMD_FILE" "command invokes the dispatch-middle skill" \
  'dispatch-middle'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
