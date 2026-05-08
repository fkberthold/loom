#!/usr/bin/env bash
# Tests for lib/refuse-on-guest.sh — shared helper that hooks/skills
# source to refuse with a consistent message when guest mode is active.
#
# API under test:
#   refuse_if_guest <action-name> [<override-hint>]
#     - exit 0, no output, when guest inactive
#     - exit 1, prints message to stderr, when guest active
#     - default message: "Guest mode active — refusing <action>.
#       Run /loom-guest off to override."
#     - override-hint, when given, replaces the default trailing
#       sentence ("Run /loom-guest off to override.").
#
# Plus wire-in text-presence checks for /docs-scaffold and
# /audit-project AUTOFIX recipe blocks.
#
# Run:  bash lib/tests/refuse-on-guest.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/refuse-on-guest.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a tmp project dir with a workflow.json (no guest block by default).
mk_project() {
  local d
  d=$(mktemp -d)
  (cd "$d" && git init -q)
  mkdir -p "$d/.claude"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '%s' "$d"
}

# Activate guest mode in the given project (host bd_mode by default).
activate_guest() {
  local d="$1"
  jq '.guest = {active: true, bd_mode: "host", repo_key: "test-deadbeef"}' \
    "$d/.claude/workflow.json" > "$d/.claude/workflow.json.tmp" \
    && mv "$d/.claude/workflow.json.tmp" "$d/.claude/workflow.json"
}

echo "== refuse-on-guest.sh library =="

# Test 1: guest inactive → exit 0, no output
proj=$(mk_project)
out=$(cd "$proj" && bash -c ". '$LIB' && refuse_if_guest docs-scaffold" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "inactive: exit 0, no output"
else
  fail "inactive: exit 0, no output" "rc=$rc out=$out"
fi
rm -rf "$proj"

# Test 2: guest active → exit 1, prints expected message to stderr
proj=$(mk_project)
activate_guest "$proj"
out=$(cd "$proj" && bash -c ". '$LIB' && refuse_if_guest docs-scaffold" 2>&1)
rc=$?
expected_action="refusing docs-scaffold"
expected_hint="Run /loom-guest off to override"
if [ "$rc" -eq 1 ] \
  && echo "$out" | grep -q "Guest mode active" \
  && echo "$out" | grep -q "$expected_action" \
  && echo "$out" | grep -q "$expected_hint"; then
  pass "active: exit 1, default message contains action + override hint"
else
  fail "active: exit 1, default message" "rc=$rc out=$out"
fi
rm -rf "$proj"

# Test 3: stderr (not stdout) carries the message
proj=$(mk_project)
activate_guest "$proj"
stdout=$(cd "$proj" && bash -c ". '$LIB' && refuse_if_guest foo" 2>/dev/null)
stderr=$(cd "$proj" && bash -c ". '$LIB' && refuse_if_guest foo" 2>&1 >/dev/null)
if [ -z "$stdout" ] && echo "$stderr" | grep -q "Guest mode active"; then
  pass "active: message goes to stderr, stdout silent"
else
  fail "active: stderr routing" "stdout='$stdout' stderr='$stderr'"
fi
rm -rf "$proj"

# Test 4: custom override-hint replaces default trailing sentence
proj=$(mk_project)
activate_guest "$proj"
out=$(cd "$proj" && bash -c \
  ". '$LIB' && refuse_if_guest gitignore-edit 'Edit .gitignore by hand if needed.'" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] \
  && echo "$out" | grep -q "Edit .gitignore by hand if needed" \
  && ! echo "$out" | grep -q "Run /loom-guest off"; then
  pass "active: custom override-hint replaces default"
else
  fail "active: custom override-hint" "rc=$rc out=$out"
fi
rm -rf "$proj"

# Test 5: action-name interpolation works for any token
proj=$(mk_project)
activate_guest "$proj"
out=$(cd "$proj" && bash -c \
  ". '$LIB' && refuse_if_guest 'AUTOFIX:gitignore-worktrees'" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "AUTOFIX:gitignore-worktrees"; then
  pass "active: action-name interpolated verbatim"
else
  fail "active: action-name interpolation" "rc=$rc out=$out"
fi
rm -rf "$proj"

# Test 6: missing action arg is a usage error (exit 2)
proj=$(mk_project)
out=$(cd "$proj" && bash -c ". '$LIB' && refuse_if_guest" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "missing action arg → exit 2 (usage error)"
else
  fail "missing action arg → exit 2" "rc=$rc out=$out"
fi
rm -rf "$proj"

# ---------------------------------------------------------------------------
# Wire-in text-presence checks
# ---------------------------------------------------------------------------

echo
echo "== wire-in: /docs-scaffold =="

# Test 7: docs-scaffold.md sources the helper and calls refuse_if_guest
file="$LOOM_ROOT/commands/docs-scaffold.md"
if grep -q "refuse-on-guest.sh" "$file" \
  && grep -q "refuse_if_guest docs-scaffold" "$file"; then
  pass "docs-scaffold.md sources helper + calls refuse_if_guest docs-scaffold"
else
  fail "docs-scaffold.md wire-in" "(grep failed against $file)"
fi

echo
echo "== wire-in: /audit-project AUTOFIX =="

# Test 8: every AUTOFIX recipe in skills/audit-project/SKILL.md has a
# refuse_if_guest gate near it. We don't pin the exact placement — we
# just require that within ~30 lines after each `[AUTOFIX:<id>]`
# section header, a `refuse_if_guest` call referencing that recipe id
# appears. (The skill is split across multiple AUTOFIX section headers
# on lines like `**[AUTOFIX:bd-hooks]**`.)
skill_file="$LOOM_ROOT/skills/audit-project/SKILL.md"
recipes=(bd-hooks workflow-json gitignore-worktrees)
for recipe in "${recipes[@]}"; do
  # Grep for the refuse_if_guest call referencing this recipe.
  if grep -q "refuse_if_guest.*$recipe\|refuse_if_guest AUTOFIX:$recipe" "$skill_file"; then
    pass "audit-project SKILL.md gates AUTOFIX:$recipe with refuse_if_guest"
  else
    fail "audit-project SKILL.md gates AUTOFIX:$recipe" "(no refuse_if_guest reference for $recipe)"
  fi
done

# Test 9: SKILL.md sources the lib at least once
if grep -q "refuse-on-guest.sh" "$skill_file"; then
  pass "audit-project SKILL.md references refuse-on-guest.sh"
else
  fail "audit-project SKILL.md references refuse-on-guest.sh"
fi

# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
