#!/usr/bin/env bash
# Fixture tests for scripts/loom-worktree-python.
#
# Closes loom-rsk: Mode 5 of the worktree-isolation failure cluster.
# `pip install -e <main>` installs the project as an editable
# site-package pointing at MAIN's source. When a dispatched worker
# invokes `python` from a linked worktree, Python's sys.path resolves
# the project module from the site-package (MAIN) instead of the
# worktree copy — so tests run against MAIN's code while pretending
# to verify the worktree's modifications. Silent and post-merge-only.
#
# The wrapper resolves this by prepending PYTHONPATH=$(pwd) and
# execing python3, so the worktree directory always wins sys.path
# resolution. The wrapper also refuses outside a linked worktree (use
# plain `python3` in main; the shadow is impossible there).
#
# Run:  bash lib/tests/loom-worktree-python.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$LOOM_ROOT/scripts/loom-worktree-python"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Skip the whole suite if python3 isn't available — the wrapper
# requires it and the failure-mode itself is python-specific.
if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not available"
  exit 0
fi

# Build a fixture: a "main" repo with the project source AND a
# simulated editable-install pointer (PYTHONPATH=$main) — plus a
# linked worktree containing the REAL (modified) copy of the same
# module.
#
# Layout per fixture:
#   $root/main/myproj/__init__.py    <- "main version" (the shadower)
#   $root/wt/myproj/__init__.py      <- "worktree version" (the target)
#
# PYTHONPATH=$main simulates the .pth entry that pip install -e adds
# to site-packages pointing at the main repo. The leak reproduces
# whenever python is invoked from a directory OTHER than $wt — which
# is the common case for pytest (rootdir resolution, subprocess
# tests, etc.). The wrapper prepends $(pwd) so the worktree copy
# wins regardless of caller cwd.
#
# echoes "main_dir wt_dir"
mk_worktree_with_shadowed_module() {
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt="$root/wt"
  mkdir -p "$main"

  (cd "$main" && git init -q && git config user.email t@t && git config user.name t)
  echo "seed" > "$main/seed.txt"
  (cd "$main" && git add seed.txt && git commit -q -m "seed")
  (cd "$main" && git worktree add -q "$wt" -b feature 2>&1 >/dev/null)

  # MAIN version of the module (the shadower — simulates the
  # editable-install target).
  mkdir -p "$main/myproj"
  cat > "$main/myproj/__init__.py" <<'PY'
VERSION = "main"
PY

  # WORKTREE version of the module (what the worker is supposed to
  # be testing).
  mkdir -p "$wt/myproj"
  cat > "$wt/myproj/__init__.py" <<'PY'
VERSION = "worktree"
PY

  printf '%s\t%s\n' "$main" "$wt"
}

# -------------------------------------------------------------------
# 1. Worktree copy wins over a shadowing editable install.
# -------------------------------------------------------------------

echo "==> 1. Worktree copy wins sys.path over shadowing site-package"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# Confirm the shadow is real: from a neutral cwd (not the worktree),
# with PYTHONPATH=$MAIN (simulating the leaked editable install),
# plain python3 picks the MAIN version. This mirrors what pytest
# does — it sets its own rootdir and uses installed entry points,
# so the worktree's cwd is not on sys.path[0].
NEUTRAL=$(mktemp -d)
shadow_out=$(cd "$NEUTRAL" && PYTHONPATH="$MAIN" python3 -c 'import myproj; print(myproj.VERSION)' 2>&1)
if [ "$shadow_out" = "main" ]; then
  pass "shadow reproduces: plain python3 picks editable-install version"
else
  fail "shadow setup broken — expected 'main', got '$shadow_out'"
fi
rm -rf "$NEUTRAL"

# The wrapper must beat the shadow: it sets cwd-of-worktree on
# PYTHONPATH so the worktree copy wins. The wrapper resolves the
# worktree toplevel internally — cwd of the CALLER doesn't matter.
NEUTRAL=$(mktemp -d)
out=$(cd "$WT" && PYTHONPATH="$MAIN" "$WRAPPER" -c 'import myproj; print(myproj.VERSION)' 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "worktree" ]; then
  pass "wrapper: worktree copy wins (got '$out')"
else
  fail "wrapper didn't beat the shadow. rc=$rc out='$out'"
fi

# The __file__ check that the bead recommends as a smoke test should
# also point at the worktree.
file_out=$(cd "$WT" && PYTHONPATH="$MAIN" "$WRAPPER" -c 'import myproj; print(myproj.__file__)' 2>&1)
case "$file_out" in
  "$WT"/*) pass "wrapper: myproj.__file__ resolves under worktree ($file_out)" ;;
  *) fail "wrapper: __file__ NOT under worktree. got: $file_out" ;;
esac
rm -rf "$NEUTRAL"

rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 2. No site-package shadow → wrapper still works (passthrough-ish).
# -------------------------------------------------------------------

echo "==> 2. No shadow → wrapper still resolves worktree copy"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# Unset PYTHONPATH entirely. Call from a neutral cwd to verify the
# wrapper finds the worktree by git resolution (not by inheriting cwd).
NEUTRAL=$(mktemp -d)
out=$(cd "$WT" && env -u PYTHONPATH "$WRAPPER" -c 'import myproj; print(myproj.VERSION)' 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "worktree" ]; then
  pass "no-shadow path: worktree copy resolved"
else
  fail "no-shadow path broken. rc=$rc out='$out'"
fi
rm -rf "$NEUTRAL"
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 3. Existing PYTHONPATH is preserved (prepended, not replaced).
# -------------------------------------------------------------------

echo "==> 3. Existing PYTHONPATH preserved (prepended, not clobbered)"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# A second module only on $MAIN that's NOT in the worktree — wrapper
# should still find it via the preserved PYTHONPATH suffix.
mkdir -p "$MAIN/extralib"
cat > "$MAIN/extralib/__init__.py" <<'PY'
TAG = "from-site"
PY

out=$(cd "$WT" && PYTHONPATH="$MAIN" "$WRAPPER" -c 'import extralib; print(extralib.TAG)' 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "from-site" ]; then
  pass "extralib resolvable through preserved PYTHONPATH suffix"
else
  fail "wrapper dropped PYTHONPATH suffix. rc=$rc out='$out'"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 4. Refuses outside a linked worktree (run from main repo).
# -------------------------------------------------------------------

echo "==> 4. Refuses outside a linked worktree"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(cd "$MAIN" && "$WRAPPER" -c 'print(1)' 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qiE "worktree|main"; then
  pass "main repo: wrapper refuses with rc != 0 + helpful message"
else
  fail "main repo: expected refusal, got rc=$rc out=$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 5. Refuses outside any git tree (cwd is /tmp).
# -------------------------------------------------------------------

echo "==> 5. Refuses outside a git working tree entirely"

NONGIT=$(mktemp -d)
out=$(cd "$NONGIT" && "$WRAPPER" -c 'print(1)' 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qiE "worktree|working tree|git"; then
  pass "non-git dir: wrapper refuses with rc != 0"
else
  fail "non-git dir: expected refusal, got rc=$rc out=$out"
fi
rm -rf "$NONGIT"

# -------------------------------------------------------------------
# 6. Exit code passthrough: python's exit code reaches the caller.
# -------------------------------------------------------------------

echo "==> 6. python exit code passes through"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

out=$(cd "$WT" && "$WRAPPER" -c 'import sys; sys.exit(7)' 2>&1); rc=$?
if [ "$rc" -eq 7 ]; then
  pass "exit code 7 passed through"
else
  fail "exit code not passed through. rc=$rc (expected 7)"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 7. Bug-class: -m module invocation (pytest's usual entry shape).
# -------------------------------------------------------------------

echo "==> 7. Bug class: 'python -m' style invocation wins worktree copy"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# Add a runnable __main__ module to both versions.
cat > "$MAIN/myproj/__main__.py" <<'PY'
import myproj
print(myproj.VERSION)
PY
cat > "$WT/myproj/__main__.py" <<'PY'
import myproj
print(myproj.VERSION)
PY

# Reproduce the shadow with -m from a neutral cwd.
NEUTRAL=$(mktemp -d)
shadow=$(cd "$NEUTRAL" && PYTHONPATH="$MAIN" python3 -m myproj 2>&1)
if [ "$shadow" = "main" ]; then
  pass "-m shadow reproduces (main version runs)"
else
  fail "-m shadow setup unexpected — got: '$shadow'"
fi

# Wrapper invoked with -m must pick the worktree version. Run from
# $NEUTRAL to prove the wrapper resolves the worktree by git, not cwd.
out=$(cd "$WT" && PYTHONPATH="$MAIN" "$WRAPPER" -m myproj 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "worktree" ]; then
  pass "wrapper -m: worktree __main__ runs"
else
  fail "wrapper -m broken. rc=$rc out='$out'"
fi
rm -rf "$NEUTRAL"
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 8. Bug-class: nested subpackage shadowing.
# -------------------------------------------------------------------

echo "==> 8. Bug class: nested subpackage shadow"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# myproj/sub/__init__.py exists in both; differ on a TAG.
mkdir -p "$MAIN/myproj/sub" "$WT/myproj/sub"
echo 'TAG = "main-sub"'     > "$MAIN/myproj/sub/__init__.py"
echo 'TAG = "worktree-sub"' > "$WT/myproj/sub/__init__.py"

out=$(cd "$WT" && PYTHONPATH="$MAIN" "$WRAPPER" -c 'from myproj.sub import TAG; print(TAG)' 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "worktree-sub" ]; then
  pass "nested subpackage: worktree wins"
else
  fail "nested subpackage broken. rc=$rc out='$out'"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 9. Bug-class: script-file invocation (python wrapper script.py).
# -------------------------------------------------------------------

echo "==> 9. Bug class: script-file invocation under worktree"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# A script that imports myproj — placed inside the worktree.
cat > "$WT/runner.py" <<'PY'
import myproj
print(myproj.VERSION)
PY

# When python3 runs a script file, sys.path[0] is the script's
# directory (the worktree). The shadow still applies if the script
# imports a package that's also on PYTHONPATH/site — but with the
# wrapper's explicit prepend, the worktree wins unambiguously.
out=$(cd "$WT" && PYTHONPATH="$MAIN" "$WRAPPER" runner.py 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "worktree" ]; then
  pass "script-file invocation: worktree copy wins"
else
  fail "script-file invocation broken. rc=$rc out='$out'"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 10. Caller cwd is OUTSIDE the worktree — wrapper refuses.
#     (Worker mistakenly cd'd elsewhere before calling the wrapper.)
# -------------------------------------------------------------------

echo "==> 10. Caller outside any worktree → refuses cleanly"

FX=$(mk_worktree_with_shadowed_module)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)

# Caller is in a non-git dir. The wrapper depends on git resolution,
# so it must refuse rather than silently failing or running with
# unset toplevel.
NEUTRAL=$(mktemp -d)
out=$(cd "$NEUTRAL" && "$WRAPPER" -c 'print(1)' 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "cwd outside any worktree: wrapper refuses (rc=$rc)"
else
  fail "wrapper should have refused, rc=$rc out=$out"
fi
rm -rf "$NEUTRAL"
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
