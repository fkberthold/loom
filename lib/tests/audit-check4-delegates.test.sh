#!/usr/bin/env bash
# Doc-presence tests for /audit-project --check=docs Check 4 delegating
# to the mechanized loom-docs engines (loom-wj26.3).
#
# Root cause fixed by loom-wj26.3: Check 4 (inclusion-glob symmetric
# coverage) re-derives the doc<->source comparison with a naive grep.
# When run in a repo that SHIPS the mechanized engines from
# loom-wjuo (scripts/loom-docs-catalogue, the index-table drift gate)
# and loom-itph (scripts/loom-docs-gen, the per-item nav-page + nav-block
# gate), Check 4 should DELEGATE the symmetric-coverage check to those
# scripts' `--check` modes and surface their findings, rather than
# re-deriving the comparison by grep. Projects WITHOUT those scripts
# keep the existing generic grep fallback.
#
# /audit-project is Claude-executed prose (a skill mode + a subagent
# detection recipe), so these are doc-presence tests over the two files
# loom-wj26.3 owns: skills/audit-project/SKILL.md (Check 4 prose) and
# agents/project-onboarder.md (the read-only detection side). They
# assert the delegation instruction is present and names both engine
# scripts with their `--check` invocation; the generic grep survives as
# the named fallback for projects that lack the scripts.
#
# Run:  bash lib/tests/audit-check4-delegates.test.sh

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

# assert_flat: match a pattern against the newline-flattened file, so a
# multi-line prose statement still matches. Used for "X ... delegate ...
# Y" co-occurrence checks that span wrapped lines.
assert_flat() {
  local name="$1" file="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if tr '\n' ' ' <"$file" | grep -qE "$pattern"; then
    pass "$name"
  else
    fail "$name" "(flattened pattern not found in $file: $pattern)"
  fi
}

# =====================================================================
# SKILL.md — Check 4 prose delegates to BOTH engines
# =====================================================================
#
# INVARIANT (bead RED:): skills/audit-project/SKILL.md Check 4 prose
# instructs delegation to scripts/loom-docs-catalogue --check AND
# scripts/loom-docs-gen --check (not a re-derived grep) when those
# scripts are present.

assert_contains "SKILL names the catalogue engine" \
  "$SKILL_FILE" 'loom-docs-catalogue'
assert_contains "SKILL names the gen engine" \
  "$SKILL_FILE" 'loom-docs-gen'
assert_contains "SKILL invokes catalogue with --check" \
  "$SKILL_FILE" 'loom-docs-catalogue --check'
assert_contains "SKILL invokes gen with --check" \
  "$SKILL_FILE" 'loom-docs-gen --check'

# The SKILL must INSTRUCT delegation (an explicit verb), not merely
# mention the scripts. Flatten before matching so the verb and the
# script name can sit on different wrapped lines.
assert_flat "SKILL instructs DELEGATING Check 4 to the engines" \
  "$SKILL_FILE" \
  '([Dd]elegate|[Pp]refer|[Rr]un|[Ii]nvoke).*loom-docs-(catalogue|gen)'

# Both engines named in one delegation statement (catalogue AND gen).
assert_flat "SKILL delegates to BOTH catalogue AND gen" \
  "$SKILL_FILE" \
  '(loom-docs-catalogue.*loom-docs-gen|loom-docs-gen.*loom-docs-catalogue)'

# The generic grep survives as the explicit fallback for projects
# WITHOUT the engine scripts (so non-loom-managed projects keep working).
assert_flat "SKILL keeps the grep fallback for projects without the scripts" \
  "$SKILL_FILE" \
  '(without|absent|lack|don.t have|no).*(loom-docs-(catalogue|gen)|script).*(grep|fallback|generic)|(grep|fallback|generic).*(without|absent|lack|no).*(loom-docs|script)'

# Lineage cited: loom-wj26.3 + the engine beads.
assert_contains "SKILL cites loom-wj26.3 lineage" \
  "$SKILL_FILE" 'loom-wj26\.3'
assert_contains "SKILL cites loom-wjuo (catalogue) lineage" \
  "$SKILL_FILE" 'loom-wjuo'
assert_contains "SKILL cites loom-itph (gen) lineage" \
  "$SKILL_FILE" 'loom-itph'

# =====================================================================
# project-onboarder.md — read-only detection side mentions delegation
# =====================================================================
#
# The onboarder is read-only; it must MENTION that Check 4 / docs-drift
# inclusion-glob detection delegates to the engines when present, so its
# detection narrative stays aligned with the skill it points at.

assert_contains "onboarder names the catalogue engine" \
  "$AGENT_FILE" 'loom-docs-catalogue'
assert_contains "onboarder names the gen engine" \
  "$AGENT_FILE" 'loom-docs-gen'

assert_flat "onboarder mentions delegating to the engines when present" \
  "$AGENT_FILE" \
  '([Dd]elegate|[Pp]refer|[Rr]un|[Ii]nvoke|--check).*loom-docs-(catalogue|gen)|loom-docs-(catalogue|gen).*--check'

assert_contains "onboarder cites loom-wj26.3 lineage" \
  "$AGENT_FILE" 'loom-wj26\.3'

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
