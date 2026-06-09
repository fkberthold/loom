#!/usr/bin/env bash
# Locking-spec test for the run_in_background DEFAULT dispatch posture.
#
# loom-li8h: central currently dispatches workers in the FOREGROUND and
# holds the turn idle until they return — observed all session
# 2026-06-08 (the parallel wave + both /dispatch-middle pipelines).
# That contradicts dispatch-v2's lean-central goal: central should
# YIELD the turn and resume on each agent's completion event
# (run_in_background:true), free to converse / plan / stage meanwhile.
# Foreground is reserved for the narrow case where the next step is
# immediate integration with nothing else interleavable.
#
# A live hazard motivates the partner caution: foreground-wait + the
# harness auto-backgrounding a long loop produced TWO suite runs racing
# in one repo (the loom-fx9m close detour). A TaskStop'd suite task left
# orphan bd-post-rewrite child processes that raced on git/bd state ->
# a false 63/2 suite result. So the prose must ALSO carry the
# concurrency caution: never run two full-suite loops in one repo at
# once; TaskStop may not reap grandchildren (orphan processes).
#
# INVARIANT (the bead's RED: line, pinned verbatim below): the dispatch
# skills/conventions document run_in_background as the DEFAULT dispatch
# mode (foreground reserved for immediate-integration), citing
# lean-central, PLUS the no-two-suite-loops / orphan-process
# concurrency caution.
#
# The skills + conventions are prose, not code. These tests are
# doc-presence guards over the four edited surfaces. If the prose
# evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/dispatch-background-default.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DISPATCH_MIDDLE="$LOOM_ROOT/skills/dispatch-middle/SKILL.md"
LIFECYCLE_SHELL="$LOOM_ROOT/skills/bead-lifecycle-shell/SKILL.md"
DISPATCHED_RULE="$LOOM_ROOT/.claude/rules/dispatched-agents.md"
PROJECT_CLAUDE="$LOOM_ROOT/CLAUDE.md"

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
    fail "$name" "(pattern not found in $(basename "$file"): $pattern)"
  fi
}

# =====================================================================
# 0. The four edited surfaces exist
# =====================================================================
echo "==> Files exist"
for f in "$DISPATCH_MIDDLE" "$LIFECYCLE_SHELL" "$DISPATCHED_RULE" "$PROJECT_CLAUDE"; do
  [ -f "$f" ] && pass "exists: $(basename "$f")" \
    || fail "exists: $(basename "$f")" "(missing: $f)"
done

# =====================================================================
# 1. run_in_background is the documented DEFAULT (each surface)
# =====================================================================
echo "==> run_in_background:true is the DEFAULT dispatch mode"
assert_in "$DISPATCH_MIDDLE" "dispatch-middle: background is the default" \
  'run_in_background.{0,40}(default|by default)|(default|by default).{0,40}run_in_background'
assert_in "$LIFECYCLE_SHELL" "lifecycle-shell: background is the default" \
  'run_in_background.{0,40}(default|by default)|(default|by default).{0,40}run_in_background'
assert_in "$DISPATCHED_RULE" "dispatched-agents rule: background is the default" \
  'run_in_background.{0,40}(default|by default)|(default|by default).{0,40}run_in_background'
assert_in "$PROJECT_CLAUDE" "CLAUDE.md: background is the default" \
  'run_in_background.{0,40}(default|by default)|(default|by default).{0,40}run_in_background'

# =====================================================================
# 2. Foreground is the EXPLICIT exception, scoped to immediate
#    integration with nothing else interleavable
# =====================================================================
echo "==> Foreground reserved for immediate-integration"
assert_in "$DISPATCH_MIDDLE" "dispatch-middle: foreground = immediate-integration exception" \
  'foreground.{0,120}(immediate integration|nothing else interleavable|exception)'
assert_in "$LIFECYCLE_SHELL" "lifecycle-shell: foreground = immediate-integration exception" \
  'foreground.{0,120}(immediate integration|nothing else interleavable|exception)'
assert_in "$DISPATCHED_RULE" "dispatched-agents rule: foreground = immediate-integration exception" \
  'foreground.{0,120}(immediate integration|nothing else interleavable|exception)'
assert_in "$PROJECT_CLAUDE" "CLAUDE.md: foreground = immediate-integration exception" \
  'foreground.{0,120}(immediate integration|nothing else interleavable|exception)'

# =====================================================================
# 3. Rationale = dispatch-v2 lean-central (central YIELDS the turn,
#    resumes on the completion event, free to converse/plan/stage)
# =====================================================================
echo "==> Rationale: lean-central (yield turn, resume on completion event)"
assert_in "$DISPATCH_MIDDLE" "dispatch-middle: cites lean-central rationale" \
  'lean[- ]central'
assert_in "$LIFECYCLE_SHELL" "lifecycle-shell: cites lean-central rationale" \
  'lean[- ]central'
assert_in "$DISPATCH_MIDDLE" "dispatch-middle: central yields the turn / resumes on completion" \
  '(yield|yields).{0,40}turn|resume.{0,40}(completion|event)|completion event'

# =====================================================================
# 4. Concurrency caution: never two full-suite loops in one repo at
#    once; TaskStop may not reap grandchildren (orphan processes)
# =====================================================================
echo "==> Concurrency caution (no two suite loops; orphan grandchildren)"
assert_in "$DISPATCH_MIDDLE" "dispatch-middle: no two suite loops in one repo" \
  '(two|2).{0,40}(full[- ]?suite|suite).{0,20}loop|never run two.{0,40}suite'
assert_in "$LIFECYCLE_SHELL" "lifecycle-shell: no two suite loops in one repo" \
  '(two|2).{0,40}(full[- ]?suite|suite).{0,20}loop|never run two.{0,40}suite'
assert_in "$DISPATCHED_RULE" "dispatched-agents rule: no two suite loops in one repo" \
  '(two|2).{0,40}(full[- ]?suite|suite).{0,20}loop|never run two.{0,40}suite'
assert_in "$DISPATCH_MIDDLE" "dispatch-middle: TaskStop may not reap grandchildren / orphans" \
  '(taskstop|task[- ]stop).{0,80}(reap|grandchild|orphan)|orphan.{0,40}(process|child|bd-post-rewrite)'
assert_in "$DISPATCHED_RULE" "dispatched-agents rule: TaskStop orphan-grandchildren hazard" \
  '(taskstop|task[- ]stop).{0,80}(reap|grandchild|orphan)|orphan.{0,40}(process|child|bd-post-rewrite)'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
