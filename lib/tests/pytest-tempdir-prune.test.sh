#!/usr/bin/env bash
# Fixture tests for hooks/pytest-tempdir-prune.sh.
#
# Closes loom-skxj (feature): a SessionStart housekeeping hook that
# prunes STALE project-scoped pytest temp dirs. pytest temp dirs
# (`./tmp/pytest-of-<user>/...`) accumulate and eat drive space; origin
# was a project with `./tmp/pytest-of-frank` growing huge.
#
# Hook is SessionStart. It:
#   1. Scopes STRICTLY to `./tmp/pytest-of-*` (cwd/project-relative).
#      Never touches /tmp/pytest-of-$USER or anything outside ./tmp/.
#   2. Removes only entries older than 24h (find -mtime +1).
#   3. Opt-out: LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1 (literal "1") → no-op.
#   4. No-op-safe: absent ./tmp/ or no match → do nothing.
#   5. ALWAYS exits 0 (non-blocking housekeeping; never blocks session
#      start, never emits blocking JSON).
#
# RED: a >24h ./tmp/pytest-of-* dir is pruned at SessionStart; a <24h
# dir AND anything outside the ./tmp/pytest-of-* pattern survive; the
# opt-out env disables all pruning.
#
# Each case runs inside a throwaway fixture dir (mktemp -d) so the test
# never touches the real repo's ./tmp.
#
# Run:  bash lib/tests/pytest-tempdir-prune.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/pytest-tempdir-prune.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook from inside a fixture dir, feeding a SessionStart-shaped
# payload on stdin (the hook drains stdin; it does not need any field).
#   $1 = cwd (the fixture project root)
#   $2 = optional extra env (string like "FOO=bar")
run_hook() {
  local cwd="$1" extra="${2:-}"
  local payload='{"hookEventName":"SessionStart","cwd":"'"$cwd"'"}'
  if [ -n "$extra" ]; then
    (cd "$cwd" && env $extra bash "$HOOK" <<<"$payload" 2>&1)
  else
    (cd "$cwd" && bash "$HOOK" <<<"$payload" 2>&1)
  fi
}

# Build a fixture project root with a ./tmp/ tree.
#   echoes the fixture root dir
mk_fixture() {
  local root; root=$(mktemp -d)
  mkdir -p "$root/tmp"
  echo "$root"
}

# Age a directory to >24h old (2 days ago).
age_old() { touch -d '2 days ago' "$1"; }

export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# -------------------------------------------------------------------
# 1. A >24h ./tmp/pytest-of-* dir is pruned.
# -------------------------------------------------------------------

echo "==> 1. Stale (>24h) ./tmp/pytest-of-* dir → pruned"

FX=$(mk_fixture)
mkdir -p "$FX/tmp/pytest-of-foo/garbage-run"
age_old "$FX/tmp/pytest-of-foo"

out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$FX/tmp/pytest-of-foo" ]; then
  pass "stale pytest-of-foo removed; hook exit 0"
else
  fail "stale dir not removed (rc=$rc, exists=$( [ -e "$FX/tmp/pytest-of-foo" ] && echo yes || echo no ))" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 2. A fresh (<24h) ./tmp/pytest-of-* dir is KEPT.
# -------------------------------------------------------------------

echo "==> 2. Fresh (<24h) ./tmp/pytest-of-* dir → kept"

FX=$(mk_fixture)
mkdir -p "$FX/tmp/pytest-of-bar/fresh-run"
# Leave mtime at now (fresh).

out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$FX/tmp/pytest-of-bar" ]; then
  pass "fresh pytest-of-bar kept; hook exit 0"
else
  fail "fresh dir incorrectly removed (rc=$rc)" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 3. LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1 → stale dir KEPT (no-op).
# -------------------------------------------------------------------

echo "==> 3. SKIP=1 → even a stale dir is kept (opt-out)"

FX=$(mk_fixture)
mkdir -p "$FX/tmp/pytest-of-skip/garbage-run"
age_old "$FX/tmp/pytest-of-skip"

out=$(run_hook "$FX" "LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1"); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$FX/tmp/pytest-of-skip" ]; then
  pass "SKIP=1: stale dir kept; hook exit 0 (no-op)"
else
  fail "SKIP=1 did not disable pruning (rc=$rc)" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 3b. SKIP=yes / SKIP=true / SKIP=0 / SKIP= → pruning STILL happens
#     (literal-"1" convention; only "1" opts out).
# -------------------------------------------------------------------

echo "==> 3b. SKIP non-1 values still prune (literal-1 convention)"

for val in yes true 0 ""; do
  FX=$(mk_fixture)
  mkdir -p "$FX/tmp/pytest-of-x/garbage"
  age_old "$FX/tmp/pytest-of-x"
  out=$(run_hook "$FX" "LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=$val"); rc=$?
  if [ "$rc" -eq 0 ] && [ ! -e "$FX/tmp/pytest-of-x" ]; then
    pass "SKIP='$val' (non-literal-1): still prunes stale dir"
  else
    fail "SKIP='$val' incorrectly bypassed pruning (rc=$rc)" "$out"
  fi
  rm -rf "$FX"
done

# -------------------------------------------------------------------
# 4. Scope guard — non-pytest siblings inside ./tmp/ are NEVER touched,
#    even when stale.
# -------------------------------------------------------------------

echo "==> 4. Scope guard — ./tmp/keepme/ and ./tmp/notpytest survive"

FX=$(mk_fixture)
# A sibling dir whose name does NOT match pytest-of-* — must survive.
mkdir -p "$FX/tmp/keepme/important"
age_old "$FX/tmp/keepme"
# A sibling file that merely contains the substring — must survive.
touch "$FX/tmp/notpytest"
age_old "$FX/tmp/notpytest"
# A real stale pytest dir to confirm the prune still runs.
mkdir -p "$FX/tmp/pytest-of-foo/junk"
age_old "$FX/tmp/pytest-of-foo"

out=$(run_hook "$FX"); rc=$?
keep_ok=0
[ -d "$FX/tmp/keepme" ] && [ -e "$FX/tmp/notpytest" ] && [ ! -e "$FX/tmp/pytest-of-foo" ] && keep_ok=1
if [ "$rc" -eq 0 ] && [ "$keep_ok" -eq 1 ]; then
  pass "non-pytest siblings kept; stale pytest dir pruned"
else
  fail "scope guard violated (rc=$rc keepme=$( [ -d "$FX/tmp/keepme" ] && echo y||echo n ) notpytest=$( [ -e "$FX/tmp/notpytest" ] && echo y||echo n ) pytest=$( [ -e "$FX/tmp/pytest-of-foo" ] && echo y||echo n ))" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 4b. Scope guard — a stale pytest-of-* dir OUTSIDE ./tmp/ (directly
#     in the project root) is NEVER touched. The prune must not escape
#     ./tmp/.
# -------------------------------------------------------------------

echo "==> 4b. Scope guard — ./pytest-of-root (outside ./tmp/) survives"

FX=$(mk_fixture)
mkdir -p "$FX/pytest-of-root/junk"   # NOT under ./tmp/
age_old "$FX/pytest-of-root"
mkdir -p "$FX/tmp/pytest-of-foo/junk"
age_old "$FX/tmp/pytest-of-foo"

out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$FX/pytest-of-root" ] && [ ! -e "$FX/tmp/pytest-of-foo" ]; then
  pass "./pytest-of-root (outside ./tmp/) kept; ./tmp/ entry pruned"
else
  fail "prune escaped ./tmp/ (rc=$rc root=$( [ -d "$FX/pytest-of-root" ] && echo y||echo n ))" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 4c. Scope guard — nested ./tmp/sub/pytest-of-deep (depth 2) is NOT
#     pruned. maxdepth keeps the prune to direct children of ./tmp/.
# -------------------------------------------------------------------

echo "==> 4c. Scope guard — nested ./tmp/sub/pytest-of-deep survives (maxdepth)"

FX=$(mk_fixture)
mkdir -p "$FX/tmp/sub/pytest-of-deep/junk"
age_old "$FX/tmp/sub/pytest-of-deep"
age_old "$FX/tmp/sub"

out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$FX/tmp/sub/pytest-of-deep" ]; then
  pass "nested ./tmp/sub/pytest-of-deep kept (not a direct child of ./tmp/)"
else
  fail "prune recursed below ./tmp/ direct children (rc=$rc)" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 5. Empty / absent ./tmp → exit 0 no-op.
# -------------------------------------------------------------------

echo "==> 5. Absent ./tmp and empty ./tmp → exit 0 no-op"

# 5a. No ./tmp at all.
FX=$(mktemp -d)   # no tmp/ subdir created
out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "absent ./tmp: exit 0 no-op"
else
  fail "absent ./tmp non-zero exit (rc=$rc)" "$out"
fi
rm -rf "$FX"

# 5b. ./tmp present but empty (no pytest-of-* matches).
FX=$(mk_fixture)
out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "empty ./tmp (no matches): exit 0 no-op"
else
  fail "empty ./tmp non-zero exit (rc=$rc)" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
# 6. Non-blocking — the hook must NEVER emit blocking JSON (no
#    "decision":"block", no exit 2). It either prints nothing or a
#    well-formed non-blocking additionalContext (SessionStart).
# -------------------------------------------------------------------

echo "==> 6. Output is non-blocking (no decision:block, exit 0)"

FX=$(mk_fixture)
mkdir -p "$FX/tmp/pytest-of-foo/junk"
age_old "$FX/tmp/pytest-of-foo"
out=$(run_hook "$FX"); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  pass "no blocking decision emitted; exit 0"
else
  fail "hook emitted blocking output or non-zero exit (rc=$rc)" "$out"
fi
rm -rf "$FX"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
