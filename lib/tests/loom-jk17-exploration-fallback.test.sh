#!/usr/bin/env bash
# Locking-spec (RED) contract test for the exploration-discovery
# FALLBACK documentation requirement (loom-jk17).
#
# Context: loom's session-startup skill (step 1e "Surface active
# explorations") and loom's explore skill both need to locate
# exploration drawers in MemPalace. The natural mechanism —
# `mempalace_tag_drawer` / a `tag_filter` search param — is NOT present
# on the currently-loaded MemPalace MCP tool surface (true as of the
# loom-40ec Dolt-backed memory-server cutover; the tool is deferred to
# tracking bead loom-40ec.4.5).
#
# CONTRACT (verbatim from the bead's locked acceptance criterion):
#   Given the absence of mempalace_tag_drawer / a tag_filter search
#   param on the current MCP surface, BOTH skill files MUST explicitly
#   document this as a known, INTERIM limitation (not silently
#   degrade) by each containing ALL of:
#     1. An acknowledgment that `mempalace_tag_drawer` is unavailable,
#        referencing tracking bead `loom-40ec.4.5` (the literal string
#        "loom-40ec.4.5" must appear).
#     2. The literal word "FALLBACK" (case-insensitive) — making the
#        interim nature greppable rather than silent.
#     3. A named fallback discovery mechanism: locate exploration
#        drawers via mempalace_search / mempalace_list_drawers (scoped
#        to the project's `<wing>/decisions` room) by matching BOTH
#        (a) a required drawer title prefix of `# EXPLORATION` and
#        (b) a machine-parseable status marker of the exact
#        standardized form `<!-- tag: exploration status: ` — the
#        literal substring `<!-- tag: exploration status:` must
#        appear in both files.
#
# Interface under test is prose, not code: the literal text content of
#   - skills/session-startup/SKILL.md
#   - skills/explore/SKILL.md
#
# This is a grep-contract test: 3 markers x 2 files = 6 checks, ALL
# must pass. As of this writing (pre-implementation) none of the three
# markers exist in either file — this test is expected to FAIL (RED).
#
# Run:  bash lib/tests/loom-jk17-exploration-fallback.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_STARTUP_FILE="$LOOM_ROOT/skills/session-startup/SKILL.md"
EXPLORE_FILE="$LOOM_ROOT/skills/explore/SKILL.md"
EXPLORATION_TEMPLATE="$LOOM_ROOT/templates/exploration/EXPLORATION.md.template"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert a fixed-string pattern is present in a file (case-insensitive).
# $1 = human-readable check name
# $2 = file path
# $3 = fixed string to search for (grep -F)
assert_contains_fixed() {
  local name="$1" file="$2" needle="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qiF "$needle" "$file"; then
    pass "$name"
  else
    fail "$name" "(string not found in $file: $needle)"
  fi
}

# ---------------------------------------------------------------------------
echo "==> Marker 1: loom-40ec.4.5 tracking-bead reference"
assert_contains_fixed \
  "session-startup references loom-40ec.4.5" \
  "$SESSION_STARTUP_FILE" \
  "loom-40ec.4.5"
assert_contains_fixed \
  "explore references loom-40ec.4.5" \
  "$EXPLORE_FILE" \
  "loom-40ec.4.5"

# ---------------------------------------------------------------------------
echo "==> Marker 2: literal word FALLBACK (case-insensitive)"
assert_contains_fixed \
  "session-startup contains the word FALLBACK" \
  "$SESSION_STARTUP_FILE" \
  "fallback"
assert_contains_fixed \
  "explore contains the word FALLBACK" \
  "$EXPLORE_FILE" \
  "fallback"

# ---------------------------------------------------------------------------
echo "==> Marker 3: standardized status-marker convention"
assert_contains_fixed \
  "session-startup documents '<!-- tag: exploration status:' convention" \
  "$SESSION_STARTUP_FILE" \
  "<!-- tag: exploration status:"
assert_contains_fixed \
  "explore documents '<!-- tag: exploration status:' convention" \
  "$EXPLORE_FILE" \
  "<!-- tag: exploration status:"

# ---------------------------------------------------------------------------
# Marker 4: the documented convention must be BACKED by the actual template
# an opened exploration is seeded from — otherwise the fallback describes a
# marker that no real drawer ever contains, silently degrading again.
echo "==> Marker 4: exploration template actually emits the status marker"
assert_contains_fixed \
  "exploration template contains '<!-- tag: exploration status:' marker" \
  "$EXPLORATION_TEMPLATE" \
  "<!-- tag: exploration status:"

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
