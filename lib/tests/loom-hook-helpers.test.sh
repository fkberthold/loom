#!/usr/bin/env bash
# Fixture tests for lib/loom-hook-helpers.sh and the additive
# mode_dispatch() in lib/workflow-state.sh.
#
# Closes loom-0ahj.2 (design-doc 14f08e6d D2 + exploration F6): a
# behavior-preserving DRY refactor that harvests three substrate
# boilerplate families into sourceable helpers, then refactors the
# hooks to call them:
#
#   1. json_get <jq_path> <flat_fallback_field> [input]
#        jq -> grep-oP/sed parse ladder (the Flavor-A fallback used by
#        8 PreToolUse hooks). Reads INPUT from $3 or stdin.
#
#   2. json_get_py <jq_path> <python_expr> [input]
#        jq -> python3 parse ladder (the Flavor-B fallback used by the
#        3 close/preflight/guest hooks that decode escapes via python).
#
#   3. loom_env_enabled <VAR>
#        literal-"1" env-var gate. True iff ${VAR} == "1" exactly.
#        Rejects =yes/=true/=0/empty (the loom-b1l convention).
#
#   4. mode_dispatch <mode> <full_cmd> <light_cmd> <off_cmd>  (in
#        lib/workflow-state.sh) — runs exactly one of the three commands
#        by mode; unknown mode is treated as `full` (the resolver's
#        default). Returns the chosen command's exit code.
#
# Behavior-preservation is the bar: these helpers must reproduce the
# pre-refactor output of the inline idioms byte-for-byte. The assertions
# below pin that contract; the existing hook test suites prove the hooks
# still behave identically after they source the helpers.
#
# Run:  bash lib/tests/loom-hook-helpers.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPERS="$LOOM_ROOT/lib/loom-hook-helpers.sh"
WFS="$LOOM_ROOT/lib/workflow-state.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

eq() {
  # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected=[$2] actual=[$3]"; fi
}

# ----------------------------------------------------------------------
# Source guards
# ----------------------------------------------------------------------
if [ ! -f "$HELPERS" ]; then
  fail "lib/loom-hook-helpers.sh exists" "missing: $HELPERS"
  echo ""; echo "Total: $passed passed, $failed failed"; exit 1
fi
# shellcheck source=../loom-hook-helpers.sh
. "$HELPERS"
# shellcheck source=../workflow-state.sh
. "$WFS"

# ----------------------------------------------------------------------
# 1. json_get — jq -> grep/sed ladder
# ----------------------------------------------------------------------
echo "== json_get (jq -> grep/sed) =="

INPUT='{"tool_name":"Bash","tool_input":{"command":"bd close loom-foo","file_path":"x.sh"}}'

# function defined
if declare -F json_get >/dev/null 2>&1; then pass "json_get defined"; else fail "json_get defined"; fi

eq "json_get tool_name (stdin)"   "Bash"               "$(printf '%s' "$INPUT" | json_get '.tool_name' 'tool_name')"
eq "json_get command (stdin)"     "bd close loom-foo"  "$(printf '%s' "$INPUT" | json_get '.tool_input.command' 'command')"
eq "json_get file_path (arg)"     "x.sh"               "$(json_get '.tool_input.file_path' 'file_path' "$INPUT")"
eq "json_get missing -> empty"    ""                   "$(json_get '.tool_input.skill' 'skill' "$INPUT")"

# Fallback path (jq forced unavailable) must match for flat fields.
# Mask `jq` specifically while keeping coreutils reachable: build a clean
# bin dir, symlink in exactly the tools the fallback needs, and run the
# subshell with PATH pointed only at it (no jq present).
NOJQ_DIR=$(mktemp -d)
for tool in grep sed head cat printf env bash sh dirname; do
  src=$(command -v "$tool" 2>/dev/null) && ln -s "$src" "$NOJQ_DIR/$tool" 2>/dev/null || true
done
(
  PATH="$NOJQ_DIR"
  export PATH
  if command -v jq >/dev/null 2>&1; then
    echo "  SKIP: could not mask jq for fallback test (jq still resolvable)"
  else
    eq "json_get tool_name (no jq)" "Bash"               "$(printf '%s' "$INPUT" | json_get '.tool_name' 'tool_name')"
    eq "json_get command (no jq)"   "bd close loom-foo"  "$(printf '%s' "$INPUT" | json_get '.tool_input.command' 'command')"
  fi
)
rm -rf "$NOJQ_DIR"

# ----------------------------------------------------------------------
# 2. json_get_py — jq -> python3 ladder
# ----------------------------------------------------------------------
echo "== json_get_py (jq -> python3) =="

if declare -F json_get_py >/dev/null 2>&1; then pass "json_get_py defined"; else fail "json_get_py defined"; fi

PYIN='{"tool_name":"Bash","tool_input":{"command":"bd close x"}}'
eq "json_get_py tool_name" "Bash" \
  "$(printf '%s' "$PYIN" | json_get_py '.tool_name' 'd.get("tool_name","")')"
eq "json_get_py command" "bd close x" \
  "$(printf '%s' "$PYIN" | json_get_py '.tool_input.command' 'd.get("tool_input",{}).get("command","")')"

# Fallback path (jq forced unavailable) routes through python3. Mask jq
# but keep python3 + coreutils reachable.
if command -v python3 >/dev/null 2>&1; then
  PYDIR=$(mktemp -d)
  for tool in python3 cat printf sed; do
    src=$(command -v "$tool" 2>/dev/null) && ln -s "$src" "$PYDIR/$tool" 2>/dev/null || true
  done
  (
    PATH="$PYDIR"; export PATH
    if command -v jq >/dev/null 2>&1; then
      echo "  SKIP: could not mask jq for json_get_py fallback test"
    else
      eq "json_get_py tool_name (no jq)" "Bash" \
        "$(printf '%s' "$PYIN" | json_get_py '.tool_name' 'd.get("tool_name","")')"
    fi
  )
  rm -rf "$PYDIR"
else
  echo "  SKIP: python3 unavailable for json_get_py fallback test"
fi

# ----------------------------------------------------------------------
# 3. loom_env_enabled — literal "1" gate
# ----------------------------------------------------------------------
echo "== loom_env_enabled (literal-1 gate) =="

if declare -F loom_env_enabled >/dev/null 2>&1; then pass "loom_env_enabled defined"; else fail "loom_env_enabled defined"; fi

( export FOO=1;    loom_env_enabled FOO    && pass "FOO=1 -> true"    || fail "FOO=1 -> true" )
( export FOO=0;    loom_env_enabled FOO    && fail "FOO=0 -> false"   || pass "FOO=0 -> false" )
( export FOO=yes;  loom_env_enabled FOO    && fail "FOO=yes -> false" || pass "FOO=yes -> false" )
( export FOO=true; loom_env_enabled FOO    && fail "FOO=true -> false" || pass "FOO=true -> false" )
( export FOO="";   loom_env_enabled FOO    && fail "FOO=empty -> false" || pass "FOO=empty -> false" )
( unset FOO 2>/dev/null; loom_env_enabled FOO && fail "FOO=unset -> false" || pass "FOO=unset -> false" )
( export FOO=10;   loom_env_enabled FOO    && fail "FOO=10 -> false"  || pass "FOO=10 -> false" )

# ----------------------------------------------------------------------
# 4. mode_dispatch — full/light/off command dispatch (in workflow-state.sh)
# ----------------------------------------------------------------------
echo "== mode_dispatch (full/light/off) =="

if declare -F mode_dispatch >/dev/null 2>&1; then pass "mode_dispatch defined"; else fail "mode_dispatch defined"; fi

eq "mode_dispatch full"  "F" "$(mode_dispatch full  'echo F' 'echo L' 'echo O')"
eq "mode_dispatch light" "L" "$(mode_dispatch light 'echo F' 'echo L' 'echo O')"
eq "mode_dispatch off"   "O" "$(mode_dispatch off   'echo F' 'echo L' 'echo O')"
# Unknown mode falls back to the full branch (resolver default is full).
eq "mode_dispatch unknown->full" "F" "$(mode_dispatch wat 'echo F' 'echo L' 'echo O')"
# Exit code of the chosen branch propagates.
mode_dispatch off 'true' 'true' 'false'; rc=$?
eq "mode_dispatch off rc propagates" "1" "$rc"

# ----------------------------------------------------------------------
echo ""
echo "Total: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
