#!/usr/bin/env bash
# Acceptance test for templates/scripts/ (loom-oxs.1).
#
# The scripts template is the canonical 8-script skeleton for the loom
# "script/ convention" (GitHub "scripts to rule them all" lineage, locked
# in the loom-adm script/-convention decision drawer). It is the source-of-
# truth skeleton that /audit-project (loom-oxs.4) recognizes + scaffolds into
# a loom-managed repo's script/ directory (singular default; the recognizer
# also accepts scripts/).
#
# The 8 canonical scripts are: bootstrap setup update server test lint cibuild
# deploy. Each stub, AS SHIPPED/UNEDITED, echoes a clear "not implemented for
# this project" message to stderr AND exits non-zero (code 2). The adopter
# later either wires the script up, or — for a genuinely-N/A script (e.g.
# server in a library) — downgrades it to echo "N/A" + exit 0. That downgrade
# is the adopter's EDIT, not the shipped default. Each stub also carries
# per-type comment hints (# Go: / # Python: / # Node: / # bash:) the adopter
# uncomments.
#
# Verifies the INVARIANT:
#   1. templates/scripts/ exists and contains all 8 canonical scripts.
#   2. Each script is executable (mode bit) and shell-shebanged.
#   3. Each unedited stub exits 2.
#   4. Each unedited stub prints a clear "not implemented" message to STDERR
#      (not stdout — adopters / CI parse stdout).
#   5. Each stub carries per-type comment hints: # Go / # Python / # Node /
#      # bash, all four present per script.
#   6. A README.md documents the convention + how to adopt.
# Plus a NEGATIVE self-check: a synthetic skeleton missing a script is flagged
# by the same all-8-present comparator (proves the comparator is not vacuous).
#
# Self-contained shell-fixture test — no external tool dependency (mirrors the
# plain-bash assert idiom of lib/tests/exploration-template.test.sh).
#
# Run:  bash lib/tests/scripts-template.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="$LOOM_ROOT/templates/scripts"

# The 8 canonical scripts, in convention order.
CANONICAL=(bootstrap setup update server test lint cibuild deploy)

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

# all_eight_present <dir> : echo names of any canonical script MISSING from
# <dir>; empty output means all 8 present. The comparator under negative test.
all_eight_present() {
  local dir="$1" s missing=""
  for s in "${CANONICAL[@]}"; do
    [ -f "$dir/$s" ] || missing="$missing $s"
  done
  echo "$missing"
}

# --- prereqs -----------------------------------------------------------
echo "==> Prereqs"
if [ ! -d "$TEMPLATE_DIR" ]; then
  fail "templates/scripts/ exists" "(directory missing — bead has not landed)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "templates/scripts/ exists"

# --- all 8 canonical scripts present -----------------------------------
echo "==> All 8 canonical scripts present"
missing="$(all_eight_present "$TEMPLATE_DIR")"
if [ -z "$missing" ]; then
  pass "all 8 canonical scripts present (${CANONICAL[*]})"
else
  fail "all 8 canonical scripts present" "(missing:$missing)"
fi

# --- per-script structural + behavioral invariants ---------------------
echo "==> Per-script invariants (executable, shebang, exit 2, stderr message, per-type hints)"
for s in "${CANONICAL[@]}"; do
  script="$TEMPLATE_DIR/$s"
  if [ ! -f "$script" ]; then
    fail "$s present"; continue
  fi

  # Executable mode bit.
  if [ -x "$script" ]; then pass "$s is executable"
  else fail "$s is executable" "(missing +x mode bit)"; fi

  # Shell shebang on line 1.
  if head -n1 "$script" | grep -qE '^#!.*\b(bash|sh)\b'; then pass "$s has a shell shebang"
  else fail "$s has a shell shebang"; fi

  # Per-type comment hints — all four present.
  assert_contains "$s carries a # Go hint"     "$script" '#[[:space:]]*Go:'
  assert_contains "$s carries a # Python hint" "$script" '#[[:space:]]*Python:'
  assert_contains "$s carries a # Node hint"   "$script" '#[[:space:]]*Node:'
  assert_contains "$s carries a # bash hint"   "$script" '#[[:space:]]*bash:'

  # Behavioral: unedited stub exits 2 and writes its message to STDERR,
  # nothing to STDOUT.
  out="$(bash "$script" 2>/dev/null)"          # stdout only
  err="$(bash "$script" 2>&1 1>/dev/null)"     # stderr only
  rc=0; bash "$script" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 2 ]; then pass "$s exits 2 unedited"
  else fail "$s exits 2 unedited" "(got rc=$rc)"; fi

  if echo "$err" | grep -qiE 'not implemented'; then pass "$s prints 'not implemented' to stderr"
  else fail "$s prints 'not implemented' to stderr" "(stderr was: $err)"; fi

  # The message must NOT be on stdout — adopters/CI parse stdout.
  if [ -z "$out" ]; then pass "$s writes nothing to stdout"
  else fail "$s writes nothing to stdout" "(stdout was: $out)"; fi
done

# --- README ------------------------------------------------------------
echo "==> README documents the convention + adoption"
README="$TEMPLATE_DIR/README.md"
if [ -f "$README" ]; then
  pass "templates/scripts/README.md present"
  assert_contains "README names the script/ convention"       "$README" 'script/'
  assert_contains "README enumerates the 8 canonical scripts" "$README" 'bootstrap.*setup|setup.*update|cibuild'
  assert_contains "README explains adoption (cp / copy)"       "$README" '(^|[^a-z])cp([^a-z]|$)|[Aa]dopt'
  assert_contains "README explains the exit-2 not-implemented default" "$README" 'exit 2|exits 2|not implemented'
else
  fail "templates/scripts/README.md present"
fi

# --- NEGATIVE self-check: missing-script skeleton is flagged -----------
echo "==> Negative self-check (synthetic skeleton missing a script is flagged)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Copy the real skeleton, then delete one canonical script.
cp "$TEMPLATE_DIR"/* "$TMP/" 2>/dev/null || true
rm -f "$TMP/server"
neg_missing="$(all_eight_present "$TMP")"
if echo "$neg_missing" | grep -qw server; then
  pass "comparator flags a skeleton missing 'server' (not vacuous)"
else
  fail "comparator flags a skeleton missing 'server'" "(comparator reported: '$neg_missing')"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
