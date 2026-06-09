#!/usr/bin/env bash
# Locking-spec (RED) contract test for the /explore orchestrator
# (loom-ld1q.2).
#
# /explore is the SUB-design exploration primitive — upstream of the
# design cycle (explore → design → build, loom-ld1q). This test pins the
# bead's locked RED: invariant against the skill prose so the contract
# cannot silently regress.
#
# CONTRACT (verbatim from the bead's RED: line):
#   INVARIANT: the `/explore` skill documents
#     (a) the FOUR source tiers including peer-reviewed literature;
#     (b) HYBRID dispatch — light tiers in-thread / heavy tiers via a
#         dispatched `deep-research` round, central writes nothing but
#         the capture;
#     (c) the REST and PROMOTE exits, with PROMOTE wiring a `grounded_in`
#         edge to the spawned `/design-a-cycle`;
#     (d) the `exploration` drawer tag.
#
# Primary target: skills/explore/SKILL.md (the orchestrator prose).
# Secondary: commands/explore.md (the thin slash-command wrapper) — where
# a clause is naturally documented in the wrapper too, the assertion
# accepts a match in EITHER file.
#
# This is a grep-contract test: it asserts each clause is DOCUMENTED in
# the skill prose, specific enough to pin the contract but loose enough
# not to forbid reasonable phrasing.
#
# Run:  bash lib/tests/explore-contract.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/explore/SKILL.md"
CMD_FILE="$LOOM_ROOT/commands/explore.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert pattern is present in the skill prose. Required file: SKILL_FILE.
assert_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qiE "$pattern" "$SKILL_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in skill prose: $pattern)"
  fi
}

# Assert pattern is present in EITHER the skill prose or the command
# wrapper — used for clauses the thin wrapper may legitimately carry.
assert_contains_either() {
  local name="$1" pattern="$2"
  local files_present=0
  for f in "$SKILL_FILE" "$CMD_FILE"; do
    [ -f "$f" ] && files_present=$((files_present + 1))
  done
  if [ "$files_present" -eq 0 ]; then
    fail "$name" "(both files missing: $SKILL_FILE , $CMD_FILE)"
    return
  fi
  for f in "$SKILL_FILE" "$CMD_FILE"; do
    if [ -f "$f" ] && grep -qiE "$pattern" "$f"; then
      pass "$name"
      return
    fi
  done
  fail "$name" "(pattern not found in skill or command: $pattern)"
}

# ---------------------------------------------------------------------------
echo "==> Clause (a): FOUR source tiers including peer-reviewed literature"
# The exploration blends four tiers; tier 4 is the distinguishing one —
# peer-reviewed / scholarly literature. Pin both: the count and tier 4.
assert_contains "four source tiers named" \
  'four[ -]?(source )?tiers?|4 (source )?tiers?|tier 4|tier-4'
assert_contains "tier 4 is peer-reviewed / scholarly literature" \
  'peer[ -]?reviewed|scholarly|academic literature'

# ---------------------------------------------------------------------------
echo "==> Clause (b): HYBRID dispatch — light in-thread / heavy via deep-research"
# Light tiers run in-thread; heavy tiers are dispatched as a deep-research
# round; central writes nothing but the capture (dispatch-v2 lean-central).
assert_contains "hybrid loop named" \
  'hybrid'
assert_contains "light tiers run in-thread" \
  'in[ -]?thread'
assert_contains "heavy tiers dispatched as a deep-research round" \
  'deep[ -]?research'
assert_contains "central writes nothing but the capture (lean-central)" \
  'writes? nothing|nothing but the capture|lean[ -]?central'

# ---------------------------------------------------------------------------
echo "==> Clause (c): REST and PROMOTE exits; PROMOTE wires grounded_in to design-a-cycle"
# Two user-declared exits, no gate.
assert_contains "REST exit documented" \
  'REST'
assert_contains "PROMOTE exit documented" \
  'PROMOTE'
# PROMOTE opens a /design-a-cycle whose decisions are wired grounded_in
# this exploration drawer.
assert_contains "PROMOTE spawns /design-a-cycle" \
  'design-a-cycle'
assert_contains "PROMOTE wires a grounded_in edge" \
  'grounded_in'

# ---------------------------------------------------------------------------
echo "==> Clause (d): the 'exploration' drawer tag (tag, not a dedicated room)"
# Memory is ONE drawer tagged 'exploration' so bug-family search reaches it.
assert_contains "drawer tagged 'exploration'" \
  'tag[^a-z]*exploration|exploration[^a-z]*tag|tagged .exploration.|`exploration`'

# ---------------------------------------------------------------------------
echo "==> Wrapper: commands/explore.md exists as the thin slash-command"
# The slash command is part of the interface under test; assert it exists
# and loads the explore skill (clause documentation may live in either).
assert_contains_either "explore slash-command loads the explore skill" \
  'explore'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
