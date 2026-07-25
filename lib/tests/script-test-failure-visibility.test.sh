#!/usr/bin/env bash
# script/test failure legibility (loom-qo4j, part 2).
#
# THE BUG. script/test printed its verdict line — "…; FAILURES PRESENT" —
# on STDOUT, but the `FAILED: <path>` lines naming WHICH files failed on
# STDERR, emitted inline as each file finished. The natural idiom
#
#     script/test 2>&1 | tail
#
# therefore shows the ALARM and hides the CAUSE: the stderr FAILED: lines
# are interleaved hundreds of lines earlier, scrolled past the tail
# window, while the summary that survives says only that *something*
# failed.
#
# THIS ACTIVELY DEFEATED A PRIOR AGENT. loom-p5ee's dispatched worker
# reported a suite failure it could not diagnose — "FAILURES PRESENT"
# with no attributable file, green on six subsequent runs. The underlying
# red was the loom-qo4j clause-(c) false positive (uncommitted work at run
# time); the reason it read as an unreproducible mystery rather than a
# one-line diagnosis was this reporting gap.
#
# THE CONTRACT. The stdout summary block must NAME the failing files, so a
# `| tail` of either stream is self-sufficient. The stderr `FAILED: <path>`
# lines are KEPT verbatim — anything already parsing them keeps working;
# this is additive.
#
# script/test honors LOOM_TEST_DIR, so every assertion here runs against a
# tiny fixture directory rather than recursing on the real suite.
#
# Run:  bash lib/tests/script-test-failure-visibility.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_TEST="$LOOM_ROOT/script/test"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# Fixture: one passing file, one failing file. Both emit chatter so the
# scenario resembles a real run where per-file output separates the
# inline stderr FAILED: line from the summary.
mkdir -p "$FIX/mixed"
printf '#!/usr/bin/env bash\necho "  PASS: something"\nexit 0\n' \
  > "$FIX/mixed/aaa_happy.test.sh"
printf '#!/usr/bin/env bash\necho "  FAIL: something"\nexit 1\n' \
  > "$FIX/mixed/zzz_broken.test.sh"

mkdir -p "$FIX/green"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/green/aaa_happy.test.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/green/bbb_happy.test.sh"

if [ ! -x "$SCRIPT_TEST" ]; then
  fail "script/test is executable" "(missing or not +x: $SCRIPT_TEST)"
  echo ""
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi

# ---------------------------------------------------------------------
echo "==> failing run: the stdout summary names WHICH files failed"

LOOM_TEST_DIR="$FIX/mixed" "$SCRIPT_TEST" >"$FIX/out" 2>"$FIX/err"
rc=$?
out="$(cat "$FIX/out")"
err="$(cat "$FIX/err")"

if [ "$rc" -ne 0 ]; then
  pass "a failing fixture exits non-zero"
else
  fail "a failing fixture exits non-zero" "(exit was 0)"
fi

if printf '%s\n' "$out" | grep -q 'FAILURES PRESENT'; then
  pass "stdout still carries the FAILURES PRESENT verdict"
else
  fail "stdout still carries the FAILURES PRESENT verdict" \
    "(stdout:
$out)"
fi

# THE RED. Before the fix, the failing path appeared ONLY on stderr.
if printf '%s\n' "$out" | grep -q 'zzz_broken.test.sh'; then
  pass "stdout names the failing test file"
else
  fail "stdout names the failing test file" \
    "(the summary announces a failure without saying which file — the
loom-p5ee diagnosis gap; stdout:
$out)"
fi

# …and it must appear in the SUMMARY BLOCK (at or after the verdict
# line), which is what makes a plain \`| tail\` self-sufficient.
summary_block="$(printf '%s\n' "$out" | sed -n '/FAILURES PRESENT/,$p')"
if printf '%s\n' "$summary_block" | grep -q 'zzz_broken.test.sh'; then
  pass "the failing path sits in the trailing summary block (survives '| tail')"
else
  fail "the failing path sits in the trailing summary block (survives '| tail')" \
    "(named somewhere earlier, but not in the tail window; summary block:
$summary_block)"
fi

if printf '%s\n' "$summary_block" | grep -q 'aaa_happy.test.sh'; then
  fail "the summary lists ONLY failing files" \
    "(a passing file was listed as failed; summary block:
$summary_block)"
else
  pass "the summary lists ONLY failing files"
fi

# Back-compat: the stderr lines anything might already parse are kept.
if printf '%s\n' "$err" | grep -qE '^FAILED: .*zzz_broken\.test\.sh$'; then
  pass "stderr still emits the verbatim 'FAILED: <path>' line (additive fix)"
else
  fail "stderr still emits the verbatim 'FAILED: <path>' line (additive fix)" \
    "(the stderr contract was broken; stderr:
$err)"
fi

# ---------------------------------------------------------------------
echo "==> passing run: no failure noise on a green suite"

LOOM_TEST_DIR="$FIX/green" "$SCRIPT_TEST" >"$FIX/gout" 2>"$FIX/gerr"
grc=$?
gout="$(cat "$FIX/gout")"

if [ "$grc" -eq 0 ]; then
  pass "an all-passing fixture exits zero"
else
  fail "an all-passing fixture exits zero" "(exit was $grc)"
fi

if printf '%s\n' "$gout" | grep -q 'ALL GREEN'; then
  pass "stdout still carries the ALL GREEN verdict"
else
  fail "stdout still carries the ALL GREEN verdict" \
    "(stdout:
$gout)"
fi

if printf '%s\n' "$gout" | grep -q 'FAILED'; then
  fail "a green run names no failing files" \
    "(stdout mentions FAILED on an all-passing suite:
$gout)"
else
  pass "a green run names no failing files"
fi

# ---------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
