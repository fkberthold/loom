#!/usr/bin/env bash
# lib/tests/convention-drift-gates.test.sh
#
# THE GATE LAYER (loom-ig3p.5).
#
# D5 (drawer_loom_decisions_4d3918198c51bb65ceaebf90, the "downstream
# convention-drift detection" design cycle) locked the tactical +
# structural COMPOSE: correctness-critical convention-drift CLASSES
# get a static-lint GATE wired into `script/test` — never a skippable
# advisory a human has to remember to run (gate-don't-advise,
# loom-wj26.1) — while everything else rides the D3 session-startup
# nudge (loom-ig3p.3).
#
# This file GENERALIZES loom-5x5o's original single-purpose gate
# (lib/tests/downstream-script-invocation.test.sh) into a small,
# EXTENSIBLE LAYER: one section per correctness-critical drift class,
# each following the same 4-part shape:
#
#   1. a `gate<N>_scan` detection function — prints one offender line
#      per violation found under a given root; EMPTY output means
#      clean.
#   2. a RED case — a planted fixture violation, proving the gate has
#      teeth (a no-op scanner that always returns empty would silently
#      pass this the same way it passes everything else).
#   3. a GREEN case — a clean-form fixture, proving the gate doesn't
#      false-positive on the correct/accepted form.
#   4. a LIVE case — the scan run against the real repo. This is the
#      actual RED->GREEN driver for `script/test`: a live regression
#      fails the suite the instant it lands, not on the next human who
#      happens to notice.
#
# Adding a new drift class later = add one more `gate<N>_scan`
# function plus its RED/GREEN/LIVE cases, following the same shape.
#
# ---------------------------------------------------------------------
# GATE 1 — downstream bare `scripts/loom-X` invocation (the loom-5x5o
# class named verbatim in this bead's RED line).
#
#   THE BUG: loom skills/commands are symlinked into ~/.claude/{skills,
#   commands} and run with cwd = the CURRENT project (any downstream
#   repo). A bare `scripts/loom-X` reference only resolves when cwd IS
#   the loom repo; in any downstream project the path misses silently.
#   The fix is to invoke via the installed global path
#   (`~/.claude/scripts/loom-X`, `$HOME/.claude/scripts/loom-X`, or
#   `.claude/scripts/loom-X`).
#
#   This gate is a LIGHTER re-assertion of the same class, composing
#   it into the layer's single-file registry so a reader finds every
#   correctness-critical class enumerated in one place. It is NOT a
#   replacement for lib/tests/downstream-script-invocation.test.sh,
#   which remains the canonical, exhaustive owner of this class
#   (including the loom-docs-catalogue/loom-docs-gen allowlist nuance
#   this file does not re-derive). GLOBAL_ONLY here is a duplicate of
#   the list there — a real dedup (extracting both into a shared
#   lib/*.sh scan helper) is a reasonable follow-up, not done here to
#   keep this bead's footprint to the one new test file.
#
# ---------------------------------------------------------------------
# GATE 2 — settings.snippet.json hook/script path integrity.
#
#   THE BUG: settings.snippet.json is the checked-in hook-registration
#   snippet every downstream project installs (via /audit-project or a
#   manual copy) into its own settings.json. Each hook entry's command
#   hardcodes a `$HOME/.claude/{hooks,scripts}/<name>` path. If a
#   hook/script file is renamed or deleted in the repo without updating
#   this snippet, the reference silently 404s at hook-fire time for
#   every downstream install: the hook command fails to execute and no
#   loud error surfaces anywhere a human is likely to look — the gate
#   the hook was supposed to provide (e.g. cwd-drift-guard,
#   constitution-enforce) is just quietly absent.
#
#   This gate asserts every `$HOME/.claude/(hooks|scripts)/<name>`
#   reference in settings.snippet.json resolves to a real
#   hooks/<name> or scripts/<name> file in the repo.
#
# Run:  bash lib/tests/convention-drift-gates.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# =====================================================================
# GATE 1 — downstream bare scripts/loom-X invocation
# =====================================================================

# The helper basenames that MUST use the installed global path (kept
# in lock-step with lib/tests/downstream-script-invocation.test.sh).
GATE1_GLOBAL_ONLY="loom-fanout-detect loom-stage-spend loom-preflight loom-guest loom-mine-history loom-audit-resolve loom-rebase-worktree loom-worktree-python loom-seam-scan loom-retro-prescan loom-doctor loom-docs-serving-check loom-print-deploy-hint"
GATE1_GLOBAL_ALT="$(echo "$GATE1_GLOBAL_ONLY" | tr ' ' '|')"

# gate1_scan <root>
#   Prints one "<file>:<lineno>:<line>" per bare GLOBAL_ONLY reference
#   found in <root>/skills/*/SKILL.md + <root>/commands/*.md. Empty
#   output means clean.
gate1_scan() {
  local root="$1" f
  for f in "$root"/skills/*/SKILL.md "$root"/commands/*.md; do
    [ -f "$f" ] || continue
    grep -nE "(^|[^/.~])scripts/($GATE1_GLOBAL_ALT)" "$f" 2>/dev/null \
      | grep -vE '\.claude/scripts' \
      | grep -vE '[~]/\.claude|\$HOME/\.claude' \
      | sed "s#^#$f:#"
  done
}

echo "==> GATE 1 case A (RED control): a bare scripts/loom-fanout-detect reference is FLAGGED"
G1A="$(mktemp -d)"
mkdir -p "$G1A/skills/demo" "$G1A/commands"
printf 'Run `scripts/loom-fanout-detect` to propose a wave.\n' > "$G1A/skills/demo/SKILL.md"
g1a_off="$(gate1_scan "$G1A")"
if [ -n "$g1a_off" ]; then
  pass "gate1: planted bare reference is flagged"
else
  fail "gate1: planted bare reference is flagged" "(gate1_scan returned empty on a planted offender — the gate has no teeth)"
fi
rm -rf "$G1A"

echo "==> GATE 1 case B (GREEN control): the ~/.claude/scripts/... form is CLEAN"
G1B="$(mktemp -d)"
mkdir -p "$G1B/skills/demo" "$G1B/commands"
printf 'Run `~/.claude/scripts/loom-fanout-detect` to propose a wave.\n' > "$G1B/skills/demo/SKILL.md"
g1b_off="$(gate1_scan "$G1B")"
if [ -z "$g1b_off" ]; then
  pass "gate1: global-path form is clean"
else
  fail "gate1: global-path form is clean" "(gate1_scan flagged a correct global reference):
$g1b_off"
fi
rm -rf "$G1B"

echo "==> GATE 1 case C (LIVE): the real repo has NO bare GLOBAL_ONLY reference"
GATE1_SCAN_ROOT="${LOOM_CDG_GATE1_SCAN_ROOT:-$LOOM_ROOT}"
g1_live_off="$(gate1_scan "$GATE1_SCAN_ROOT")"
if [ -z "$g1_live_off" ]; then
  pass "gate1: LIVE scan of $GATE1_SCAN_ROOT is clean"
else
  fail "gate1: LIVE scan of $GATE1_SCAN_ROOT is clean" \
    "(the following lines still use a bare repo-relative GLOBAL_ONLY reference):
$g1_live_off"
fi

# =====================================================================
# GATE 2 — settings.snippet.json hook/script path integrity
# =====================================================================

# gate2_scan <root> <snippet_file>
#   Prints one "<snippet_file>:<lineno>: missing <kind>/<name> ..." per
#   $HOME/.claude/(hooks|scripts)/<name> reference in <snippet_file>
#   whose target does NOT exist as <root>/<kind>/<name>. Empty output
#   means clean. A missing <snippet_file> itself is reported as a
#   single offender line (never silently "clean").
gate2_scan() {
  local root="$1" snippet="$2"
  if [ ! -f "$snippet" ]; then
    echo "$snippet: MISSING (no snippet file to scan)"
    return
  fi
  grep -noE '\$HOME/\.claude/(hooks|scripts)/[A-Za-z0-9._-]+' "$snippet" 2>/dev/null \
    | while IFS=: read -r lineno match; do
        local kind name target
        kind="$(printf '%s\n' "$match" | sed -E 's#.*\.claude/(hooks|scripts)/.*#\1#')"
        name="$(printf '%s\n' "$match" | sed -E 's#.*/##')"
        target="$root/$kind/$name"
        if [ ! -f "$target" ]; then
          echo "$snippet:$lineno: missing $kind/$name (referenced as $match)"
        fi
      done
}

echo "==> GATE 2 case A (RED control): a reference to a nonexistent hook is FLAGGED"
G2A="$(mktemp -d)"
mkdir -p "$G2A/hooks" "$G2A/scripts"
cat > "$G2A/settings.snippet.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "command": "bash $HOME/.claude/hooks/does-not-exist.sh" } ] }
    ]
  }
}
EOF
g2a_off="$(gate2_scan "$G2A" "$G2A/settings.snippet.json")"
if [ -n "$g2a_off" ]; then
  pass "gate2: planted missing-hook reference is flagged"
else
  fail "gate2: planted missing-hook reference is flagged" "(gate2_scan returned empty on a planted offender — the gate has no teeth)"
fi
rm -rf "$G2A"

echo "==> GATE 2 case B (GREEN control): a reference to an existing hook is CLEAN"
G2B="$(mktemp -d)"
mkdir -p "$G2B/hooks" "$G2B/scripts"
: > "$G2B/hooks/real-hook.sh"
cat > "$G2B/settings.snippet.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "command": "bash $HOME/.claude/hooks/real-hook.sh" } ] }
    ]
  }
}
EOF
g2b_off="$(gate2_scan "$G2B" "$G2B/settings.snippet.json")"
if [ -z "$g2b_off" ]; then
  pass "gate2: existing-hook reference is clean"
else
  fail "gate2: existing-hook reference is clean" "(gate2_scan flagged a real, existing hook):
$g2b_off"
fi
rm -rf "$G2B"

echo "==> GATE 2 case C (LIVE): the real settings.snippet.json has NO dangling hook/script reference"
GATE2_SCAN_ROOT="${LOOM_CDG_GATE2_SCAN_ROOT:-$LOOM_ROOT}"
GATE2_SNIPPET="${LOOM_CDG_GATE2_SNIPPET:-$GATE2_SCAN_ROOT/settings.snippet.json}"
g2_live_off="$(gate2_scan "$GATE2_SCAN_ROOT" "$GATE2_SNIPPET")"
if [ -z "$g2_live_off" ]; then
  pass "gate2: LIVE scan of $GATE2_SNIPPET is clean"
else
  fail "gate2: LIVE scan of $GATE2_SNIPPET is clean" \
    "(the following referenced hooks/scripts do not exist):
$g2_live_off"
fi

# =====================================================================
echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="
[ "$failed" -eq 0 ]
