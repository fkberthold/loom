#!/usr/bin/env bash
# Fixture tests for hooks/askuserquestion-option-cap.sh (loom-42cw.9).
#
# The gate half of D7, from the decision-routing design cycle
# (drawer_loom_decisions_97b8a01aa8d18d7a32e86c2d). D3 caps an ask at two
# authored options and reads a third as a diagnosis rather than a style
# problem, so the check has nothing for a human to weigh in on and gates
# instead of nudging (docs/explanation/gate-dont-advise.md).
#
# RED contract, D7's L3 spec verbatim:
#   Given an AskUserQuestion call carrying three or more authored options
#   When  the PreToolUse hook evaluates it
#   Then  the call is refused with exit 2 and the diagnosis is named
#
# The cap is PER QUESTION, not per call. D3 rests on choice-set findings
# (the attraction effect in numeric attribute matrices, and the repulsion
# result in Frederick, Lee and Baskin 2014), and a set is one question's
# option list. Two questions of two options each are two decisions, so
# they pass.
#
# Run:  bash lib/tests/askuserquestion-option-cap.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

HOOK="$LOOM_ROOT/hooks/askuserquestion-option-cap.sh"
SNIPPET="$LOOM_ROOT/settings.snippet.json"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -e "$HOOK" ]; then
  fail "hooks/askuserquestion-option-cap.sh exists" "not found at $HOOK"
  echo ""
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ERR="$TMP/stderr"

# ---------------------------------------------------------------------
# Payload builders. `ask N [N...]` builds an AskUserQuestion payload with
# one question per argument, carrying that many authored options.
# ---------------------------------------------------------------------
ask() {
  local qs="" q n i opts
  for n in "$@"; do
    opts=""
    for ((i = 1; i <= n; i++)); do
      [ -n "$opts" ] && opts="$opts,"
      opts="$opts{\"label\":\"opt$i\",\"description\":\"option $i\"}"
    done
    q="{\"question\":\"which one\",\"header\":\"Pick\",\"multiSelect\":false,\"options\":[$opts]}"
    [ -n "$qs" ] && qs="$qs,"
    qs="$qs$q"
  done
  printf '{"tool_name":"AskUserQuestion","tool_input":{"questions":[%s]}}' "$qs"
}

# run <payload> [VAR=VAL ...] — feed the payload on stdin, capture stderr
# in $ERR, echo nothing, return the hook's exit code.
run() {
  local payload="$1"; shift
  : > "$ERR"
  printf '%s' "$payload" | env "$@" bash "$HOOK" 2>"$ERR" >/dev/null
}

expect_rc() {
  local want="$1" desc="$2" payload="$3"; shift 3
  run "$payload" "$@"
  local rc=$?
  if [ "$rc" -eq "$want" ]; then
    pass "$desc (rc=$rc)"
  else
    fail "$desc: expected rc=$want, got rc=$rc" "$(cat "$ERR")"
  fi
}

# ---------------------------------------------------------------------
echo "==> 1. RED contract: three or more authored options are refused"
# ---------------------------------------------------------------------

expect_rc 2 "three options refused" "$(ask 3)"

run "$(ask 3)"
msg="$(cat "$ERR")"

if echo "$msg" | grep -qi "research"; then
  pass "refusal names the research branch of the diagnosis"
else
  fail "refusal does not name the research branch" "$msg"
fi

if echo "$msg" | grep -qi "more than one problem"; then
  pass "refusal names the more-than-one-problem branch of the diagnosis"
else
  fail "refusal does not name the more-than-one-problem branch" "$msg"
fi

if echo "$msg" | grep -qE '3 (authored )?options'; then
  pass "refusal reports the count it counted"
else
  fail "refusal does not report the option count" "$msg"
fi

# The count is read off the payload, not hardcoded at the cap.
run "$(ask 6)"
if grep -qE '6 (authored )?options' "$ERR"; then
  pass "refusal reports 6 for a six-option call"
else
  fail "refusal does not report the real count for a six-option call" "$(cat "$ERR")"
fi

expect_rc 2 "four options refused"  "$(ask 4)"
expect_rc 2 "six options refused"   "$(ask 6)"

# ---------------------------------------------------------------------
echo "==> 2. At or under the cap, the call passes through"
# ---------------------------------------------------------------------

expect_rc 0 "two options allowed" "$(ask 2)"
expect_rc 0 "one option allowed"  "$(ask 1)"
expect_rc 0 "empty options array allowed" "$(ask 0)"
expect_rc 0 "options key absent allowed" \
  '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"q"}]}}'
expect_rc 0 "questions key absent allowed" \
  '{"tool_name":"AskUserQuestion","tool_input":{}}'

# ---------------------------------------------------------------------
echo "==> 3. The cap is per question, not per call"
# ---------------------------------------------------------------------

expect_rc 0 "two questions of two options each allowed" "$(ask 2 2)"
expect_rc 2 "two questions, one carrying three, refused" "$(ask 2 3)"
expect_rc 2 "three questions, the last carrying five, refused" "$(ask 1 2 5)"

# ---------------------------------------------------------------------
echo "==> 4. Passthrough and fail-open"
# ---------------------------------------------------------------------

expect_rc 0 "a Bash call carrying the same shape is not this hook's business" \
  '{"tool_name":"Bash","tool_input":{"questions":[{"options":[1,2,3,4]}]}}'
expect_rc 0 "an Edit call passes through" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x"}}'
expect_rc 0 "malformed JSON fails open" '{"tool_name":"AskUserQuestion",'
expect_rc 0 "empty stdin fails open" ''
expect_rc 0 "a JSON array rather than an object fails open" '[1,2,3]'

# Neither counter available: the hook cannot prove a violation, so it
# must not block.
expect_rc 0 "no jq and no python3 fails open on a three-option call" \
  "$(ask 3)" "LOOM_JQ_BIN=$TMP/nope-jq" "LOOM_PY_BIN=$TMP/nope-py"

# ---------------------------------------------------------------------
echo "==> 5. The python3 rung counts the same as the jq rung"
# ---------------------------------------------------------------------

expect_rc 2 "python3 rung refuses three options"  "$(ask 3)" "LOOM_JQ_BIN=$TMP/nope-jq"
expect_rc 0 "python3 rung allows two options"     "$(ask 2)" "LOOM_JQ_BIN=$TMP/nope-jq"
expect_rc 0 "python3 rung fails open on malformed JSON" \
  '{"tool_name":"AskUserQuestion",' "LOOM_JQ_BIN=$TMP/nope-jq"

# ---------------------------------------------------------------------
echo "==> 6. Bypass matches the literal string 1 and nothing else"
# ---------------------------------------------------------------------

expect_rc 0 "bypass=1 lets three options through" \
  "$(ask 3)" "LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP=1"

for bad in yes true 0 "" 11; do
  expect_rc 2 "bypass=[$bad] is rejected" \
    "$(ask 3)" "LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP=$bad"
done

# ---------------------------------------------------------------------
echo "==> 7. Shipping surface"
# ---------------------------------------------------------------------

if [ -x "$HOOK" ]; then
  pass "hook file carries the executable bit"
else
  fail "hook file is not executable" "$(ls -l "$HOOK")"
fi

if grep -q 'askuserquestion-option-cap.sh' "$SNIPPET"; then
  pass "settings.snippet.json names the hook"
else
  fail "settings.snippet.json does not name the hook" \
    "a shipped hook nobody registers never runs (loom-kwkc)"
fi

if grep -q '"matcher": "AskUserQuestion"' "$SNIPPET"; then
  pass "settings.snippet.json registers an AskUserQuestion matcher"
else
  fail "settings.snippet.json has no AskUserQuestion matcher" "$(grep -n matcher "$SNIPPET")"
fi

# ---------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
