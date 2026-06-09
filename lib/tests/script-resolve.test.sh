#!/usr/bin/env bash
# Fixture tests for lib/loom-script-resolve.sh.
#
# Covers loom-oxs.2: the `loom_resolve_command <X>` resolution helper
# that implements the loom "script/ convention" resolution contract
# locked in loom-adm (the script/ convention drawer — D-pivot layering
# + resolution contract). The contract has THREE layers, checked in
# strict priority order:
#
#   1. script/X (or scripts/X — EITHER dir accepted) present AND
#      executable → RUN it. Its exit code is authoritative (the
#      convention's stub semantics: exit 2 = not-wired stub, exit 0 =
#      ran / genuinely-N/A).
#   2. Else if canonical_commands.X is set in
#      .claude/project-constitution.md → RUN that string command.
#   3. Else → emit a warning to stderr ("no X command defined") and
#      return NON-ZERO. NEVER a silent pass / exit 0 — the
#      no-false-green guard.
#
# The layering this encodes: script/ is the EXECUTABLE layer; the
# constitution's canonical_commands is the DECLARATIVE pointer; script/X
# is the default impl of canonical_commands.X.
#
# Stubs the project tree (script/, scripts/, .claude/project-
# constitution.md) inside an isolated tmpdir per test (mirrors the
# LOOM_HOME isolation pattern in loom-upstream.test.sh). The library is
# sourced in a subshell rooted at the fake project so it walks up to the
# stub constitution, never the real one.
#
# Run:  bash lib/tests/script-resolve.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-script-resolve.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build an isolated fake project root. Returns the path on stdout.
mk_project() {
  mktemp -d
}

# Write a minimal constitution with a canonical_commands block. Args:
#   $1 = project root, $2.. = "key=value" pairs for canonical_commands.
write_constitution() {
  local root="$1"; shift
  mkdir -p "$root/.claude"
  {
    echo "---"
    echo "package_manager: none"
    echo "language:"
    echo "  runtime: bash"
    echo "canonical_commands:"
    local pair k v
    for pair in "$@"; do
      k="${pair%%=*}"
      v="${pair#*=}"
      echo "  $k: \"$v\""
    done
    echo "---"
    echo ""
    echo "# stub constitution prose body"
  } > "$root/.claude/project-constitution.md"
}

# Run loom_resolve_command in a subshell rooted at the fake project.
# Captures stdout, stderr, rc into the named globals via temp files.
# Usage: run_resolve <root> <X> [extra-args...]
RUN_OUT=""; RUN_ERR=""; RUN_RC=0
run_resolve() {
  local root="$1"; shift
  local x="$1"; shift
  local o e
  o=$(mktemp); e=$(mktemp)
  ( cd "$root" && source "$LIB" && loom_resolve_command "$x" "$@" ) >"$o" 2>"$e"
  RUN_RC=$?
  RUN_OUT=$(cat "$o"); RUN_ERR=$(cat "$e")
  rm -f "$o" "$e"
}

# -------------------------------------------------------------------
# 1. script/X present and executable → runs it; exit code propagates.
#    The convention's authoritative-exit-code semantics: a not-wired
#    stub exits 2 and the resolver must surface that 2, NOT mask it.
# -------------------------------------------------------------------

echo "==> 1. script/X present → runs it, exit code is authoritative"

ROOT=$(mk_project)
mkdir -p "$ROOT/script"
cat > "$ROOT/script/test" <<'EOF'
#!/usr/bin/env bash
echo "ran script/test"
exit 0
EOF
chmod +x "$ROOT/script/test"

run_resolve "$ROOT" test

if [ "$RUN_RC" -eq 0 ]; then
  pass "exit 0 propagated from script/test"
else
  fail "expected rc 0 from script/test, got $RUN_RC" "err: $RUN_ERR"
fi

if echo "$RUN_OUT" | grep -q "ran script/test"; then
  pass "script/test actually executed (stdout marker present)"
else
  fail "script/test did not execute" "out: $RUN_OUT err: $RUN_ERR"
fi

# Exit-code-authoritative: a stub exiting 2 must surface 2.
cat > "$ROOT/script/test" <<'EOF'
#!/usr/bin/env bash
echo "not wired" >&2
exit 2
EOF
chmod +x "$ROOT/script/test"

run_resolve "$ROOT" test

if [ "$RUN_RC" -eq 2 ]; then
  pass "stub exit 2 surfaced authoritatively (not masked to 0)"
else
  fail "expected rc 2 from not-wired stub, got $RUN_RC" "err: $RUN_ERR"
fi

# The script must win OVER a competing canonical_commands entry —
# script/ is the executable layer; the string is only a fallback.
write_constitution "$ROOT" "test=echo CONSTITUTION_STRING_RAN"
cat > "$ROOT/script/test" <<'EOF'
#!/usr/bin/env bash
echo "ran script/test"
exit 0
EOF
chmod +x "$ROOT/script/test"

run_resolve "$ROOT" test

if echo "$RUN_OUT" | grep -q "ran script/test" \
   && ! echo "$RUN_OUT" | grep -q "CONSTITUTION_STRING_RAN"; then
  pass "script/X wins over canonical_commands.X (executable layer priority)"
else
  fail "script/X did not take priority over canonical_commands.X" \
       "out: $RUN_OUT"
fi

rm -rf "$ROOT"

# -------------------------------------------------------------------
# 2. scripts/X (alternate plural dir) is recognized identically.
# -------------------------------------------------------------------

echo "==> 2. scripts/X (alt plural dir) recognized"

ROOT=$(mk_project)
mkdir -p "$ROOT/scripts"
cat > "$ROOT/scripts/lint" <<'EOF'
#!/usr/bin/env bash
echo "ran scripts/lint"
exit 0
EOF
chmod +x "$ROOT/scripts/lint"

run_resolve "$ROOT" lint

if [ "$RUN_RC" -eq 0 ] && echo "$RUN_OUT" | grep -q "ran scripts/lint"; then
  pass "scripts/lint executed and exit 0 propagated"
else
  fail "scripts/ (plural) dir not recognized" "rc=$RUN_RC out: $RUN_OUT err: $RUN_ERR"
fi

# A non-executable script/X must NOT be treated as the executable
# layer — it falls through to the next resolution rung.
ROOT2=$(mk_project)
mkdir -p "$ROOT2/script"
echo '#!/usr/bin/env bash' > "$ROOT2/script/test"   # NOT chmod +x
write_constitution "$ROOT2" "test=echo FELL_THROUGH_TO_STRING"

run_resolve "$ROOT2" test

if echo "$RUN_OUT" | grep -q "FELL_THROUGH_TO_STRING"; then
  pass "non-executable script/X falls through to canonical_commands.X"
else
  fail "non-executable script/X was wrongly treated as runnable" \
       "rc=$RUN_RC out: $RUN_OUT err: $RUN_ERR"
fi

rm -rf "$ROOT" "$ROOT2"

# -------------------------------------------------------------------
# 3. script absent, canonical_commands.X set → runs the string command.
# -------------------------------------------------------------------

echo "==> 3. no script, canonical_commands.X set → runs the string"

ROOT=$(mk_project)
# No script/ or scripts/ dir at all.
write_constitution "$ROOT" "build=echo BUILD_STRING_RAN" "test=echo TEST_STRING_RAN"

run_resolve "$ROOT" build

if [ "$RUN_RC" -eq 0 ] && echo "$RUN_OUT" | grep -q "BUILD_STRING_RAN"; then
  pass "canonical_commands.build string command executed, exit 0"
else
  fail "canonical_commands.build string not run" "rc=$RUN_RC out: $RUN_OUT err: $RUN_ERR"
fi

# The exit code of the string command is authoritative too.
write_constitution "$ROOT" "test=sh -c 'exit 3'"
run_resolve "$ROOT" test
if [ "$RUN_RC" -eq 3 ]; then
  pass "string command exit code is authoritative (got 3)"
else
  fail "string command exit code not propagated" "rc=$RUN_RC err: $RUN_ERR"
fi

# An EMPTY canonical_commands.X value counts as "not set" → must fall
# through to the warn-non-zero rung, NOT silently exit 0.
write_constitution "$ROOT" "gen="
run_resolve "$ROOT" gen
if [ "$RUN_RC" -ne 0 ]; then
  pass "empty canonical_commands.gen string treated as unset (non-zero)"
else
  fail "empty canonical_commands.gen wrongly treated as defined (rc 0)" \
       "out: $RUN_OUT err: $RUN_ERR"
fi

rm -rf "$ROOT"

# -------------------------------------------------------------------
# 4. NO script AND NO canonical_commands.X → warns + returns non-zero.
#    The no-false-green guard: the resolver must NEVER silently pass.
# -------------------------------------------------------------------

echo "==> 4. both absent → warns to stderr + non-zero (no false green)"

ROOT=$(mk_project)
# A constitution exists but defines a DIFFERENT command, not the one
# we ask for — so X is genuinely undefined.
write_constitution "$ROOT" "build=echo something_else"

run_resolve "$ROOT" test

if [ "$RUN_RC" -ne 0 ]; then
  pass "undefined command returns NON-ZERO (never a silent pass)"
else
  fail "undefined command returned 0 — FALSE GREEN" "out: $RUN_OUT err: $RUN_ERR"
fi

if echo "$RUN_ERR" | grep -qi "no .*test.* command\|no test command\|test.*not defined\|no command"; then
  pass "warning emitted to stderr naming the missing command"
else
  fail "no warning naming the missing command on stderr" "err: $RUN_ERR"
fi

# Same guard when there is NO constitution at all.
ROOT2=$(mk_project)
run_resolve "$ROOT2" test
if [ "$RUN_RC" -ne 0 ]; then
  pass "no constitution + no script → still non-zero (no false green)"
else
  fail "missing constitution + missing script returned 0 — FALSE GREEN" \
       "out: $RUN_OUT err: $RUN_ERR"
fi
if echo "$RUN_ERR" | grep -qi "test"; then
  pass "warning still names the command when constitution is absent"
else
  fail "warning missing command name when constitution absent" "err: $RUN_ERR"
fi

rm -rf "$ROOT" "$ROOT2"

# -------------------------------------------------------------------
# 5. Sourcing the library is side-effect-free (matches loom-upstream
#    convention: a sourced lib runs no functions, touches no files).
# -------------------------------------------------------------------

echo "==> 5. Sourcing the library is side-effect-free"

PROBE=$(mktemp -d)
out=$(cd "$PROBE" && bash -c "source '$LIB'" 2>&1); rc=$?
extras=$(ls -A "$PROBE")

if [ "$rc" -eq 0 ] && [ -z "$extras" ]; then
  pass "source-only execution is clean (no files, exit 0)"
else
  fail "sourcing the library had side effects (rc=$rc extras=$extras)" "$out"
fi

rm -rf "$PROBE"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
