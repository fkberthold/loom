#!/usr/bin/env bash
# Tests for the drawer-author agent prompt's guest-mode prefix
# instruction. The drawer-author runs as an LLM-driven subagent —
# there's no executable code path to assert on. These are plain
# text-presence tests against agents/drawer-author.md, verifying:
#   - the prompt references the workflow-state guest.active check
#   - the literal `[guest project:` prefix template is present
#   - an example shows the prefix in use
#
# Behavior under load (does the agent actually emit the prefix?)
# requires a live LLM smoke test:
#
#   1. In a guest-mode-active repo (run `/loom-guest on` first),
#      invoke drawer-author for a closed bead. The DECISION
#      paragraph's first sentence should open with
#      `[guest project: <repo_key>]`.
#   2. In a non-guest repo (no guest.active marker), the same
#      invocation should produce a DECISION paragraph with no
#      `[guest project:` marker.
#
# Run:  bash lib/tests/drawer-author-guest.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMPT="$LOOM_ROOT/agents/drawer-author.md"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Test 0: prompt file exists
if [ -f "$PROMPT" ]; then
  pass "agents/drawer-author.md exists"
else
  fail "agents/drawer-author.md exists" "missing: $PROMPT"
  echo "Results: $passed passed, $failed failed"
  exit 1
fi

# Test 1: prompt references workflow-state get guest.active
if grep -q 'workflow-state get guest.active' "$PROMPT"; then
  pass "prompt references 'workflow-state get guest.active'"
else
  fail "prompt references 'workflow-state get guest.active'" \
    "no match for 'workflow-state get guest.active' in $PROMPT"
fi

# Test 2: prompt references guest.repo_key lookup
if grep -q 'guest.repo_key' "$PROMPT"; then
  pass "prompt references 'guest.repo_key'"
else
  fail "prompt references 'guest.repo_key'" \
    "no match for 'guest.repo_key' in $PROMPT"
fi

# Test 3: literal prefix template '[guest project:' is present
if grep -qF '[guest project:' "$PROMPT"; then
  pass "prompt contains literal '[guest project:' prefix template"
else
  fail "prompt contains literal '[guest project:' prefix template" \
    "no match for '[guest project:' in $PROMPT"
fi

# Test 4: at least one concrete example shows the prefix attached to
# a DECISION line. We look for `[guest project: <something>]` followed
# by non-bracket content on the same line — the example demonstrates
# usage, not just the template.
if grep -E '\[guest project: [^]]+\] [^[:space:]]' "$PROMPT" >/dev/null; then
  pass "prompt has at least one concrete '[guest project: <key>] ...' example"
else
  fail "prompt has at least one concrete example" \
    "no '[guest project: <key>] <text>' example line in $PROMPT"
fi

# Test 5: prompt distinguishes the active vs inactive cases, so future
# editors don't drop one branch silently. Look for both an "active"
# and "inactive" (or "not active" / "skip the prefix") cue near the
# guest-mode block.
if grep -qiE 'guest mode (active|inactive)|skip the prefix|guest mode is active' "$PROMPT"; then
  pass "prompt distinguishes active vs inactive guest mode"
else
  fail "prompt distinguishes active vs inactive guest mode" \
    "no active/inactive cue found"
fi

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
