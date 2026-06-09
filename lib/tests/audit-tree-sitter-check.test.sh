#!/usr/bin/env bash
# Behavior + doc-text tests for the /audit-project tree-sitter check
# (loom-qvs).
#
# Surfaced 2026-05-24 by mforth: `tree-sitter generate` against
# tree-sitter-mforth/ printed
#
#   Warning: No tree-sitter.json file found in your grammar, this file
#   is required to generate with ABI 15. Using ABI version 14 instead.
#
# tree-sitter 0.25+ (current default ABI 15) wants a tree-sitter.json
# sibling to grammar.js. Older grammar repos work fine without it but
# quietly fall back to ABI 14. The audit check catches the silent gap.
#
# /audit-project is Claude-executed prose (a skill mode + a subagent
# detection recipe), so this test is split the same way every other
# audit-project prose test in this suite is:
#
#   1. Behavior tests — exercise the DETERMINISTIC half of the check
#      against fixture project trees. The detection logic (find every
#      directory containing grammar.js; for each, check whether a
#      sibling tree-sitter.json exists; absent -> WARN, present -> OK)
#      is mechanical and MUST produce a stable verdict per tree. We
#      embed a reference implementation of the detector here (the
#      contract the SKILL.md / project-onboarder.md prose must
#      describe) and assert it against fixture trees: a grammar with
#      NO tree-sitter.json -> WARN; one WITH the sibling -> OK; a tree
#      with no grammar.js at all -> nothing to check.
#
#   2. Doc-presence tests — verify the SKILL.md / project-onboarder.md
#      prose (the two files loom-qvs owns) describes the check, the
#      ABI-15 warning message, and the recipe-only fix (`tree-sitter
#      init -p <dir>` is NEVER auto-run — it needs a TTY).
#
# The detector is the executable spec the prose carries; if the prose
# evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/audit-tree-sitter-check.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/audit-project/SKILL.md"
AGENT_FILE="$LOOM_ROOT/agents/project-onboarder.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" file="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in $file: $pattern)"
  fi
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name" "(expected '$expected', got '$actual')"
  fi
}

# =====================================================================
# Reference detection implementation — the contract the SKILL.md /
# project-onboarder.md prose must describe.
#
# Emits one line per grammar directory found under $1, sorted by path:
#
#   WARN <dir>    grammar.js present, NO sibling tree-sitter.json
#   OK   <dir>    grammar.js present, sibling tree-sitter.json present
#
# A tree with no grammar.js anywhere emits nothing (nothing to check).
#
# Heuristic (exactly the bead loom-qvs set):
#   - find any directory containing grammar.js (typically tree-sitter-*
#     subdirs, but naming is not assumed — the grammar.js marker is)
#   - for each, OK iff tree-sitter.json is a sibling, else WARN
# =====================================================================
detect_tree_sitter_gaps() {
  local root="$1"
  # Find every grammar.js under root; the dir holding it is a grammar dir.
  find "$root" -type f -name 'grammar.js' 2>/dev/null \
    | sort \
    | while IFS= read -r gjs; do
        local dir
        dir="$(dirname "$gjs")"
        if [ -f "$dir/tree-sitter.json" ]; then
          printf 'OK %s\n' "$dir"
        else
          printf 'WARN %s\n' "$dir"
        fi
      done
}

verdict_for() {
  # Return the verdict token (OK / WARN) for the grammar dir whose
  # basename is $2, scanning the detector output $1.
  printf '%s\n' "$1" | awk -v d="$2" '
    { n = split($2, parts, "/"); if (parts[n] == d) { print $1; exit } }'
}

# =====================================================================
# 1. Behavior — fixture project trees each detect the expected verdict.
# =====================================================================
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Fixture A: grammar.js with NO tree-sitter.json -> WARN ----
echo "==> Fixture A: grammar.js, NO tree-sitter.json -> WARN"
A="$TMP/proj-a"; mkdir -p "$A/tree-sitter-foo"
printf 'module.exports = grammar({ name: "foo", rules: {} });\n' \
  >"$A/tree-sitter-foo/grammar.js"
fpA="$(detect_tree_sitter_gaps "$A")"
assert_eq "A tree-sitter-foo is WARN (no sibling tree-sitter.json)" \
  "WARN" "$(verdict_for "$fpA" tree-sitter-foo)"

# ---- Fixture B: grammar.js WITH sibling tree-sitter.json -> OK ----
echo "==> Fixture B: grammar.js + sibling tree-sitter.json -> OK"
B="$TMP/proj-b"; mkdir -p "$B/tree-sitter-bar"
printf 'module.exports = grammar({ name: "bar", rules: {} });\n' \
  >"$B/tree-sitter-bar/grammar.js"
printf '{ "grammars": [{ "name": "bar", "scope": "source.bar" }] }\n' \
  >"$B/tree-sitter-bar/tree-sitter.json"
fpB="$(detect_tree_sitter_gaps "$B")"
assert_eq "B tree-sitter-bar is OK (sibling tree-sitter.json present)" \
  "OK" "$(verdict_for "$fpB" tree-sitter-bar)"

# ---- Fixture C: no grammar.js anywhere -> nothing to check ----
echo "==> Fixture C: no grammar.js -> no verdict lines"
C="$TMP/proj-c"; mkdir -p "$C/src"
printf '{"name":"app"}\n' >"$C/package.json"
fpC="$(detect_tree_sitter_gaps "$C")"
assert_eq "C emits no verdict lines (no grammar.js)" "" "$fpC"

# ---- Fixture D: non-standard grammar dir name (not tree-sitter-*) ----
#      The grammar.js marker drives detection, NOT the dir name.
echo "==> Fixture D: grammar.js in a non-tree-sitter-* dir -> WARN"
D="$TMP/proj-d"; mkdir -p "$D/grammars/mylang"
printf 'module.exports = grammar({ name: "mylang", rules: {} });\n' \
  >"$D/grammars/mylang/grammar.js"
fpD="$(detect_tree_sitter_gaps "$D")"
assert_eq "D detects grammar dir by grammar.js marker, not name -> WARN" \
  "WARN" "$(verdict_for "$fpD" mylang)"

# ---- Fixture E: mixed — one WARN, one OK ----
echo "==> Fixture E: two grammar dirs, one WARN + one OK"
E="$TMP/proj-e"
mkdir -p "$E/tree-sitter-aa" "$E/tree-sitter-bb"
printf 'grammar({});\n' >"$E/tree-sitter-aa/grammar.js"
printf 'grammar({});\n' >"$E/tree-sitter-bb/grammar.js"
printf '{}\n'           >"$E/tree-sitter-bb/tree-sitter.json"
fpE="$(detect_tree_sitter_gaps "$E")"
assert_eq "E tree-sitter-aa is WARN (no sibling)" \
  "WARN" "$(verdict_for "$fpE" tree-sitter-aa)"
assert_eq "E tree-sitter-bb is OK (sibling present)" \
  "OK" "$(verdict_for "$fpE" tree-sitter-bb)"

# =====================================================================
# 2. Doc-presence — SKILL.md documents the tree-sitter check.
# =====================================================================
echo "==> SKILL.md documents the tree-sitter check"
assert_contains "SKILL describes --check=tree-sitter flag" \
  "$SKILL_FILE" '\-\-check=tree-sitter'
assert_contains "SKILL cites loom-qvs lineage" \
  "$SKILL_FILE" 'loom-qvs'

echo "==> SKILL.md documents the detection + verdict logic"
assert_contains "SKILL: grammar.js is the detection marker" \
  "$SKILL_FILE" 'grammar\.js'
assert_contains "SKILL: tree-sitter.json sibling presence is the check" \
  "$SKILL_FILE" 'tree-sitter\.json'
assert_contains "SKILL: ABI 15 mentioned in the warning rationale" \
  "$SKILL_FILE" 'ABI 15'

echo "==> SKILL.md documents the recipe-only fix (never auto-run)"
assert_contains "SKILL: the fix recipe is tree-sitter init -p <dir>" \
  "$SKILL_FILE" 'tree-sitter init -p'
# tree-sitter init needs a TTY -> NEVER auto-run; recipe-only.
assert_contains "SKILL: recipe-only — tree-sitter init never auto-run (needs TTY)" \
  "$SKILL_FILE" '([Nn]ever auto-run|recipe-only|not.*auto-run|TTY)'

# =====================================================================
# 3. Doc-presence — project-onboarder.md carries the detection recipe.
# =====================================================================
echo "==> project-onboarder.md describes the tree-sitter detection recipe"
assert_contains "onboarder describes the tree-sitter check" \
  "$AGENT_FILE" 'tree-sitter'
assert_contains "onboarder: grammar.js is the detection marker" \
  "$AGENT_FILE" 'grammar\.js'
assert_contains "onboarder: tree-sitter.json sibling presence is the check" \
  "$AGENT_FILE" 'tree-sitter\.json'
assert_contains "onboarder: WARN verdict on absent tree-sitter.json" \
  "$AGENT_FILE" 'WARN'
# Recipe-only: the onboarder reports; tree-sitter init is never auto-run.
assert_contains "onboarder: recipe-only fix — tree-sitter init never auto-run" \
  "$AGENT_FILE" '(tree-sitter init|recipe-only|never auto-run|TTY)'
assert_contains "onboarder cites loom-qvs lineage" \
  "$AGENT_FILE" 'loom-qvs'

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
