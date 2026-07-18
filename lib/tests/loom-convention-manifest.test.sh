#!/usr/bin/env bash
# Fixture tests for scripts/loom-convention-manifest — the foundation
# of the D1 downstream convention-drift detector (loom-ig3p.1; design
# drawer drawer_loom_decisions_4d3918198c51bb65ceaebf90).
#
# INVARIANT under test: the manifest-hash is DETERMINISTIC across runs
# AND changes IFF a listed convention file's content changes.
#
#   A. determinism  — two runs over the SAME content yield the SAME hash.
#   B. sensitivity  — editing a LISTED convention file's content changes
#                      the hash.
#   C. exclusion    — editing a NON-listed file (outside the manifest's
#                      convention roots — e.g. skills/, hooks/, or the
#                      project's own .claude/project-constitution.md,
#                      all explicitly excluded per the loom-ig3p.1 brief)
#                      does NOT change the hash.
#
# All three run against an isolated TEMP fixture tree via --root, never
# against loom's real repo files, so the test cannot mutate anything it
# doesn't own.
#
# Run:  bash lib/tests/loom-convention-manifest.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$LOOM_ROOT/scripts/loom-convention-manifest"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -e "$BIN" ]; then
  fail "scripts/loom-convention-manifest exists" "not found at $BIN"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
if [ ! -x "$BIN" ]; then
  fail "scripts/loom-convention-manifest is executable" "missing +x bit at $BIN"
fi

# --- fixture tree -----------------------------------------------------
FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

mkdir -p "$FIXTURE/templates/sub"
mkdir -p "$FIXTURE/skills"
mkdir -p "$FIXTURE/hooks"
mkdir -p "$FIXTURE/.claude"

echo "convention content v1" > "$FIXTURE/templates/foo.md"
echo "nested convention content v1" > "$FIXTURE/templates/sub/bar.md"
echo "not a convention file (symlinked, always current)" > "$FIXTURE/skills/baz.md"
echo "not a convention file (symlinked, always current)" > "$FIXTURE/hooks/qux.sh"
echo "own constitution copy — has its OWN staleness nudge (loom-1lj)" \
  > "$FIXTURE/.claude/project-constitution.md"

run_hash() {
  "$BIN" --root "$FIXTURE"
}

# --- A. determinism -----------------------------------------------------
hash1="$(run_hash 2>&1)"
rc1=$?
hash2="$(run_hash 2>&1)"
rc2=$?

if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
  fail "manifest hash runs cleanly (rc=0)" "rc1=$rc1 rc2=$rc2 out1=$hash1 out2=$hash2"
elif [ -z "$hash1" ]; then
  fail "manifest hash is non-empty" "got empty output"
elif [ "$hash1" = "$hash2" ]; then
  pass "determinism: two runs over unchanged content yield the same hash ($hash1)"
else
  fail "determinism: two runs over unchanged content yield the same hash" "hash1=$hash1 hash2=$hash2"
fi

baseline="$hash1"

# --- B. sensitivity: editing a LISTED convention file changes the hash --
echo "convention content v2 — CHANGED" > "$FIXTURE/templates/foo.md"
hash_after_listed_edit="$(run_hash 2>&1)"

if [ "$hash_after_listed_edit" != "$baseline" ] && [ -n "$hash_after_listed_edit" ]; then
  pass "sensitivity: editing templates/foo.md (listed) changes the hash"
else
  fail "sensitivity: editing templates/foo.md (listed) changes the hash" \
    "baseline=$baseline after=$hash_after_listed_edit"
fi

# same check for a NESTED listed file
echo "convention content v1" > "$FIXTURE/templates/foo.md"   # restore
hash_restored="$(run_hash 2>&1)"
if [ "$hash_restored" = "$baseline" ]; then
  pass "restoring templates/foo.md's original content restores the original hash"
else
  fail "restoring templates/foo.md's original content restores the original hash" \
    "baseline=$baseline restored=$hash_restored"
fi

echo "nested convention content v2 — CHANGED" > "$FIXTURE/templates/sub/bar.md"
hash_after_nested_edit="$(run_hash 2>&1)"
if [ "$hash_after_nested_edit" != "$hash_restored" ] && [ -n "$hash_after_nested_edit" ]; then
  pass "sensitivity: editing templates/sub/bar.md (listed, nested) changes the hash"
else
  fail "sensitivity: editing templates/sub/bar.md (listed, nested) changes the hash" \
    "before=$hash_restored after=$hash_after_nested_edit"
fi
echo "nested convention content v1" > "$FIXTURE/templates/sub/bar.md"   # restore
baseline2="$(run_hash 2>&1)"

# --- C. exclusion: editing NON-listed files does NOT change the hash ----
echo "skills/ changed — should NOT affect manifest hash (symlinked, always current)" \
  > "$FIXTURE/skills/baz.md"
hash_after_skills_edit="$(run_hash 2>&1)"
if [ "$hash_after_skills_edit" = "$baseline2" ]; then
  pass "exclusion: editing skills/baz.md (non-listed) does NOT change the hash"
else
  fail "exclusion: editing skills/baz.md (non-listed) does NOT change the hash" \
    "before=$baseline2 after=$hash_after_skills_edit"
fi

echo "hooks/ changed — should NOT affect manifest hash (symlinked, always current)" \
  > "$FIXTURE/hooks/qux.sh"
hash_after_hooks_edit="$(run_hash 2>&1)"
if [ "$hash_after_hooks_edit" = "$baseline2" ]; then
  pass "exclusion: editing hooks/qux.sh (non-listed) does NOT change the hash"
else
  fail "exclusion: editing hooks/qux.sh (non-listed) does NOT change the hash" \
    "before=$baseline2 after=$hash_after_hooks_edit"
fi

echo "constitution changed — has its OWN staleness nudge (loom-1lj), not double-counted" \
  > "$FIXTURE/.claude/project-constitution.md"
hash_after_constitution_edit="$(run_hash 2>&1)"
if [ "$hash_after_constitution_edit" = "$baseline2" ]; then
  pass "exclusion: editing .claude/project-constitution.md (non-listed) does NOT change the hash"
else
  fail "exclusion: editing .claude/project-constitution.md (non-listed) does NOT change the hash" \
    "before=$baseline2 after=$hash_after_constitution_edit"
fi

# adding a brand new file OUTSIDE the manifest roots must not move the hash either
echo "new untracked file" > "$FIXTURE/README.md"
hash_after_new_nonlisted_file="$(run_hash 2>&1)"
if [ "$hash_after_new_nonlisted_file" = "$baseline2" ]; then
  pass "exclusion: adding a new non-listed file does NOT change the hash"
else
  fail "exclusion: adding a new non-listed file does NOT change the hash" \
    "before=$baseline2 after=$hash_after_new_nonlisted_file"
fi

# --- D. --list enumerates exactly the listed files, sorted --------------
list_out="$("$BIN" --root "$FIXTURE" --list 2>&1)"
expected_list="$(printf 'templates/foo.md\ntemplates/sub/bar.md')"
if [ "$list_out" = "$expected_list" ]; then
  pass "--list enumerates exactly the manifest file set, sorted"
else
  fail "--list enumerates exactly the manifest file set, sorted" \
    "expected:
$expected_list
got:
$list_out"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
