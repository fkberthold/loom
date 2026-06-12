#!/usr/bin/env bash
# RED→GREEN gate for loom-5x5o: downstream-routed loom skills/commands
# must invoke loom helper scripts by the INSTALLED GLOBAL path
# (`~/.claude/scripts/loom-X`), never the bare repo-relative
# `scripts/loom-X`.
#
# THE BUG: loom skills/commands are symlinked into ~/.claude/{skills,
# commands} and run with cwd = the CURRENT project (any downstream
# repo). A bare `scripts/loom-fanout-detect` only resolves when cwd IS
# the loom repo; in any downstream project the path misses silently
# (the helper never runs, the step degrades to a no-op or a confusing
# command-not-found). The canonical fix is to invoke via the installed
# global path `~/.claude/scripts/loom-X` — which matches what
# session-startup already does for its own `~/.claude/scripts/
# workflow-state` mode-check, and the `$HOME/.claude` convention locked
# in loom-fxad / loom-0ahj.2.
#
# THE GATE: a static lint over skills/*/SKILL.md + commands/*.md. It
# flags any line invoking/mentioning a GLOBAL_ONLY helper by a bare
# `scripts/loom-X` reference that is NOT prefixed by one of the three
# accepted global-path forms (`~/.claude/`, `$HOME/.claude/`,
# `.claude/scripts/`). The LIVE case (case 4) scans the real repo and
# is the RED→GREEN driver: RED before the offenders are converted,
# GREEN after.
#
# PATTERN: follows the loom-yuy6 recursion-safe-fixture + live-assertion
# shape (see lib/tests/script-test-runs-full-suite.test.sh). The LIVE
# scan honors a LOOM_DSI_SCAN_ROOT override so a hermetic self-test can
# point it at a fixture instead of the real tree; it defaults to the
# real $LOOM_ROOT.
#
# ALLOWLIST — `loom-docs-catalogue` and `loom-docs-gen` are DELIBERATELY
# absent from GLOBAL_ONLY. They are loom-repo-scoped on purpose: the
# pre-push hook guards them behind `[ -x scripts/... ]`, and nothing
# scaffolds them into downstream projects, so their bare repo-relative
# form is correct. Do NOT add them to GLOBAL_ONLY and do NOT "fix" their
# bare references — they are intentional exceptions.
#
# Run:  bash lib/tests/downstream-script-invocation.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# The helper basenames that MUST use the installed global path. These
# are the loom helpers that downstream-routed skills/commands invoke
# with cwd = the downstream project, so a bare repo-relative path would
# miss. (loom-docs-catalogue / loom-docs-gen are intentionally NOT
# here — see the ALLOWLIST note in the header.)
GLOBAL_ONLY="loom-fanout-detect loom-stage-spend loom-preflight loom-guest loom-mine-history loom-audit-resolve loom-rebase-worktree loom-worktree-python loom-seam-scan loom-retro-prescan loom-doctor loom-docs-serving-check loom-print-deploy-hint"

# Build an alternation of the global-only basenames for the regex.
GLOBAL_ALT="$(echo "$GLOBAL_ONLY" | tr ' ' '|')"

# scan_dir <root>
#   Prints (one per line) every offending "<file>:<lineno>:<line>" in
#   <root>/skills/*/SKILL.md + <root>/commands/*.md that contains a bare
#   `scripts/<global-only>` reference NOT already prefixed by an accepted
#   global-path form. An empty output means CLEAN.
#
#   Detection:
#     1. grep for `scripts/<global-only>` where the char immediately
#        before `scripts/` is start-of-field or NOT one of [/.~] — this
#        is the bare repo-relative form. Prefixed forms (`~/.claude/
#        scripts/...`, `$HOME/.claude/scripts/...`, `.claude/scripts/
#        ...`) all put a `/`, `.`, or `~` directly before `scripts/`, so
#        the negated-class anchor skips them.
#     2. filter out any matched line that ALSO contains `.claude/scripts`
#        (belt-and-suspenders: a line that mixes a prefixed and an
#        accidental bare reference still counts as offending only if a
#        truly bare one survives — but the common prefixed forms are
#        dropped here so they never reach the offender list).
scan_dir() {
  local root="$1"
  local f
  for f in "$root"/skills/*/SKILL.md "$root"/commands/*.md; do
    [ -f "$f" ] || continue
    # The `[^/.~]` negated class already lets the bare-only form match
    # while skipping every prefixed form (each accepted global prefix
    # puts a `/`, `.`, or `~` directly before `scripts/`). The two grep
    # -v filters are belt-and-suspenders, dropping any line that carries
    # an accepted global-path form anywhere on it. The first
    # (`.claude/scripts`) catches all three accepted prefixes; the second
    # is a literal home-prefix match. `[~]` is a bracketed literal tilde
    # — it does NOT expand (shellcheck SC2088 is a false positive on a
    # grep PATTERN, so the bracket form sidesteps it).
    grep -nE "(^|[^/.~])scripts/($GLOBAL_ALT)" "$f" 2>/dev/null \
      | grep -vE '\.claude/scripts' \
      | grep -vE '[~]/\.claude|\$HOME/\.claude' \
      | sed "s#^#$f:#"
  done
}

# =====================================================================
# Case 1 — planted bare invocation is FLAGGED
# =====================================================================
echo "==> case 1: a bare scripts/loom-fanout-detect reference is FLAGGED"
FIX1="$(mktemp -d)"
trap 'rm -rf "$FIX1"' EXIT
mkdir -p "$FIX1/skills/demo" "$FIX1/commands"
printf 'Run `scripts/loom-fanout-detect` to propose a wave.\n' \
  > "$FIX1/skills/demo/SKILL.md"
offenders1="$(scan_dir "$FIX1")"
if [ -n "$offenders1" ]; then
  pass "planted bare reference is flagged (non-empty offender list)"
else
  fail "planted bare reference is flagged" "(scan_dir returned empty on a planted offender)"
fi

# =====================================================================
# Case 2 — the global-path form is CLEAN
# =====================================================================
echo "==> case 2: the ~/.claude/scripts/loom-fanout-detect form is CLEAN"
FIX2="$(mktemp -d)"
mkdir -p "$FIX2/skills/demo" "$FIX2/commands"
printf 'Run `~/.claude/scripts/loom-fanout-detect` to propose a wave.\n' \
  > "$FIX2/skills/demo/SKILL.md"
offenders2="$(scan_dir "$FIX2")"
if [ -z "$offenders2" ]; then
  pass "global-path form is clean (empty offender list)"
else
  fail "global-path form is clean" "(scan_dir flagged a correct global reference):
$offenders2"
fi
rm -rf "$FIX2"

# =====================================================================
# Case 3 — allowlist proof: bare scripts/loom-docs-catalogue is CLEAN
# =====================================================================
echo "==> case 3: a bare scripts/loom-docs-catalogue line is CLEAN (allowlist)"
FIX3="$(mktemp -d)"
mkdir -p "$FIX3/skills/demo" "$FIX3/commands"
printf 'Run `scripts/loom-docs-catalogue --check` (loom-repo-scoped).\n' \
  > "$FIX3/skills/demo/SKILL.md"
offenders3="$(scan_dir "$FIX3")"
if [ -z "$offenders3" ]; then
  pass "allowlisted loom-docs-catalogue bare ref is NOT flagged"
else
  fail "allowlisted loom-docs-catalogue bare ref is NOT flagged" \
    "(scan_dir flagged an intentional repo-scoped exception):
$offenders3"
fi
rm -rf "$FIX3"

# =====================================================================
# Case 4 — LIVE: the real repo is CLEAN (the RED→GREEN gate)
# =====================================================================
echo "==> case 4 (LIVE): the real repo has NO bare GLOBAL_ONLY reference"
SCAN_ROOT="${LOOM_DSI_SCAN_ROOT:-$LOOM_ROOT}"
offenders_live="$(scan_dir "$SCAN_ROOT")"
if [ -z "$offenders_live" ]; then
  pass "LIVE scan of $SCAN_ROOT is clean"
else
  fail "LIVE scan of $SCAN_ROOT is clean" \
    "(the following lines still use a bare repo-relative GLOBAL_ONLY reference):
$offenders_live"
fi

# =====================================================================
echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="
[ "$failed" -eq 0 ]
