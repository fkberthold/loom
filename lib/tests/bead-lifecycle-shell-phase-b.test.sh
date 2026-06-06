#!/usr/bin/env bash
# Locking-spec test for skills/bead-lifecycle-shell/SKILL.md — Phase B
# (variable middle handoff) central-agent delegation discipline.
#
# loom-7p6.1: the shell's variable-middle section must read as
# "dispatch a worker", not "do the work yourself". Six child beads
# (loom-7p6.2 … loom-7p6.7) rewrite each activity recipe's middle to
# cite this shell — so the boilerplate + brief template + decision
# rules live here and only here.
#
# These tests are doc-presence guards over the markdown prose. If the
# wording evolves, update the patterns in the same commit. The
# boilerplate paragraph is matched verbatim because downstream recipes
# will quote it.
#
# Run:  bash lib/tests/bead-lifecycle-shell-phase-b.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/bead-lifecycle-shell/SKILL.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  # Regex match — tries line-by-line first (cheap), then falls back to
  # a whitespace-collapsed single-line haystack so phrases that wrap
  # across the file's ~70-column line break still match.
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qE "$pattern" "$SKILL_FILE"; then
    pass "$name"
    return
  fi
  local haystack
  haystack=$(tr -s '[:space:]' ' ' < "$SKILL_FILE")
  if printf '%s' "$haystack" | grep -qE "$pattern"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

assert_contains_literal() {
  # Verbatim phrase match that tolerates the file's hard line-wrap:
  # collapse all whitespace in both haystack and needle, then compare.
  # The phrase content is load-bearing (recipes will quote it); the
  # wrapping is house style and should not break the test.
  local name="$1" needle="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  local haystack needle_norm
  haystack=$(tr -s '[:space:]' ' ' < "$SKILL_FILE")
  needle_norm=$(printf '%s' "$needle" | tr -s '[:space:]' ' ')
  if printf '%s' "$haystack" | grep -qF -- "$needle_norm"; then
    pass "$name"
  else
    fail "$name" "(literal not found: $needle)"
  fi
}

# =====================================================================
# 1. Boilerplate paragraph — verbatim string match
# =====================================================================
#
# Recipes cite this paragraph by reference. The wording is load-bearing.

echo "==> Phase B dispatch-discipline boilerplate present (verbatim)"
assert_contains_literal "boilerplate: dispatch discipline opener" \
  "Dispatch discipline (uniform across all recipes): Phase B is worker territory"
assert_contains_literal "boilerplate: brief a single worker via Agent + isolation worktree" \
  "Brief a single worker via Agent + isolation: worktree covering the full variable middle in one dispatch."
assert_contains_literal "boilerplate: do NOT use Edit/Write/MultiEdit between claim and close" \
  "Do NOT use Edit/Write/MultiEdit yourself between bead-claim and bead-close."
assert_contains_literal "boilerplate: while-worker-runs allowed actions" \
  "While the worker runs"
assert_contains_literal "boilerplate: parallel code-work forbidden in central" \
  "do NOT start parallel code-work in the central session"
assert_contains_literal "boilerplate: worker returns; you review; re-dispatch only on surprises" \
  "The worker returns; you review; you re-dispatch only on surprises."

# =====================================================================
# 1b. Worker-dispatch default + mechanical inline-exception threshold
# =====================================================================
#
# loom-mcy (T4 of loom-yb5): worker-dispatch is the stated DEFAULT for
# any RED→GREEN-cycle bead; inline is the explicit exception, allowed
# without justification only under a mechanical, checkable threshold.

echo "==> Worker-dispatch default + mechanical inline-exception threshold"
assert_contains "default: worker-dispatch is the DEFAULT for RED→GREEN beads" \
  '[Ww]orker-dispatch is the DEFAULT'
assert_contains "default: keyed to RED→GREEN cycle" \
  'RED→GREEN cycle|RED→GREEN-shaped'
assert_contains "exception: inline is the explicit/justified exception" \
  '[Ii]nline is the explicit'
assert_contains "threshold: ≤ ~15 lines bound" \
  '≤ ?~?15 lines|15 lines'
assert_contains "threshold: single non-test file" \
  'single non-test file'
assert_contains "threshold: adds no new test" \
  'no new test|adds no new test'
assert_contains "recording: workflow-state dispatch field" \
  'workflow-state.*dispatch field|dispatch=worker|dispatch=inline'
assert_contains "cross-ref: dispatch-nudge hook (loom-h5s)" \
  'dispatch-nudge hook|loom-h5s'

# =====================================================================
# 2. While-worker-runs allowed/forbidden explicit lists
# =====================================================================

echo "==> Explicit while-worker-runs allowed/forbidden lists"
assert_contains "while-worker-runs: allowed list" \
  '[Aa]llowed[[:space:]]+while[[:space:]]+the[[:space:]]+worker[[:space:]]+runs|[Aa]llowed.*worker.*runs'
assert_contains "while-worker-runs: forbidden list" \
  '[Ff]orbidden[[:space:]]+while[[:space:]]+the[[:space:]]+worker[[:space:]]+runs|[Ff]orbidden.*worker.*runs'

# =====================================================================
# 3. Worker-brief template — seven section headers
# =====================================================================
#
# The template is inline in the skill (not a separate file). Each
# section header must be present as a recognizable subhead so workers
# reading the brief see the same shape every time.

echo "==> Worker-brief template — seven section headers"
assert_contains "brief section: Subject" '\*\*Subject\*\*|^####? +Subject\b|^- \*\*Subject\*\*'
assert_contains "brief section: Context" '\*\*Context\*\*|^####? +Context\b|^- \*\*Context\*\*'
assert_contains "brief section: Scope" '\*\*Scope\*\*|^####? +Scope\b|^- \*\*Scope\*\*'
assert_contains "brief section: Anti-scope" '\*\*Anti-scope\*\*|^####? +Anti-scope\b|^- \*\*Anti-scope\*\*'
assert_contains "brief section: Voice" '\*\*Voice\*\*|^####? +Voice\b|^- \*\*Voice\*\*'
assert_contains "brief section: Dispatch hygiene" '\*\*Dispatch hygiene\*\*|^####? +Dispatch hygiene\b|^- \*\*Dispatch hygiene\*\*'
assert_contains "brief section: Stop-and-report triggers" '\*\*Stop-and-report triggers\*\*|^####? +Stop-and-report triggers\b|^- \*\*Stop-and-report triggers\*\*'

# Cross-cutting content the dispatch-hygiene section must surface
echo "==> Dispatch hygiene specifics inside the brief template"
assert_contains "dispatch hygiene cites pre-flight smoke battery" \
  'pre-flight smoke battery|smoke battery'
assert_contains "dispatch hygiene cites bd update --claim" \
  'bd update.*--claim'
assert_contains "dispatch hygiene cites frank/<id> branch rename" \
  'frank/<id>|frank/<bead'
assert_contains "dispatch hygiene says commit but do not merge/push/close" \
  '[Dd]o not (merge|push|close)|not (merge|push|close)|commit but do not'

# =====================================================================
# 4. Re-dispatch decision rule
# =====================================================================
#
# Clean / minor polish ≤3 lines central does / substantive rework fresh
# worker.

echo "==> Re-dispatch decision rule present"
assert_contains "re-dispatch decision rule named" \
  '[Rr]e-dispatch|re-?dispatch decision'
assert_contains "re-dispatch rule names 3-line polish threshold" \
  '3[- ]lines?|three[- ]lines?|≤[[:space:]]*3'
assert_contains "re-dispatch rule names substantive rework / fresh worker branch" \
  '[Ss]ubstantive rework|fresh worker'

# =====================================================================
# 5. Central re-runs verification after worker returns
# =====================================================================

echo "==> Trust-but-verify note: central re-runs verification"
assert_contains "central re-runs verification after worker returns" \
  'verification-before-completion|re-run.*verif|central re-runs|trust-but-verify'

# =====================================================================
# 6. Phase-ownership clarification
# =====================================================================
#
# A1 (search) and D-drafting are subagent-owned; A2/A3 (claim+worktree),
# C (commit+finish), D (file) are central; B (variable middle) is worker.

echo "==> Phase-ownership clarification present"
assert_contains "ownership: central owns A2/A3 + C + D-filing" \
  'CENTRAL|central[[:space:]]+(owns|agent)'
assert_contains "ownership: subagent owns A1 + D-drafting" \
  'SUBAGENT|subagent[[:space:]]+(owns|territory)|bug-family-researcher.*drawer-author|drawer-author.*kg-relationship-extractor'
assert_contains "ownership: worker owns B (variable middle)" \
  '[Ww]orker.*(owns|territory)|B.*worker|worker.*\bB\b|variable middle.*worker'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
