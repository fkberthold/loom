#!/usr/bin/env bash
# Acceptance test for templates/design-doc/ (loom-dhra).
#
# The L2 living-design-document template is the working-surface artifact a
# /design-a-cycle orchestrator maintains. It mirrors templates/diataxis/ —
# a sed-substitution skeleton with {{ topic }} / {{ wing }} tokens — but
# unlike the diataxis tree it has NO mkdocs build step. The skeleton is a
# MemPalace DESIGN DOC drawer body, so this test is self-contained
# (structural assertions only; no external tool dependency).
#
# Verifies:
#   1. templates/design-doc/ exists and carries a *.template skeleton.
#   2. Substituting {{ topic }} / {{ wing }} into a copy and renaming
#      *.template -> * yields a well-formed design doc.
#   3. The STRUCTURED STATE HEADER carries every field the orchestrator
#      reads/updates each cycle: cycle-number, locked-decisions,
#      open [CLARIFICATION] markers, soundness-status (red/amber/green),
#      spawned research-bead IDs, target implementation-epic ID.
#   4. The reasoning sections are present: Question/Scope; Decisions-locked;
#      Grounding-checklist; Lineage.
#   5. A locked-decision block shows the required shape: grounding cite,
#      options / why-not, and an optional L3 spec block (Given-When-Then
#      OR INVARIANT:).
#   6. No surviving {{ topic }} / {{ wing }} placeholders after sed.
#   7. A short README explains the substitution mechanism (mirrors the
#      diataxis substitution-pointer convention).
#
# Run:  bash lib/tests/design-doc-template.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="$LOOM_ROOT/templates/design-doc"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" path="$2" pattern="$3"
  if [ ! -f "$path" ]; then fail "$name" "(file missing: $path)"; return; fi
  if grep -qE "$pattern" "$path"; then pass "$name"
  else fail "$name" "(pattern not found in $path: $pattern)"; fi
}

# --- prereqs -----------------------------------------------------------
echo "==> Prereqs"
if [ ! -d "$TEMPLATE_DIR" ]; then
  fail "templates/design-doc/ exists" "(directory missing — bead has not landed)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "templates/design-doc/ exists"

# A *.template skeleton file must exist (the design-doc drawer body).
SKEL="$(find "$TEMPLATE_DIR" -type f -name '*.md.template' | head -n1)"
if [ -z "$SKEL" ]; then
  fail "a *.md.template skeleton exists under templates/design-doc/"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "skeleton present: ${SKEL#$LOOM_ROOT/}"

# A README explaining the substitution mechanism (mirrors diataxis).
README="$(find "$TEMPLATE_DIR" -maxdepth 1 -type f -iname 'readme*' | head -n1)"
if [ -n "$README" ]; then
  pass "substitution README present: ${README#$LOOM_ROOT/}"
  assert_contains "README explains sed substitution" "$README" '(^|[^a-z])sed([^a-z]|$)'
  assert_contains "README names the {{ topic }} token" "$README" '\{\{ topic \}\}'
  assert_contains "README names the {{ wing }} token" "$README" '\{\{ wing \}\}'
else
  fail "substitution README present under templates/design-doc/"
fi

# --- pre-substitution token contract -----------------------------------
echo "==> Tokens present in the raw skeleton (pre-substitution)"
assert_contains "skeleton carries {{ topic }} token" "$SKEL" '\{\{ topic \}\}'
assert_contains "skeleton carries {{ wing }} token" "$SKEL" '\{\{ wing \}\}'

# --- populate a tmp copy -----------------------------------------------
echo "==> Populate (sed substitution + rename, mirroring templates/diataxis)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -r "$TEMPLATE_DIR/." "$TMP/"

TOPIC="design-cycle layered substrate"
WING="loom"

# substitute placeholders in every regular file (same mechanism as
# lib/tests/diataxis-template.test.sh)
while IFS= read -r -d '' f; do
  sed -i \
    -e "s|{{ topic }}|$TOPIC|g" \
    -e "s|{{ wing }}|$WING|g" \
    "$f"
done < <(find "$TMP" -type f -print0)

# rename *.template -> *
while IFS= read -r -d '' f; do
  mv "$f" "${f%.template}"
done < <(find "$TMP" -type f -name '*.template' -print0)

DOC="$(find "$TMP" -type f -name '*.md' ! -iname 'readme*' | head -n1)"
if [ -z "$DOC" ]; then
  fail "populated design doc produced (*.md after rename)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "populated design doc produced: ${DOC#$TMP/}"

# --- substitution happened ---------------------------------------------
echo "==> Substituted values present"
assert_contains "topic substituted into the doc" "$DOC" "$TOPIC"
assert_contains "wing substituted into the doc" "$DOC" "(^|[^a-z])$WING([^a-z]|$)"

# --- STATE HEADER fields -----------------------------------------------
echo "==> Structured STATE HEADER fields (orchestrator reads/updates each cycle)"
assert_contains "STATE HEADER section marker" "$DOC" 'STATE HEADER'
assert_contains "field: cycle-number"          "$DOC" '[Cc]ycle'
assert_contains "field: locked-decisions"      "$DOC" '[Ll]ocked.[Dd]ecisions|[Ll]ocked decisions'
assert_contains "field: open [CLARIFICATION] markers" "$DOC" '\[CLARIFICATION'
assert_contains "field: soundness-status"      "$DOC" '[Ss]oundness'
assert_contains "soundness uses red/amber/green vocabulary" "$DOC" 'red.*amber.*green|red/amber/green'
assert_contains "field: spawned research-bead IDs" "$DOC" '[Rr]esearch.[Bb]ead|research-bead|[Ss]pawned'
assert_contains "field: target implementation-epic ID" "$DOC" '[Ii]mplementation.[Ee]pic|implementation-epic|[Tt]arget [Ee]pic'

# --- reasoning sections ------------------------------------------------
echo "==> Reasoning sections"
assert_contains "section: Question / Scope" "$DOC" '[Qq]uestion|[Ss]cope'
assert_contains "section: Decisions-locked" "$DOC" '[Dd]ecisions.[Ll]ocked|Decisions locked'
assert_contains "section: Grounding-checklist" "$DOC" '[Gg]rounding'
assert_contains "section: Lineage" "$DOC" '[Ll]ineage'

# --- locked-decision block shape ---------------------------------------
echo "==> Locked-decision block shape (grounding + options/why-not + optional L3 spec)"
assert_contains "decision block cites grounding" "$DOC" '[Gg]rounding'
assert_contains "decision block shows options / why-not" "$DOC" '[Ww]hy.not|[Oo]ptions'
# L3 spec block: at least one of Given-When-Then OR INVARIANT: must appear.
if grep -qE 'Given.*When.*Then|GIVEN|INVARIANT:' "$DOC"; then
  pass "decision block shows an optional L3 spec block (Given-When-Then or INVARIANT:)"
else
  fail "decision block shows an optional L3 spec block (Given-When-Then or INVARIANT:)" \
    "(neither a Given-When-Then scenario nor an INVARIANT: line found)"
fi

# --- no surviving placeholders -----------------------------------------
echo "==> No surviving {{ topic }} / {{ wing }} placeholders after substitution"
stray=$(grep -rEl '\{\{ (topic|wing) \}\}' "$TMP" 2>/dev/null || true)
if [ -z "$stray" ]; then
  pass "no surviving topic/wing placeholders"
else
  fail "no surviving topic/wing placeholders" "$stray"
fi

# --- no leftover *.template files ---------------------------------------
echo "==> No leftover *.template files after rename"
leftover=$(find "$TMP" -type f -name '*.template' 2>/dev/null || true)
if [ -z "$leftover" ]; then
  pass "no leftover *.template files"
else
  fail "no leftover *.template files" "$leftover"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
