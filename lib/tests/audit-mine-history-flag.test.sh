#!/usr/bin/env bash
# Contract tests for the audit-project --mine-history flag + the
# project-onboarder decision-history informational gap line (loom-bn7.5).
#
# audit-project is Claude-executed prose (a skill + a subagent), so the
# testable surface is the CONTRACT the prose commits to: that the flag
# is documented + passed through, that delegation targets the already-
# tested /loom-mine-history engine, and that the gap line is
# INFORMATIONAL (never WARN/MISS, never AUTOFIX). These grep-contract
# assertions pin the prose against silent drift — the same approach used
# for other prose-surface checks in this suite.
#
# Run:  bash lib/tests/audit-mine-history-flag.test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CMD="$ROOT/commands/audit-project.md"
SKILL="$ROOT/skills/audit-project/SKILL.md"
ONB="$ROOT/agents/project-onboarder.md"

passed=0; failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }

# =====================================================================
# 1. Command doc documents the --mine-history pass-through flag.
# =====================================================================
echo "==> 1. commands/audit-project.md documents --mine-history"
if grep -q -- '--mine-history' "$CMD"; then
  pass "command doc mentions --mine-history"
else
  fail "command doc missing --mine-history"
fi

# =====================================================================
# 2. Skill documents the --mine-history flag + delegates to the
#    /loom-mine-history engine, AFTER the audit, only when set.
# =====================================================================
echo "==> 2. SKILL.md --mine-history delegation"
if grep -q -- '--mine-history' "$SKILL"; then
  pass "SKILL documents --mine-history"
else
  fail "SKILL missing --mine-history"
fi
if grep -qi 'loom-mine-history' "$SKILL"; then
  pass "SKILL delegates to the loom-mine-history engine"
else
  fail "SKILL does not reference loom-mine-history"
fi
# Default (no flag) must NOT auto-mine — only flag the gap.
if grep -qiE 'only flag|does not (auto-)?mine|never auto-mine|no flag.*flag' "$SKILL"; then
  pass "SKILL states default only flags the gap (never auto-mines)"
else
  fail "SKILL does not state the no-auto-mine default"
fi

# =====================================================================
# 3. project-onboarder has the decision-history informational item:
#    shells out to loom-mine-history --dry-run, INFO/PASS only, NO
#    AUTOFIX (mining is expensive — never auto-applied).
# =====================================================================
echo "==> 3. project-onboarder decision-history gap line"
if grep -qi 'loom-mine-history' "$ONB" && grep -qi 'dry-run' "$ONB"; then
  pass "onboarder probes via loom-mine-history --dry-run (zero spend)"
else
  fail "onboarder does not probe via loom-mine-history --dry-run"
fi
if grep -qiE 'unmined|decision[- ]history' "$ONB"; then
  pass "onboarder reports the unmined decision-history gap"
else
  fail "onboarder missing the decision-history gap line"
fi
# Must be informational — the gap-line item must NOT carry an AUTOFIX
# *tag* (the `[AUTOFIX:<id>]` bracket form that --apply-onboarding acts
# on). Note the prose legitimately says "No AUTOFIX tag", so match the
# bracket form, not the bare word.
block=$(awk '/[Dd]ecision[- ]history|unmined/{flag=1} flag{print} /^[0-9]+\. |^## /{if(flag && !/[Dd]ecision[- ]history|unmined/)exit}' "$ONB")
if printf '%s' "$block" | grep -q '\[AUTOFIX'; then
  fail "decision-history item wrongly carries an [AUTOFIX:...] tag (mining must not auto-apply)"
else
  pass "decision-history item carries NO [AUTOFIX:...] tag (informational only)"
fi
if printf '%s' "$block" | grep -qiE 'INFO|PASS'; then
  pass "decision-history item is INFO/PASS-shaped"
else
  fail "decision-history item not marked INFO/PASS"
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
