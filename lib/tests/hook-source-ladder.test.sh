#!/usr/bin/env bash
# lib/tests/hook-source-ladder.test.sh
#
# THE GATE: every hook that sources a lib/ file must resolve
# LOOM_TEST_LIB_DIR FIRST (loom-8ztk).
#
# THE BUG. `install.sh` installs `~/.claude/lib/*` as SYMLINKS into the
# loom repo's MAIN checkout. A hook that sources
# `$HOME/.claude/lib/loom-hook-helpers.sh` from inside a dispatched
# worker's worktree therefore loads MAIN's copy of the helper — not the
# worktree's. A worker that modifies `lib/` and runs the hook tests gets
# tests that silently exercise MAIN's code while appearing to verify its
# own work.
#
# This is the BASH flavor of the Python-import shadow already documented
# in `.claude/rules/dispatched-agents.md` ("Python import resolution",
# loom-rsk Mode 5): same dishonest-verification failure, different
# runtime. `scripts/loom-worktree-python` is the mechanical fix on the
# Python side; the TESTLIB-first source ladder is the mechanical fix on
# the bash side.
#
# THE CONTRACT (the RED: line on loom-8ztk):
#   INVARIANT: every hook in `hooks/` that sources a `lib/` file resolves
#   `LOOM_TEST_LIB_DIR` FIRST when it is set and the file exists there,
#   before `$HOME/.claude/lib` and before the repo-relative fallback; a
#   gate in `script/test` fails naming any hook that does not.
#
# The canonical ladder shape (see hooks/loom-drift-nudge.sh,
# hooks/constitution-enforce.sh):
#
#   if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/<lib>" ]; then
#     . "$LOOM_TEST_LIB_DIR/<lib>"
#   elif [ -f "$HOME/.claude/lib/<lib>" ]; then
#     . "$HOME/.claude/lib/<lib>"
#   else
#     . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/<lib>"
#   fi
#
# ...or the assign-then-source variant used where the fallback rung is
# deliberately absent (fail-open), e.g. hooks/dispatch-nudge.sh:
#
#   if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/<lib>" ]; then
#     WFS_LIB="$LOOM_TEST_LIB_DIR/<lib>"
#   elif ...
#
# Both satisfy the gate: what is checked is that the guarded
# LOOM_TEST_LIB_DIR rung for a given lib appears BEFORE any
# `$HOME/.claude/lib/<lib>` or `../lib/<lib>` reference in the same file.
# Which rungs follow, and whether the tail is fail-open or fail-closed,
# is each hook's own business — this gate governs ORDER only.
#
# Per gate-don't-advise (loom-wj26.1) this is a correctness invariant, so
# it GATES via script/test rather than nudging. It scans EVERY
# `hooks/*.sh` by glob — never a hardcoded list — so a newly added hook
# cannot ship shadowed.
#
# Shape follows lib/tests/convention-drift-gates.test.sh: a `scan`
# function, a planted-violation RED case proving the scanner has teeth, a
# clean-form GREEN case proving it does not false-positive, and a LIVE
# case run against the real hooks/ tree. A dynamic section then binds the
# static rule to real behavior on representative hooks.
#
# Run:  bash lib/tests/hook-source-ladder.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ----------------------------------------------------------------------
# Detection
# ----------------------------------------------------------------------

# first_line <fixed-string> <file> — line number of the first NON-COMMENT
# line containing the fixed string, or empty. Comment lines are skipped
# so a `# shellcheck source=../lib/foo.sh` directive is not mistaken for
# a real source site.
first_line() {
  grep -Fn -- "$1" "$2" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | head -1 | cut -d: -f1
}

# libs_referenced <file> — the distinct lib basenames the file sources,
# one per line. Recognizes all three rungs (LOOM_TEST_LIB_DIR, the
# installed $HOME/.claude/lib copy, the repo-relative ../lib fallback) in
# both the direct-source and the assign-to-variable forms.
libs_referenced() {
  grep -nE '(\$LOOM_TEST_LIB_DIR|\$HOME/\.claude/lib|\.\./lib)/[A-Za-z0-9._-]+\.sh' "$1" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -oE '(\$LOOM_TEST_LIB_DIR|\$HOME/\.claude/lib|\.\./lib)/[A-Za-z0-9._-]+\.sh' \
    | sed -E 's#.*/##' \
    | sort -u
}

# scan <hooks-dir> — prints one offender line per violation:
#   <hook-basename>: <lib> (<why>)
# EMPTY output means clean.
scan() {
  local dir="$1" hook base lib guard other
  for hook in "$dir"/*.sh; do
    [ -e "$hook" ] || continue
    base=$(basename "$hook")
    while IFS= read -r lib; do
      [ -n "$lib" ] || continue

      # The guarded TESTLIB rung, as a fixed string.
      guard=$(first_line '[ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/'"$lib"'" ]' "$hook")

      # The earliest lower-precedence rung for the same lib.
      local home_ln repo_ln
      home_ln=$(first_line '$HOME/.claude/lib/'"$lib" "$hook")
      repo_ln=$(first_line '../lib/'"$lib" "$hook")
      other=""
      if [ -n "$home_ln" ] && [ -n "$repo_ln" ]; then
        other=$([ "$home_ln" -lt "$repo_ln" ] && echo "$home_ln" || echo "$repo_ln")
      else
        other="${home_ln:-$repo_ln}"
      fi

      if [ -z "$guard" ]; then
        # No lower rung either means the lib is not actually sourced here.
        [ -n "$other" ] || continue
        echo "$base: $lib (no guarded LOOM_TEST_LIB_DIR rung)"
      elif [ -n "$other" ] && [ "$guard" -gt "$other" ]; then
        echo "$base: $lib (LOOM_TEST_LIB_DIR rung at line $guard comes AFTER lower-precedence rung at line $other)"
      fi
    done < <(libs_referenced "$hook")
  done
}

# ----------------------------------------------------------------------
# 1. RED case — planted violations. Proves the scanner has teeth: a
#    no-op scanner that always prints nothing would sail through the
#    LIVE case below exactly as a clean tree does.
# ----------------------------------------------------------------------
echo "==> 1. RED: planted violations are detected"

BAD_DIR=$(mktemp -d)

# 1a. No TESTLIB rung at all (the 13-hook majority case).
cat > "$BAD_DIR/no-rung.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
EOF

# 1b. TESTLIB rung present but ordered AFTER the installed copy
#     (the edit-write-pwd-guard.sh case).
cat > "$BAD_DIR/wrong-order.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
DETECT_LIB=""
if [ -f "$HOME/.claude/lib/worktree-detect.sh" ]; then
  DETECT_LIB="$HOME/.claude/lib/worktree-detect.sh"
elif [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/worktree-detect.sh" ]; then
  DETECT_LIB="$LOOM_TEST_LIB_DIR/worktree-detect.sh"
fi
. "$DETECT_LIB"
EOF

# 1c. Repo-relative-only source with no TESTLIB rung (the
#     bd-remember-guest-guard.sh workflow-config.sh case). The repo-
#     relative path happens to resolve inside a worktree when invoked
#     directly, but NOT when invoked through an installed symlink — and
#     the invariant is about precedence, not luck.
cat > "$BAD_DIR/repo-only.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/workflow-config.sh"
EOF

bad_out=$(scan "$BAD_DIR")

if echo "$bad_out" | grep -q '^no-rung\.sh: loom-hook-helpers\.sh (no guarded'; then
  pass "RED 1a: missing TESTLIB rung detected"
else
  fail "RED 1a: missing TESTLIB rung NOT detected" "$bad_out"
fi

if echo "$bad_out" | grep -q '^wrong-order\.sh: worktree-detect\.sh (LOOM_TEST_LIB_DIR rung at line .* comes AFTER'; then
  pass "RED 1b: mis-ordered TESTLIB rung detected"
else
  fail "RED 1b: mis-ordered TESTLIB rung NOT detected" "$bad_out"
fi

if echo "$bad_out" | grep -q '^repo-only\.sh: workflow-config\.sh (no guarded'; then
  pass "RED 1c: repo-relative-only source with no TESTLIB rung detected"
else
  fail "RED 1c: repo-relative-only source NOT detected" "$bad_out"
fi

rm -rf "$BAD_DIR"

# ----------------------------------------------------------------------
# 2. GREEN case — clean forms are NOT flagged. Proves the scanner does
#    not simply flag everything.
# ----------------------------------------------------------------------
echo "==> 2. GREEN: correct ladders are not flagged"

GOOD_DIR=$(mktemp -d)

# 2a. The canonical three-rung direct-source ladder.
cat > "$GOOD_DIR/three-rung.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi
EOF

# 2b. The assign-then-source two-rung variant (fail-open tail).
cat > "$GOOD_DIR/assign-form.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
WFS_LIB=""
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  WFS_LIB="$LOOM_TEST_LIB_DIR/workflow-state.sh"
elif [ -f "$HOME/.claude/lib/workflow-state.sh" ]; then
  WFS_LIB="$HOME/.claude/lib/workflow-state.sh"
fi
[ -n "$WFS_LIB" ] || exit 0
. "$WFS_LIB"
EOF

# 2c. A hook that sources no lib at all is vacuously clean.
cat > "$GOOD_DIR/no-libs.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
exit 0
EOF

good_out=$(scan "$GOOD_DIR")

if [ -z "$good_out" ]; then
  pass "GREEN: clean ladders produce no offenders"
else
  fail "GREEN: clean ladders were flagged" "$good_out"
fi

rm -rf "$GOOD_DIR"

# ----------------------------------------------------------------------
# 3. LIVE case — the real hooks/ tree. This is the RED->GREEN driver for
#    script/test: a regression fails the suite the instant it lands.
# ----------------------------------------------------------------------
echo "==> 3. LIVE: every hooks/*.sh resolves LOOM_TEST_LIB_DIR first"

hook_count=$(find "$LOOM_ROOT/hooks" -maxdepth 1 -name '*.sh' | wc -l)
if [ "$hook_count" -gt 0 ]; then
  pass "scanned $hook_count hook(s) by glob (not a hardcoded list)"
else
  fail "no hooks found under $LOOM_ROOT/hooks — the gate would vacuously pass"
fi

live_out=$(scan "$LOOM_ROOT/hooks")

if [ -z "$live_out" ]; then
  pass "no shadowed hooks: every lib source site is TESTLIB-first"
else
  n=$(echo "$live_out" | wc -l)
  fail "$n shadowed lib source site(s) — these load MAIN's lib/ from inside a worktree" "$live_out"
fi

# ----------------------------------------------------------------------
# 4. DYNAMIC — bind the static rule to real behavior.
#
#    The static scan above is exhaustive but structural. This section
#    proves the ordering actually decides which file gets sourced, by
#    running representative hooks with BOTH candidate libs present and
#    each emitting a distinct sentinel. A hook honoring the ladder emits
#    the TESTLIB sentinel and never the HOME one.
#
#    Representative (not exhaustive) by design: hooks source their
#    second/third lib behind command-matching guards that would need
#    hand-crafted stdin per hook. The lib every hook loads unconditionally
#    at the top is loom-hook-helpers.sh, so that is what is exercised.
# ----------------------------------------------------------------------
echo "==> 4. DYNAMIC: LOOM_TEST_LIB_DIR actually wins at runtime"

DYN=$(mktemp -d)
mkdir -p "$DYN/testlib" "$DYN/home/.claude/lib" "$DYN/cwd"

# Faithful copies of the real helper, each prefixed with a sentinel so we
# can tell which one the hook loaded. Copies (not stubs) so the hook's
# subsequent loom_env_enabled/json_get calls behave normally.
#
# The sentinel is appended to a TRACE FILE, not echoed to stderr: the
# legacy `. "$HOME/.claude/lib/..." 2>/dev/null || ...` idiom redirects
# the sourced file's stderr to /dev/null, which would swallow a stderr
# sentinel and make the shadowed case look clean.
TRACE="$DYN/trace"
: > "$TRACE"
{
  echo "echo LADDER_SENTINEL_TESTLIB >> '$TRACE'"
  cat "$LOOM_ROOT/lib/loom-hook-helpers.sh"
} > "$DYN/testlib/loom-hook-helpers.sh"
{
  echo "echo LADDER_SENTINEL_HOME >> '$TRACE'"
  cat "$LOOM_ROOT/lib/loom-hook-helpers.sh"
} > "$DYN/home/.claude/lib/loom-hook-helpers.sh"

# Representative hooks + the bypass var each checks immediately after
# sourcing. Setting the bypass makes the hook exit 0 right after the
# source line, so the dynamic probe observes the ladder without running
# any of the hook's real side effects.
dyn_probe() {
  local hook="$1" skipvar="$2" out trace
  : > "$TRACE"
  out=$(cd "$DYN/cwd" && env HOME="$DYN/home" \
          LOOM_TEST_LIB_DIR="$DYN/testlib" "$skipvar=1" \
          bash "$LOOM_ROOT/hooks/$hook" </dev/null 2>&1)
  trace=$(cat "$TRACE")

  if echo "$trace" | grep -q LADDER_SENTINEL_TESTLIB; then
    pass "$hook: sourced the LOOM_TEST_LIB_DIR copy"
  else
    fail "$hook: did NOT source the LOOM_TEST_LIB_DIR copy" "trace=[$trace] out=[$out]"
  fi

  if echo "$trace" | grep -q LADDER_SENTINEL_HOME; then
    fail "$hook: ALSO sourced \$HOME/.claude/lib (shadow active)" "trace=[$trace] out=[$out]"
  else
    pass "$hook: never touched \$HOME/.claude/lib"
  fi
}

dyn_probe post-rewrite.sh      LOOM_BD_POST_REWRITE_SKIP
dyn_probe cwd-drift-guard.sh   LOOM_CWD_DRIFT_GUARD_SKIP
dyn_probe skill-redirect.sh    LOOM_SKILL_REDIRECT_SKIP

rm -rf "$DYN"

# ----------------------------------------------------------------------
echo ""
echo "Total: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
