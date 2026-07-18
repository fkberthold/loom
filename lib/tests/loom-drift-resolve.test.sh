#!/usr/bin/env bash
# Fixture tests for scripts/loom-drift-resolve — the reusable per-item
# review-queue engine `/audit-project --apply-drift` drives (loom-ig3p.4;
# design drawer drawer_loom_decisions_4d3918198c51bb65ceaebf90 / D2).
#
# NAMING NOTE: the bead brief named this script `loom-audit-resolve`,
# but that name is ALREADY TAKEN by loom-6ah's unrelated `--root`/
# `--wing`/primitive-autodetect resolution prelude
# (scripts/loom-audit-resolve, lib/tests/loom-audit-resolve.test.sh,
# wired into skills/audit-project/SKILL.md Step 1, 15/15 tests). This
# engine is named `loom-drift-resolve` instead to avoid clobbering that
# merged, in-use script. See the loom-ig3p.4 close notes for the
# deviation record.
#
# INVARIANT under test (the RED spec on loom-ig3p.4): given a set of
# "drifted" fixture items and a decision stream, the engine applies
# ONLY the approved items and leaves skipped ones untouched — and with
# NO approval recorded at all, it applies NOTHING (never-auto-apply).
# This mirrors --apply-onboarding's per-item AUTOFIX gate but as a
# standalone, non-interactively-testable unit (decisions come from a
# file/env fixture, never raw stdin prompts, so this test never blocks
# on a TTY).
#
# All fixtures live under mktemp -d trees; the real repo is never
# touched.
#
# Run:  bash lib/tests/loom-drift-resolve.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$LOOM_ROOT/scripts/loom-drift-resolve"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -e "$BIN" ]; then
  fail "scripts/loom-drift-resolve exists" "not found at $BIN"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
if [ ! -x "$BIN" ]; then
  fail "scripts/loom-drift-resolve is executable" "missing +x bit at $BIN"
fi

FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

mkdir -p "$FIXTURE/src" "$FIXTURE/dst"

# --- shared source content, three candidate drift items -----------------
echo "loom current content — alpha v2" > "$FIXTURE/src/alpha.md"
echo "loom current content — beta v2"  > "$FIXTURE/src/beta.md"
echo "loom current content — gamma v2" > "$FIXTURE/src/gamma.md"

# alpha + beta pre-exist downstream with STALE content; gamma has never
# been synced (no downstream file yet).
echo "downstream stale content — alpha v1" > "$FIXTURE/dst/alpha.md"
echo "downstream stale content — beta v1"  > "$FIXTURE/dst/beta.md"

items_file="$FIXTURE/items.tsv"
cat > "$items_file" <<EOF
# comment line and a blank line below are ignored
$FIXTURE/dst/alpha.md	$FIXTURE/src/alpha.md

$FIXTURE/dst/beta.md	$FIXTURE/src/beta.md
$FIXTURE/dst/gamma.md	$FIXTURE/src/gamma.md
EOF

# =========================================================================
# A. NO decisions at all (no --decisions, no env var) → applies NOTHING.
#    This is the core never-auto-apply invariant from the bead's RED spec.
# =========================================================================
unset LOOM_AUDIT_RESOLVE_DECISIONS
out_a="$("$BIN" --items "$items_file" < /dev/null 2>&1)"
rc_a=$?

alpha_after_a="$(cat "$FIXTURE/dst/alpha.md")"
beta_after_a="$(cat "$FIXTURE/dst/beta.md")"
gamma_exists_a="no"; [ -e "$FIXTURE/dst/gamma.md" ] && gamma_exists_a="yes"

if [ "$alpha_after_a" = "downstream stale content — alpha v1" ] \
   && [ "$beta_after_a" = "downstream stale content — beta v1" ] \
   && [ "$gamma_exists_a" = "no" ]; then
  pass "no decisions recorded (empty stream) -> applies NOTHING (never-auto-apply)"
else
  fail "no decisions recorded (empty stream) -> applies NOTHING (never-auto-apply)" \
    "alpha=$alpha_after_a beta=$beta_after_a gamma_exists=$gamma_exists_a rc=$rc_a out=$out_a"
fi

if echo "$out_a" | grep -q "no decision"; then
  pass "no-decision items are reported as SKIP with a 'no decision recorded' note"
else
  fail "no-decision items are reported as SKIP with a 'no decision recorded' note" "out=$out_a"
fi

# =========================================================================
# B. Mixed decisions: alpha=approve, beta=skip, gamma=(absent) -----------
#    -> ONLY alpha is applied; beta stays stale; gamma stays absent.
# =========================================================================
decisions_file="$FIXTURE/decisions-b.txt"
cat > "$decisions_file" <<EOF
$FIXTURE/dst/alpha.md=approve
$FIXTURE/dst/beta.md=skip
EOF

out_b="$("$BIN" --items "$items_file" --decisions "$decisions_file" 2>&1)"

alpha_after_b="$(cat "$FIXTURE/dst/alpha.md" 2>/dev/null)"
beta_after_b="$(cat "$FIXTURE/dst/beta.md" 2>/dev/null)"
gamma_exists_b="no"; [ -e "$FIXTURE/dst/gamma.md" ] && gamma_exists_b="yes"

if [ "$alpha_after_b" = "loom current content — alpha v2" ]; then
  pass "approved item IS applied (target content becomes source content)"
else
  fail "approved item IS applied (target content becomes source content)" \
    "alpha_after=$alpha_after_b out=$out_b"
fi

if [ "$beta_after_b" = "downstream stale content — beta v1" ]; then
  pass "explicitly-skipped item is left UNTOUCHED"
else
  fail "explicitly-skipped item is left UNTOUCHED" "beta_after=$beta_after_b"
fi

if [ "$gamma_exists_b" = "no" ]; then
  pass "item with no decision key present stays UNAPPLIED (target never created)"
else
  fail "item with no decision key present stays UNAPPLIED (target never created)" \
    "gamma_exists=$gamma_exists_b"
fi

if echo "$out_b" | grep -qF "[APPLY] $FIXTURE/dst/alpha.md"; then
  pass "output reports [APPLY] for the approved item"
else
  fail "output reports [APPLY] for the approved item" "out=$out_b"
fi

# =========================================================================
# C. approve on an item whose target does not exist yet -> file is CREATED
#    (parent dirs made as needed).
# =========================================================================
decisions_file_c="$FIXTURE/decisions-c.txt"
echo "$FIXTURE/dst/gamma.md=approve" > "$decisions_file_c"
"$BIN" --items "$items_file" --decisions "$decisions_file_c" >/dev/null 2>&1

if [ -f "$FIXTURE/dst/gamma.md" ] && [ "$(cat "$FIXTURE/dst/gamma.md")" = "loom current content — gamma v2" ]; then
  pass "approving a never-synced item CREATES the target with source content"
else
  fail "approving a never-synced item CREATES the target with source content" \
    "exists=$([ -f "$FIXTURE/dst/gamma.md" ] && echo yes || echo no) content=$(cat "$FIXTURE/dst/gamma.md" 2>/dev/null)"
fi

# =========================================================================
# D. LOOM_AUDIT_RESOLVE_DECISIONS env var works as a --decisions fallback.
# =========================================================================
FIXTURE_D="$(mktemp -d)"
mkdir -p "$FIXTURE_D/src" "$FIXTURE_D/dst"
echo "env-driven current content" > "$FIXTURE_D/src/delta.md"
items_d="$FIXTURE_D/items.tsv"
printf '%s\t%s\n' "$FIXTURE_D/dst/delta.md" "$FIXTURE_D/src/delta.md" > "$items_d"
decisions_d="$FIXTURE_D/decisions.txt"
echo "$FIXTURE_D/dst/delta.md=approve" > "$decisions_d"

LOOM_AUDIT_RESOLVE_DECISIONS="$decisions_d" "$BIN" --items "$items_d" >/dev/null 2>&1

if [ -f "$FIXTURE_D/dst/delta.md" ] && [ "$(cat "$FIXTURE_D/dst/delta.md")" = "env-driven current content" ]; then
  pass "LOOM_AUDIT_RESOLVE_DECISIONS env var is honored when --decisions is omitted"
else
  fail "LOOM_AUDIT_RESOLVE_DECISIONS env var is honored when --decisions is omitted" \
    "exists=$([ -f "$FIXTURE_D/dst/delta.md" ] && echo yes || echo no)"
fi
rm -rf "$FIXTURE_D"

# =========================================================================
# E. quit stops the queue: remaining items (even ones later marked
#    approve in the decisions file) are left UNRESOLVED once quit fires.
# =========================================================================
FIXTURE_E="$(mktemp -d)"
mkdir -p "$FIXTURE_E/src" "$FIXTURE_E/dst"
echo "e-one-current" > "$FIXTURE_E/src/one.md"
echo "e-two-current" > "$FIXTURE_E/src/two.md"
echo "e-three-current" > "$FIXTURE_E/src/three.md"
items_e="$FIXTURE_E/items.tsv"
{
  printf '%s\t%s\n' "$FIXTURE_E/dst/one.md" "$FIXTURE_E/src/one.md"
  printf '%s\t%s\n' "$FIXTURE_E/dst/two.md" "$FIXTURE_E/src/two.md"
  printf '%s\t%s\n' "$FIXTURE_E/dst/three.md" "$FIXTURE_E/src/three.md"
} > "$items_e"
decisions_e="$FIXTURE_E/decisions.txt"
{
  echo "$FIXTURE_E/dst/one.md=approve"
  echo "$FIXTURE_E/dst/two.md=quit"
  # three is marked approve but comes AFTER the quit in queue order —
  # it must NOT be applied.
  echo "$FIXTURE_E/dst/three.md=approve"
} > "$decisions_e"

out_e="$("$BIN" --items "$items_e" --decisions "$decisions_e" 2>&1)"

one_ok="no"; [ -f "$FIXTURE_E/dst/one.md" ] && [ "$(cat "$FIXTURE_E/dst/one.md")" = "e-one-current" ] && one_ok="yes"
three_exists_e="no"; [ -e "$FIXTURE_E/dst/three.md" ] && three_exists_e="yes"

if [ "$one_ok" = "yes" ] && [ "$three_exists_e" = "no" ]; then
  pass "quit halts the queue: items before quit still applied, items after quit left unresolved"
else
  fail "quit halts the queue: items before quit still applied, items after quit left unresolved" \
    "one_ok=$one_ok three_exists=$three_exists_e out=$out_e"
fi

if echo "$out_e" | grep -q "QUIT"; then
  pass "output reports [QUIT] when the queue is halted"
else
  fail "output reports [QUIT] when the queue is halted" "out=$out_e"
fi
rm -rf "$FIXTURE_E"

# =========================================================================
# F. usage error: missing --items fails loudly (non-zero, no writes)
# =========================================================================
FIXTURE_F="$(mktemp -d)"
"$BIN" --decisions /dev/null > "$FIXTURE_F/out.log" 2>&1
rc_f=$?
if [ "$rc_f" -ne 0 ]; then
  pass "missing --items fails loudly (non-zero exit)"
else
  fail "missing --items fails loudly (non-zero exit)" "rc=$rc_f out=$(cat "$FIXTURE_F/out.log")"
fi
rm -rf "$FIXTURE_F"

# =========================================================================
# G. approve with a missing source file fails that item without crashing
#    the whole run, and does NOT write the target.
# =========================================================================
FIXTURE_G="$(mktemp -d)"
mkdir -p "$FIXTURE_G/dst"
items_g="$FIXTURE_G/items.tsv"
printf '%s\t%s\n' "$FIXTURE_G/dst/ghost.md" "$FIXTURE_G/src/does-not-exist.md" > "$items_g"
decisions_g="$FIXTURE_G/decisions.txt"
echo "$FIXTURE_G/dst/ghost.md=approve" > "$decisions_g"
out_g="$("$BIN" --items "$items_g" --decisions "$decisions_g" 2>&1)"
rc_g=$?

if [ ! -e "$FIXTURE_G/dst/ghost.md" ] && [ "$rc_g" -ne 0 ] && echo "$out_g" | grep -qi "fail"; then
  pass "approve on a missing source fails that item (no write, non-zero exit, FAIL noted)"
else
  fail "approve on a missing source fails that item (no write, non-zero exit, FAIL noted)" \
    "exists=$([ -e "$FIXTURE_G/dst/ghost.md" ] && echo yes || echo no) rc=$rc_g out=$out_g"
fi
rm -rf "$FIXTURE_G"

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
