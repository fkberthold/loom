#!/usr/bin/env bash
# lib/tests/bd-claim-research.test.sh
#
# Fixture tests for hooks/bd-claim-research.sh bead-ID parsing.
#
# THE BUG (loom-6mf7). The hook extracted the bead ID with a hand-rolled
# character class:
#
#   grep -oE '[a-z][a-z0-9-]*-[a-z0-9]+\.?[a-z0-9]*'
#
# Two defects, both silent:
#
#   1. The prefix class admits `-` but NOT `_`, so a snake_case project
#      prefix truncates: `liza_base-6r49` parses as `base-6r49`. The
#      truncated ID is then handed to `bd show` (wrong bead / no bead)
#      and written into workflow-state.json as the claimed bead.
#   2. The dotted tail `\.?[a-z0-9]*` matches at most ONE level, so
#      `loom-ig3p.1` parses but `loom-z3m.1.4` truncates to `loom-z3m.1`.
#
# A third, louder symptom fell out of the same regex: with no minimum
# suffix length it matched prose/shell noise. Observed live during the
# loom-bbq7 investigation, where the hook fired on a command containing a
# `[a-z]` grep literal and announced "About to claim a-z".
#
# THE CONTRACT (the RED: line on loom-6mf7):
#   INVARIANT: a bead id whose project prefix contains an underscore
#   (liza_base-6r49) and one with a multi-level dotted tail
#   (loom-z3m.1.4) both round-trip unchanged through every bead-id parse
#   site in hooks/ and lib/.
#
# THE FIX. Unify onto lib/bd-id-extract.sh, which is immune BY
# CONSTRUCTION: it detects the project's bd prefix as a LITERAL string
# (from .beads/issues.jsonl) and anchors the scan on that literal, so the
# `_` vs `-` shape question never arises. The hook sources the lib
# through the standard TESTLIB-first ladder and calls
# `bd_id_detect_prefix` + `bd_id_scan`. When no prefix can be detected
# the hook falls back to a generic pattern that is underscore-aware AND
# carries the `{3,}` suffix minimum (so `a-z` no longer matches).
#
# Behavior explicitly pinned as UNCHANGED: the hook stays advisory —
# always exit 0, never blocks — and stays mode-aware (light/off silence
# it entirely).
#
# Run:  bash lib/tests/bd-claim-research.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"
HOOK="$LOOM_ROOT/hooks/bd-claim-research.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

TMPS=()
cleanup() { [ "${#TMPS[@]}" -gt 0 ] && rm -rf "${TMPS[@]}"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# mk_proj <mode> <seed-id>... — a project root carrying .beads/issues.jsonl
# (the prefix-detection source), a workflow.json pinning the mode, and a
# fake `bd` on PATH that answers `show` and `list`.
mk_proj() {
  local mode="$1"; shift
  local dir; dir=$(mktemp -d)
  TMPS+=("$dir")
  mkdir -p "$dir/.beads" "$dir/.claude" "$dir/bin"
  : >"$dir/.beads/issues.jsonl"
  local id
  for id in "$@"; do
    printf '{"id":"%s","title":"fixture","status":"open"}\n' "$id" \
      >>"$dir/.beads/issues.jsonl"
  done
  printf '{"v":1,"mode":"%s"}\n' "$mode" >"$dir/.claude/workflow.json"
  cat >"$dir/bin/bd" <<'BD'
#!/usr/bin/env bash
# Fake bd: `show <id>` prints a bug-typed record for seeded IDs;
# `list --limit 1 --json` echoes the first seeded record.
set -u
if [ "${1:-}" = "show" ]; then
  id="${2:-}"
  [ -n "$id" ] || exit 1
  [ -f .beads/issues.jsonl ] || exit 1
  if grep -qF "\"id\":\"$id\"" .beads/issues.jsonl 2>/dev/null; then
    echo "$id"
    echo "Type: bug"
    exit 0
  fi
  echo "Error: no issue found matching \"$id\"" >&2
  exit 1
fi
if [ "${1:-}" = "list" ]; then
  if [ ! -s .beads/issues.jsonl ]; then echo "[]"; exit 0; fi
  echo "["
  head -1 .beads/issues.jsonl
  echo "]"
  exit 0
fi
exit 0
BD
  chmod +x "$dir/bin/bd"
  echo "$dir"
}

# run_hook <proj> <command> — feed the hook a PreToolUse Bash payload.
# Sets HOOK_OUT (stdout+stderr) and RC. Deliberately NOT called via
# command substitution: RC set inside a `$( )` subshell would never
# reach the caller, silently defeating every exit-code assertion.
RC=0
HOOK_OUT=""
run_hook() {
  local proj="$1" cmd="$2"
  local payload tmp
  payload=$(CMD_TEXT="$cmd" python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD_TEXT"]}}))')
  tmp=$(mktemp)
  (cd "$proj" && PATH="$proj/bin:$PATH" HOME="$proj/fakehome" \
    bash "$HOOK" <<<"$payload" >"$tmp" 2>&1)
  RC=$?
  HOOK_OUT=$(cat "$tmp")
  rm -f "$tmp"
}

# claimed_id <hook-output> — the ID the hook announced, from the
# "About to claim <id>." sentence in additionalContext. The token runs to
# the next SPACE, not the next dot: bead IDs carry dotted sub-suffixes
# (loom-z3m.1.4) and a dot-terminated capture would silently truncate
# them here, in the harness, and mask the very defect under test.
claimed_id() {
  printf '%s' "$1" | grep -oE 'About to claim [^ ]+' | head -1 \
    | sed -E 's/^About to claim //; s/\.$//'
}

# state_bead <proj> — the bead field the hook wrote to workflow-state.json.
state_bead() {
  local f="$1/.claude/workflow-state.json"
  [ -f "$f" ] || { printf ''; return 0; }
  grep -oE '"bead"[[:space:]]*:[[:space:]]*("[^"]*"|null)' "$f" \
    | head -1 | sed -E 's/.*:[[:space:]]*//; s/^"//; s/"$//'
}

# ---------------------------------------------------------------------------
# 1. Snake_case project prefix must round-trip (the loom-6mf7 trigger)
# ---------------------------------------------------------------------------

echo "==> 1. snake_case prefix: liza_base-6r49 round-trips"

P1=$(mk_proj full liza_base-6r49 liza_base-e63)
run_hook "$P1" 'bd update liza_base-6r49 --claim'
out1="$HOOK_OUT"

if [ "$RC" -eq 0 ]; then
  pass "1: hook exits 0 (non-blocking)"
else
  fail "1: hook exit code" "(got $RC; output: $out1)"
fi

got1=$(claimed_id "$out1")
if [ "$got1" = "liza_base-6r49" ]; then
  pass "1: announced ID is liza_base-6r49"
else
  fail "1: snake_case prefix truncated" "(announced '$got1', expected 'liza_base-6r49')"
fi

sb1=$(state_bead "$P1")
if [ "$sb1" = "liza_base-6r49" ]; then
  pass "1: workflow-state bead is liza_base-6r49"
else
  fail "1: workflow-state bead wrong" "(got '$sb1', expected 'liza_base-6r49')"
fi

# ---------------------------------------------------------------------------
# 2. Multi-level dotted tail must round-trip
# ---------------------------------------------------------------------------

echo "==> 2. multi-level dotted tail: loom-z3m.1.4 round-trips"

P2=$(mk_proj full loom-z3m loom-z3m.1.4)
run_hook "$P2" 'bd update loom-z3m.1.4 --claim'
out2="$HOOK_OUT"

got2=$(claimed_id "$out2")
if [ "$got2" = "loom-z3m.1.4" ]; then
  pass "2: announced ID is loom-z3m.1.4"
else
  fail "2: dotted tail truncated" "(announced '$got2', expected 'loom-z3m.1.4')"
fi

# Single-level dotted tail is the regression guard for the same site.
P2b=$(mk_proj full loom-ig3p loom-ig3p.1)
run_hook "$P2b" 'bd update loom-ig3p.1 --claim'
out2b="$HOOK_OUT"
got2b=$(claimed_id "$out2b")
if [ "$got2b" = "loom-ig3p.1" ]; then
  pass "2: single-level dotted tail still round-trips (loom-ig3p.1)"
else
  fail "2: single-level dotted tail broke" "(announced '$got2b')"
fi

# ---------------------------------------------------------------------------
# 3. Plain hyphen prefix — regression guard for the common case
# ---------------------------------------------------------------------------

echo "==> 3. plain prefix: loom-6mf7 still parses"

P3=$(mk_proj full loom-6mf7)
run_hook "$P3" 'bd update loom-6mf7 --claim'
out3="$HOOK_OUT"
got3=$(claimed_id "$out3")
if [ "$got3" = "loom-6mf7" ]; then
  pass "3: announced ID is loom-6mf7"
else
  fail "3: plain prefix regressed" "(announced '$got3')"
fi

# Multi-hyphen prefix (HAW-style) — the loom-z3m.8 shape.
P3b=$(mk_proj full hundred-acre-woods-huu hundred-acre-woods-2st)
run_hook "$P3b" 'bd update hundred-acre-woods-huu --claim'
out3b="$HOOK_OUT"
got3b=$(claimed_id "$out3b")
if [ "$got3b" = "hundred-acre-woods-huu" ]; then
  pass "3: multi-hyphen prefix round-trips (hundred-acre-woods-huu)"
else
  fail "3: multi-hyphen prefix truncated" "(announced '$got3b')"
fi

# ---------------------------------------------------------------------------
# 4. No false positive on shell/prose noise (the "About to claim a-z" bug)
# ---------------------------------------------------------------------------

echo "==> 4. shell noise is not mistaken for a bead ID"

P4=$(mk_proj full loom-6mf7)
run_hook "$P4" "grep -oE '[a-z]' notes.txt; bd update loom-6mf7 --claim"
out4="$HOOK_OUT"
got4=$(claimed_id "$out4")
if [ "$got4" = "loom-6mf7" ]; then
  pass "4: grep literal '[a-z]' ignored; announced loom-6mf7"
else
  fail "4: shell noise parsed as the bead ID" "(announced '$got4', expected 'loom-6mf7')"
fi

# A foreign-prefix token in the command must not win over the project's own.
P4b=$(mk_proj full loom-6mf7)
run_hook "$P4b" 'bd update loom-6mf7 --claim --reason "see other-proj-xyz"'
out4b="$HOOK_OUT"
got4b=$(claimed_id "$out4b")
if [ "$got4b" = "loom-6mf7" ]; then
  pass "4: foreign-prefix token ignored"
else
  fail "4: foreign-prefix token won" "(announced '$got4b')"
fi

# ---------------------------------------------------------------------------
# 5. Mode-awareness is unchanged: light and off are silent
# ---------------------------------------------------------------------------

echo "==> 5. mode-awareness preserved (light/off silent)"

for m in light off; do
  PM=$(mk_proj "$m" liza_base-6r49)
  run_hook "$PM" 'bd update liza_base-6r49 --claim'
  outm="$HOOK_OUT"
  if [ "$RC" -eq 0 ] && [ -z "${outm//[[:space:]]/}" ]; then
    pass "5: mode=$m is silent and exits 0"
  else
    fail "5: mode=$m not silent" "(rc=$RC output: $outm)"
  fi
done

# ---------------------------------------------------------------------------
# 6. Non-blocking posture: never a non-zero exit, always valid JSON
# ---------------------------------------------------------------------------

echo "==> 6. non-blocking posture"

# 6a. A command that is not `bd update --claim` passes through silently.
P6=$(mk_proj full loom-6mf7)
run_hook "$P6" 'bd list --status=open'
out6="$HOOK_OUT"
if [ "$RC" -eq 0 ] && [ -z "${out6//[[:space:]]/}" ]; then
  pass "6a: non-claim command passes through silently"
else
  fail "6a: non-claim command produced output" "(rc=$RC output: $out6)"
fi

# 6b. A claim with no parseable ID still exits 0 with the placeholder.
P6b=$(mk_proj full loom-6mf7)
run_hook "$P6b" 'bd update --claim'
out6b="$HOOK_OUT"
if [ "$RC" -eq 0 ]; then
  pass "6b: unparseable claim exits 0"
else
  fail "6b: unparseable claim exit code" "(got $RC; output: $out6b)"
fi
if printf '%s' "$out6b" | grep -qF 'About to claim <bead>'; then
  pass "6b: unparseable claim uses the <bead> placeholder"
else
  fail "6b: placeholder missing" "(output: $out6b)"
fi

# 6c. Emitted stdout is valid JSON carrying the PreToolUse envelope.
P6c=$(mk_proj full liza_base-6r49)
run_hook "$P6c" 'bd update liza_base-6r49 --claim'
out6c="$HOOK_OUT"
if printf '%s' "$out6c" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="PreToolUse"; assert d["hookSpecificOutput"]["additionalContext"]' 2>/dev/null; then
  pass "6c: stdout is valid PreToolUse JSON"
else
  fail "6c: stdout is not valid PreToolUse JSON" "(output: $out6c)"
fi

# 6d. The bug-family-researcher instruction survives the refactor.
if printf '%s' "$out6c" | grep -qF 'bug-family-researcher'; then
  pass "6d: bug-family-researcher reminder preserved"
else
  fail "6d: bug-family-researcher reminder lost" "(output: $out6c)"
fi

# ---------------------------------------------------------------------------
# 7. Fallback path — prefix undetectable, generic pattern still correct
# ---------------------------------------------------------------------------

echo "==> 7. fallback when the bd prefix cannot be detected"

# Empty issues.jsonl + a fake bd whose `list` returns nothing usable, so
# prefix detection fails and the generic pattern must carry the case.
P7=$(mk_proj full)
run_hook "$P7" 'bd update liza_base-6r49 --claim'
out7="$HOOK_OUT"
got7=$(claimed_id "$out7")
if [ "$got7" = "liza_base-6r49" ]; then
  pass "7: fallback pattern round-trips liza_base-6r49"
else
  fail "7: fallback pattern truncated" "(announced '$got7', expected 'liza_base-6r49')"
fi

P7b=$(mk_proj full)
run_hook "$P7b" 'bd update loom-z3m.1.4 --claim'
out7b="$HOOK_OUT"
got7b=$(claimed_id "$out7b")
if [ "$got7b" = "loom-z3m.1.4" ]; then
  pass "7: fallback pattern round-trips loom-z3m.1.4"
else
  fail "7: fallback dotted tail truncated" "(announced '$got7b')"
fi

P7c=$(mk_proj full)
run_hook "$P7c" "grep -oE '[a-z]' n.txt; bd update loom-6mf7 --claim"
out7c="$HOOK_OUT"
got7c=$(claimed_id "$out7c")
if [ "$got7c" = "loom-6mf7" ]; then
  pass "7: fallback pattern rejects the 'a-z' noise match"
else
  fail "7: fallback pattern matched shell noise" "(announced '$got7c')"
fi

# ---------------------------------------------------------------------------
# 8. lib/bd-id-extract.sh is sourceable without side effects
# ---------------------------------------------------------------------------

echo "==> 8. lib/bd-id-extract.sh exposes reusable functions"

P8=$(mk_proj full liza_base-6r49 liza_base-e63)
probe=$(cd "$P8" && PATH="$P8/bin:$PATH" bash -c '
  . "'"$LOOM_ROOT"'/lib/bd-id-extract.sh"
  p=$(bd_id_detect_prefix "$PWD") || exit 3
  echo "prefix=$p"
  printf %s "bd update liza_base-6r49 --claim" | bd_id_scan "$p"
' 2>&1)
probe_rc=$?

if [ "$probe_rc" -eq 0 ]; then
  pass "8: sourcing the lib does not run the CLI (exit 0)"
else
  fail "8: sourcing the lib failed" "(rc=$probe_rc output: $probe)"
fi
if printf '%s' "$probe" | grep -qFx 'prefix=liza_base'; then
  pass "8: bd_id_detect_prefix returns the literal prefix"
else
  fail "8: bd_id_detect_prefix wrong" "(output: $probe)"
fi
if printf '%s' "$probe" | grep -qFx 'liza_base-6r49'; then
  pass "8: bd_id_scan extracts the full ID"
else
  fail "8: bd_id_scan did not extract the ID" "(output: $probe)"
fi

# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "RESULT: passed=$passed failed=$failed"
echo "============================================================"
[ "$failed" -eq 0 ]
