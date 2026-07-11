#!/usr/bin/env bash
# Locking-spec contract test for exploration-drawer discovery via REAL
# MemPalace tagging (loom-40ec.4.5.6). Supersedes and replaces
# loom-jk17-exploration-fallback.test.sh, which locked the INTERIM
# title+marker text-fallback loom-jk17 (2026-07-10) introduced because
# mempalace_tag_drawer/tag_filter were not yet available on the
# post-cutover Dolt-backed MCP surface. loom-40ec.4.5.2 shipped the
# real tag_drawer/untag_drawer/list_tags tools plus a tag_filter param
# on mempalace_search; this bead retires the interim fallback and
# backfills the 3 pre-existing exploration drawers with the real tag.
#
# CONTRACT:
#   Both skill files MUST:
#     1. NOT describe discovery/filing as an "INTERIM FALLBACK" (the
#        literal phrase must not appear) -- the capability is no
#        longer missing.
#     2. Reference `mempalace_tag_drawer` as the filing-time tag call.
#   session-startup/SKILL.md (owns discovery) MUST additionally:
#     3. Reference `tag_filter` as the real search-time discovery
#        mechanism.
#
# Interface under test is prose, not code: the literal text content of
#   - skills/session-startup/SKILL.md
#   - skills/explore/SKILL.md
#
# Run:  bash lib/tests/loom-exploration-tag-discovery.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_STARTUP_FILE="$LOOM_ROOT/skills/session-startup/SKILL.md"
EXPLORE_FILE="$LOOM_ROOT/skills/explore/SKILL.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

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

assert_not_contains_fixed() {
  local name="$1" file="$2" needle="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qiF "$needle" "$file"; then
    fail "$name" "(retired string still present in $file: $needle)"
  else
    pass "$name"
  fi
}

# ---------------------------------------------------------------------------
echo "==> Marker 1: INTERIM FALLBACK framing retired"
assert_not_contains_fixed \
  "session-startup no longer describes an INTERIM FALLBACK" \
  "$SESSION_STARTUP_FILE" \
  "INTERIM FALLBACK"
assert_not_contains_fixed \
  "explore no longer describes an INTERIM FALLBACK" \
  "$EXPLORE_FILE" \
  "INTERIM FALLBACK"

# ---------------------------------------------------------------------------
echo "==> Marker 2: mempalace_tag_drawer named as the filing-time tag call"
assert_contains_fixed \
  "session-startup references mempalace_tag_drawer" \
  "$SESSION_STARTUP_FILE" \
  "mempalace_tag_drawer"
assert_contains_fixed \
  "explore references mempalace_tag_drawer" \
  "$EXPLORE_FILE" \
  "mempalace_tag_drawer"

# ---------------------------------------------------------------------------
echo "==> Marker 3: session-startup documents tag_filter-based discovery"
assert_contains_fixed \
  "session-startup documents tag_filter-based discovery" \
  "$SESSION_STARTUP_FILE" \
  "tag_filter"

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
