#!/usr/bin/env bash
# Locking-spec test for the project-constitution schema artifacts (loom-vin).
#
# Four files implement the schema:
#   1. templates/project-constitution.md          — fillable template
#   2. .claude/project-constitution.md            — loom's own dogfooded sample
#   3. docs/reference/project-constitution.md     — Diataxis reference doc
#   4. references/project-constitution.schema.json — JSON Schema (draft 2020-12)
#
# This test asserts:
#   - Template carries every required front-matter key
#   - Loom's own constitution carries accurate values for loom
#     (shell.enter empty, package_manager=none, language.runtime=bash)
#   - Reference doc documents every field name from the schema
#   - JSON Schema parses as valid JSON
#
# Run:  bash lib/tests/project-constitution-schema.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$LOOM_ROOT/templates/project-constitution.md"
SAMPLE="$LOOM_ROOT/.claude/project-constitution.md"
REFDOC="$LOOM_ROOT/docs/reference/project-constitution.md"
SCHEMA="$LOOM_ROOT/references/project-constitution.schema.json"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_file_exists() {
  local name="$1" path="$2"
  if [ -f "$path" ]; then pass "$name"; else fail "$name" "(missing: $path)"; fi
}

assert_contains() {
  local name="$1" path="$2" pattern="$3"
  if [ ! -f "$path" ]; then fail "$name" "(file missing: $path)"; return; fi
  if grep -qE "$pattern" "$path"; then pass "$name"
  else fail "$name" "(pattern not found in $path: $pattern)"; fi
}

# =====================================================================
# 1. Files exist
# =====================================================================
echo "==> All four artifacts present"
assert_file_exists "template exists" "$TEMPLATE"
assert_file_exists "loom's own constitution exists" "$SAMPLE"
assert_file_exists "reference doc exists" "$REFDOC"
assert_file_exists "JSON Schema exists" "$SCHEMA"

# =====================================================================
# 2. Template front-matter coverage
# =====================================================================
echo "==> Template carries every required front-matter key"
for key in shell enter run_prefix package_manager language runtime version \
           forbidden canonical_commands build test lint gen dev bypass_patterns; do
  assert_contains "template names key: $key" "$TEMPLATE" "^[[:space:]]*${key}:"
done

# Template prose body should have TODO markers (no auto-generated prose).
assert_contains "template has TODO markers in prose body" "$TEMPLATE" 'TODO'

# =====================================================================
# 3. Loom's own constitution — accurate values
# =====================================================================
echo "==> Loom's own constitution carries loom-accurate values"
# shell.enter is empty (no project shell)
assert_contains "loom sample: shell.enter is empty string" "$SAMPLE" \
  '^[[:space:]]*enter:[[:space:]]*("")?[[:space:]]*$'
# shell.run_prefix is empty
assert_contains "loom sample: shell.run_prefix is empty string" "$SAMPLE" \
  '^[[:space:]]*run_prefix:[[:space:]]*("")?[[:space:]]*$'
# package_manager: none
assert_contains "loom sample: package_manager is none" "$SAMPLE" \
  '^[[:space:]]*package_manager:[[:space:]]+none[[:space:]]*$'
# language.runtime: bash
assert_contains "loom sample: language.runtime is bash" "$SAMPLE" \
  '^[[:space:]]*runtime:[[:space:]]+bash[[:space:]]*$'
# canonical_commands.test references bats or lib/tests
assert_contains "loom sample: test command references lib/tests or bats" \
  "$SAMPLE" 'lib/tests|bats'
# Prose body has TODO markers (Frank authors, not auto-generated)
assert_contains "loom sample: prose body has TODO markers" "$SAMPLE" 'TODO'

# =====================================================================
# 4. Reference doc — every field name documented
# =====================================================================
echo "==> Reference doc documents every front-matter field"
for key in shell enter run_prefix package_manager language runtime version \
           forbidden canonical_commands build test lint gen dev bypass_patterns; do
  assert_contains "refdoc mentions field: $key" "$REFDOC" "\\b${key}\\b"
done

# Reference doc must cite the bead lineage.
assert_contains "refdoc cites loom-vin" "$REFDOC" 'loom-vin'
assert_contains "refdoc cites parent epic loom-6f8" "$REFDOC" 'loom-6f8'

# =====================================================================
# 5. JSON Schema — valid JSON, declares schema dialect
# =====================================================================
echo "==> JSON Schema parses + declares draft 2020-12"
if [ -f "$SCHEMA" ]; then
  if python3 -c "import json,sys; json.load(open('$SCHEMA'))" 2>/dev/null; then
    pass "schema parses as valid JSON"
  else
    fail "schema parses as valid JSON" "(json.load failed)"
  fi
else
  fail "schema parses as valid JSON" "(file missing: $SCHEMA)"
fi
assert_contains "schema declares draft 2020-12" "$SCHEMA" \
  '2020-12/schema'
# Schema must declare every front-matter property at some nesting level.
for key in shell enter run_prefix package_manager language runtime version \
           forbidden canonical_commands build test lint gen dev bypass_patterns; do
  assert_contains "schema declares property: $key" "$SCHEMA" "\"${key}\""
done

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
