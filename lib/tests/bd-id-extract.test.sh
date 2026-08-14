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
# Lib ladder (loom-8ztk): the hook cases below must load the WORKTREE's
# lib/, not the installed ~/.claude/lib symlink into MAIN.
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"
HELPER="$LOOM_ROOT/lib/bd-id-extract.sh"
HOOK="$LOOM_ROOT/hooks/bd-claim-research.sh"

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

# ===========================================================================
# loom-ib6y — a bead-id scan must never return a FILENAME as a bead id.
#
# THE OBSERVED FAILURE (2026-08-14, live). Claiming loom-apcn, the
# bd-claim-research PreToolUse hook announced "About to claim
# loom-upstream.md." There is no such bead. The command carried the path
# `commands/check-loom-upstream.md`, and the scanner pulled
# `loom-upstream.md` out of it.
#
# TWO DEFECTS:
#   1. The dotted sub-id tail `(\.[a-z0-9]+)*` cannot tell a real bd
#      sub-id (loom-z3m.1.4) from a file extension (loom-upstream.md).
#      Any <prefix>-<word>.<ext> path parses as a bead id. This defect
#      lives in BOTH scan paths: the prefix-anchored `bd_id_pattern` in
#      lib/bd-id-extract.sh, and the generic fallback regex in
#      hooks/bd-claim-research.sh (used when the prefix is undetectable).
#   2. The hook scans the WHOLE command line — payloads included — and
#      takes `head -1`, so a path appearing BEFORE the operand of the
#      `bd update ... --claim` outranks the bead actually being claimed.
#
# THE CONTRACT (the RED: line on loom-ib6y):
#   INVARIANT: a bead-id scan over a command line never returns a
#   FILENAME as a bead id — given a command containing
#   `commands/check-loom-upstream.md` and the bead id `loom-apcn`,
#   `bd_id_scan loom-` returns `loom-apcn` and never `loom-upstream.md`;
#   a filename extension (`.md`, `.sh`, `.json`) is not a valid dotted
#   sub-id tail.
#
# SCOPE NOTE on defect 2. What is pinned here is the case the contract
# covers: a payload path that would otherwise WIN by position must not,
# and the operand must be the announced bead. The broader question — a
# payload carrying a legitimately-shaped bead id (`--description "see
# loom-xyz9"`) ahead of the operand — is NOT pinned, because separating
# operand from payload requires a design decision about how $CMD is
# sliced, not a test.
# ===========================================================================

# scan_ids <prefix> <text> — bd_id_scan over <text>, via the SOURCED lib
# (not the CLI), so the assertion is on the scan itself rather than on
# the dead-list filtering layered above it.
scan_ids() {
  local prefix="$1" text="$2"
  # shellcheck disable=SC1090
  printf '%s' "$text" | ( . "$HELPER" && bd_id_scan "$prefix" )
}

# filename_tails <scan-output> — every emitted token that ends in a
# filename extension. Non-empty means a filename parsed as a bead id.
filename_tails() {
  printf '%s\n' "$1" | grep -E '\.(md|sh|json)$' || true
}

# ---------------------------------------------------------------------------
# Case 9: prefix-anchored scan — filenames are not bead IDs
# ---------------------------------------------------------------------------

echo "==> Case 9: prefix-anchored scan rejects filenames (loom-ib6y)"

# 9a. The live failure, verbatim in shape.
cmd_9a='git add commands/check-loom-upstream.md && bd update loom-apcn --claim'
out_9a="$(scan_ids loom "$cmd_9a")"

if printf '%s\n' "$out_9a" | grep -qFx 'loom-upstream.md'; then
  fail "case 9a: filename returned as a bead ID (loom-upstream.md)" "(scan: $out_9a)"
else
  pass "case 9a: loom-upstream.md not returned as a bead ID"
fi
if printf '%s\n' "$out_9a" | grep -qFx 'loom-apcn'; then
  pass "case 9a: the real bead ID is still returned (loom-apcn)"
else
  fail "case 9a: real bead ID lost" "(scan: $out_9a)"
fi
# The hook takes head -1, so first-match IS the announced bead. This is
# the operand-vs-payload half of the contract at the lib level.
first_9a="$(printf '%s\n' "$out_9a" | head -1)"
if [ "$first_9a" = "loom-apcn" ]; then
  pass "case 9a: first match is the operand, not the payload path"
else
  fail "case 9a: payload path outranks the operand" "(first match '$first_9a', expected 'loom-apcn'; scan: $out_9a)"
fi

# 9b. .sh extension.
cmd_9b='bash lib/tests/loom-guest.test.sh; bd update loom-apcn --claim'
out_9b="$(scan_ids loom "$cmd_9b")"
bad_9b="$(filename_tails "$out_9b")"
if [ -z "${bad_9b//[[:space:]]/}" ]; then
  pass "case 9b: no .sh-tailed token returned"
else
  fail "case 9b: .sh filename returned as a bead ID" "(offending: $bad_9b; scan: $out_9b)"
fi
if [ "$(printf '%s\n' "$out_9b" | head -1)" = "loom-apcn" ]; then
  pass "case 9b: first match is the operand (loom-apcn)"
else
  fail "case 9b: .sh path outranks the operand" "(scan: $out_9b)"
fi

# 9c. .json extension.
cmd_9c='jq . .claude/loom-drift.json; bd update loom-apcn --claim'
out_9c="$(scan_ids loom "$cmd_9c")"
bad_9c="$(filename_tails "$out_9c")"
if [ -z "${bad_9c//[[:space:]]/}" ]; then
  pass "case 9c: no .json-tailed token returned"
else
  fail "case 9c: .json filename returned as a bead ID" "(offending: $bad_9c; scan: $out_9c)"
fi
if [ "$(printf '%s\n' "$out_9c" | head -1)" = "loom-apcn" ]; then
  pass "case 9c: first match is the operand (loom-apcn)"
else
  fail "case 9c: .json path outranks the operand" "(scan: $out_9c)"
fi

# ---------------------------------------------------------------------------
# Case 10: real dotted sub-IDs survive the extension rule
# ---------------------------------------------------------------------------
#
# The bug CLASS, not the instance: an over-broad fix that rejects every
# dotted tail would break real multi-level sub-beads. These must stay
# intact. (Case 4 above adds a further constraint the fix must respect:
# `loom-9z1.deadie` — an ALPHABETIC dotted tail that is not a filename
# extension — must still parse, so "numeric tails only" is not a legal
# fix either.)

echo "==> Case 10: real dotted sub-IDs survive (loom-ib6y)"

cmd_10='bd update loom-z3m.1.4 --claim  # rolls up loom-myhi.6 and loom-7p6.7'
out_10="$(scan_ids loom "$cmd_10")"
for want in loom-z3m.1.4 loom-myhi.6 loom-7p6.7; do
  if printf '%s\n' "$out_10" | grep -qFx "$want"; then
    pass "case 10: dotted sub-ID intact ($want)"
  else
    fail "case 10: dotted sub-ID lost or truncated ($want)" "(scan: $out_10)"
  fi
done

# ---------------------------------------------------------------------------
# Case 11: underscored prefix still works (loom-6mf7 regression guard)
# ---------------------------------------------------------------------------

echo "==> Case 11: underscored prefix not regressed (loom-ib6y / loom-6mf7)"

cmd_11='bd update liza_base-6r49 --claim'
out_11="$(scan_ids liza_base "$cmd_11")"
if printf '%s\n' "$out_11" | grep -qFx 'liza_base-6r49'; then
  pass "case 11: liza_base-6r49 round-trips unchanged"
else
  fail "case 11: underscored prefix truncated" "(scan: $out_11)"
fi
if printf '%s\n' "$out_11" | grep -qFx 'base-6r49'; then
  fail "case 11: prefix truncated to base-6r49" "(scan: $out_11)"
else
  pass "case 11: no base-6r49 truncation"
fi

# Underscored prefix + a filename that shares it.
cmd_11b='git add docs/liza_base-notes.md && bd update liza_base-6r49 --claim'
out_11b="$(scan_ids liza_base "$cmd_11b")"
bad_11b="$(filename_tails "$out_11b")"
if [ -z "${bad_11b//[[:space:]]/}" ]; then
  pass "case 11b: no filename token under an underscored prefix"
else
  fail "case 11b: filename returned under an underscored prefix" "(offending: $bad_11b; scan: $out_11b)"
fi
if [ "$(printf '%s\n' "$out_11b" | head -1)" = "liza_base-6r49" ]; then
  pass "case 11b: first match is the operand (liza_base-6r49)"
else
  fail "case 11b: payload path outranks the operand" "(scan: $out_11b)"
fi

# ---------------------------------------------------------------------------
# Case 12: the GENERIC FALLBACK regex (hooks/bd-claim-research.sh)
# ---------------------------------------------------------------------------
#
# The second code path. When no bd prefix is detectable the hook drops to
# a hand-rolled pattern that carries the SAME extension defect — and it
# is worse there, because with no prefix anchor a bare `some-config.json`
# parses as a bead id outright. Reached by a fixture whose issues.jsonl
# is empty and whose fake `bd list` yields nothing usable.

echo "==> Case 12: generic fallback regex rejects filenames (loom-ib6y)"

TMP_FB="$(mktemp -d)"
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6" "$TMP7" "$TMP_OVR" "$TMP_FB"' EXIT

mk_project "$TMP_FB"            # no seed IDs -> prefix undetectable
mkdir -p "$TMP_FB/.claude"
printf '{"v":1,"mode":"full"}\n' >"$TMP_FB/.claude/workflow.json"

# run_hook <proj> <command> — feed the hook a PreToolUse Bash payload
# against <proj>; sets HOOK_OUT.
HOOK_OUT=""
run_hook() {
  local proj="$1" cmd="$2" payload tmp
  payload=$(CMD_TEXT="$cmd" python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD_TEXT"]}}))')
  tmp=$(mktemp)
  (cd "$proj" && PATH="$proj/bin:$PATH" HOME="$proj/fakehome" \
    bash "$HOOK" <<<"$payload" >"$tmp" 2>&1)
  HOOK_OUT=$(cat "$tmp")
  rm -f "$tmp"
}

# claimed_id <hook-output> — the ID announced in "About to claim <id>."
# Captured to the next SPACE, not the next dot: a dot-terminated capture
# would truncate dotted sub-IDs here in the harness and mask the defect.
claimed_id() {
  printf '%s' "$1" | grep -oE 'About to claim [^ ]+' | head -1 \
    | sed -E 's/^About to claim //; s/\.$//'
}

# 12a. The live failure, through the fallback path.
run_hook "$TMP_FB" 'git add commands/check-loom-upstream.md && bd update loom-apcn --claim'
got_12a="$(claimed_id "$HOOK_OUT")"
if [ "$got_12a" = "loom-apcn" ]; then
  pass "case 12a: fallback announces the operand (loom-apcn)"
else
  fail "case 12a: fallback announced a filename" "(announced '$got_12a', expected 'loom-apcn')"
fi

# 12b. .sh extension.
run_hook "$TMP_FB" 'bash lib/tests/loom-guest.test.sh; bd update loom-apcn --claim'
got_12b="$(claimed_id "$HOOK_OUT")"
if [ "$got_12b" = "loom-apcn" ]; then
  pass "case 12b: fallback ignores a .sh path"
else
  fail "case 12b: fallback announced a .sh filename" "(announced '$got_12b', expected 'loom-apcn')"
fi

# 12c. .json extension, with NO project prefix in the filename at all —
# the shape only the unanchored fallback can mis-parse.
run_hook "$TMP_FB" 'jq . config/some-config.json; bd update loom-apcn --claim'
got_12c="$(claimed_id "$HOOK_OUT")"
if [ "$got_12c" = "loom-apcn" ]; then
  pass "case 12c: fallback ignores a .json path"
else
  fail "case 12c: fallback announced a .json filename" "(announced '$got_12c', expected 'loom-apcn')"
fi

# 12d/12e. Regression guards on the same fallback: the loom-6mf7 shapes
# must not be collateral damage of the extension rule.
run_hook "$TMP_FB" 'bd update liza_base-6r49 --claim'
got_12d="$(claimed_id "$HOOK_OUT")"
if [ "$got_12d" = "liza_base-6r49" ]; then
  pass "case 12d: fallback still round-trips liza_base-6r49"
else
  fail "case 12d: fallback truncated the underscored prefix" "(announced '$got_12d')"
fi

run_hook "$TMP_FB" 'bd update loom-z3m.1.4 --claim'
got_12e="$(claimed_id "$HOOK_OUT")"
if [ "$got_12e" = "loom-z3m.1.4" ]; then
  pass "case 12e: fallback still round-trips loom-z3m.1.4"
else
  fail "case 12e: fallback truncated the dotted tail" "(announced '$got_12e')"
fi

# ===========================================================================
# loom-ib6y (round 2) — an extension ENUMERATION is not the class.
#
# WHY THIS SECTION EXISTS. The first round of cases above (9-12) was
# turned GREEN by an allowlist: `BD_ID_FILE_EXTENSIONS`, ~35 entries
# (md, sh, bash, json, jsonl, yml, yaml, txt, py, js, jsx, ts, tsx, go,
# rb, java, c, h, cpp, hpp, rs, toml, ini, cfg, conf, log, csv, xml,
# html, css, scss, sql, lock, env, proto, swift, kt, php), rejecting a
# candidate whose LAST dotted segment is a member. Cases 9-12 pass
# because `.md`, `.sh` and `.json` are on the list — and ONLY because of
# that. Six extensions that are not on it (`.tf`, `.zig`, `.nix`,
# `.bats`, `.mdx`, `.tfvars`) reproduce the original bug intact.
#
# This is loom-6mf7's recorded finding restated: immunity is STRUCTURAL,
# not a better character class. An extension allowlist IS a character
# class wearing a different hat — it rots silently as new file types
# appear, and the rot reintroduces the exact defect. The cases below
# therefore use extensions deliberately absent from any plausible list,
# including an invented `.qqq`, so that no enumeration can satisfy them.
#
# TWO STRUCTURAL SHAPES, deliberately separated — they need different
# discrimination, and a fix for one need not cover the other.
#
#   PATH-EMBEDDED (cases 13-15). The candidate is not at a command-token
#   boundary: it is preceded by `/` (`infra/loom-cluster.tf`) or begins
#   mid-token after a `-` (`check-loom-upstream.md`, where the anchored
#   match starts at `loom-`). This IS decidable by syntax — the position
#   of the match within its token is a property of the input string, no
#   tracker lookup required.
#
#   BARE ARGUMENT (case 16). The candidate IS at a token boundary and is
#   still a filename: `git add loom-notes.qqq`. This is NOT decidable by
#   syntax — see the note below. It is pinned at the HOOK only, never at
#   the lib.
#
# WHY THE BARE-ARGUMENT SHAPE IS UNDECIDABLE BY SYNTAX. Compare
# `loom-notes.qqq` against `loom-9z1.deadie` from case 4. Same prefix,
# same alnum suffix shape, same alphabetic dotted tail, both at a token
# boundary — they are token-identical. The only fact that separates them
# is whether the id EXISTS in the tracker, which is semantics, not
# syntax. Any syntactic rule strong enough to reject `loom-notes.qqq`
# also rejects `loom-9z1.deadie`, and case 4 requires the latter to
# parse. So no rule over the input string alone can do it.
#
# THE POLARITY TRAP that follows from that, which any fix must respect:
# `bd_id_scan` has TWO callers wanting OPPOSITE things.
#   - `bd_id_extract_main` (audit-project Check 2a) wants candidates that
#     do NOT exist — those are the dead links it reports. Existence-
#     validation inside the scan would make its dead-list permanently
#     empty.
#   - `hooks/bd-claim-research.sh` wants the one candidate that DOES
#     exist — the bead being claimed.
# So existence-validation, if that is the chosen answer, belongs at the
# HOOK, not in the lib's scan. The lib's permissiveness is correct for
# its own caller.
#
# A NOTE FOR THE FIX (recorded, not implemented here).
# `hooks/bd-claim-research.sh` ALREADY calls `bd show "$BEAD_ID"`
# immediately after extraction, to read the bead's type. The ground
# truth — does this id exist in the tracker — is therefore already being
# fetched, just one step too late to reject a bogus candidate. Whether
# existence-validation is the right structural answer is the
# implementer's call; these cases are written to OUTCOMES (which id is
# returned / announced) rather than to any mechanism, so they neither
# require nor preclude it.
# ===========================================================================

# Extensions chosen to defeat enumeration: none is on the ~35-entry list,
# and `.qqq` is invented outright so no future list can plausibly carry it.
UNLISTED_EXTS="tf zig nix bats mdx tfvars qqq"

# ---------------------------------------------------------------------------
# Case 13: prefix-anchored scan — path-embedded, ANY extension
# ---------------------------------------------------------------------------

echo "==> Case 13: anchored scan rejects path-embedded filenames for ANY extension (loom-ib6y)"

# 13a. Slash-preceded: the candidate sits after a path separator.
for ext in $UNLISTED_EXTS; do
  cmd_13a="git add infra/loom-cluster.$ext && bd update loom-apcn --claim"
  out_13a="$(scan_ids loom "$cmd_13a")"
  first_13a="$(printf '%s\n' "$out_13a" | head -1)"
  if [ "$first_13a" = "loom-apcn" ]; then
    pass "case 13a: .$ext path-embedded filename rejected; operand wins"
  else
    fail "case 13a: .$ext path-embedded filename outranks the operand" "(first match '$first_13a', expected 'loom-apcn'; scan: $out_13a)"
  fi
done

# 13b. Mid-token after a `-`: the live 2026-08-14 shape, generalized off
# the three extensions the enumeration happens to cover.
for ext in tf zig qqq; do
  cmd_13b="git add commands/check-loom-upstream.$ext && bd update loom-apcn --claim"
  out_13b="$(scan_ids loom "$cmd_13b")"
  first_13b="$(printf '%s\n' "$out_13b" | head -1)"
  if [ "$first_13b" = "loom-apcn" ]; then
    pass "case 13b: .$ext mid-token filename rejected; operand wins"
  else
    fail "case 13b: .$ext mid-token filename outranks the operand" "(first match '$first_13b', expected 'loom-apcn'; scan: $out_13b)"
  fi
done

# ---------------------------------------------------------------------------
# Case 14: the HOOK, prefix-anchored path — path-embedded, ANY extension
# ---------------------------------------------------------------------------
#
# The live path: a project whose prefix IS detectable and whose bead
# loom-apcn really exists. This is the configuration that announced
# "About to claim loom-upstream.md" on 2026-08-14.

echo "==> Case 14: hook (anchored) announces the operand for ANY extension (loom-ib6y)"

TMP_HK="$(mktemp -d)"
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6" "$TMP7" "$TMP_OVR" "$TMP_FB" "$TMP_HK"' EXIT

mk_project "$TMP_HK" loom-apcn loom-z3m.1.4
mkdir -p "$TMP_HK/.claude"
printf '{"v":1,"mode":"full"}\n' >"$TMP_HK/.claude/workflow.json"

for ext in $UNLISTED_EXTS; do
  run_hook "$TMP_HK" "git add infra/loom-cluster.$ext && bd update loom-apcn --claim"
  got_14="$(claimed_id "$HOOK_OUT")"
  if [ "$got_14" = "loom-apcn" ]; then
    pass "case 14: hook ignores a .$ext path; announces loom-apcn"
  else
    fail "case 14: hook announced a .$ext filename" "(announced '$got_14', expected 'loom-apcn')"
  fi
done

# ---------------------------------------------------------------------------
# Case 15: the HOOK, fallback path — path-embedded, ANY extension
# ---------------------------------------------------------------------------

echo "==> Case 15: hook (fallback) announces the operand for ANY extension (loom-ib6y)"

for ext in $UNLISTED_EXTS; do
  run_hook "$TMP_FB" "git add infra/loom-cluster.$ext && bd update loom-apcn --claim"
  got_15="$(claimed_id "$HOOK_OUT")"
  if [ "$got_15" = "loom-apcn" ]; then
    pass "case 15: fallback ignores a .$ext path; announces loom-apcn"
  else
    fail "case 15: fallback announced a .$ext filename" "(announced '$got_15', expected 'loom-apcn')"
  fi
done

# ---------------------------------------------------------------------------
# Case 16: BARE ARGUMENT — pinned at the HOOK only
# ---------------------------------------------------------------------------
#
# `loom-notes.qqq` is at a command-token boundary and is token-identical
# to the real ghost id `loom-9z1.deadie` (case 4). No syntactic rule can
# separate them, so this is deliberately NOT asserted against
# `bd_id_scan` — only against the hook, which has a tracker to consult
# and an unambiguous right answer: the bead being claimed is loom-apcn.
#
# The fixture seeds loom-apcn so the correct answer is reachable: a hook
# that validates existence must still be able to announce it.

echo "==> Case 16: hook rejects a BARE filename argument (loom-ib6y)"

for ext in qqq tf zig; do
  run_hook "$TMP_HK" "git add loom-notes.$ext && bd update loom-apcn --claim"
  got_16="$(claimed_id "$HOOK_OUT")"
  if [ "$got_16" = "loom-apcn" ]; then
    pass "case 16: bare .$ext argument rejected; announces loom-apcn"
  else
    fail "case 16: bare .$ext argument announced as the bead" "(announced '$got_16', expected 'loom-apcn')"
  fi
done

# A bare argument with no extension at all, for the same reason: a
# tracker-absent token must not outrank a tracker-present one.
run_hook "$TMP_HK" 'git add loom-scratch && bd update loom-apcn --claim'
got_16b="$(claimed_id "$HOOK_OUT")"
if [ "$got_16b" = "loom-apcn" ]; then
  pass "case 16b: extensionless bare argument rejected; announces loom-apcn"
else
  fail "case 16b: extensionless bare argument announced as the bead" "(announced '$got_16b', expected 'loom-apcn')"
fi

# ---------------------------------------------------------------------------
# Case 17: polarity guard — the LIB must stay permissive for Check 2a
# ---------------------------------------------------------------------------
#
# The counterweight to cases 13-16. An over-broad fix that pushes
# existence-validation down into `bd_id_scan`, or that rejects every
# alphabetic dotted tail, would silently empty audit-project Check 2a's
# dead-list — the scan would stop reporting exactly the broken links it
# exists to find. These IDs are tracker-ABSENT by construction and must
# still be extracted.

echo "==> Case 17: lib stays permissive for prose/dead-link scanning (loom-ib6y)"

prose_17='Prior art: loom-9z1.deadie and loom-z3m.1.4 and loom-ghosty.'
out_17="$(scan_ids loom "$prose_17")"
for want in loom-9z1.deadie loom-z3m.1.4 loom-ghosty; do
  if printf '%s\n' "$out_17" | grep -qFx "$want"; then
    pass "case 17: prose ID still extracted ($want)"
  else
    fail "case 17: prose ID lost — Check 2a dead-list would go silent ($want)" "(scan: $out_17)"
  fi
done

# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "RESULT: passed=$passed failed=$failed"
echo "============================================================"
[ "$failed" -eq 0 ]
