#!/usr/bin/env bash
# Fixture tests for scripts/loom-sync-stamp — the "stamp" half of the
# D1 downstream convention-drift detector (loom-ig3p.2; design drawer
# drawer_loom_decisions_4d3918198c51bb65ceaebf90).
#
# INVARIANT under test: after a stamp, <target>/.claude/.loom-sync
# records loom's current convention-manifest hash (+ a date field).
#
# CRITICAL meta-recursion note: this test NEVER invokes install.sh
# end-to-end (that would mutate this checkout's real ~/.claude/ +
# .git/config state). Instead it exercises the stamp UNIT directly —
# `loom_write_sync_stamp`, defined in scripts/loom-sync-stamp and
# reachable either by sourcing the script (function form) or by
# invoking the script as a standalone CLI (subprocess form, the shape
# install.sh and the audit-project skill use). Both forms are tested
# below.
#
# Run:  bash lib/tests/loom-sync-stamp.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAMP_BIN="$LOOM_ROOT/scripts/loom-sync-stamp"
MANIFEST_BIN="$LOOM_ROOT/scripts/loom-convention-manifest"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -e "$STAMP_BIN" ]; then
  fail "scripts/loom-sync-stamp exists" "not found at $STAMP_BIN"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
if [ ! -x "$STAMP_BIN" ]; then
  fail "scripts/loom-sync-stamp is executable" "missing +x bit at $STAMP_BIN"
fi
if [ ! -e "$MANIFEST_BIN" ]; then
  fail "dependency scripts/loom-convention-manifest exists" "not found at $MANIFEST_BIN (loom-ig3p.1 not merged?)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi

# --- sourcing the script must NOT execute anything (function-only) ----
# Sourcing must define loom_write_sync_stamp without side effects (no
# stamp written anywhere, no output). This is what lets install.sh (or
# any caller) `source` the helper safely. Capture stdout/stderr via a
# temp file rather than `$(source ...)` — command substitution runs
# the source in a SUBSHELL, which would define the function there and
# lose it for the rest of this (parent) script.
unset -f loom_write_sync_stamp 2>/dev/null || true
source_log="$(mktemp)"
# shellcheck source=/dev/null
source "$STAMP_BIN" >"$source_log" 2>&1
source_output="$(cat "$source_log")"
rm -f "$source_log"
if [ -n "$source_output" ]; then
  fail "sourcing scripts/loom-sync-stamp produces no output (no side effects)" "got: $source_output"
else
  pass "sourcing scripts/loom-sync-stamp produces no output (no side effects)"
fi
if declare -f loom_write_sync_stamp >/dev/null 2>&1; then
  pass "sourcing scripts/loom-sync-stamp defines loom_write_sync_stamp"
else
  fail "sourcing scripts/loom-sync-stamp defines loom_write_sync_stamp" "function not found after source"
fi

# --- current manifest hash, computed once, reused as the expected value
current_hash="$("$MANIFEST_BIN" 2>&1)"
if [ -z "$current_hash" ]; then
  fail "loom-convention-manifest produced a hash to stamp with" "got empty output"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi

# --- A. function form: loom_write_sync_stamp <target> <hash> [date] ---
FIXTURE_A="$(mktemp -d)"
loom_write_sync_stamp "$FIXTURE_A" "$current_hash" "2026-07-17"
rc=$?

if [ "$rc" -ne 0 ]; then
  fail "loom_write_sync_stamp returns 0 on success" "rc=$rc"
elif [ ! -f "$FIXTURE_A/.claude/.loom-sync" ]; then
  fail "loom_write_sync_stamp writes <target>/.claude/.loom-sync" "not found at $FIXTURE_A/.claude/.loom-sync"
else
  pass "loom_write_sync_stamp writes <target>/.claude/.loom-sync"
fi

stamp_contents_a="$(cat "$FIXTURE_A/.claude/.loom-sync" 2>/dev/null)"
if printf '%s\n' "$stamp_contents_a" | grep -qxF "hash=$current_hash"; then
  pass "stamp records loom's current convention-manifest hash (matches scripts/loom-convention-manifest output)"
else
  fail "stamp records loom's current convention-manifest hash" \
    "expected hash=$current_hash in:
$stamp_contents_a"
fi

if printf '%s\n' "$stamp_contents_a" | grep -qxF "date=2026-07-17"; then
  pass "stamp records the passed-in date field"
else
  fail "stamp records the passed-in date field" \
    "expected date=2026-07-17 in:
$stamp_contents_a"
fi

rm -rf "$FIXTURE_A"

# --- B. date defaults to today (UTC) when omitted ----------------------
FIXTURE_B="$(mktemp -d)"
loom_write_sync_stamp "$FIXTURE_B" "$current_hash"
today="$(date -u +%Y-%m-%d)"
stamp_contents_b="$(cat "$FIXTURE_B/.claude/.loom-sync" 2>/dev/null)"
if printf '%s\n' "$stamp_contents_b" | grep -qxF "date=$today"; then
  pass "stamp date defaults to today (UTC) when omitted"
else
  fail "stamp date defaults to today (UTC) when omitted" \
    "expected date=$today in:
$stamp_contents_b"
fi
rm -rf "$FIXTURE_B"

# --- C. re-stamping overwrites (not appends) ----------------------------
FIXTURE_C="$(mktemp -d)"
loom_write_sync_stamp "$FIXTURE_C" "deadbeef" "2020-01-01"
loom_write_sync_stamp "$FIXTURE_C" "$current_hash" "2026-07-17"
line_count="$(wc -l < "$FIXTURE_C/.claude/.loom-sync" | tr -d ' ')"
stamp_contents_c="$(cat "$FIXTURE_C/.claude/.loom-sync" 2>/dev/null)"
if [ "$line_count" -eq 2 ] && printf '%s\n' "$stamp_contents_c" | grep -qxF "hash=$current_hash"; then
  pass "re-stamping overwrites the previous stamp (not append)"
else
  fail "re-stamping overwrites the previous stamp (not append)" \
    "line_count=$line_count contents:
$stamp_contents_c"
fi
rm -rf "$FIXTURE_C"

# --- D. creates .claude/ when missing ------------------------------------
FIXTURE_D="$(mktemp -d)"
if [ -d "$FIXTURE_D/.claude" ]; then
  fail "fixture D starts without .claude/" "pre-existing .claude/ in fresh mktemp -d"
fi
loom_write_sync_stamp "$FIXTURE_D" "$current_hash"
if [ -d "$FIXTURE_D/.claude" ] && [ -f "$FIXTURE_D/.claude/.loom-sync" ]; then
  pass "loom_write_sync_stamp creates .claude/ when missing"
else
  fail "loom_write_sync_stamp creates .claude/ when missing" "no .claude/.loom-sync after stamp"
fi
rm -rf "$FIXTURE_D"

# --- E. subprocess (CLI) form: scripts/loom-sync-stamp <target> <hash> [date]
FIXTURE_E="$(mktemp -d)"
"$STAMP_BIN" "$FIXTURE_E" "$current_hash" "2026-07-17" >/dev/null
stamp_contents_e="$(cat "$FIXTURE_E/.claude/.loom-sync" 2>/dev/null)"
if printf '%s\n' "$stamp_contents_e" | grep -qxF "hash=$current_hash" \
   && printf '%s\n' "$stamp_contents_e" | grep -qxF "date=2026-07-17"; then
  pass "CLI form (scripts/loom-sync-stamp <target> <hash> [date]) stamps identically"
else
  fail "CLI form (scripts/loom-sync-stamp <target> <hash> [date]) stamps identically" \
    "contents:
$stamp_contents_e"
fi
rm -rf "$FIXTURE_E"

# --- F. missing required args fail loudly (non-zero, no partial write) --
FIXTURE_F="$(mktemp -d)"
"$STAMP_BIN" "$FIXTURE_F" >/dev/null 2>&1
rc_f=$?
if [ "$rc_f" -ne 0 ] && [ ! -e "$FIXTURE_F/.claude/.loom-sync" ]; then
  pass "missing manifest_hash argument fails loudly (non-zero, no partial write)"
else
  fail "missing manifest_hash argument fails loudly (non-zero, no partial write)" \
    "rc=$rc_f stamp_exists=$([ -e "$FIXTURE_F/.claude/.loom-sync" ] && echo yes || echo no)"
fi
rm -rf "$FIXTURE_F"

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
