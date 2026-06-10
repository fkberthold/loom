#!/usr/bin/env bash
# Fail-loud guard for the constitution shellcheck lint gate (loom-n6uv).
#
# THE PROPERTY UNDER TEST — no false green.
#   loom's gated lint is `shellcheck --severity=warning hooks/*.sh
#   lib/*.sh scripts/*`, declared as canonical_commands.lint in
#   .claude/project-constitution.md and run through the three-rung
#   resolver loom_resolve_command (lib/loom-script-resolve.sh).
#
#   The failure mode this test pins: if `shellcheck` is NOT installed,
#   the lint gate must FAIL LOUD — return NON-ZERO — never silently
#   pass. A lint command that can't actually run is a refusal, not a
#   success. (This was the live hazard the bead fixed: shellcheck was
#   absent for a whole session, so the gate "passed" by never running.)
#
#   Mechanism: when `lint` resolves via rung 2 to the constitution's
#   `shellcheck ...` string, the resolver runs it through `bash -c`.
#   With shellcheck absent from PATH, `bash -c "shellcheck ..."` exits
#   127 (command-not-found) — non-zero. The resolver surfaces that code
#   verbatim (its exit code is authoritative). This test asserts that.
#
# Hermetic: builds an isolated fixture project (mirrors
# lib/tests/script-resolve.test.sh) with a constitution whose
# canonical_commands.lint names shellcheck, and NO script/lint or
# scripts/lint that would shadow rung 2. The resolver is sourced in a
# subshell rooted at the fixture so it walks up to the stub
# constitution, never the real repo's.
#
# Run:  bash lib/tests/lint-fail-loud.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-script-resolve.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build an isolated fixture project root carrying a constitution whose
# canonical_commands.lint is the loom-style shellcheck gate. No
# script/lint or scripts/lint is created, so `loom_resolve_command lint`
# falls to rung 2 (the constitution string) — the rung under test.
mk_lint_project() {
  local root
  root=$(mktemp -d)
  mkdir -p "$root/.claude"
  {
    echo "---"
    echo "package_manager: none"
    echo "language:"
    echo "  runtime: bash"
    echo "canonical_commands:"
    echo "  lint: \"shellcheck --severity=warning hooks/*.sh lib/*.sh scripts/*\""
    echo "---"
    echo ""
    echo "# stub constitution prose body"
  } > "$root/.claude/project-constitution.md"
  # A trivial shell file so the glob has something to match if shellcheck
  # IS present (the positive control below relies on this).
  mkdir -p "$root/hooks"
  printf '#!/usr/bin/env bash\necho ok\n' > "$root/hooks/ok.sh"
  printf '%s\n' "$root"
}

# Run loom_resolve_command lint in a subshell rooted at the fixture,
# with PATH set to $1 (so a caller can exclude shellcheck). Captures rc
# into RUN_RC and stderr into RUN_ERR.
RUN_RC=0; RUN_ERR=""
run_lint_with_path() {
  local root="$1" path="$2"
  local e
  e=$(mktemp)
  ( cd "$root" && PATH="$path" && export PATH && source "$LIB" \
      && loom_resolve_command lint ) >/dev/null 2>"$e"
  RUN_RC=$?
  RUN_ERR=$(cat "$e")
  rm -f "$e"
}

# ---------------------------------------------------------------------
# 1. PRIMARY: shellcheck ABSENT from PATH → lint resolves + runs +
#    returns NON-ZERO. The no-false-green guarantee.
# ---------------------------------------------------------------------
echo "==> shellcheck absent from PATH → gated lint fails loud (non-zero)"
ROOT="$(mk_lint_project)"
# A deliberately minimal PATH that does NOT contain shellcheck. /usr/bin
# is the form the bead brief named; we additionally assert shellcheck is
# genuinely not reachable there before trusting the result (so a host
# that happens to ship /usr/bin/shellcheck doesn't make the test vacuous).
NOSC_PATH="/usr/bin"
if PATH="$NOSC_PATH" command -v shellcheck >/dev/null 2>&1; then
  # Fall back to a guaranteed-empty bin dir if the host has shellcheck
  # on /usr/bin — keeps the test honest on any machine.
  NOSC_PATH="$(mktemp -d)"
fi
run_lint_with_path "$ROOT" "$NOSC_PATH"
if [ "$RUN_RC" -ne 0 ]; then
  pass "lint returned non-zero (rc=$RUN_RC) when shellcheck is absent — no false green"
else
  fail "lint returned 0 when shellcheck is absent — FALSE GREEN (the bug this bead fixed)" \
    "(rc=$RUN_RC; stderr='${RUN_ERR}')"
fi
rm -rf "$ROOT"

# ---------------------------------------------------------------------
# 2. POSITIVE CONTROL: when shellcheck IS on PATH and the target is
#    clean, the same resolved lint returns 0. Proves the test in (1)
#    is not vacuously always-non-zero (e.g. due to a broken constitution
#    or a resolver that always fails) — the rc=0 path is reachable.
#    Skipped (not failed) if shellcheck is not installed on this host.
# ---------------------------------------------------------------------
echo "==> shellcheck present + clean target → gated lint returns 0 (control)"
if command -v shellcheck >/dev/null 2>&1; then
  SC_DIR="$(dirname "$(command -v shellcheck)")"
  ROOT2="$(mk_lint_project)"
  # Constrain the glob to the one clean file so the control is
  # deterministic regardless of the fixture's other (absent) dirs.
  # Rewrite the constitution lint to target only the known-clean file.
  sed -i 's#  lint: .*#  lint: "shellcheck --severity=warning hooks/ok.sh"#' \
    "$ROOT2/.claude/project-constitution.md"
  run_lint_with_path "$ROOT2" "$SC_DIR:/usr/bin:/bin"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "lint returned 0 when shellcheck is present and target is clean — rc=0 path reachable"
  else
    fail "lint returned non-zero with shellcheck present + clean target — control broken" \
      "(rc=$RUN_RC; stderr='${RUN_ERR}')"
  fi
  rm -rf "$ROOT2"
else
  echo "  SKIP: shellcheck not installed on this host — positive control skipped"
fi

# ---------------------------------------------------------------------
echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
