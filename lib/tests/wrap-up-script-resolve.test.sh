#!/usr/bin/env bash
# Locking-spec (RED) contract test for /wrap-up's quality-gate step
# resolving the test command via loom_resolve_command (loom-oxs.5).
#
# /wrap-up step 2 (preflight checks) must run the project's test suite
# through the script/ convention RESOLVER — script/test →
# canonical_commands.test → warn — instead of a hardcoded
# `python3 -m pytest` example. The resolver lives at
# lib/loom-script-resolve.sh, function loom_resolve_command
# (loom-oxs.2). This wires /wrap-up to the resolver so the test command
# is project-agnostic and a missing command WARNS (never reports green).
#
# CONTRACT (verbatim from the bead's RED: line):
#   Given /wrap-up's quality-gate step: When loom_resolve_command
#   resolves a test command → /wrap-up runs the RESOLVED command, NOT a
#   hardcoded python3 -m pytest. When no test command resolves → it
#   warns (never reports green).
#
# Primary target: commands/wrap-up.md (the /wrap-up slash-command prose;
# the bead text said "skills/wrap-up" but grep confirmed the definition
# lives in commands/wrap-up.md).
#
# This is a grep-contract test: it asserts the quality-gate step
# references loom_resolve_command, no longer hardcodes
# `python3 -m pytest` as THE test command, and documents the
# warn-on-absent / never-green fallback.
#
# Run:  bash lib/tests/wrap-up-script-resolve.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPUP_FILE="$LOOM_ROOT/commands/wrap-up.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert pattern is present in the /wrap-up prose.
assert_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$WRAPUP_FILE" ]; then
    fail "$name" "(file missing: $WRAPUP_FILE)"
    return
  fi
  if grep -qiE "$pattern" "$WRAPUP_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in /wrap-up prose: $pattern)"
  fi
}

# Assert pattern is ABSENT from the /wrap-up prose.
assert_absent() {
  local name="$1" pattern="$2"
  if [ ! -f "$WRAPUP_FILE" ]; then
    fail "$name" "(file missing: $WRAPUP_FILE)"
    return
  fi
  if grep -qiE "$pattern" "$WRAPUP_FILE"; then
    fail "$name" "(forbidden pattern still present: $pattern)"
  else
    pass "$name"
  fi
}

# ---------------------------------------------------------------------------
echo "==> Clause: the quality-gate step references loom_resolve_command"
# The resolver function from lib/loom-script-resolve.sh — script/test →
# canonical_commands.test → warn. /wrap-up must call it to resolve the
# test command, NOT name a single project's test runner.
assert_contains "loom_resolve_command named in /wrap-up" \
  'loom_resolve_command'
# Resolve the 'test' command specifically.
assert_contains "resolves the 'test' command" \
  'loom_resolve_command[[:space:]]+test'

# ---------------------------------------------------------------------------
echo "==> Clause: the RESOLVED command is run (not a hardcoded runner)"
# Step 2 must run whatever the resolver returns, not assert a literal
# pytest invocation as THE suite command.
assert_absent "no hardcoded 'python3 -m pytest' test command remains" \
  'python3 -m pytest'

# ---------------------------------------------------------------------------
echo "==> Clause: warn-on-absent — never report green when no command resolves"
# Rung 3 of the resolver warns + returns non-zero. /wrap-up must honor
# that: a missing test command is a refusal/block, NOT a silent pass.
assert_contains "warn-on-absent / never-green fallback documented" \
  'warn|never.*green|never.*pass|block|refus'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
