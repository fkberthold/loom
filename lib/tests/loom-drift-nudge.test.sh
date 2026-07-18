#!/usr/bin/env bash
# Fixture tests for hooks/loom-drift-nudge.sh — the D3/D4 detector half
# of the downstream convention-drift epic (loom-ig3p.3; design drawer
# drawer_loom_decisions_4d3918198c51bb65ceaebf90). Compares a managed
# project's STAMPED loom-convention-manifest hash
# (.claude/.loom-sync, written by scripts/loom-sync-stamp / loom-ig3p.2)
# against loom's CURRENT manifest hash (scripts/loom-convention-manifest
# / loom-ig3p.1); a mismatch emits ONE non-blocking, one-time-per-session
# stderr nudge pointing at `/audit-project --apply-drift`.
#
# CRITICAL meta-recursion note: this test NEVER points the hook at the
# real loom checkout's templates/ tree and NEVER triggers a live
# SessionStart. It exercises the compare+nudge LOGIC directly via
# `LOOM_TEST_ROOT` (an isolated fixture "loom repo" with its own
# scripts/loom-convention-manifest + templates/) and `LOOM_TEST_LIB_DIR`
# (this worktree's lib/, not the installed ~/.claude copy) — the same
# test-injection idiom lib/tests/constitution-enforce.test.sh and
# lib/tests/loom-convention-manifest.test.sh already use.
#
# Cases covered:
#   A. stale stamp (hash mismatch) → exactly ONE nudge, names the drift,
#      points at /audit-project --apply-drift, exit 0.
#   B. matching hash → NO nudge, exit 0.
#   C. no .claude/.loom-sync at all → SILENT no-op, exit 0.
#   D. second invocation, SAME session (same XDG_RUNTIME_DIR), same
#      stale project → does NOT repeat the nudge (one-shot sentinel).
#   E. second invocation, DIFFERENT session (fresh XDG_RUNTIME_DIR) →
#      DOES nudge again (sentinel is per-session, not permanent).
#   F. LOOM_DRIFT_NUDGE_SKIP=1 bypasses even a stale project.
#   G. non-literal-1 skip value does NOT bypass (loom-b1l convention).
#   H. subagent (isSidechain) payload → silent no-op even when stale.
#   I. malformed stamp (no hash= line) → fail-open silent.
#   J. settings.snippet.json registers the hook in the SessionStart
#      group (additive — siblings still present).
#
# Run:  bash lib/tests/loom-drift-nudge.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/loom-drift-nudge.sh"
LIB_DIR="$LOOM_ROOT/lib"
MANIFEST_BIN="$LOOM_ROOT/scripts/loom-convention-manifest"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -e "$HOOK" ]; then
  fail "hooks/loom-drift-nudge.sh exists" "not found at $HOOK"
  echo; echo "Tests: $passed passed, $failed failed"; exit 1
fi
if [ ! -x "$HOOK" ]; then
  fail "hooks/loom-drift-nudge.sh is executable" "missing +x bit at $HOOK"
fi
if [ ! -x "$MANIFEST_BIN" ]; then
  fail "dependency scripts/loom-convention-manifest exists+executable" "not found at $MANIFEST_BIN (loom-ig3p.1 not merged?)"
  echo; echo "Tests: $passed passed, $failed failed"; exit 1
fi

# --- Fixture "loom repo" — its OWN templates/ tree + a copy of the real
# manifest script, so the hash computation never touches the real repo.
mk_fixture_loom_root() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/scripts" "$d/templates"
  cp "$MANIFEST_BIN" "$d/scripts/loom-convention-manifest"
  chmod +x "$d/scripts/loom-convention-manifest"
  echo "convention v1" > "$d/templates/foo.md"
  echo "$d"
}

# --- Fixture managed project ---------------------------------------------
mk_fixture_project() {
  local d hash date; d=$(mktemp -d)
  hash="${1:-}"; date="${2:-2026-01-01}"
  mkdir -p "$d/.claude"
  if [ -n "$hash" ]; then
    printf 'hash=%s\ndate=%s\n' "$hash" "$date" > "$d/.claude/.loom-sync"
  fi
  echo "$d"
}

# run_hook <project-dir> <fixture-loom-root> <session-dir> <payload-json> [extra env KEY=VAL...]
# Returns exit code in $?; combined stdout+stderr echoed.
run_hook() {
  local proj="$1" froot="$2" sess="$3" payload="$4"
  shift 4
  ( cd "$proj" && env "$@" \
      LOOM_TEST_LIB_DIR="$LIB_DIR" LOOM_TEST_ROOT="$froot" XDG_RUNTIME_DIR="$sess" \
      bash "$HOOK" <<<"$payload" 2>&1 )
}

# =========================================================================
echo "==> A. stale stamp → exactly one nudge, names drift, points at fix"
FROOT=$(mk_fixture_loom_root)
CURRENT_HASH=$("$FROOT/scripts/loom-convention-manifest" --root "$FROOT")
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS=$(mktemp -d)

out=$(run_hook "$P" "$FROOT" "$SESS" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] \
   && echo "$out" | grep -q 'deadbeefdead' \
   && echo "$out" | grep -q '/audit-project --apply-drift'; then
  pass "stale stamp: exactly one nudge naming the drift + pointing at the fix, exit 0"
else
  fail "stale stamp nudge shape" "rc=$rc lines=$lines out=$out"
fi
rm -rf "$P"

# =========================================================================
echo "==> B. matching hash → no nudge"
P=$(mk_fixture_project "$CURRENT_HASH" "2026-07-17")
SESS_B=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_B" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "matching hash → silent, exit 0"
else
  fail "matching hash should be silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_B"

# =========================================================================
echo "==> C. no .claude/.loom-sync at all → silent no-op"
P=$(mk_fixture_project "")   # no hash → mk_fixture_project skips writing the file
SESS_C=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_C" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "no stamp file → silent no-op, exit 0"
else
  fail "no-stamp path should be silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_C"

# =========================================================================
echo "==> D. second call, SAME session → does not repeat"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_D=$(mktemp -d)
out1=$(run_hook "$P" "$FROOT" "$SESS_D" '{}')
out2=$(run_hook "$P" "$FROOT" "$SESS_D" '{}')
if echo "$out1" | grep -q 'loom-drift-nudge' && [ -z "$out2" ]; then
  pass "same-session repeat call: first nudges, second is silent (one-shot sentinel)"
else
  fail "one-shot-per-session sentinel" "out1=$out1 out2=$out2"
fi
rm -rf "$P" "$SESS_D"

# =========================================================================
echo "==> E. second call, DIFFERENT session → nudges again"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_E1=$(mktemp -d)
SESS_E2=$(mktemp -d)
out1=$(run_hook "$P" "$FROOT" "$SESS_E1" '{}')
out2=$(run_hook "$P" "$FROOT" "$SESS_E2" '{}')
if echo "$out1" | grep -q 'loom-drift-nudge' && echo "$out2" | grep -q 'loom-drift-nudge'; then
  pass "different session (fresh XDG_RUNTIME_DIR) → nudges again (sentinel is per-session)"
else
  fail "cross-session nudge should re-fire" "out1=$out1 out2=$out2"
fi
rm -rf "$P" "$SESS_E1" "$SESS_E2"

# =========================================================================
echo "==> F. LOOM_DRIFT_NUDGE_SKIP=1 bypasses even a stale project"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_F=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_F" '{}' LOOM_DRIFT_NUDGE_SKIP=1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "LOOM_DRIFT_NUDGE_SKIP=1 bypasses an otherwise-nudged stale project"
else
  fail "SKIP=1 did not bypass" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_F"

# =========================================================================
echo "==> G. non-literal-1 skip value does NOT bypass (loom-b1l convention)"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_G=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_G" '{}' LOOM_DRIFT_NUDGE_SKIP=yes); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'loom-drift-nudge'; then
  pass "LOOM_DRIFT_NUDGE_SKIP=yes does NOT bypass (literal-1 only)"
else
  fail "SKIP=yes wrongly bypassed" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_G"

# =========================================================================
echo "==> H. subagent payload (isSidechain) → silent no-op even when stale"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_H=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_H" '{"isSidechain": true}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "subagent (isSidechain=true) payload → silent no-op"
else
  fail "subagent payload should be silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_H"

# =========================================================================
echo "==> I. malformed stamp (no hash= line) → fail-open silent"
P=$(mk_fixture_project "")
mkdir -p "$P/.claude"
printf 'date=2026-01-01\n' > "$P/.claude/.loom-sync"   # no hash= line
SESS_I=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_I" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "malformed stamp (no hash=) → fail-open silent"
else
  fail "malformed stamp should fail open silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_I"

rm -rf "$FROOT"

# =========================================================================
echo "==> J. settings.snippet.json registers the hook in SessionStart (additive)"
SNIP="$LOOM_ROOT/settings.snippet.json"
chain_has() {
  local needle="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$needle" '.hooks.SessionStart[].hooks[] | select(.command | test($n))' "$SNIP" >/dev/null 2>&1
  else
    SNIP="$SNIP" N="$needle" python3 -c '
import json, os, sys, re
s = json.load(open(os.environ["SNIP"]))
needle = os.environ["N"]
for grp in s["hooks"]["SessionStart"]:
    for h in grp["hooks"]:
        if re.search(needle, h.get("command", "")):
            sys.exit(0)
sys.exit(1)'
  fi
}
if chain_has "loom-drift-nudge.sh" && chain_has "bd-prime-wrapper.sh"; then
  pass "snippet registers loom-drift-nudge.sh AND keeps bd-prime-wrapper.sh (additive)"
else
  fail "settings.snippet.json missing loom-drift-nudge.sh in SessionStart (or dropped a sibling)"
fi

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
