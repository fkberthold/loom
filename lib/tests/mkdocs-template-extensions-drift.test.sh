#!/usr/bin/env bash
# Regression test for loom-p4tf.
#
# GUARDS AGAINST the loom-be3t drift class: loom's OWN site
# `mkdocs.yml` silently lagging the diataxis template's
# `markdown_extensions`. In be3t (fixed 2026-06-08, commit 17f42ac)
# loom's front page rendered grid-card icons as LITERAL TEXT
# (`:material-school:`) instead of SVG, because loom's instance
# `mkdocs.yml` had quietly lacked `pymdownx.emoji` for ~2 weeks — the
# single extension it lacked vs templates/diataxis/mkdocs.yml.template.
# The template gained the extension in loom-ad1 (commit cda3730);
# loom's own instance was never re-synced.
#
# WHY THIS LAYER (and why neither existing check catches it):
#   - `mkdocs build --strict` does NOT catch it: a stray
#     `:material-school:` is perfectly valid markdown — it just
#     renders as text. No warning, no error, exit 0.
#   - The serving check does NOT catch it: the page still returns
#     HTTP 200; only a human eyeball notices the icons are text.
#   The correct detection layer is therefore a TEMPLATE-DRIFT guard:
#   compare the instance's extension set against the template's at the
#   source-text level, before any build, with no mkdocs runtime.
#
# THE INVARIANT (locked contract):
#   Every `markdown_extensions` NAME declared in
#   templates/diataxis/mkdocs.yml.template is also declared in loom's
#   own mkdocs.yml (instance ⊇ template, compared by extension NAME).
#
# WHY NAME-ALTITUDE, NOT FULL CONFIG-BLOCK comparison:
#   Extensions carry per-extension sub-config (e.g. `toc:
#   permalink: true`, the `pymdownx.emoji` index/generator block). A
#   project legitimately tunes that sub-config without drifting. We
#   compare only the extension NAMES (the `- ext` / `- ext:` keys), so
#   config tuning never false-positives, but a WHOLE extension going
#   missing — the be3t bug — is caught.
#
# THE NEGATIVE SELF-CHECK IS THE CATCH-PROOF:
#   The production invariant is already GREEN (be3t synced both files),
#   so a naive "both sets match" assertion would be vacuously green and
#   could rot into a no-op without anyone noticing. To prove the
#   comparator actually catches drift, we synthesize a temporary
#   "instance" = loom's mkdocs.yml with ONE template extension removed,
#   run the comparator against it, and assert it reports that exact
#   extension as missing. That synthetic-miss assertion is what
#   demonstrates the guard is live, not vacuous.
#
# Run:  bash lib/tests/mkdocs-template-extensions-drift.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$LOOM_ROOT/templates/diataxis/mkdocs.yml.template"
INSTANCE="$LOOM_ROOT/mkdocs.yml"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# extract_ext_names <mkdocs-yaml-file>
#
# Prints, one per line, the SET of extension NAMES declared under the
# `markdown_extensions:` block of the given mkdocs YAML file.
#
# Parsing rules (name-altitude):
#   - The block starts at a top-level `markdown_extensions:` line and
#     ends at the next top-level key (e.g. `nav:`, `plugins:`) — i.e.
#     the next line that begins in column 0 with a non-space, non-`-`
#     character — or EOF.
#   - A list ITEM begins with `-` at the block's item indentation:
#       `  - admonition`        (bare)
#       `  - toc:`              (name, with deeper-indented sub-config)
#       `  - pymdownx.emoji:`   (name, with deeper-indented sub-config)
#     The NAME is the token after `- `, up to a trailing `:` or EOL,
#     trimmed of whitespace.
#   - Deeper-indented sub-config lines (e.g. `      permalink: true`)
#     do NOT begin with `-` at the item indent, so they are ignored.
extract_ext_names() {
  local file="$1"
  awk '
    # Enter the block on a column-0 `markdown_extensions:` key.
    /^markdown_extensions:[[:space:]]*$/ { inblock = 1; next }
    inblock {
      # A new top-level key (non-space, non-dash in column 0) ends the
      # block. Whitespace-only lines stay inside the block.
      if ($0 ~ /^[^[:space:][:cntrl:]-]/) { inblock = 0; next }
      # A list item: optional leading spaces, then `- `, then a name.
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)   # strip "  - "
        sub(/:.*$/, "", line)                          # strip ":" + sub-config marker
        gsub(/[[:space:]]+$/, "", line)                # rstrip
        gsub(/^[[:space:]]+/, "", line)                # lstrip (defensive)
        if (line != "") print line
      }
      # else: deeper-indented sub-config — ignored.
    }
  ' "$file"
}

# --- Fixtures present ---------------------------------------------------

if [ ! -f "$TEMPLATE" ]; then
  fail "templates/diataxis/mkdocs.yml.template exists"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "template file present"

if [ ! -f "$INSTANCE" ]; then
  fail "loom mkdocs.yml exists"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "loom mkdocs.yml present"

# --- Comparator sanity: the extractor found a non-empty set -------------

template_names="$(extract_ext_names "$TEMPLATE")"
instance_names="$(extract_ext_names "$INSTANCE")"

if [ -n "$template_names" ]; then
  pass "extractor found template markdown_extensions ($(printf '%s\n' "$template_names" | grep -c .) names)"
else
  fail "extractor found template markdown_extensions" \
    "(extract_ext_names returned empty for $TEMPLATE — parser bug?)"
fi

if [ -n "$instance_names" ]; then
  pass "extractor found instance markdown_extensions ($(printf '%s\n' "$instance_names" | grep -c .) names)"
else
  fail "extractor found instance markdown_extensions" \
    "(extract_ext_names returned empty for $INSTANCE — parser bug?)"
fi

# --- Positive assertion: template name-set ⊆ instance name-set ----------
# For EACH template extension missing from the instance, FAIL with a
# line naming the missing extension explicitly. Currently GREEN.

missing_prod=""
while IFS= read -r ext; do
  [ -n "$ext" ] || continue
  if ! printf '%s\n' "$instance_names" | grep -qxF "$ext"; then
    missing_prod="$missing_prod $ext"
    fail "template extension '$ext' present in loom mkdocs.yml" \
      "(diataxis template declares '$ext' but the instance does not — sync mkdocs.yml from templates/diataxis/mkdocs.yml.template)"
  fi
done <<<"$template_names"

if [ -z "$missing_prod" ]; then
  pass "loom mkdocs.yml ⊇ diataxis template markdown_extensions (no drift)"
fi

# --- Negative self-check (CATCH-PROOF) ----------------------------------
# Synthesize an "instance" = loom's mkdocs.yml with ONE template
# extension removed; assert the comparator reports that exact extension
# as missing. This proves the guard is live, not vacuously green.

TMPDIR_NEG="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_NEG"' EXIT

VICTIM="pymdownx.emoji"   # the exact extension the be3t bug dropped
SYNTH="$TMPDIR_NEG/mkdocs-missing-emoji.yml"

# Drop the `- pymdownx.emoji:` item AND its deeper-indented sub-config
# (emoji_index / emoji_generator), reproducing the be3t drift exactly.
awk '
  # Match the victim list item (bare or with trailing colon).
  $0 ~ /^[[:space:]]*-[[:space:]]+pymdownx\.emoji:?[[:space:]]*$/ {
    skipping = 1
    # capture the item indentation depth to know where sub-config ends
    match($0, /^[[:space:]]*/); item_indent = RLENGTH
    next
  }
  skipping {
    # sub-config lines are indented DEEPER than the item dash; a line
    # indented at-or-shallower than the item indent ends the skip.
    match($0, /^[[:space:]]*/); ind = RLENGTH
    if (ind > item_indent && $0 ~ /[^[:space:]]/) { next }   # sub-config — drop
    skipping = 0
    # fall through to print this (non-sub-config) line
  }
  { print }
' "$INSTANCE" >"$SYNTH"

synth_names="$(extract_ext_names "$SYNTH")"

# 1. The synthetic instance must actually be missing the victim.
if printf '%s\n' "$synth_names" | grep -qxF "$VICTIM"; then
  fail "negative self-check: synthetic instance dropped '$VICTIM'" \
    "(awk failed to strip the victim extension — the synthetic miss was not constructed)"
else
  pass "negative self-check: synthetic instance is missing '$VICTIM'"
fi

# 2. The comparator must REPORT the victim as missing when run against
#    the synthetic instance.
synth_missing=""
while IFS= read -r ext; do
  [ -n "$ext" ] || continue
  if ! printf '%s\n' "$synth_names" | grep -qxF "$ext"; then
    synth_missing="$synth_missing $ext"
  fi
done <<<"$template_names"

if printf '%s' "$synth_missing" | grep -qw "$VICTIM"; then
  pass "negative self-check: comparator flags '$VICTIM' as drifted (guard is live, not vacuous)"
else
  fail "negative self-check: comparator flags '$VICTIM' as drifted" \
    "(comparator did NOT report '$VICTIM' missing from the synthetic instance — the guard is vacuous; reported missing set: '${synth_missing:-<none>}')"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
