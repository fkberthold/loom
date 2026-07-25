#!/usr/bin/env bash
# Fixture tests for scripts/loom-sync-stamp — the "stamp" half of the
# D1 downstream convention-drift detector (loom-ig3p.2; design drawer
# drawer_loom_decisions_4d3918198c51bb65ceaebf90).
#
# INVARIANT under test: after a stamp, <target>/.claude/.loom-sync
# records loom's current convention-manifest hash (+ a date field).
#
# INVARIANT under test (loom-uh4i): a read-only `/audit-project`
# invocation — a `--check=...` mode with no apply — does NOT cause the
# drift nudge to go silent; only an invocation that actually applied
# remediation updates the synced-hash the nudge compares against. The
# stamp therefore carries TWO facts, not one:
#   last_checked / last_checked_date  — any invocation. Informational.
#   last_synced  / last_synced_date   — only a real apply (--synced).
# Cases G-N below pin the split, the check-preserves-sync
# read-modify-write, the legacy hash=/date= migration rule, and the
# audit-project + install.sh call sites. The end-to-end
# "a check does not silence the nudge" assertion lives in
# lib/tests/loom-drift-nudge.test.sh (cases Q-U), which owns the hook.
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

# --- stamp-field reader used by every case below ------------------------
# <fixture-dir> <key> -> the first value for that key, or "" if absent.
stamp_val() {
  sed -n "s/^$2=//p" "$1/.claude/.loom-sync" 2>/dev/null | head -1
}

# --- A. function form: loom_write_sync_stamp --synced <target> <hash> [date]
FIXTURE_A="$(mktemp -d)"
loom_write_sync_stamp --synced "$FIXTURE_A" "$current_hash" "2026-07-17"
rc=$?

if [ "$rc" -ne 0 ]; then
  fail "loom_write_sync_stamp returns 0 on success" "rc=$rc"
elif [ ! -f "$FIXTURE_A/.claude/.loom-sync" ]; then
  fail "loom_write_sync_stamp writes <target>/.claude/.loom-sync" "not found at $FIXTURE_A/.claude/.loom-sync"
else
  pass "loom_write_sync_stamp writes <target>/.claude/.loom-sync"
fi

stamp_contents_a="$(cat "$FIXTURE_A/.claude/.loom-sync" 2>/dev/null)"
if printf '%s\n' "$stamp_contents_a" | grep -qxF "last_synced=$current_hash"; then
  pass "--synced stamp records loom's current convention-manifest hash as last_synced"
else
  fail "--synced stamp records loom's current convention-manifest hash as last_synced" \
    "expected last_synced=$current_hash in:
$stamp_contents_a"
fi

if printf '%s\n' "$stamp_contents_a" | grep -qxF "last_synced_date=2026-07-17"; then
  pass "--synced stamp records the passed-in date as last_synced_date"
else
  fail "--synced stamp records the passed-in date as last_synced_date" \
    "expected last_synced_date=2026-07-17 in:
$stamp_contents_a"
fi

# A sync is also a check — both pairs are written by one --synced call.
if printf '%s\n' "$stamp_contents_a" | grep -qxF "last_checked=$current_hash" \
   && printf '%s\n' "$stamp_contents_a" | grep -qxF "last_checked_date=2026-07-17"; then
  pass "--synced stamp ALSO records last_checked/last_checked_date (a sync is a check)"
else
  fail "--synced stamp ALSO records last_checked/last_checked_date" \
    "contents:
$stamp_contents_a"
fi

rm -rf "$FIXTURE_A"

# --- B. date defaults to today (UTC) when omitted ----------------------
FIXTURE_B="$(mktemp -d)"
loom_write_sync_stamp --synced "$FIXTURE_B" "$current_hash"
today="$(date -u +%Y-%m-%d)"
stamp_contents_b="$(cat "$FIXTURE_B/.claude/.loom-sync" 2>/dev/null)"
if printf '%s\n' "$stamp_contents_b" | grep -qxF "last_synced_date=$today"; then
  pass "stamp date defaults to today (UTC) when omitted"
else
  fail "stamp date defaults to today (UTC) when omitted" \
    "expected last_synced_date=$today in:
$stamp_contents_b"
fi
rm -rf "$FIXTURE_B"

# --- C. re-stamping replaces a key's value; never appends a duplicate ---
FIXTURE_C="$(mktemp -d)"
loom_write_sync_stamp --synced "$FIXTURE_C" "deadbeef" "2020-01-01"
loom_write_sync_stamp --synced "$FIXTURE_C" "$current_hash" "2026-07-17"
stamp_contents_c="$(cat "$FIXTURE_C/.claude/.loom-sync" 2>/dev/null)"
dupes_c=""
for _k in last_synced last_synced_date last_checked last_checked_date; do
  _n=$(printf '%s\n' "$stamp_contents_c" | grep -c "^$_k=")
  [ "$_n" -eq 1 ] || dupes_c="$dupes_c $_k=$_n"
done
if [ -z "$dupes_c" ] && [ "$(stamp_val "$FIXTURE_C" last_synced)" = "$current_hash" ]; then
  pass "re-stamping replaces each key's value (no duplicate key lines)"
else
  fail "re-stamping replaces each key's value (no duplicate key lines)" \
    "dupes:$dupes_c contents:
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
"$STAMP_BIN" --synced "$FIXTURE_E" "$current_hash" "2026-07-17" >/dev/null
stamp_contents_e="$(cat "$FIXTURE_E/.claude/.loom-sync" 2>/dev/null)"
if printf '%s\n' "$stamp_contents_e" | grep -qxF "last_synced=$current_hash" \
   && printf '%s\n' "$stamp_contents_e" | grep -qxF "last_synced_date=2026-07-17"; then
  pass "CLI form (scripts/loom-sync-stamp --synced <target> <hash> [date]) stamps identically"
else
  fail "CLI form (scripts/loom-sync-stamp --synced <target> <hash> [date]) stamps identically" \
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

# =========================================================================
# loom-uh4i — the CHECKED/SYNCED SPLIT.
#
# THE BUG: `/audit-project` re-stamped `.claude/.loom-sync`
# unconditionally on EVERY invocation, including a read-only
# `--check=...` run that applied nothing. Because
# `hooks/loom-drift-nudge.sh` compares the stamped hash against loom's
# current one, merely LOOKING at a project marked it synced and silenced
# the nudge — measured 2026-07-25 against ~/repos/liza_base, stamped with
# a hash matching loom exactly while its CLAUDE.md and
# .claude/rules/dispatched-agents.md were byte-unchanged and missing
# every current convention.
#
# THE FIX separates the two facts rather than dropping either (the
# original unconditional-stamp rationale is real — a project audited
# before the drift machinery existed still needs a baseline):
#
#   last_synced / last_synced_date   — written ONLY when remediation
#                                      actually applied (--synced).
#   last_checked / last_checked_date — written by ANY invocation.
#
# The nudge compares against last_synced. Default (no flag) is
# CHECK-ONLY: the safe polarity, since a forgotten flag leaves the nudge
# firing (loud) rather than silently silencing it (this bug).
# =========================================================================

# --- G. DEFAULT (no flag) is check-only ---------------------------------
FIXTURE_G="$(mktemp -d)"
loom_write_sync_stamp "$FIXTURE_G" "$current_hash" "2026-07-25"
stamp_contents_g="$(cat "$FIXTURE_G/.claude/.loom-sync" 2>/dev/null)"
if [ "$(stamp_val "$FIXTURE_G" last_checked)" = "$current_hash" ] \
   && [ "$(stamp_val "$FIXTURE_G" last_checked_date)" = "2026-07-25" ] \
   && [ -z "$(stamp_val "$FIXTURE_G" last_synced)" ]; then
  pass "default (no flag) writes last_checked ONLY — never last_synced"
else
  fail "default (no flag) writes last_checked ONLY — never last_synced" \
    "contents:
$stamp_contents_g"
fi
rm -rf "$FIXTURE_G"

# --- H. a check must NOT clobber a prior sync record --------------------
# The read-only-check path is a read-modify-write, not a blind overwrite:
# recording "we looked" must never destroy the record of "we synced".
FIXTURE_H="$(mktemp -d)"
loom_write_sync_stamp --synced "$FIXTURE_H" "aaaa1111" "2026-01-01"
loom_write_sync_stamp "$FIXTURE_H" "bbbb2222" "2026-07-25"
stamp_contents_h="$(cat "$FIXTURE_H/.claude/.loom-sync" 2>/dev/null)"
if [ "$(stamp_val "$FIXTURE_H" last_synced)" = "aaaa1111" ] \
   && [ "$(stamp_val "$FIXTURE_H" last_synced_date)" = "2026-01-01" ] \
   && [ "$(stamp_val "$FIXTURE_H" last_checked)" = "bbbb2222" ] \
   && [ "$(stamp_val "$FIXTURE_H" last_checked_date)" = "2026-07-25" ]; then
  pass "check-only write PRESERVES a prior last_synced/last_synced_date"
else
  fail "check-only write PRESERVES a prior last_synced/last_synced_date" \
    "contents:
$stamp_contents_h"
fi
rm -rf "$FIXTURE_H"

# --- I. --synced advances BOTH pairs ------------------------------------
FIXTURE_I="$(mktemp -d)"
loom_write_sync_stamp --synced "$FIXTURE_I" "aaaa1111" "2026-01-01"
loom_write_sync_stamp --synced "$FIXTURE_I" "cccc3333" "2026-07-25"
if [ "$(stamp_val "$FIXTURE_I" last_synced)" = "cccc3333" ] \
   && [ "$(stamp_val "$FIXTURE_I" last_synced_date)" = "2026-07-25" ] \
   && [ "$(stamp_val "$FIXTURE_I" last_checked)" = "cccc3333" ]; then
  pass "--synced advances BOTH last_synced and last_checked"
else
  fail "--synced advances BOTH last_synced and last_checked" \
    "contents:
$(cat "$FIXTURE_I/.claude/.loom-sync")"
fi
rm -rf "$FIXTURE_I"

# --- J. LEGACY MIGRATION: a bare hash=/date= stamp reads as last_synced -
# Backward compatibility is load-bearing. Every project stamped before
# this change carries only `hash=`/`date=`; under the OLD semantics that
# write happened at what was CALLED a sync, so the grandfathered reading
# is last_synced (NOT last_checked). Reading it any other way would take
# every already-stamped project from silent to nudging overnight and
# would break loom-oktm's deliberately grandfathered
# stamped-but-no-workflow.json shape (its fixtures A/D/E/F/G).
FIXTURE_J="$(mktemp -d)"
mkdir -p "$FIXTURE_J/.claude"
printf 'hash=%s\ndate=%s\n' "legacy9999" "2026-02-02" > "$FIXTURE_J/.claude/.loom-sync"
loom_write_sync_stamp "$FIXTURE_J" "$current_hash" "2026-07-25"
stamp_contents_j="$(cat "$FIXTURE_J/.claude/.loom-sync" 2>/dev/null)"
if [ "$(stamp_val "$FIXTURE_J" last_synced)" = "legacy9999" ] \
   && [ "$(stamp_val "$FIXTURE_J" last_synced_date)" = "2026-02-02" ] \
   && [ "$(stamp_val "$FIXTURE_J" last_checked)" = "$current_hash" ]; then
  pass "legacy hash=/date= stamp migrates to last_synced/last_synced_date on the next write"
else
  fail "legacy hash=/date= stamp migrates to last_synced/last_synced_date" \
    "contents:
$stamp_contents_j"
fi
# The migration CONSUMES the legacy keys — the file converges on the v2
# shape rather than carrying two representations of the same fact (the
# conflation that caused this bug in the first place).
if ! printf '%s\n' "$stamp_contents_j" | grep -q '^hash=' \
   && ! printf '%s\n' "$stamp_contents_j" | grep -q '^date='; then
  pass "migration drops the legacy hash=/date= keys (single representation)"
else
  fail "migration drops the legacy hash=/date= keys" \
    "contents:
$stamp_contents_j"
fi
rm -rf "$FIXTURE_J"

# --- K. --synced over a legacy stamp supersedes the grandfathered value -
FIXTURE_K="$(mktemp -d)"
mkdir -p "$FIXTURE_K/.claude"
printf 'hash=%s\ndate=%s\n' "legacy9999" "2026-02-02" > "$FIXTURE_K/.claude/.loom-sync"
loom_write_sync_stamp --synced "$FIXTURE_K" "$current_hash" "2026-07-25"
if [ "$(stamp_val "$FIXTURE_K" last_synced)" = "$current_hash" ] \
   && [ "$(stamp_val "$FIXTURE_K" last_synced_date)" = "2026-07-25" ]; then
  pass "--synced over a legacy stamp supersedes the grandfathered last_synced"
else
  fail "--synced over a legacy stamp supersedes the grandfathered last_synced" \
    "contents:
$(cat "$FIXTURE_K/.claude/.loom-sync")"
fi
rm -rf "$FIXTURE_K"

# --- L. key=value shape preserved; no key ever duplicated ---------------
FIXTURE_L="$(mktemp -d)"
loom_write_sync_stamp --synced "$FIXTURE_L" "aaaa1111" "2026-01-01"
loom_write_sync_stamp "$FIXTURE_L" "bbbb2222" "2026-07-24"
loom_write_sync_stamp "$FIXTURE_L" "cccc3333" "2026-07-25"
stamp_contents_l="$(cat "$FIXTURE_L/.claude/.loom-sync" 2>/dev/null)"
bad_l=""
while IFS= read -r _line; do
  [ -z "$_line" ] && continue
  printf '%s' "$_line" | grep -q '^[a-z_]\{1,\}=' || bad_l="$bad_l|$_line"
done <<EOF
$stamp_contents_l
EOF
dupes_l=""
for _k in last_synced last_synced_date last_checked last_checked_date; do
  _n=$(printf '%s\n' "$stamp_contents_l" | grep -c "^$_k=")
  [ "$_n" -eq 1 ] || dupes_l="$dupes_l $_k=$_n"
done
if [ -z "$bad_l" ] && [ -z "$dupes_l" ]; then
  pass "stamp keeps the flat key=value shape across mixed check/sync writes (no dupes, no stray lines)"
else
  fail "stamp keeps the flat key=value shape across mixed check/sync writes" \
    "bad=$bad_l dupes=$dupes_l contents:
$stamp_contents_l"
fi
rm -rf "$FIXTURE_L"

# --- M. audit-project SKILL.md encodes the split ------------------------
# The skill is prose an agent executes, so the invariant is pinned as
# doc-presence assertions (same shape as lib/tests/audit-apply-flags.test.sh).
SKILL_FILE="$LOOM_ROOT/skills/audit-project/SKILL.md"

# NOTE: grep the FILE, never `printf '%s' "$txt" | grep -q`. `grep -q`
# exits on first match and SIGPIPEs the upstream printf; under this
# file's `set -o pipefail` that makes a SUCCESSFUL match report 141, so
# a doc assertion silently inverts into a false pass on any file big
# enough for printf not to have finished writing. Caught RED-side while
# writing these cases.
if grep -q 'last_synced' "$SKILL_FILE" && grep -q 'last_checked' "$SKILL_FILE"; then
  pass "SKILL.md names both last_checked and last_synced"
else
  fail "SKILL.md names both last_checked and last_synced"
fi

# Step 1c must NOT claim it writes the SYNC record unconditionally.
if grep -q 'must be written unconditionally' "$SKILL_FILE"; then
  fail "SKILL.md still claims the sync stamp 'must be written unconditionally' (the loom-uh4i bug)" \
    "$(grep -n 'must be written unconditionally' "$SKILL_FILE")"
else
  pass "SKILL.md no longer claims the sync stamp is written unconditionally"
fi

# The read-only path must be documented as check-only.
if grep -qi 'does NOT silence\|never silences' "$SKILL_FILE"; then
  pass "SKILL.md states a read-only check does NOT silence the drift nudge"
else
  fail "SKILL.md states a read-only check does NOT silence the drift nudge"
fi

# The sync record is gated on --apply-drift having actually applied >= 1.
if grep -q 'resolved: ' "$SKILL_FILE" && grep -q -- '--synced' "$SKILL_FILE"; then
  pass "SKILL.md gates the --synced re-stamp on loom-drift-resolve's applied count"
else
  fail "SKILL.md gates the --synced re-stamp on loom-drift-resolve's applied count"
fi

# The all-[SKIP] decision is explicit (loom-uh4i): zero applied is a
# check, not a sync — a run that leaves the project byte-identical must
# leave the nudge state byte-identical.
if grep -q 'SKIP\]' "$SKILL_FILE" \
   && grep -qi 'zero applied\|0 applied\|nothing was applied' "$SKILL_FILE"; then
  pass "SKILL.md documents the all-[SKIP] / zero-applied case as a check, not a sync"
else
  fail "SKILL.md documents the all-[SKIP] / zero-applied case as a check, not a sync"
fi

# Step 1c-pre must read last_synced with a legacy hash= fallback.
if grep -q 'last_synced=' "$SKILL_FILE" && grep -qi 'legacy' "$SKILL_FILE"; then
  pass "SKILL.md Step 1c-pre reads last_synced with the legacy hash= fallback"
else
  fail "SKILL.md Step 1c-pre reads last_synced with the legacy hash= fallback"
fi

# --- N. install.sh stamps loom's own root as a real SYNC ----------------
# install.sh installs loom's conventions — that IS remediation applied,
# so it takes --synced. If this were left on the check-only default,
# loom's own repo would nudge "never synced" every session.
if grep -q 'loom-sync-stamp" --synced\|loom-sync-stamp --synced' "$LOOM_ROOT/install.sh"; then
  pass "install.sh stamps loom's own .loom-sync with --synced"
else
  fail "install.sh stamps loom's own .loom-sync with --synced" \
    "$(grep -n 'loom-sync-stamp' "$LOOM_ROOT/install.sh")"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
