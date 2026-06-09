#!/usr/bin/env bash
# Fixture tests for the INSTALLED-symlink sourcing path of loom's hooks.
#
# Closes loom-fxad: the installed git hooks (.git/hooks/post-rewrite,
# .git/hooks/pre-push) are SYMLINKS into this repo's hooks/*.sh. When git
# runs a hook, BASH_SOURCE[0] is the .git/hooks/<name> symlink path, so a
# fallback source of the form
#
#     . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"
#
# resolves to .git/lib/loom-hook-helpers.sh — which does NOT exist. The
# hooks therefore only work via the PRIMARY source
# ($HOME/.claude/lib/loom-hook-helpers.sh), which exists only after
# install.sh symlinks it; any window before that re-runs leaves the
# installed hooks broken (`loom_env_enabled: command not found`).
#
# The fix resolves the fallback THROUGH the symlink with readlink -f:
#
#     . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
#
# so dirname/../lib lands on the REPO's lib/ even when invoked via a
# .git/hooks symlink. For a non-symlink (direct) invocation, readlink -f
# of a regular file returns its own canonical path, so repo-path
# resolution is unchanged (behavior preserved — the existing hook test
# suites prove that).
#
# This test exercises the symlink invocation path that every other hook
# test misses (they all invoke the repo hook DIRECTLY, where the
# fallback already happens to resolve). It forces the PRIMARY source to
# be unavailable by pointing HOME at an empty temp dir, so the BASH_SOURCE
# fallback is the only path that can succeed.
#
# RED against pre-fix main: fallback resolves to the missing .git/lib/ ->
# `command not found`. GREEN after the readlink -f fix.
#
# Run:  bash lib/tests/hook-symlink-sourcing.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Representative hook that sources the helper near the top of its body
# (so the source line is reached before any bd/git no-op guards).
HOOK="$LOOM_ROOT/hooks/post-rewrite.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ----------------------------------------------------------------------
# Build a fake .git/hooks/ dir with a SYMLINK to the repo hook, exactly
# as install.sh wires the installed hooks. The symlink lives OUTSIDE the
# repo's hooks/ dir so that ../lib from the symlink's own location does
# NOT accidentally reach the repo's lib/.
# ----------------------------------------------------------------------
FAKE_GIT=$(mktemp -d)            # acts as a .git/ dir
mkdir -p "$FAKE_GIT/hooks"
HOOK_LINK="$FAKE_GIT/hooks/post-rewrite"
ln -s "$HOOK" "$HOOK_LINK"

# Empty HOME so $HOME/.claude/lib/loom-hook-helpers.sh does NOT exist —
# this forces the BASH_SOURCE fallback to be the only viable source path.
EMPTY_HOME=$(mktemp -d)
# Sanity: the primary source target must be absent under EMPTY_HOME.
if [ ! -e "$EMPTY_HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  pass "primary source ($EMPTY_HOME/.claude/lib/...) is absent (fallback forced)"
else
  fail "EMPTY_HOME unexpectedly contains .claude/lib/loom-hook-helpers.sh"
fi

# Sanity: the naive fallback target (.git/lib/ alongside the symlink) is
# absent — this is the missing path the unfixed fallback would hit.
if [ ! -e "$FAKE_GIT/lib/loom-hook-helpers.sh" ]; then
  pass "naive fallback target (.git/lib/loom-hook-helpers.sh) is absent"
else
  fail "fake .git unexpectedly contains lib/loom-hook-helpers.sh"
fi

# ----------------------------------------------------------------------
# 1. Invoke the REAL hook THROUGH the symlink with HOME forced empty.
#    No `command not found` must appear on stderr — that is the symptom
#    of the fallback resolving to the missing .git/lib/ and the helper
#    functions never being defined.
# ----------------------------------------------------------------------
echo "==> 1. Real hook invoked through symlink (HOME empty): no 'command not found'"

WORK=$(mktemp -d)
(cd "$WORK" && git init -q -b main 2>/dev/null \
   && git config user.email t@t && git config user.name t)

# Run the symlinked hook from a throwaway git repo. The hook will no-op
# on its bd logic (no .beads/), but it MUST first source the helper and
# call loom_env_enabled — which is exactly where the bug bites.
out=$(cd "$WORK" && HOME="$EMPTY_HOME" bash "$HOOK_LINK" rebase </dev/null 2>&1); rc=$?

if echo "$out" | grep -qi "command not found"; then
  fail "symlinked hook emitted 'command not found' (helper not sourced)" "$out"
else
  pass "symlinked hook: no 'command not found' on stderr"
fi

if echo "$out" | grep -qi "No such file or directory"; then
  fail "symlinked hook: fallback source hit a missing path" "$out"
else
  pass "symlinked hook: no missing-source 'No such file or directory'"
fi

# ----------------------------------------------------------------------
# 2. The helper functions are actually DEFINED + usable after the
#    symlinked-hook sourcing line runs. We can't inspect the hook's own
#    subshell, so we replicate the EXACT sourcing idiom from the hook in
#    a probe that runs THROUGH the same symlink path, with HOME empty,
#    then asserts loom_env_enabled and json_get are callable.
# ----------------------------------------------------------------------
echo "==> 2. Helper functions defined/usable via the symlink fallback path"

# Build a faithful MIRROR of the repo layout: a probe hook at
# <repo>/hooks/probe-real.sh next to a <repo>/lib/loom-hook-helpers.sh.
# This mirrors how a real installed hook sits in hooks/ with the helper
# one level up in lib/ — so when readlink -f resolves the symlink to the
# probe's real location, dirname/../lib reaches the (mirrored) helper.
# The mirror's lib/ holds a SYMLINK to the real helper, so we test the
# actual helper's functions, not a copy.
FAKE_REPO=$(mktemp -d)
mkdir -p "$FAKE_REPO/hooks" "$FAKE_REPO/lib"
ln -s "$LOOM_ROOT/lib/loom-hook-helpers.sh" "$FAKE_REPO/lib/loom-hook-helpers.sh"

# Extract the `. primary || fallback` sourcing idiom verbatim from the
# representative hook so the probe sources EXACTLY what the hook does
# (stripping the shellcheck comment lines). The probe is reached THROUGH
# a .git/hooks symlink so BASH_SOURCE[0] inside it is the symlink path —
# the unfixed fallback would point at .git/lib/ (absent), the fixed one
# resolves through readlink -f to the mirror's hooks/, then ../lib.
SRC_LINES=$(grep -nE 'loom-hook-helpers\.sh' "$HOOK" \
  | grep -vE '^\s*[0-9]+:\s*#' | sed -E 's/^[0-9]+://')

PROBE_REAL="$FAKE_REPO/hooks/probe-real.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -uo pipefail'
  printf '%s\n' "$SRC_LINES"
  # Use the helpers — if they are undefined, these calls fail with
  # `command not found` and the declare checks below print MISSING.
  echo 'declare -F loom_env_enabled >/dev/null 2>&1 && echo "HAVE loom_env_enabled" || echo "MISSING loom_env_enabled"'
  echo 'declare -F json_get >/dev/null 2>&1 && echo "HAVE json_get" || echo "MISSING json_get"'
  # Exercise loom_env_enabled for real (literal-1 gate).
  echo 'if FOO=1 loom_env_enabled FOO; then echo "loom_env_enabled FOO=1 -> true"; else echo "loom_env_enabled FOO=1 -> FALSE"; fi'
  # Exercise json_get for real.
  echo 'echo "json_get => $(printf %s "{\"tool_name\":\"Bash\"}" | json_get .tool_name tool_name)"'
} > "$PROBE_REAL"
chmod +x "$PROBE_REAL"

# The installed-hook symlink: .git/hooks/probe-link -> <repo>/hooks/probe-real.sh
PROBE_LINK="$FAKE_GIT/hooks/probe-link"
ln -s "$PROBE_REAL" "$PROBE_LINK"

probe_out=$(HOME="$EMPTY_HOME" bash "$PROBE_LINK" 2>&1); probe_rc=$?

if echo "$probe_out" | grep -q "HAVE loom_env_enabled"; then
  pass "loom_env_enabled defined after symlink-fallback source"
else
  fail "loom_env_enabled NOT defined via symlink fallback" "$probe_out"
fi

if echo "$probe_out" | grep -q "HAVE json_get"; then
  pass "json_get defined after symlink-fallback source"
else
  fail "json_get NOT defined via symlink fallback" "$probe_out"
fi

if echo "$probe_out" | grep -qi "command not found"; then
  fail "probe emitted 'command not found' (helper unusable)" "$probe_out"
else
  pass "probe: no 'command not found'"
fi

if echo "$probe_out" | grep -q "loom_env_enabled FOO=1 -> true"; then
  pass "loom_env_enabled is callable + correct via symlink fallback"
else
  fail "loom_env_enabled not callable/correct via symlink fallback" "$probe_out"
fi

if echo "$probe_out" | grep -q "json_get => Bash"; then
  pass "json_get is callable + correct via symlink fallback"
else
  fail "json_get not callable/correct via symlink fallback" "$probe_out"
fi

# ----------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------
rm -rf "$FAKE_GIT" "$FAKE_REPO" "$EMPTY_HOME" "$WORK"

# ----------------------------------------------------------------------
echo ""
echo "Total: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
