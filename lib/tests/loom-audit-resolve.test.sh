#!/usr/bin/env bash
# Fixture tests for scripts/loom-audit-resolve (loom-6ah).
#
# The audit-project skill is prose, but its RESOLUTION prelude is
# deterministic and bug-prone: --root precedence, the default-wing
# sanitization, primitive-type autodetection, and the docs/.no-diataxis
# opt-out probe. This helper extracts that prelude into testable bash
# (mirroring scripts/loom-mine-history's resolution role) so the skill
# prose can call it and read back resolved key=value lines.
#
# CONTRACT (stdout, one key=value per line):
#   root=<abs path>
#   wing=<name>                  # default = basename(root) VERBATIM
#   primitives=<csv subset of skills,commands,agents,hooks>
#   diataxis_optout=<0|1>        # docs/.no-diataxis present
#   loom_managed=<0|1>           # .beads/ AND a docs Diataxis quadrant
#
# Wing default = basename VERBATIM (no `_`↔`-` substitution), matching
# skills/audit-project/SKILL.md's deliberate convention. Verbatim is the
# only rule correct for BOTH underscore wings (liza_base,
# hundred_acre_woods) and dash wings (golden-path, dreamer-engine): a
# `-`→`_` transform breaks golden-path, a `_`→`-` transform breaks
# hundred_acre_woods. (loom-mine-history's `-`→`_` is wrong for dash
# wings — tracked as a separate follow-up.)
#
# Run:  bash lib/tests/loom-audit-resolve.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$LOOM_ROOT/scripts/loom-audit-resolve"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Read one key's value from the helper's key=value stdout.
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# Build a fixture project dir. Args: dirname + which primitive dirs +
# whether to add .beads / docs quadrant / .no-diataxis.
#   mk_proj <basename> "<primitive dirs space-sep>" <beads:0|1> <quadrant:0|1> <optout:0|1>
mk_proj() {
  local base="$1" prims="$2" beads="$3" quad="$4" optout="$5"
  local work proj
  work=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; return 1; }
  # Guard: never proceed on an empty/non-/tmp work dir (a failed mktemp
  # must not let later rm -rf escape to / or the harness temp root).
  case "$work" in /tmp/*) : ;; *) echo "FATAL: mktemp gave unsafe dir '$work'" >&2; return 1 ;; esac
  [ -d "$work" ] || { echo "FATAL: work dir missing '$work'" >&2; return 1; }
  proj="$work/$base"; mkdir -p "$proj"
  local p
  for p in $prims; do mkdir -p "$proj/$p"; done
  [ "$beads" = "1" ] && mkdir -p "$proj/.beads"
  [ "$quad" = "1" ] && mkdir -p "$proj/docs/reference"
  if [ "$optout" = "1" ]; then mkdir -p "$proj/docs"; : > "$proj/docs/.no-diataxis"; fi
  echo "$proj"
}

# Safe cleanup: remove the mktemp dir that holds $PROJ (one level up),
# refusing anything not under /tmp. NB: $PROJ = <mktemp-dir>/<base>, so
# the temp dir is dirname($PROJ) — exactly ONE dirname, never two.
cleanup_proj() {
  local proj="$1" work
  [ -n "$proj" ] || return 0
  work=$(dirname "$proj")
  case "$work" in
    /tmp/*) rm -rf "$work" ;;
    *) echo "REFUSE: cleanup target '$work' not under /tmp" >&2 ;;
  esac
}

# =====================================================================
# 0. Helper exists + is executable.
# =====================================================================
echo "==> 0. helper shape"
if [ -x "$BIN" ]; then pass "scripts/loom-audit-resolve exists + executable"; else fail "helper missing/not executable"; fi

# =====================================================================
# 1. --root precedence: explicit --root used; nonexistent → exit 2.
# =====================================================================
echo "==> 1. --root resolution"
PROJ=$(mk_proj myproj "skills commands" 1 1 0)
out=$("$BIN" --root "$PROJ" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ "$(val "$out" root)" = "$(realpath "$PROJ")" ]; then
  pass "explicit --root resolved to its realpath"
else
  fail "explicit --root not resolved" "rc=$rc out=$out"
fi

out=$("$BIN" --root /no/such/dir/xyzzy 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then pass "nonexistent --root → exit 2"; else fail "nonexistent --root rc=$rc (want 2)" "$out"; fi
cleanup_proj "$PROJ"

# =====================================================================
# 2. default wing = basename VERBATIM (no _↔- substitution). Verbatim
#    is the only rule correct for both underscore and dash wings.
# =====================================================================
echo "==> 2. default wing = basename verbatim"

# Underscore wing preserved verbatim.
PROJ=$(mk_proj liza_base "skills" 1 0 0)
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" wing)" = "liza_base" ]; then
  pass "dir 'liza_base' → wing 'liza_base' (underscore preserved verbatim)"
else
  fail "underscore wing not verbatim" "got '$(val "$out" wing)' want 'liza_base'"
fi
cleanup_proj "$PROJ"

# DECIDING CASE: dash wing preserved verbatim (a -→_ transform would
# break this; this is why verbatim is canonical).
PROJ=$(mk_proj golden-path "skills" 1 0 0)
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" wing)" = "golden-path" ]; then
  pass "dir 'golden-path' → wing 'golden-path' (dash preserved — the deciding case)"
else
  fail "dash wing not verbatim (would break golden-path/dreamer-engine)" "got '$(val "$out" wing)' want 'golden-path'"
fi
cleanup_proj "$PROJ"

# Verbatim also means NO case-folding (SKILL.md: "no case-folding").
PROJ=$(mk_proj MyProj_Repo "skills" 1 0 0)
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" wing)" = "MyProj_Repo" ]; then
  pass "dir 'MyProj_Repo' → wing 'MyProj_Repo' (no case-folding)"
else
  fail "wing was case-folded (not verbatim)" "got '$(val "$out" wing)'"
fi
cleanup_proj "$PROJ"

# loom → loom (self-audit unchanged).
PROJ=$(mk_proj loom "skills commands agents hooks" 1 1 0)
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" wing)" = "loom" ]; then pass "dir 'loom' → wing 'loom'"; else fail "loom wing wrong" "$(val "$out" wing)"; fi

# explicit --wing overrides the default.
out=$("$BIN" --root "$PROJ" --wing custom_wing 2>/dev/null)
if [ "$(val "$out" wing)" = "custom_wing" ]; then pass "explicit --wing overrides default"; else fail "--wing override failed" "$(val "$out" wing)"; fi
cleanup_proj "$PROJ"

# =====================================================================
# 3. primitive autodetection: only present dirs are listed.
# =====================================================================
echo "==> 3. primitive autodetect"
PROJ=$(mk_proj proj "skills commands" 1 0 0)
out=$("$BIN" --root "$PROJ" 2>/dev/null)
prims=$(val "$out" primitives)
if printf '%s' "$prims" | grep -q "skills" && printf '%s' "$prims" | grep -q "commands"; then
  pass "present primitives (skills,commands) detected"
else
  fail "present primitives not detected" "primitives=$prims"
fi
if printf '%s' "$prims" | grep -q "agents\|hooks"; then
  fail "absent primitives (agents/hooks) wrongly listed" "primitives=$prims"
else
  pass "absent primitives (agents,hooks) NOT listed (no spurious '0 hooks')"
fi
cleanup_proj "$PROJ"

# =====================================================================
# 4. docs/.no-diataxis opt-out detection.
# =====================================================================
echo "==> 4. diataxis opt-out marker"
PROJ=$(mk_proj proj "skills" 1 1 1)   # quadrant dir present AND opt-out marker
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" diataxis_optout)" = "1" ]; then
  pass "docs/.no-diataxis → diataxis_optout=1 (marker wins even with quadrant dirs)"
else
  fail "opt-out not detected" "$(val "$out" diataxis_optout)"
fi
cleanup_proj "$PROJ"

PROJ=$(mk_proj proj "skills" 1 1 0)   # no marker
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" diataxis_optout)" = "0" ]; then pass "no marker → diataxis_optout=0"; else fail "false opt-out" "$(val "$out" diataxis_optout)"; fi
cleanup_proj "$PROJ"

# =====================================================================
# 5. loom_managed = .beads AND a docs Diataxis quadrant.
# =====================================================================
echo "==> 5. loom_managed heuristic"
PROJ=$(mk_proj proj "skills" 1 1 0)   # .beads + docs/reference
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" loom_managed)" = "1" ]; then pass ".beads + quadrant → loom_managed=1"; else fail "loom_managed false-neg" "$out"; fi
cleanup_proj "$PROJ"

PROJ=$(mk_proj proj "skills" 0 1 0)   # docs quadrant but NO .beads
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" loom_managed)" = "0" ]; then pass "no .beads → loom_managed=0"; else fail "loom_managed false-pos" "$out"; fi
cleanup_proj "$PROJ"

PROJ=$(mk_proj proj "skills" 1 0 0)   # .beads but NO docs quadrant
out=$("$BIN" --root "$PROJ" 2>/dev/null)
if [ "$(val "$out" loom_managed)" = "0" ]; then pass ".beads but no quadrant → loom_managed=0 (needs BOTH)"; else fail "loom_managed false-pos (no quadrant)" "$out"; fi
cleanup_proj "$PROJ"

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
