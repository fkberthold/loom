#!/usr/bin/env bash
# Locking-spec test for skills/bead-lifecycle-shell/SKILL.md — Phase B
# (variable middle handoff) central-agent delegation discipline.
#
# loom-7p6.1 (original): the shell's variable-middle section must read
# as "dispatch a worker", not "do the work yourself".
#
# loom-6bv1 (T2 of epic loom-5m94, dispatch architecture v2): the
# variable middle's DEFAULT is now `/dispatch-middle` — a test-author
# THEN implementer pipeline of DIFFERENT agents, central writes NOTHING
# in the middle. NOT the old loom-yb5 "one worker does RED→GREEN"
# model, NOT inline. This file is updated in lock-step to pin the new
# contract: the test-author→implementer-via-/dispatch-middle default,
# central-writes-nothing, and the sharpened central/worker line.
# Architecture locked in drawer_loom_decisions_fe831554f7a62b9c6ea4bf18
# (dispatch-v2 brainstorm, 2026-06-07).
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

assert_absent() {
  # Negative guard — the pattern must NOT appear (a superseded phrasing
  # was removed). Same wrap-tolerant haystack as assert_contains.
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  local haystack
  haystack=$(tr -s '[:space:]' ' ' < "$SKILL_FILE")
  if grep -qE "$pattern" "$SKILL_FILE" \
     || printf '%s' "$haystack" | grep -qE "$pattern"; then
    fail "$name" "(superseded pattern still present: $pattern)"
  else
    pass "$name"
  fi
}

# =====================================================================
# 1. Boilerplate paragraph — verbatim string match
# =====================================================================
#
# Recipes cite this paragraph by reference. The wording is load-bearing.
# loom-6bv1: the v2 default is /dispatch-middle (test-author THEN
# implementer, DIFFERENT agents), and central writes NOTHING in the
# middle — NOT the old loom-yb5 "one worker does the full RED→GREEN".

echo "==> Phase B dispatch-discipline boilerplate present (verbatim)"
assert_contains_literal "boilerplate: dispatch discipline opener" \
  "Dispatch discipline (uniform across all recipes): the variable middle is dispatched"
assert_contains_literal "boilerplate: default is /dispatch-middle" \
  "The DEFAULT is \`/dispatch-middle\`"
assert_contains_literal "boilerplate: test-author THEN implementer, different agents" \
  "test-author THEN implementer (DIFFERENT agents)"
assert_contains_literal "boilerplate: central writes nothing in the middle" \
  "Central writes NOTHING in the middle"
assert_contains_literal "boilerplate: do NOT use Edit/Write/MultiEdit between claim and close" \
  "Do NOT use Edit/Write/MultiEdit yourself between bead-claim and bead-close."
assert_contains_literal "boilerplate: while the pipeline runs" \
  "While the pipeline runs"
assert_contains_literal "boilerplate: parallel code-work forbidden in central" \
  "do NOT start parallel code-work in the central session"
assert_contains_literal "boilerplate: pipeline returns; you integrate; re-dispatch only on surprises" \
  "The pipeline returns; you integrate; you re-dispatch only on surprises."

# The old loom-yb5 "one worker covers the full variable middle" model
# must be explicitly retired — assert the superseded phrasing is GONE.
echo "==> Old single-worker-whole-middle model is retired"
assert_absent "retired: single worker covers the full variable middle" \
  "single worker.*covering the full variable middle"

# =====================================================================
# 1b. /dispatch-middle default + sharpened central/worker line
# =====================================================================
#
# loom-6bv1 (T2 of loom-5m94): the variable middle's DEFAULT is the
# test-author→implementer split via /dispatch-middle. The central/
# worker line is sharpened: central does ONLY conversation +
# contract-lock + integration; workers do RED-test + GREEN-code +
# research + review, each with a MINIMAL scoped context.

echo "==> /dispatch-middle default + sharpened central/worker line"
assert_contains "default: /dispatch-middle is the DEFAULT" \
  '/dispatch-middle.*(is the|the).*DEFAULT|DEFAULT is.*/dispatch-middle'
assert_contains "default: test-author then implementer pipeline" \
  'test-author.*(→|->|then).*implementer'
assert_contains "default: different agents (independence)" \
  '[Dd]ifferent agents|DIFFERENT agents'
assert_contains "central: writes NOTHING in the middle" \
  'central writes NOTHING|writes NOTHING in the middle|never writes a (test|line)'
assert_contains "central line: conversation + contract-lock + integration" \
  'conversation.*contract-?lock.*integration|contract-?lock.*integration'
assert_contains "central: contract-lock is M1 user dialogue" \
  'M1.*(user|dialogue)|contract-?lock.*M1'
assert_contains "central: integration is cwd-sensitive + bd-authoritative" \
  'cwd-sensitive.*bd-authoritative|bd-authoritative.*cwd-sensitive'
assert_contains "worker line: RED-test + GREEN-code + research + review" \
  'RED-?test.*GREEN-?code.*research.*review'
assert_contains "worker line: minimal scoped context" \
  '[Mm]inimal.*(scoped|slice).*context|[Mm]inimal scoped|MINIMAL.*(scoped|slice).*context'

# =====================================================================
# 1c. Friction-inversion rationale + mechanical inline exception
# =====================================================================
#
# loom-6bv1: dispatch is now a single cheap command, so inline's only
# remaining justification is the mechanical threshold (≤15 lines /
# single non-test file / no new test) — and even that PREFERS
# /dispatch-middle.

echo "==> Friction-inversion rationale + mechanical inline exception"
assert_contains "friction-inversion: dispatch is a single cheap command" \
  'single (cheap )?command|cheap.*command|friction-invert'
assert_contains "exception: inline is the explicit/justified exception" \
  '[Ii]nline is the explicit'
assert_contains "threshold: ≤ ~15 lines bound" \
  '≤ ?~?15 lines|15 lines'
assert_contains "threshold: single non-test file" \
  'single non-test file'
assert_contains "threshold: adds no new test" \
  'no new test|adds no new test'
assert_contains "exception: even the threshold PREFERS /dispatch-middle" \
  '[Pp]refer.*/dispatch-middle|even.*prefers? .*/dispatch-middle|still prefer'
assert_contains "recording: workflow-state dispatch field" \
  'workflow-state.*dispatch field|dispatch=worker|dispatch=inline'
assert_contains "cross-ref: dispatch-nudge hook points at /dispatch-middle" \
  'dispatch-nudge hook|dispatch-nudge'

# =====================================================================
# 2. While-the-pipeline-runs allowed/forbidden explicit lists
# =====================================================================
#
# loom-6bv1: the in-flight window is now "while the pipeline runs"
# (test-author → implementer), not "while the worker runs". Central's
# in-flight posture is unchanged: conversation + read-only investigation
# allowed; any code-write / merge / close forbidden.

echo "==> Explicit while-the-pipeline-runs allowed/forbidden lists"
assert_contains "while-pipeline-runs: allowed list" \
  '[Aa]llowed[[:space:]]+while[[:space:]]+the[[:space:]]+pipeline[[:space:]]+runs|[Aa]llowed.*pipeline.*runs'
assert_contains "while-pipeline-runs: forbidden list" \
  '[Ff]orbidden[[:space:]]+while[[:space:]]+the[[:space:]]+pipeline[[:space:]]+runs|[Ff]orbidden.*pipeline.*runs'

# =====================================================================
# 3. Brief templates delegated to /dispatch-middle
# =====================================================================
#
# loom-6bv1: the shell no longer carries the old single 7-section
# worker-brief template. /dispatch-middle owns the TWO brief templates
# (test-author + implementer); the shell points at it by reference
# rather than duplicating. Assert the delegation + the load-bearing
# dispatch-hygiene facts still surface here.

echo "==> Brief templates delegated to /dispatch-middle"
assert_contains "shell cites /dispatch-middle for the brief templates" \
  '/dispatch-middle'
assert_contains "shell names the test-author + implementer brief pair" \
  'test-author.*brief.*implementer|test-author.*implementer.*brief|two brief templates'
# The old single-worker 7-section brief template must be retired —
# it now lives in /dispatch-middle, not duplicated in the shell.
assert_absent "retired: old 7-section single-worker brief template (Anti-scope/Voice)" \
  '\*\*Anti-scope\*\*.*\*\*Voice\*\*'

echo "==> Dispatch hygiene specifics surfaced (smoke battery + branch + hand-off)"
assert_contains "dispatch hygiene cites pre-flight smoke battery" \
  'pre-flight smoke battery|smoke battery'
assert_contains "dispatch hygiene cites frank/<id> branch / worktree" \
  'frank/<id>|frank/<bead'
assert_contains "dispatch hygiene says workers commit but do not merge/push/close" \
  '[Dd]o not (merge|push|close)|not (merge|push|close)|commit but do not|central.*integrat'

# =====================================================================
# 4. Re-dispatch decision rule
# =====================================================================
#
# Clean / minor polish ≤3 lines central does / substantive rework fresh
# pipeline (re-brief the test-author or implementer).

echo "==> Re-dispatch decision rule present"
assert_contains "re-dispatch decision rule named" \
  '[Rr]e-dispatch|re-?dispatch decision'
assert_contains "re-dispatch rule names 3-line polish threshold" \
  '3[- ]lines?|three[- ]lines?|≤[[:space:]]*3'
assert_contains "re-dispatch rule names substantive rework / fresh pipeline" \
  '[Ss]ubstantive rework|fresh worker|re-brief'

# =====================================================================
# 5. Central re-runs verification after the pipeline returns
# =====================================================================

echo "==> Trust-but-verify note: central re-runs verification"
assert_contains "central re-runs verification after the pipeline returns" \
  'verification-before-completion|re-run.*verif|central re-runs|trust-but-verify'

# =====================================================================
# 6. Phase-ownership clarification
# =====================================================================
#
# A1 (search) and D-drafting are subagent-owned; A2/A3 (claim+worktree),
# C (commit+finish), D (file) are central; B (variable middle) runs as
# the test-author→implementer pipeline (workers), central writes nothing.

echo "==> Phase-ownership clarification present"
assert_contains "ownership: central owns A2/A3 + C + D-filing" \
  'CENTRAL|central[[:space:]]+(owns|agent)'
assert_contains "ownership: subagent owns A1 + D-drafting" \
  'SUBAGENT|subagent[[:space:]]+(owns|territory)|bug-family-researcher.*drawer-author|drawer-author.*kg-relationship-extractor'
assert_contains "ownership: pipeline (test-author→implementer) owns B" \
  '/dispatch-middle|test-author.*implementer|PIPELINE|pipeline.*(owns|territory)|variable middle.*pipeline'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
