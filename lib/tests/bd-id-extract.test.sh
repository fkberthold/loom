#!/usr/bin/env bash
# Fixture tests for lib/bd-id-extract.sh.
#
# Covers loom-6m8: audit-project Check 2a "every bd-ID looks dead" was a
# regex bug, not real drift. The bug surfaced on liza_base (snake_case
# prefix) but the ad-hoc-regex approach was inherently brittle — different
# agents on different runs produce different regexes. Replace ad-hoc-prose
# with a small helper that:
#   1. Detects the project's bd prefix (literal, not pattern-derived)
#   2. Anchors the scan on that literal prefix
#   3. Resolves each candidate via 'cd <root> && bd show <id>' so the
#      lookup hits the project's own .beads/, not loom's
#   4. Emits dead candidates on stdout (one per line, preserving order,
#      dedup'd)
#
# Run:  bash lib/tests/bd-id-extract.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$LOOM_ROOT/lib/bd-id-extract.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a fake project root with:
#   .beads/config.yaml    — fixture config
#   .beads/issues.jsonl   — N seed beads (for prefix detection + fake bd)
#   bin/bd                — fake bd: exits 0 if ID present, exit 1 otherwise
mk_project() {
  local dir="$1" ; shift
  local -a ids=("$@")
  mkdir -p "$dir/.beads" "$dir/bin"
  printf '# fixture config\n' >"$dir/.beads/config.yaml"
  : >"$dir/.beads/issues.jsonl"
  for id in "${ids[@]}"; do
    printf '{"id":"%s","title":"fixture","status":"open"}\n' "$id" \
      >>"$dir/.beads/issues.jsonl"
  done
  cat >"$dir/bin/bd" <<'BD'
#!/usr/bin/env bash
# Fake bd that supports:
#   bd show <id>  — exit 0 if id in .beads/issues.jsonl, else 1
#   bd list ...   — emit one issue from .beads/issues.jsonl
# Resolves .beads relative to PWD.
set -u
if [ "${1:-}" = "show" ]; then
  id="${2:-}"
  if [ -z "$id" ]; then exit 1; fi
  if [ ! -f .beads/issues.jsonl ]; then exit 1; fi
  if grep -q "\"id\":\"$id\"" .beads/issues.jsonl 2>/dev/null; then
    echo "id=$id ok"
    exit 0
  fi
  echo "Error: no issue found matching \"$id\"" >&2
  exit 1
fi
if [ "${1:-}" = "list" ]; then
  if [ ! -f .beads/issues.jsonl ]; then
    echo "[]"
    exit 0
  fi
  echo "["
  head -1 .beads/issues.jsonl
  echo "]"
  exit 0
fi
echo "fake bd: unsupported args: $*" >&2
exit 2
BD
  chmod +x "$dir/bin/bd"
}

# Run helper with PATH pointing at the fixture's fake bd.
# Note: writes stdin to a tmpfile so subshell quoting + extra flag args
# don't tangle.
run_helper() {
  local proj="$1" stdin="$2"
  shift 2
  local stdin_file
  stdin_file=$(mktemp)
  printf '%s' "$stdin" >"$stdin_file"
  (cd "$proj" && PATH="$proj/bin:$PATH" bash "$HELPER" "$@" <"$stdin_file" 2>&1)
  local rc=$?
  rm -f "$stdin_file"
  return $rc
}

# ---------------------------------------------------------------------------
# Pre-flight: helper exists
# ---------------------------------------------------------------------------

if [ ! -f "$HELPER" ]; then
  fail "lib/bd-id-extract.sh exists" "(missing: $HELPER)"
  echo
  echo "============================================================"
  echo "RESULT: passed=$passed failed=$failed (helper missing — RED)"
  echo "============================================================"
  exit 1
fi
pass "lib/bd-id-extract.sh exists"

if [ -x "$HELPER" ]; then
  pass "lib/bd-id-extract.sh is executable"
else
  fail "lib/bd-id-extract.sh is executable"
fi

# ---------------------------------------------------------------------------
# Case 1: snake_case prefix (liza_base-XXX) — the original loom-6m8 trigger
# ---------------------------------------------------------------------------

echo "==> Case 1: snake_case prefix (liza_base-XXX)"
TMP1="$(mktemp -d)"
TMP2="$(mktemp -d)"
TMP3="$(mktemp -d)"
TMP4="$(mktemp -d)"
TMP5="$(mktemp -d)"
TMP6="$(mktemp -d)"
TMP7="$(mktemp -d)"
TMP_OVR="$(mktemp -d)"
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6" "$TMP7" "$TMP_OVR"' EXIT

mk_project "$TMP1" liza_base-e63 liza_base-py4 liza_base-rhx
input_1=$'## A doc\n\nSee `liza_base-e63` for context. The fix landed in liza_base-py4. Also reference liza_base-rhx and liza_base-dead.\n'
out_1="$(run_helper "$TMP1" "$input_1")"
exit_1=$?

if [ "$exit_1" -eq 0 ]; then
  pass "case 1: helper exits 0 on success"
else
  fail "case 1: helper exit code" "(got $exit_1, expected 0; output: $out_1)"
fi
if echo "$out_1" | grep -qFx 'liza_base-dead'; then
  pass "case 1: dead ID reported (liza_base-dead)"
else
  fail "case 1: dead ID missing from output" "(output: $out_1)"
fi
for live in liza_base-e63 liza_base-py4 liza_base-rhx; do
  if echo "$out_1" | grep -qFx "$live"; then
    fail "case 1: live ID falsely flagged ($live)" "(output: $out_1)"
  else
    pass "case 1: live ID not flagged ($live)"
  fi
done

# ---------------------------------------------------------------------------
# Case 2: hyphen-only prefix (tla-puzzles-XXX) — already worked, regression guard
# ---------------------------------------------------------------------------

echo "==> Case 2: hyphen-in-prefix (tla-puzzles-XXX)"
mk_project "$TMP2" tla-puzzles-bwv tla-puzzles-abc
input_2=$'See [tla-puzzles-bwv](url) and tla-puzzles-abc.\nGhost: tla-puzzles-ghosthere.\n'
out_2="$(run_helper "$TMP2" "$input_2")"
if echo "$out_2" | grep -qFx 'tla-puzzles-ghosthere'; then
  pass "case 2: dead tla-puzzles ID reported"
else
  fail "case 2: dead tla-puzzles ID missing" "(output: $out_2)"
fi
for live in tla-puzzles-bwv tla-puzzles-abc; do
  if echo "$out_2" | grep -qFx "$live"; then
    fail "case 2: live tla-puzzles ID falsely flagged ($live)"
  else
    pass "case 2: live tla-puzzles ID not flagged ($live)"
  fi
done

# ---------------------------------------------------------------------------
# Case 3: short prefix (loom-XXX)
# ---------------------------------------------------------------------------

echo "==> Case 3: short prefix (loom-XXX)"
mk_project "$TMP3" loom-rsk loom-6m8
input_3='Prior art: loom-rsk, loom-6m8, loom-ghost.'
out_3="$(run_helper "$TMP3" "$input_3")"
if echo "$out_3" | grep -qFx 'loom-ghost'; then
  pass "case 3: dead loom ID reported"
else
  fail "case 3: dead loom ID missing" "(output: $out_3)"
fi
if echo "$out_3" | grep -qE '^(loom-rsk|loom-6m8)$'; then
  fail "case 3: live loom ID falsely flagged" "(output: $out_3)"
else
  pass "case 3: live loom IDs not flagged"
fi

# ---------------------------------------------------------------------------
# Case 4: dotted sub-suffix (loom-9z1.8) — must be treated as one ID
# ---------------------------------------------------------------------------

echo "==> Case 4: dotted sub-suffix preserved (loom-9z1.8)"
mk_project "$TMP4" loom-9z1 loom-9z1.8
input_4='Sub-bead: loom-9z1.8 belongs to loom-9z1. Ghost dot: loom-9z1.deadie.'
out_4="$(run_helper "$TMP4" "$input_4")"
if echo "$out_4" | grep -qFx 'loom-9z1.deadie'; then
  pass "case 4: dotted ghost ID reported"
else
  fail "case 4: dotted ghost ID missing" "(output: $out_4)"
fi
if echo "$out_4" | grep -qFx 'loom-9z1.8'; then
  fail "case 4: live dotted ID falsely flagged (loom-9z1.8)" "(output: $out_4)"
else
  pass "case 4: live dotted ID not flagged (loom-9z1.8)"
fi

# ---------------------------------------------------------------------------
# Case 5: empty stdin → empty output, exit 0
# ---------------------------------------------------------------------------

echo "==> Case 5: empty stdin → empty output"
mk_project "$TMP5" loom-abc loom-def
out_5="$(run_helper "$TMP5" "")"
exit_5=$?
if [ "$exit_5" -eq 0 ]; then
  pass "case 5: empty stdin exits 0"
else
  fail "case 5: empty stdin exit code" "(got $exit_5)"
fi
if [ -z "${out_5//[[:space:]]/}" ]; then
  pass "case 5: empty stdin → no output"
else
  fail "case 5: empty stdin produced output" "(output: $out_5)"
fi

# ---------------------------------------------------------------------------
# Case 6: all IDs resolve → empty dead-list
# ---------------------------------------------------------------------------

echo "==> Case 6: all IDs resolve → empty dead-list"
mk_project "$TMP6" loom-aaa loom-bbb loom-ccc
input_6='loom-aaa, loom-bbb, and loom-ccc all exist.'
out_6="$(run_helper "$TMP6" "$input_6")"
if [ -z "${out_6//[[:space:]]/}" ]; then
  pass "case 6: all-live → no output"
else
  fail "case 6: all-live produced output" "(output: $out_6)"
fi

# ---------------------------------------------------------------------------
# Case 7: deduplication — same dead ID cited 3x → reported once
# ---------------------------------------------------------------------------

echo "==> Case 7: dedup — same dead ID reported only once"
mk_project "$TMP7" loom-real
input_7='loom-ghost here. loom-ghost again. (loom-ghost) third.'
out_7="$(run_helper "$TMP7" "$input_7")"
ghost_count=$(echo "$out_7" | grep -cFx 'loom-ghost')
if [ "$ghost_count" -eq 1 ]; then
  pass "case 7: dedup — loom-ghost listed once (count=$ghost_count)"
else
  fail "case 7: dedup failed" "(loom-ghost count=$ghost_count, expected 1; output: $out_7)"
fi

# ---------------------------------------------------------------------------
# Case 8: explicit --prefix override (in case auto-detection fails)
# ---------------------------------------------------------------------------

echo "==> Case 8: --prefix override"
mkdir -p "$TMP_OVR/bin"
cat >"$TMP_OVR/bin/bd" <<'BD'
#!/usr/bin/env bash
if [ "${1:-}" = "show" ]; then
  case "${2:-}" in
    foo-aaa|foo-bbb) echo "ok"; exit 0 ;;
    *) echo "missing" >&2; exit 1 ;;
  esac
fi
exit 2
BD
chmod +x "$TMP_OVR/bin/bd"
input_8='foo-aaa, foo-bbb, foo-zzz.'
stdin_8=$(mktemp)
printf '%s' "$input_8" >"$stdin_8"
out_8="$(cd "$TMP_OVR" && PATH="$TMP_OVR/bin:$PATH" \
  bash "$HELPER" --prefix=foo <"$stdin_8" 2>&1)"
rm -f "$stdin_8"
if echo "$out_8" | grep -qFx 'foo-zzz'; then
  pass "case 8: --prefix override detects dead ID"
else
  fail "case 8: --prefix override failed" "(output: $out_8)"
fi
if echo "$out_8" | grep -qE '^(foo-aaa|foo-bbb)$'; then
  fail "case 8: --prefix override falsely flagged live IDs" "(output: $out_8)"
else
  pass "case 8: --prefix override: live IDs preserved"
fi

# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "RESULT: passed=$passed failed=$failed"
echo "============================================================"
[ "$failed" -eq 0 ]
