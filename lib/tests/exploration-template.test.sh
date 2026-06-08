#!/usr/bin/env bash
# Acceptance test for templates/exploration/ (loom-ld1q.1).
#
# The exploration template is the light, SUB-design drawer skeleton that the
# `/explore <idea>` command seeds into MemPalace wing `loom` room `decisions`,
# tagged `exploration`. It is the front-door to `/design-a-cycle`: an
# above-bead exploration primitive that is NOT a bead and NOT a design cycle
# (no soundness gate). It mirrors templates/design-doc/ — a sed-substitution
# skeleton with {{ question }} / {{ wing }} tokens — but unlike the diataxis
# tree it has NO mkdocs build step. The skeleton is a MemPalace drawer body,
# so this test is self-contained (structural assertions only; no external
# tool dependency).
#
# Verifies:
#   1. templates/exploration/ exists and carries a *.template skeleton.
#   2. Substituting {{ question }} / {{ wing }} into a copy and renaming
#      *.template -> * yields a well-formed exploration drawer.
#   3. The STATE HEADER carries every field the exploration loop reads/updates:
#      question, status (allowed values active|rested|promoted), tiers-touched,
#      open-threads, current-understanding.
#   4. The sections are present: Inquiry log; Findings; Lineage.
#   5. No surviving {{ question }} / {{ wing }} placeholders after sed.
#   6. No leftover *.template files after rename.
#   7. A short README explains the substitution mechanism (mirrors the
#      diataxis / design-doc substitution-pointer convention).
#
# Run:  bash lib/tests/exploration-template.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="$LOOM_ROOT/templates/exploration"

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
  fail "templates/exploration/ exists" "(directory missing — bead has not landed)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "templates/exploration/ exists"

# A *.template skeleton file must exist (the exploration drawer body).
SKEL="$(find "$TEMPLATE_DIR" -type f -name '*.md.template' | head -n1)"
if [ -z "$SKEL" ]; then
  fail "a *.md.template skeleton exists under templates/exploration/"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "skeleton present: ${SKEL#$LOOM_ROOT/}"

# A README explaining the substitution mechanism (mirrors design-doc/diataxis).
README="$(find "$TEMPLATE_DIR" -maxdepth 1 -type f -iname 'readme*' | head -n1)"
if [ -n "$README" ]; then
  pass "substitution README present: ${README#$LOOM_ROOT/}"
  assert_contains "README explains sed substitution" "$README" '(^|[^a-z])sed([^a-z]|$)'
  assert_contains "README names the {{ question }} token" "$README" '\{\{ question \}\}'
  assert_contains "README names the {{ wing }} token" "$README" '\{\{ wing \}\}'
else
  fail "substitution README present under templates/exploration/"
fi

# --- pre-substitution token contract -----------------------------------
echo "==> Tokens present in the raw skeleton (pre-substitution)"
assert_contains "skeleton carries {{ question }} token" "$SKEL" '\{\{ question \}\}'
assert_contains "skeleton carries {{ wing }} token" "$SKEL" '\{\{ wing \}\}'

# --- populate a tmp copy -----------------------------------------------
echo "==> Populate (sed substitution + rename, mirroring templates/design-doc)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -r "$TEMPLATE_DIR/." "$TMP/"

QUESTION="what shape should the explore primitive take"
WING="loom"

# substitute placeholders in every regular file (same mechanism as
# lib/tests/design-doc-template.test.sh)
while IFS= read -r -d '' f; do
  sed -i \
    -e "s|{{ question }}|$QUESTION|g" \
    -e "s|{{ wing }}|$WING|g" \
    "$f"
done < <(find "$TMP" -type f -print0)

# rename *.template -> *
while IFS= read -r -d '' f; do
  mv "$f" "${f%.template}"
done < <(find "$TMP" -type f -name '*.template' -print0)

DOC="$(find "$TMP" -type f -name '*.md' ! -iname 'readme*' | head -n1)"
if [ -z "$DOC" ]; then
  fail "populated exploration drawer produced (*.md after rename)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "populated exploration drawer produced: ${DOC#$TMP/}"

# --- substitution happened ---------------------------------------------
echo "==> Substituted values present"
assert_contains "question substituted into the doc" "$DOC" "$QUESTION"
assert_contains "wing substituted into the doc" "$DOC" "(^|[^a-z])$WING([^a-z]|$)"

# --- STATE HEADER fields -----------------------------------------------
echo "==> STATE HEADER fields (the exploration loop reads/updates each touch)"
assert_contains "STATE HEADER section marker" "$DOC" 'STATE HEADER'
assert_contains "field: question"              "$DOC" '[Qq]uestion'
assert_contains "field: status"                "$DOC" '[Ss]tatus'
assert_contains "status allowed values active|rested|promoted" "$DOC" 'active.*rested.*promoted|active \| rested \| promoted'
assert_contains "field: tiers-touched"         "$DOC" '[Tt]iers.touched|tiers-touched'
assert_contains "field: open-threads"          "$DOC" '[Oo]pen.threads|open-threads'
assert_contains "field: current-understanding" "$DOC" '[Cc]urrent.understanding|current-understanding'

# --- sections ----------------------------------------------------------
echo "==> Sections"
assert_contains "section: Inquiry log" "$DOC" '##[[:space:]]*[Ii]nquiry log'
assert_contains "section: Findings"    "$DOC" '##[[:space:]]*[Ff]indings'
assert_contains "section: Lineage"     "$DOC" '##[[:space:]]*[Ll]ineage'

# --- no surviving placeholders -----------------------------------------
echo "==> No surviving {{ question }} / {{ wing }} placeholders after substitution"
stray=$(grep -rEl '\{\{ (question|wing) \}\}' "$TMP" 2>/dev/null || true)
if [ -z "$stray" ]; then
  pass "no surviving question/wing placeholders"
else
  fail "no surviving question/wing placeholders" "$stray"
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
