#!/usr/bin/env bash
# Grep-contract test for loom-ld4 — constitution surfacing at the
# three load points so it never gets forgotten:
#
#   1. session-startup SKILL.md  — a constitution-surfacing step that
#      reads .claude/project-constitution.md if present, surfaces a
#      one-line fingerprint, and soft-nudges /audit-project when a
#      loom-managed project LACKS it. Never blocks.
#   2. .claude/rules/dispatched-agents.md — a step 0 in the pre-flight
#      smoke battery that CATs the constitution (information, not
#      action) before pwd verification.
#   3. bugfix / feature / refactor -a-bead SKILL.md — a VERBATIM
#      phase-B re-read line ("re-read the constitution;
#      canonical_commands.test is authoritative") present, byte-
#      identical, in all three recipes. (research / cleanup / docs are
#      deliberately SKIPPED — they don't run project commands.)
#
# These are doc-presence + verbatim-identity guards. The files are
# prose, not code; if the prose evolves, update these patterns in the
# same commit.
#
# Run:  bash lib/tests/constitution-surfacing.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_STARTUP="$LOOM_ROOT/skills/session-startup/SKILL.md"
RULE_FILE="$LOOM_ROOT/.claude/rules/dispatched-agents.md"
BUGFIX="$LOOM_ROOT/skills/bugfix-a-bead/SKILL.md"
FEATURE="$LOOM_ROOT/skills/feature-a-bead/SKILL.md"
REFACTOR="$LOOM_ROOT/skills/refactor-a-bead/SKILL.md"

# The verbatim phase-B line. This exact string must appear byte-
# identical in all three recipe files. Keep it on one logical line.
PHASE_B_LINE='Re-read `.claude/project-constitution.md` if present — its `canonical_commands.test` is the authoritative test command for this project; run THAT, not a guessed-at command.'

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" pattern="$2" file="$3"
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

# Fixed-string presence (no regex interpretation) — used for the
# byte-identical verbatim phase-B line.
assert_contains_fixed() {
  local name="$1" needle="$2" file="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qF "$needle" "$file"; then
    pass "$name"
  else
    fail "$name" "(fixed string not found in $file)"
  fi
}

# =====================================================================
# 1. session-startup constitution step (constitution-surfacing step)
# =====================================================================

echo "==> session-startup: constitution-surfacing step"
assert_contains "names the constitution file path" \
  '\.claude/project-constitution\.md' "$SESSION_STARTUP"
assert_contains "surfaces a one-line fingerprint" \
  '[Ff]ingerprint' "$SESSION_STARTUP"
assert_contains "soft-nudges /audit-project when missing" \
  '/audit-project' "$SESSION_STARTUP"
assert_contains "never-blocks / soft-nudge framing" \
  '[Nn]ever (block|fail)|soft|nudge|never blocks?' "$SESSION_STARTUP"
assert_contains "the step is loom-managed-project conditional" \
  'loom[- ]managed' "$SESSION_STARTUP"
assert_contains "cites loom-ld4 lineage" 'loom-ld4' "$SESSION_STARTUP"

# =====================================================================
# 2. smoke-battery step 0 — cat the constitution before pwd check
# =====================================================================

echo "==> dispatched-agents: smoke-battery step 0 cats the constitution"
assert_contains "smoke battery names step 0 / constitution read" \
  '0\. .*[Cc]onstitution|[Cc]onstitution.*step 0' "$RULE_FILE"
assert_contains "step 0 cats .claude/project-constitution.md" \
  'cat[^|]*\.claude/project-constitution\.md' "$RULE_FILE"
assert_contains "step 0 framed as information not action" \
  '[Ii]nformation, not action' "$RULE_FILE"
assert_contains "rule file cites loom-ld4" 'loom-ld4' "$RULE_FILE"

# The step-0 cat must live INSIDE the aggregator fenced bash block,
# and BEFORE the pwd-verification (`git rev-parse --show-toplevel`)
# line — i.e. step 0 precedes step 1.
echo "==> step 0 cat precedes pwd verification in the aggregator block"
if awk '
  /^```bash/ { in_block=1; block=""; next }
  /^```/ && in_block { in_block=0;
    if (block ~ /\.claude\/project-constitution\.md/ &&
        block ~ /git rev-parse --show-toplevel/) {
      n=split(block, lines, "\n");
      cat_at=0; pwd_at=0;
      for (i=1;i<=n;i++) {
        if (lines[i] ~ /\.claude\/project-constitution\.md/ && cat_at==0) cat_at=i;
        if (lines[i] ~ /git rev-parse --show-toplevel/ && pwd_at==0) pwd_at=i;
      }
      if (cat_at>0 && pwd_at>0 && cat_at < pwd_at) found=1;
    }
    block=""; next
  }
  in_block { block = block "\n" $0 }
  END { exit (found ? 0 : 1) }
' "$RULE_FILE"; then
  pass "step-0 constitution cat appears before pwd check in aggregator block"
else
  fail "step-0 constitution cat NOT found before pwd check in a single bash block"
fi

# =====================================================================
# 3. verbatim phase-B line in all three recipes (byte-identical)
# =====================================================================

echo "==> phase-B verbatim line present in all three recipes"
assert_contains_fixed "bugfix-a-bead has the phase-B line" \
  "$PHASE_B_LINE" "$BUGFIX"
assert_contains_fixed "feature-a-bead has the phase-B line" \
  "$PHASE_B_LINE" "$FEATURE"
assert_contains_fixed "refactor-a-bead has the phase-B line" \
  "$PHASE_B_LINE" "$REFACTOR"

echo "==> phase-B line is byte-identical across the three recipes"
# Extract the matching line from each file and confirm all three are
# byte-for-byte identical to one another.
bug_line=$(grep -F "$PHASE_B_LINE" "$BUGFIX" 2>/dev/null | head -1)
feat_line=$(grep -F "$PHASE_B_LINE" "$FEATURE" 2>/dev/null | head -1)
ref_line=$(grep -F "$PHASE_B_LINE" "$REFACTOR" 2>/dev/null | head -1)
if [ -n "$bug_line" ] && [ "$bug_line" = "$feat_line" ] && [ "$feat_line" = "$ref_line" ]; then
  pass "phase-B line is byte-identical across bugfix/feature/refactor"
else
  fail "phase-B line differs across recipes" \
    "bugfix:   [$bug_line]
feature:  [$feat_line]
refactor: [$ref_line]"
fi

echo "==> phase-B line NOT added to deliberately-skipped recipes"
# research/cleanup/docs don't run project commands — they must NOT
# carry the line (guards against over-eager copy-paste).
for skipname in research cleanup docs; do
  skipfile="$LOOM_ROOT/skills/${skipname}-a-bead/SKILL.md"
  if [ -f "$skipfile" ]; then
    if grep -qF "$PHASE_B_LINE" "$skipfile"; then
      fail "${skipname}-a-bead should NOT carry the phase-B line"
    else
      pass "${skipname}-a-bead correctly omits the phase-B line"
    fi
  fi
done

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
