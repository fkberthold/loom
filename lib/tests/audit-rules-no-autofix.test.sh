#!/usr/bin/env bash
# Contract tests pinning the loom-d50 invariant:
#
#   /audit-project (+ the project-onboarder subagent) NEVER auto-drafts
#   or auto-applies `.claude/rules/<x>.md` CONTENT. For a project missing
#   a rules file it may SCAFFOLD an empty `[HUMAN AUTHOR]` stub or SUGGEST
#   one, but it must NOT write authored rule content. Rule text encodes
#   project conventions; a human authors it.
#
# RED → the loom-wxo liza_base trial (2026-05-04): a
# `--dangerously-skip-permissions` /audit-project run silently
# drafted+applied `.claude/rules/tests.md` content (project conventions)
# with no human authorship — violating the loom-a29 Wave-2 exclusion that
# listed `.claude/rules/` CONTENT as EXCLUDED from AUTOFIX. This test
# pins the fix so the regression cannot silently return.
#
# audit-project is Claude-executed prose (a skill + a subagent), so the
# testable surface is the CONTRACT the prose commits to. These
# grep-contract assertions pin the prose against silent drift — the same
# approach used by audit-mine-history-flag.test.sh and the other
# prose-surface checks in this suite.
#
# Run:  bash lib/tests/audit-rules-no-autofix.test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/skills/audit-project/SKILL.md"
ONB="$ROOT/agents/project-onboarder.md"

passed=0; failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_file() {
  [ -f "$1" ] || { fail "fixture file present" "(missing: $1)"; exit 1; }
}
assert_file "$SKILL"
assert_file "$ONB"

# =====================================================================
# 1. SKILL hard-excludes `.claude/rules/` CONTENT from auto-apply.
# =====================================================================
echo "==> 1. SKILL.md hard-excludes .claude/rules/ content from auto-apply"

# The exclusion must be stated explicitly, anchored on the rules dir.
if grep -qiE 'rules/.*(HARD[- ]EXCLUD|EXCLUD).*auto[- ]appl|(HARD[- ]EXCLUD|EXCLUD).*auto[- ]appl.*rules|never auto-?(draft|appl).*rule' "$SKILL"; then
  pass "SKILL states .claude/rules/ content is excluded from auto-apply"
else
  fail "SKILL does not explicitly exclude .claude/rules/ content from auto-apply"
fi

# The exclusion must name the scaffold-stub-or-suggest escape: an empty
# [HUMAN AUTHOR] stub OR a suggestion — never authored content.
if grep -qiE 'scaffold.*(\[HUMAN AUTHOR\]|stub).*(suggest|only)|(suggest|stub).*\[HUMAN AUTHOR\]|scaffold[- ]stub' "$SKILL"; then
  pass "SKILL describes the scaffold-stub-or-suggest-only rules fix"
else
  fail "SKILL does not describe scaffold-stub-or-suggest-only for rules files"
fi

# The [HUMAN AUTHOR] marker must appear in the rules-content context.
if grep -q '\[HUMAN AUTHOR\]' "$SKILL"; then
  pass "SKILL carries a [HUMAN AUTHOR] marker for human-authored content"
else
  fail "SKILL missing the [HUMAN AUTHOR] marker"
fi

# The exclusion must be lineage-tagged to loom-d50.
if grep -q 'loom-d50' "$SKILL"; then
  pass "SKILL cites loom-d50 lineage for the rules-content exclusion"
else
  fail "SKILL missing loom-d50 lineage tag"
fi

# =====================================================================
# 2. SKILL's Step 3.5 (the --apply-onboarding walk + 'does NOT do'
#    block) explicitly refuses authored rule content.
# =====================================================================
echo "==> 2. SKILL Step 3.5 'does NOT do' refuses authored rule content"

# Slice the Step 3.5 'What this step does NOT do' block.
block=$(awk '/#### What this step does NOT do/{flag=1} flag{print} /^### Step 4 /{if(flag)exit}' "$SKILL")
if [ -z "$block" ]; then
  fail "could not locate Step 3.5 'does NOT do' block in SKILL"
else
  if printf '%s' "$block" | grep -qiE 'rules/.*content|content.*rules/'; then
    pass "Step 3.5 'does NOT do' block names .claude/rules/ content"
  else
    fail "Step 3.5 'does NOT do' block does not mention .claude/rules/ content"
  fi
  if printf '%s' "$block" | grep -qiE 'never auto-?(draft|appl)|scaffold[- ]stub|HARD EXCLUSION'; then
    pass "Step 3.5 'does NOT do' block forbids auto-drafting/applying rule content"
  else
    fail "Step 3.5 'does NOT do' block does not forbid auto-drafting rule content"
  fi
fi

# =====================================================================
# 3. project-onboarder item 7 reports the rules gap as a
#    suggestion/stub — never drafts content, never tags AUTOFIX.
# =====================================================================
echo "==> 3. project-onboarder item 7 is suggest/stub, never content/AUTOFIX"

# Slice item 7 ('.claude/rules/ scaffolded ...') up to item 8.
item7=$(awk '/^7\. \*\*`\.claude\/rules\/`/{flag=1} flag{print} /^8\. /{if(flag)exit}' "$ONB")
if [ -z "$item7" ]; then
  fail "could not locate item 7 in project-onboarder"
else
  if printf '%s' "$item7" | grep -qiE 'never (draft|propose|author).*(content|rule)|scaffold.*\[HUMAN AUTHOR\]|stub'; then
    pass "onboarder item 7 says scaffold-stub / never-draft-content"
  else
    fail "onboarder item 7 does not pin scaffold-stub-not-content"
  fi
  # Item 7's line must NOT carry an APPLIED [AUTOFIX:<recipe-id>] tag.
  # Match the applied form (a concrete lowercase recipe id) — NOT the
  # `[AUTOFIX:...]` placeholder the prose uses to say "never tag this".
  if printf '%s' "$item7" | grep -qE '\[AUTOFIX:[a-z0-9-]+\]'; then
    fail "onboarder item 7 wrongly carries an applied [AUTOFIX:<id>] tag (rules content must never auto-apply)"
  else
    pass "onboarder item 7 carries NO applied [AUTOFIX:<id>] tag"
  fi
  if printf '%s' "$item7" | grep -q 'loom-d50'; then
    pass "onboarder item 7 cites loom-d50 lineage"
  else
    fail "onboarder item 7 missing loom-d50 lineage tag"
  fi
fi

# =====================================================================
# 4. The onboarder's AUTOFIX-tags exclusion list names '7 rules
#    content' as a do-not-tag item.
# =====================================================================
echo "==> 4. onboarder AUTOFIX exclusion list names rules content"
if grep -qiE 'Do NOT tag.*7 rules content|7 rules content' "$ONB"; then
  pass "onboarder do-not-tag list names '7 rules content'"
else
  fail "onboarder do-not-tag list does not name rules content"
fi

# =====================================================================
# 5. The onboarder's 'Do NOT' section forbids drafting rule content.
# =====================================================================
echo "==> 5. onboarder 'Do NOT' section forbids drafting rule content"
donot=$(awk '/^## Do NOT/{flag=1} flag{print}' "$ONB")
if printf '%s' "$donot" | grep -qiE 'rules/.*content|Draft or propose.*rules'; then
  pass "onboarder 'Do NOT' forbids drafting .claude/rules/ content"
else
  fail "onboarder 'Do NOT' does not forbid drafting rule content"
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
