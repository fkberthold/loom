#!/usr/bin/env bash
# Locking-spec test for the D3-capture fan-out DEFAULT.
#
# loom-0ahj.5 (child of epic loom-0ahj, substrate consolidation):
# grounding design-doc 14f08e6d D6 + the exploration "capture-tax"
# finding. The drawer-author + kg-relationship-extractor subagents
# ALREADY exist; this bead is WIRING, not new capability — it makes
# the two-agent capture fan-out the DOCUMENTED DEFAULT path at
# bead-lifecycle-shell phase D3 (and at /wrap-up). Central REVIEWS +
# FILES their drafts; central does NOT hand-write the drawer / diary /
# KG triples.
#
# INVARIANT: bead-lifecycle-shell phase D3 documents the drawer-author
# + kg-extractor fan-out as the DEFAULT capture path — central
# reviews-not-writes.
#
# Doc-presence test (prose-only). Mirrors the assertion idiom of
# lib/tests/dispatch-middle-contract.test.sh. If the prose evolves,
# update these patterns in the same commit.
#
# Run:  bash lib/tests/capture-fanout-default.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_FILE="$LOOM_ROOT/skills/bead-lifecycle-shell/SKILL.md"
WRAPUP_FILE="$LOOM_ROOT/commands/wrap-up.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert a (case-insensitive, extended) pattern is present in a file.
# Tries a line-by-line match first, then falls back to a whitespace-
# collapsed single-line haystack so phrases that wrap across the
# file's ~70-column line break still match.
assert_in() {
  local file="$1" name="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qiE "$pattern" "$file"; then
    pass "$name"
    return
  fi
  if tr '\n' ' ' < "$file" | tr -s ' ' | grep -qiE "$pattern"; then
    pass "$name"
    return
  fi
  fail "$name" "(pattern not found: $pattern)"
}

# Assert a pattern is present WITHIN the literal "### D3." section of
# the shell SKILL.md (from the "### D3" heading to the next "### " or
# "## " heading). This scopes the DEFAULT-capture assertions to the D3
# section body itself — NOT the pre-existing phase-ownership block —
# so the test genuinely fails until phase D3 documents the fan-out
# default. Whitespace-collapsed so wrapped phrases match.
D3_SECTION="$(awk '
  /^### D3\./ { grab=1 }
  grab && /^(### |## )/ && !/^### D3\./ { grab=0 }
  grab { print }
' "$SHELL_FILE" | tr "\n" " " | tr -s " ")"

assert_in_d3() {
  local name="$1" pattern="$2"
  if printf '%s' "$D3_SECTION" | grep -qiE "$pattern"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in D3 section: $pattern)"
  fi
}

# =====================================================================
# 0. The two files exist
# =====================================================================
echo "==> Files exist"
[ -f "$SHELL_FILE" ] && pass "skills/bead-lifecycle-shell/SKILL.md exists" \
  || fail "skills/bead-lifecycle-shell/SKILL.md exists" "(missing: $SHELL_FILE)"
[ -f "$WRAPUP_FILE" ] && pass "commands/wrap-up.md exists" \
  || fail "commands/wrap-up.md exists" "(missing: $WRAPUP_FILE)"

# =====================================================================
# 1. Phase D3 SECTION names both capture-fan-out subagents
#    (asserted against the D3 section body, NOT the phase-ownership
#    block elsewhere in the file).
# =====================================================================
echo "==> D3 section names the drawer-author + kg-extractor fan-out"
assert_in_d3 "D3 section names drawer-author" \
  'drawer-author'
assert_in_d3 "D3 section names kg-relationship-extractor" \
  'kg-relationship-extractor'

# =====================================================================
# 2. The fan-out is the DOCUMENTED DEFAULT in D3 (not just an option)
# =====================================================================
echo "==> Fan-out is the DEFAULT capture path in D3"
assert_in_d3 "D3 marks the fan-out as the DEFAULT" \
  'default.*(capture|fan[- ]?out|drawer-author|two[- ]agent)|(capture|fan[- ]?out).*default'
assert_in_d3 "D3 names a two-agent / parallel fan-out" \
  'fan[- ]?out|two[- ]agent|both subagents|in parallel'

# =====================================================================
# 3. In D3, central REVIEWS + FILES, does NOT hand-write the capture
#    (the reviews-not-writes posture).
# =====================================================================
echo "==> D3: central reviews + files, does NOT hand-write"
assert_in_d3 "D3 says central reviews the drafts" \
  'central[[:space:]]+reviews|reviews?[[:space:]]+(the[[:space:]]+)?(drafted[[:space:]]+)?(draft|output)'
assert_in_d3 "D3 says central files via mempalace tools" \
  'files?.*(via|through).*mempalace|mempalace.*(mcp|tool)|central[[:space:]]+files'
assert_in_d3 "D3 says central does NOT hand-write the capture" \
  '(does not|do not|never|not).*(hand[- ]?write|hand[- ]?author).*(drawer|diary|kg|capture|triple)|drafting is (subagent|worker)|not[[:space:]]+hand[- ]?write'

# =====================================================================
# 4. In D3, the subagents DRAFT; central is the reviewer/filer.
# =====================================================================
echo "==> D3: subagents draft; central reviews-and-files (the split)"
assert_in_d3 "D3 says subagents DRAFT the capture artifacts" \
  '(drawer-author|kg-relationship-extractor|subagent).*draft|draft.*(drawer|kg|triple)'

# =====================================================================
# 5. /wrap-up triggers the same default fan-out
# =====================================================================
echo "==> /wrap-up triggers the same default fan-out"
assert_in "$WRAPUP_FILE" "wrap-up names drawer-author" \
  'drawer-author'
assert_in "$WRAPUP_FILE" "wrap-up names kg-relationship-extractor" \
  'kg-relationship-extractor'
assert_in "$WRAPUP_FILE" "wrap-up dispatches the fan-out by DEFAULT" \
  'default.*(fan[- ]?out|dispatch|drawer-author|subagent)|(fan[- ]?out|dispatch).*default|in parallel'
assert_in "$WRAPUP_FILE" "wrap-up: central reviews-not-writes" \
  '(review|reviews).*(output|draft)|central.*(review|file).*not.*write|does not.*hand[- ]?write'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
