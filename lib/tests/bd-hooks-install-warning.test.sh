#!/usr/bin/env bash
# Doc-presence tests for the loom-cka mitigation: every surface that
# tells the user to run `bd hooks install` must also tell them to
# run an absorbing bd-only commit before any logical commit, so the
# bd pre-commit hook's `.beads/issues.jsonl` re-export does not ride
# along into the user's first logical commit (observed in loom-b6o
# tla-puzzles trial 2026-05-04, cardinality commit 891d2ae).
#
# This is a doc-text guard — it asserts the warning language stays
# put across edits. If the prose evolves, update the patterns here
# in the same commit.
#
# Run:  bash lib/tests/bd-hooks-install-warning.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" file="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in $file: $pattern)"
  fi
}

# --- project-onboarder MISS line carries the absorbing-commit guidance
echo "==> agents/project-onboarder.md (item 3 MISS expansion)"
assert_contains \
  "MISS suggestion mentions absorbing commit" \
  "$LOOM_ROOT/agents/project-onboarder.md" \
  "post-install export sync|absorb the export-pending queue|absorbing commit"
assert_contains \
  "MISS suggestion cites loom-cka lineage" \
  "$LOOM_ROOT/agents/project-onboarder.md" \
  "loom-cka"

# --- bd-cli reference doc carries the warning admonition
echo "==> docs/reference/bd-cli.md (Hooks section warning)"
assert_contains \
  "bd-cli has the absorbing-commit warning" \
  "$LOOM_ROOT/docs/reference/bd-cli.md" \
  "absorb|absorbing commit|post-install export sync"
assert_contains \
  "bd-cli warning cites the trial-observation lineage" \
  "$LOOM_ROOT/docs/reference/bd-cli.md" \
  "loom-cka|loom-b6o|891d2ae"

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
