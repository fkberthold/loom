#!/usr/bin/env bash
# RED→GREEN contract for loom-yuy6: script/test must run ALL test files,
# never the glob-positional false-green that runs only the first.
#
# THE BUG: canonical_commands.test was `bash lib/tests/*.test.sh`. The
# glob expands to `bash f1 f2 ... f86` — bash runs ONLY f1 (the rest
# become its positional args), exits 0, and the suite LOOKS green while
# 85 files never ran. Surfaced by dogfooding the oxs.5 /wrap-up resolver
# path (loom_resolve_command test → `bash -c "$cmd"` → 1/86).
#
# THE FIX: an executable `script/test` (resolver rung-1) that LOOPS over
# lib/tests/*.test.sh, running each file separately and propagating a
# non-zero exit if ANY file fails.
#
# INVARIANT (verbatim from the bead's RED: line):
#   running the project's resolved test command executes ALL
#   lib/tests/*.test.sh files (failure in any propagates a non-zero
#   exit), NOT just the first; a bare `bash <glob>` that runs only
#   file1 is forbidden.
#
# RECURSION SAFETY: script/test defaults to the real lib/tests dir, but
# honors a LOOM_TEST_DIR override so this test can point it at a tiny
# fixture (2 files) instead of re-running the whole suite (which would
# recurse, since this file lives in lib/tests/). The functional
# assertions use that override.
#
# Run:  bash lib/tests/script-test-runs-full-suite.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_TEST="$LOOM_ROOT/script/test"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# ---------------------------------------------------------------------------
echo "==> script/test exists and is executable (resolver rung-1)"
if [ -f "$SCRIPT_TEST" ]; then
  pass "script/test exists"
else
  fail "script/test exists" "(missing: $SCRIPT_TEST)"
fi
if [ -x "$SCRIPT_TEST" ]; then
  pass "script/test is executable"
else
  fail "script/test is executable" "(not +x — resolver rung-1 requires executable)"
fi

# ---------------------------------------------------------------------------
echo "==> anti-pattern guard: script/test does NOT use a bare 'bash <glob>'"
# The exact false-green form. script/test must loop, not hand the glob to
# a single bash invocation.
if [ -f "$SCRIPT_TEST" ]; then
  if grep -qE 'bash[[:space:]]+("?\$?\{?[A-Za-z_]*\}?/?)*\*\.test\.sh' "$SCRIPT_TEST" \
     && ! grep -qE 'for[[:space:]]' "$SCRIPT_TEST"; then
    fail "script/test avoids the bare 'bash <glob>' false-green" \
      "(found a bare glob handed to bash, with no loop)"
  else
    pass "script/test avoids the bare 'bash <glob>' false-green"
  fi
  if grep -qE 'for[[:space:]]+[A-Za-z_]+[[:space:]]+in' "$SCRIPT_TEST" \
     && grep -qE 'bash[[:space:]]+"?\$' "$SCRIPT_TEST"; then
    pass "script/test loops, invoking bash per-file (bash \"\$f\")"
  else
    fail "script/test loops, invoking bash per-file" \
      "(no for-loop with a per-file 'bash \$f' invocation found)"
  fi
else
  fail "script/test avoids the bare 'bash <glob>' false-green" "(no script/test)"
  fail "script/test loops, invoking bash per-file" "(no script/test)"
fi

# ---------------------------------------------------------------------------
echo "==> functional: a failure in ANY file propagates non-zero (runs all, not just file1)"
# Fixture: a PASSING first file + a FAILING second file. A runner that
# stops after file1 would exit 0 (false green). The fix must exit
# non-zero because it reaches and runs the failing second file.
mkdir -p "$FIX/all_or_nothing"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/all_or_nothing/aaa_first.test.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FIX/all_or_nothing/zzz_second.test.sh"
if [ -x "$SCRIPT_TEST" ]; then
  LOOM_TEST_DIR="$FIX/all_or_nothing" "$SCRIPT_TEST" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "pass-then-fail fixture → non-zero exit (reached the 2nd file)"
  else
    fail "pass-then-fail fixture → non-zero exit" \
      "(exit was 0 — runner stopped after the first file: the false-green bug)"
  fi
else
  fail "pass-then-fail fixture → non-zero exit" "(no executable script/test)"
fi

# ---------------------------------------------------------------------------
echo "==> functional: all-passing fixture → zero exit"
mkdir -p "$FIX/all_pass"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/all_pass/a.test.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/all_pass/b.test.sh"
if [ -x "$SCRIPT_TEST" ]; then
  LOOM_TEST_DIR="$FIX/all_pass" "$SCRIPT_TEST" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "all-passing fixture → zero exit"
  else
    fail "all-passing fixture → zero exit" "(exit was $rc on two passing files)"
  fi
else
  fail "all-passing fixture → zero exit" "(no executable script/test)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="
[ "$failed" -eq 0 ]
