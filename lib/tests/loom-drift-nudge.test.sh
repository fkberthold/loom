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
#   C. no .claude/.loom-sync at all in a NON-loom-managed project (no
#      .claude/workflow.json) → SILENT no-op, exit 0.
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
#   K. loom-managed (.claude/workflow.json) + NO stamp → exactly ONE
#      never-synced nudge, exit 0 (loom-oktm).
#   L. the never-synced nudge is DISTINGUISHABLE from the stale-stamp
#      nudge (different states, different remediation emphasis).
#   M. loom-managed + no stamp: one-time-per-session sentinel applies
#      (second same-session call silent; fresh session nudges again).
#   N. loom-managed + no stamp: SKIP=1 and subagent payload still bypass.
#   O. loom-managed + MATCHING stamp → still silent (managed-ness alone
#      never nudges a current project).
#   P. unwritable sentinel path (nonexistent $XDG_RUNTIME_DIR) → the
#      nudge is still EXACTLY one clean line, no shell redirection
#      complaint leaking to stderr.
#   Q. v2 split stamp, matching last_synced + stale last_checked →
#      silent (the nudge keys on last_synced) (loom-uh4i).
#   R. v2 split stamp, stale last_synced + MATCHING last_checked →
#      NUDGES. A read-only check must never silence the detector.
#   S. v2 split stamp, last_checked only (no last_synced) →
#      never-synced nudge; absence of last_synced is the key.
#   T. legacy `hash=` stamp is grandfathered as last_synced (keeps
#      loom-oktm's fixtures A/D/E/F/G green).
#   U. end-to-end through the REAL scripts/loom-sync-stamp: stale →
#      nudge; read-only check (== all-[SKIP] apply) → still nudge;
#      real apply (--synced) → silent.
#   V-AC. loom-5od2 — the STAMP-INDEPENDENT owned-file signal. A
#      matching last_synced is a claim about the PAST; the owned
#      template's bytes on disk are a fact about the PRESENT, and the
#      fact wins. See the block header above case V.
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
echo "==> C. no stamp AND not loom-managed (no workflow.json) → silent no-op"
P=$(mk_fixture_project "")   # no hash → mk_fixture_project skips writing the file
SESS_C=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_C" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "no stamp + not loom-managed → silent no-op, exit 0"
else
  fail "unmanaged no-stamp path should be silent" "rc=$rc out=$out"
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

# =========================================================================
# loom-oktm — the NEVER-SYNCED case. Before this, "no stamp" collapsed two
# very different states into one silence: a project that is CURRENT and a
# project that has NEVER received loom's conventions at all. The
# never-synced case is the one that most needs the nudge. The loom-managed
# test is `.claude/workflow.json` — the same signal session-startup step 1f
# uses for its constitution nudge — so unmanaged projects stay silent.
mk_managed_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  printf '{"mode": "standard"}\n' > "$d/.claude/workflow.json"
  echo "$d"
}

echo "==> K. loom-managed + NO stamp → exactly one never-synced nudge"
P=$(mk_managed_project)
SESS_K=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_K" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] \
   && echo "$out" | grep -q 'never been synced' \
   && echo "$out" | grep -q '\.claude/\.loom-sync' \
   && echo "$out" | grep -q '/audit-project --apply-drift'; then
  pass "loom-managed + no stamp: exactly one never-synced nudge pointing at the fix, exit 0"
else
  fail "never-synced nudge shape" "rc=$rc lines=$lines out=$out"
fi
MISSING_OUT="$out"
rm -rf "$P" "$SESS_K"

# =========================================================================
echo "==> L. never-synced nudge is distinguishable from the stale-stamp nudge"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_L=$(mktemp -d)
STALE_OUT=$(run_hook "$P" "$FROOT" "$SESS_L" '{}')
if [ -n "$MISSING_OUT" ] && [ "$MISSING_OUT" != "$STALE_OUT" ] \
   && echo "$MISSING_OUT" | grep -q 'loom-drift-nudge' \
   && echo "$STALE_OUT" | grep -q 'hash=' \
   && ! echo "$STALE_OUT" | grep -q 'never been synced' \
   && ! echo "$MISSING_OUT" | grep -q 'hash='; then
  pass "never-synced and stale-stamp messages are distinct (stale names hashes; never-synced names the absent stamp)"
else
  fail "missing- vs stale-stamp messages not distinguishable" "missing=$MISSING_OUT stale=$STALE_OUT"
fi
rm -rf "$P" "$SESS_L"

# =========================================================================
echo "==> M. loom-managed + no stamp: one-shot per session, re-fires next session"
P=$(mk_managed_project)
SESS_M1=$(mktemp -d)
SESS_M2=$(mktemp -d)
out1=$(run_hook "$P" "$FROOT" "$SESS_M1" '{}')
out2=$(run_hook "$P" "$FROOT" "$SESS_M1" '{}')
out3=$(run_hook "$P" "$FROOT" "$SESS_M2" '{}')
if echo "$out1" | grep -q 'loom-drift-nudge' && [ -z "$out2" ] \
   && echo "$out3" | grep -q 'loom-drift-nudge'; then
  pass "never-synced nudge honors the one-time-per-session sentinel (and re-fires in a fresh session)"
else
  fail "never-synced sentinel" "out1=$out1 out2=$out2 out3=$out3"
fi
rm -rf "$P" "$SESS_M1" "$SESS_M2"

# =========================================================================
echo "==> N. loom-managed + no stamp: SKIP=1 and subagent payload still bypass"
P=$(mk_managed_project)
SESS_N1=$(mktemp -d)
SESS_N2=$(mktemp -d)
SESS_N3=$(mktemp -d)
out_skip=$(run_hook "$P" "$FROOT" "$SESS_N1" '{}' LOOM_DRIFT_NUDGE_SKIP=1); rc_skip=$?
out_sub=$(run_hook "$P" "$FROOT" "$SESS_N2" '{"isSidechain": true}'); rc_sub=$?
# Control: the SAME fixture with no bypass DOES nudge — so the two
# silences above are the bypasses working, not a vacuous pass.
out_ctl=$(run_hook "$P" "$FROOT" "$SESS_N3" '{}')
if [ "$rc_skip" -eq 0 ] && [ -z "$out_skip" ] \
   && [ "$rc_sub" -eq 0 ] && [ -z "$out_sub" ] \
   && echo "$out_ctl" | grep -q 'loom-drift-nudge'; then
  pass "never-synced path respects LOOM_DRIFT_NUDGE_SKIP=1 and the subagent silent no-op (control fixture nudges)"
else
  fail "never-synced bypass posture" "skip: rc=$rc_skip out=$out_skip | sub: rc=$rc_sub out=$out_sub | ctl=$out_ctl"
fi
rm -rf "$P" "$SESS_N1" "$SESS_N2" "$SESS_N3"

# =========================================================================
echo "==> O. loom-managed + MATCHING stamp → still silent"
P=$(mk_managed_project)
printf 'hash=%s\ndate=%s\n' "$CURRENT_HASH" "2026-07-17" > "$P/.claude/.loom-sync"
SESS_O=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_O" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "loom-managed + matching hash → silent (managed-ness alone never nudges a current project)"
else
  fail "managed + matching hash should be silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_O"

# =========================================================================
echo "==> P. unwritable sentinel path → still exactly one clean line"
P=$(mk_managed_project)
SESS_P=$(mktemp -d)
rmdir "$SESS_P"          # XDG_RUNTIME_DIR now points at a nonexistent dir
out=$(run_hook "$P" "$FROOT" "$SESS_P" '{}'); rc=$?
n=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$n" -eq 1 ] && echo "$out" | grep -q 'loom-drift-nudge'; then
  pass "unwritable sentinel: exactly one clean nudge line, no redirection complaint"
else
  fail "unwritable sentinel leaked shell noise" "rc=$rc lines=$n out=$out"
fi
rm -rf "$P"

# =========================================================================
# loom-uh4i — the CHECKED/SYNCED SPLIT.
#
# THE BUG: `/audit-project` re-stamped `.claude/.loom-sync`
# unconditionally on every invocation, so a read-only `--check=...` run
# that applied NOTHING still wrote loom's current hash — and this hook,
# comparing that hash against loom's current one, went silent. The
# detector could be quieted by LOOKING at it. Measured 2026-07-25:
# ~/repos/liza_base stamped 14:23:51 with a hash matching loom exactly,
# nudge silent, zero remediation applied, its CLAUDE.md (mtime 07-15) and
# .claude/rules/dispatched-agents.md (mtime 07-10) byte-unchanged and
# still missing every current convention.
#
# THE FIX: the stamp carries two facts. `last_checked` is written by any
# invocation (informational); `last_synced` only by one that actually
# applied remediation. THIS HOOK COMPARES AGAINST `last_synced` — and its
# loom-oktm never-synced branch keys on the ABSENCE of `last_synced`.
# A legacy stamp carrying only `hash=` is grandfathered as `last_synced`.
#
# v2 fixture: writes the split-field stamp directly (the hook is a pure
# reader — the writer is exercised by lib/tests/loom-sync-stamp.test.sh).
# mk_v2_project <synced-hash> <synced-date> <checked-hash> <checked-date>
# Any argument may be "" to omit that key.
mk_v2_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  : > "$d/.claude/.loom-sync"
  [ -n "${1:-}" ] && printf 'last_synced=%s\n' "$1" >> "$d/.claude/.loom-sync"
  [ -n "${2:-}" ] && printf 'last_synced_date=%s\n' "$2" >> "$d/.claude/.loom-sync"
  [ -n "${3:-}" ] && printf 'last_checked=%s\n' "$3" >> "$d/.claude/.loom-sync"
  [ -n "${4:-}" ] && printf 'last_checked_date=%s\n' "$4" >> "$d/.claude/.loom-sync"
  echo "$d"
}

echo "==> Q. v2 stamp: matching last_synced + STALE last_checked → silent"
P=$(mk_v2_project "$CURRENT_HASH" "2026-07-17" "deadbeefdeadbeef00000000" "2026-07-25")
SESS_Q=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_Q" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "v2: nudge keys on last_synced — a stale last_checked alone never nudges"
else
  fail "v2 matching last_synced should be silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_Q"

echo "==> R. v2 stamp: STALE last_synced + MATCHING last_checked → NUDGES"
# The exact bug shape: a read-only check recorded loom's current hash,
# but no remediation ever landed. The nudge must survive that.
P=$(mk_v2_project "deadbeefdeadbeef00000000" "2026-01-01" "$CURRENT_HASH" "2026-07-25")
SESS_R=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_R" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] \
   && echo "$out" | grep -q 'deadbeefdead' \
   && echo "$out" | grep -q '/audit-project --apply-drift'; then
  pass "v2: a current last_checked does NOT silence a stale last_synced (the loom-uh4i bug)"
else
  fail "current last_checked wrongly silenced a stale last_synced" "rc=$rc lines=$lines out=$out"
fi
rm -rf "$P" "$SESS_R"

echo "==> S. v2 stamp: last_checked ONLY (never synced) → never-synced nudge"
P=$(mk_v2_project "" "" "$CURRENT_HASH" "2026-07-25")
SESS_S=$(mktemp -d)
out=$(run_hook "$P" "$FROOT" "$SESS_S" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] \
   && echo "$out" | grep -q 'never been synced' \
   && echo "$out" | grep -q '/audit-project --apply-drift'; then
  pass "v2: checked-but-never-synced → never-synced nudge (absence of last_synced is the key)"
else
  fail "checked-but-never-synced should nudge" "rc=$rc lines=$lines out=$out"
fi
rm -rf "$P" "$SESS_S"

echo "==> T. legacy hash= stamp is grandfathered as last_synced"
# loom-oktm's stamped-but-no-workflow.json shape (its fixtures A/D/E/F/G)
# must keep working byte-for-byte: matching → silent, stale → nudge.
P=$(mk_fixture_project "$CURRENT_HASH" "2026-07-17")
SESS_T1=$(mktemp -d)
out_ok=$(run_hook "$P" "$FROOT" "$SESS_T1" '{}')
rm -rf "$P"
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_T2=$(mktemp -d)
out_stale=$(run_hook "$P" "$FROOT" "$SESS_T2" '{}')
if [ -z "$out_ok" ] && echo "$out_stale" | grep -q 'loom-drift-nudge' \
   && ! echo "$out_stale" | grep -q 'never been synced'; then
  pass "legacy hash= reads as last_synced (matching → silent; stale → STALE nudge, not never-synced)"
else
  fail "legacy hash= grandfathering" "ok=$out_ok stale=$out_stale"
fi
rm -rf "$P" "$SESS_T1" "$SESS_T2"

echo "==> U. END-TO-END: a read-only check does not silence; a real apply does"
# Drives the REAL writer (scripts/loom-sync-stamp) exactly as
# audit-project's Step 1c (check-only) and its post---apply-drift
# re-stamp (--synced) do, then re-runs the hook in a FRESH session.
STAMP_BIN="$LOOM_ROOT/scripts/loom-sync-stamp"
P=$(mk_managed_project)
# 1. Project synced at an old hash → stale → nudges.
"$STAMP_BIN" --synced "$P" "deadbeefdeadbeef00000000" "2026-01-01" >/dev/null 2>&1
SESS_U1=$(mktemp -d); out_u1=$(run_hook "$P" "$FROOT" "$SESS_U1" '{}')
# 2. A read-only `/audit-project --check=drift` runs: Step 1c records the
#    CHECK. This is ALSO the all-[SKIP] shape — `--apply-drift` where the
#    user skipped every item applies nothing, so it takes the same
#    check-only path. A run that leaves the project byte-identical must
#    leave the nudge state byte-identical.
"$STAMP_BIN" "$P" "$CURRENT_HASH" "2026-07-25" >/dev/null 2>&1
SESS_U2=$(mktemp -d); out_u2=$(run_hook "$P" "$FROOT" "$SESS_U2" '{}')
# 3. `--apply-drift` applies >= 1 item → Step 3.5 re-stamps --synced.
"$STAMP_BIN" --synced "$P" "$CURRENT_HASH" "2026-07-25" >/dev/null 2>&1
SESS_U3=$(mktemp -d); out_u3=$(run_hook "$P" "$FROOT" "$SESS_U3" '{}')
if echo "$out_u1" | grep -q 'loom-drift-nudge' \
   && echo "$out_u2" | grep -q 'loom-drift-nudge' \
   && [ -z "$out_u3" ]; then
  pass "end-to-end: read-only check (and an all-[SKIP] apply) leaves the nudge firing; a real apply silences it"
else
  fail "end-to-end checked-vs-synced round trip" \
    "stale=$out_u1
after-check=$out_u2
after-sync=$out_u3"
fi
rm -rf "$P" "$SESS_U1" "$SESS_U2" "$SESS_U3"

rm -rf "$FROOT"

# =========================================================================
# loom-5od2 — the STAMP-INDEPENDENT OWNED-FILE SIGNAL.
#
# THE GAP. Everything above compares ONE number: the project's stamped
# `last_synced` against loom's current manifest hash. loom-f59h added a
# second, structurally different signal — a BYTE comparison of loom's
# OWNED templates (`scripts/loom-owned-templates`) against the project's
# live copies — whose whole point is that it does not consult the stamp:
# *the stamp is a claim about the past; the bytes are a fact about the
# present, and the fact wins.* But that check ran only inside
# `/audit-project` step 3.3a, i.e. on manual invocation.
#
# The hole that leaves: per loom-uh4i, an `--apply-drift` run with N>=1
# items applied re-stamps `last_synced` at loom's FULL current hash. A
# user who applies some items and SKIPS the `loom-conventions.md` item
# therefore ends up stamped-CURRENT with the owned file still absent —
# and the SessionStart nudge stays silent until the next convention
# change happens to move the hash. That is a smaller version of exactly
# the false-green loom-uh4i fixed, one layer along.
#
# THE FIX: the hook nudges if EITHER signal fires — hash mismatch OR an
# owned file absent/stale — with distinguishable wording per condition.
#
# Fixture "loom repo" carrying BOTH scripts (manifest + owned-template
# registry) and a real owned template under templates/rules/.
OWNED_BIN="$LOOM_ROOT/scripts/loom-owned-templates"
if [ ! -x "$OWNED_BIN" ]; then
  fail "dependency scripts/loom-owned-templates exists+executable" "not found at $OWNED_BIN (loom-f59h not merged?)"
  echo; echo "Tests: $passed passed, $failed failed"; exit 1
fi

# mk_owned_loom_root [--no-registry] [--no-source]
#   --no-registry  omit scripts/loom-owned-templates entirely (the
#                  "registry unresolvable" degradation case)
#   --no-source    ship the registry but NOT templates/rules/loom-conventions.md
#                  (loom's OWN copy missing → --check reports [FAIL], not [DRIFT])
mk_owned_loom_root() {
  local d registry=1 source=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-registry) registry=0 ;;
      --no-source)   source=0 ;;
    esac
    shift
  done
  d=$(mktemp -d)
  mkdir -p "$d/scripts" "$d/templates/rules"
  cp "$MANIFEST_BIN" "$d/scripts/loom-convention-manifest"
  chmod +x "$d/scripts/loom-convention-manifest"
  if [ "$registry" -eq 1 ]; then
    cp "$OWNED_BIN" "$d/scripts/loom-owned-templates"
    chmod +x "$d/scripts/loom-owned-templates"
  fi
  echo "convention v1" > "$d/templates/foo.md"
  if [ "$source" -eq 1 ]; then
    printf 'loom-owned conventions, current revision\n' > "$d/templates/rules/loom-conventions.md"
  fi
  echo "$d"
}

# mk_owned_project <synced-hash> <live-owned-content|""|"@current"> [loom-root]
#   ""          → the owned file is ABSENT (never seeded)
#   "@current"  → a BYTE-IDENTICAL copy of [loom-root]'s owned template.
#                 Copied, never round-tripped through `$(cat)`, which
#                 would strip the trailing newline and make a "current"
#                 fixture spuriously differ by one byte.
#   otherwise   → written verbatim (a stale/divergent copy)
mk_owned_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  printf '{"mode": "standard"}\n' > "$d/.claude/workflow.json"
  printf 'last_synced=%s\nlast_synced_date=%s\n' "$1" "2026-07-25" > "$d/.claude/.loom-sync"
  if [ -n "${2:-}" ]; then
    mkdir -p "$d/.claude/rules"
    if [ "$2" = "@current" ]; then
      cp "${3:?@current needs a loom root}/templates/rules/loom-conventions.md" \
         "$d/.claude/rules/loom-conventions.md"
    else
      printf '%s' "$2" > "$d/.claude/rules/loom-conventions.md"
    fi
  fi
  echo "$d"
}

OFROOT=$(mk_owned_loom_root)
OHASH=$("$OFROOT/scripts/loom-convention-manifest" --root "$OFROOT")

echo "==> V. stamp MATCHES + owned file ABSENT → nudge anyway"
P=$(mk_owned_project "$OHASH" "")
SESS_V=$(mktemp -d)
out=$(run_hook "$P" "$OFROOT" "$SESS_V" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] \
   && echo "$out" | grep -q '\.claude/rules/loom-conventions\.md' \
   && echo "$out" | grep -q 'absent' \
   && echo "$out" | grep -q '/audit-project --apply-drift'; then
  pass "matching stamp + absent owned file → exactly one nudge naming the live path, exit 0"
else
  fail "owned-absent nudge shape" "rc=$rc lines=$lines out=$out"
fi
OWNED_OUT="$out"
rm -rf "$P" "$SESS_V"

echo "==> W. stamp MATCHES + owned file CONTENT DIFFERS → nudge anyway"
P=$(mk_owned_project "$OHASH" "an older revision of the conventions")
SESS_W=$(mktemp -d)
out=$(run_hook "$P" "$OFROOT" "$SESS_W" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] \
   && echo "$out" | grep -q '\.claude/rules/loom-conventions\.md' \
   && echo "$out" | grep -q 'differs' \
   && echo "$out" | grep -q '/audit-project --apply-drift'; then
  pass "matching stamp + stale owned file → exactly one nudge naming the content difference"
else
  fail "owned-stale nudge shape" "rc=$rc lines=$lines out=$out"
fi
rm -rf "$P" "$SESS_W"

echo "==> X. stamp MATCHES + owned file byte-identical → silent"
P=$(mk_owned_project "$OHASH" "@current" "$OFROOT")
SESS_X=$(mktemp -d)
out=$(run_hook "$P" "$OFROOT" "$SESS_X" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "matching stamp + byte-identical owned file → silent (no false positive)"
else
  fail "fully-current project should stay silent" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_X"

echo "==> Y. owned-drift nudge is distinguishable from BOTH other variants"
# A reader must be able to tell WHICH condition tripped: the stale-stamp
# nudge names hashes, the never-synced one names the absent stamp, and
# the owned-file one names the FILE — and says so in stamp-independent
# terms, because its whole point is that the stamp says "current".
P=$(mk_fixture_project "deadbeefdeadbeef00000000" "2026-01-01")
SESS_Y1=$(mktemp -d)
STALE_OUT=$(run_hook "$P" "$OFROOT" "$SESS_Y1" '{}')
rm -rf "$P"
P=$(mk_managed_project)
SESS_Y2=$(mktemp -d)
NEVER_OUT=$(run_hook "$P" "$OFROOT" "$SESS_Y2" '{}')
if [ -n "$OWNED_OUT" ] \
   && [ "$OWNED_OUT" != "$STALE_OUT" ] && [ "$OWNED_OUT" != "$NEVER_OUT" ] \
   && ! echo "$OWNED_OUT" | grep -q 'hash=' \
   && ! echo "$OWNED_OUT" | grep -q 'never been synced' \
   && echo "$OWNED_OUT" | grep -qi 'byte' \
   && ! echo "$STALE_OUT" | grep -q 'loom-conventions\.md' \
   && ! echo "$NEVER_OUT" | grep -q 'loom-conventions\.md'; then
  pass "owned-file nudge is distinct from stale-stamp and never-synced (names the file + the byte comparison, never a hash)"
else
  fail "nudge variants not distinguishable" "owned=$OWNED_OUT
stale=$STALE_OUT
never=$NEVER_OUT"
fi
rm -rf "$P" "$SESS_Y1" "$SESS_Y2"

echo "==> Z. registry script unresolvable → degrade to hash-only, silently"
# A loom checkout without scripts/loom-owned-templates (an older install,
# a partial checkout) must not error, must not nudge, and must not
# announce the degradation. It just falls back to the hash comparison.
NOREG=$(mk_owned_loom_root --no-registry)
NOREG_HASH=$("$NOREG/scripts/loom-convention-manifest" --root "$NOREG")
P=$(mk_owned_project "$NOREG_HASH" "")   # owned file absent — and unnoticeable
SESS_Z=$(mktemp -d)
out=$(run_hook "$P" "$NOREG" "$SESS_Z" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "missing scripts/loom-owned-templates → silent hash-only degradation, exit 0"
else
  fail "unresolvable registry should degrade silently" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_Z" "$NOREG"

echo "==> AA. loom's OWN owned-template source missing → silent (not the project's fault)"
NOSRC=$(mk_owned_loom_root --no-source)
NOSRC_HASH=$("$NOSRC/scripts/loom-convention-manifest" --root "$NOSRC")
P=$(mk_owned_project "$NOSRC_HASH" "")
SESS_AA=$(mktemp -d)
out=$(run_hook "$P" "$NOSRC" "$SESS_AA" '{}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "registry [FAIL] (loom source missing) is not project drift → silent, exit 0"
else
  fail "loom-side source gap wrongly nudged the project" "rc=$rc out=$out"
fi
rm -rf "$P" "$SESS_AA" "$NOSRC"

echo "==> AB. BOTH signals fire → exactly ONE nudge, and it is the stale-stamp one"
P=$(mk_owned_project "deadbeefdeadbeef00000000" "")
SESS_AB=$(mktemp -d)
out=$(run_hook "$P" "$OFROOT" "$SESS_AB" '{}'); rc=$?
lines=$(printf '%s\n' "$out" | grep -c 'loom-drift-nudge')
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && echo "$out" | grep -q 'deadbeefdead'; then
  pass "hash mismatch + owned drift → one nudge (the stale-stamp one; same fix command, no double-nudge)"
else
  fail "double-nudge when both signals fire" "rc=$rc lines=$lines out=$out"
fi
rm -rf "$P" "$SESS_AB"

echo "==> AC. owned-drift nudge honors the sentinel, SKIP=1, and the subagent no-op"
P=$(mk_owned_project "$OHASH" "")
SESS_AC1=$(mktemp -d); SESS_AC2=$(mktemp -d)
SESS_AC3=$(mktemp -d); SESS_AC4=$(mktemp -d)
out1=$(run_hook "$P" "$OFROOT" "$SESS_AC1" '{}')
out2=$(run_hook "$P" "$OFROOT" "$SESS_AC1" '{}')
out3=$(run_hook "$P" "$OFROOT" "$SESS_AC2" '{}')
out_skip=$(run_hook "$P" "$OFROOT" "$SESS_AC3" '{}' LOOM_DRIFT_NUDGE_SKIP=1)
out_sub=$(run_hook "$P" "$OFROOT" "$SESS_AC4" '{"isSidechain": true}')
if echo "$out1" | grep -q 'loom-drift-nudge' && [ -z "$out2" ] \
   && echo "$out3" | grep -q 'loom-drift-nudge' \
   && [ -z "$out_skip" ] && [ -z "$out_sub" ]; then
  pass "owned-drift nudge: one-shot per session, re-fires next session, bypassed by SKIP=1 and by a subagent payload"
else
  fail "owned-drift nudge bypass/sentinel posture" "out1=$out1 out2=$out2 out3=$out3 skip=$out_skip sub=$out_sub"
fi
rm -rf "$P" "$SESS_AC1" "$SESS_AC2" "$SESS_AC3" "$SESS_AC4"

rm -rf "$OFROOT"

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
