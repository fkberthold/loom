#!/usr/bin/env bash
# Locking-spec test for .claude/rules/dispatched-agents.md.
#
# loom-g5k: the rule file must surface the three pre-flight smoke
# tests every dispatched worker runs before doing anything else:
#
#   1. Path    — pwd == git rev-parse --show-toplevel (Mode 1 / Mode 4)
#   2. Import  — python3 -c 'import <pkg>; print(<pkg>.__file__)' must
#                resolve to a worktree path (Mode 5 — landed in loom-rsk)
#   3. bd state — bd list -n 1 returns at least one issue, not empty
#                (Mode 3 — bd-state-empty fresh worktree, loom-x4m)
#
# Companion to loom-rsk's "## Python import resolution" section in the
# same file. g5k adds adjacent "## Pwd verification" and "## bd state
# preseed" sections so the three sections together form a single
# pre-flight battery.
#
# The rule file is prose, not code. These tests are doc-presence guards:
# the file must NAME each smoke test, its risk lineage, and its
# mechanical-fix pointer. If the prose evolves, update these patterns
# in the same commit.
#
# Run:  bash lib/tests/dispatched-agents-rule.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RULE_FILE="$LOOM_ROOT/.claude/rules/dispatched-agents.md"
SKILL_FILE="$LOOM_ROOT/skills/dispatch-middle/SKILL.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$RULE_FILE" ]; then
    fail "$name" "(file missing: $RULE_FILE)"
    return
  fi
  if grep -qE "$pattern" "$RULE_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

assert_file_contains() {
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

assert_not_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$RULE_FILE" ]; then
    fail "$name" "(file missing: $RULE_FILE)"
    return
  fi
  if grep -qE "$pattern" "$RULE_FILE"; then
    fail "$name" "(unwanted pattern found: $pattern)"
  else
    pass "$name"
  fi
}

# =====================================================================
# 1. All three pre-flight sections are present
# =====================================================================

echo "==> Four pre-flight sections form one battery"
assert_contains "section: Pwd verification" '^## Pwd verification'
assert_contains "section: Python import resolution (loom-rsk)" \
  '^## Python import resolution'
assert_contains "section: bd state preseed" '^## bd state preseed'
assert_contains "section: Base-freshness check (loom-6zi)" \
  '^## Base[- ]freshness check'

# =====================================================================
# 2. Pwd verification section (Mode 1 / Mode 4)
# =====================================================================

echo "==> Pwd verification section — risk + smoke + mechanical fix"
assert_contains "pwd risk cites Mode 1 / dispatcher absolute paths" \
  'Mode 1|absolute[- ]path|dispatcher.*brief'
assert_contains "pwd risk cites Mode 4 / relative-path resolution surprise" \
  'Mode 4|relative[- ]path resolution|symlink'
assert_contains "pwd smoke test uses git rev-parse --show-toplevel" \
  'git rev-parse --show-toplevel'
assert_contains "pwd smoke test compares against pwd" \
  '\bpwd\b'
assert_contains "pwd smoke uses realpath for symlink normalization" \
  'realpath'
assert_contains "pwd section points at loom-ymc edit-write-pwd-guard hook" \
  'loom-ymc|edit-write-pwd-guard'

# =====================================================================
# 3. Python import resolution section (loom-rsk — already landed)
# =====================================================================

echo "==> Python import section — already-shipped loom-rsk content preserved"
assert_contains "python smoke prints import file path" \
  "python3 -c 'import"
assert_contains "python mechanical-fix wrapper name" \
  'loom-worktree-python'
assert_contains "python section cites loom-rsk" 'loom-rsk'

# =====================================================================
# 4. bd state preseed section (Mode 3 / loom-x4m)
# =====================================================================

echo "==> bd state preseed section — risk + smoke + mechanical fix"
assert_contains "bd state risk cites Mode 3 / fresh-worktree empty dolt" \
  'Mode 3|empty dolt|fresh worktree|embedded.?dolt'
assert_contains "bd state smoke uses bd list -n 1" \
  'bd list -n 1'
assert_contains "bd state section points at loom-x4m preseed hook" \
  'loom-x4m|bd-worktree-preseed'

# =====================================================================
# 5. Aggregator: copy-pasteable "first bash call" block
# =====================================================================
#
# The acceptance criterion says workers should be able to copy-paste
# the smoke tests into their first bash call. So there should be a
# single fenced bash block somewhere in the file that contains all
# three checks together.

echo "==> First-bash-call aggregator block present"
# Look for a block that names all four smoke commands within a
# reasonable proximity (a single fenced bash block).
if awk '
  /^```bash/ { in_block=1; block=""; next }
  /^```/ && in_block { in_block=0;
    if (block ~ /git rev-parse --show-toplevel/ &&
        block ~ /import / &&
        block ~ /bd list -n 1/ &&
        block ~ /git merge-base[[:space:]]+HEAD[[:space:]]+main/ &&
        block ~ /git rev-parse[[:space:]]+main/) { found=1 }
    block=""; next
  }
  in_block { block = block "\n" $0 }
  END { exit (found ? 0 : 1) }
' "$RULE_FILE"; then
  pass "single fenced bash block contains all four smoke commands"
else
  fail "no single fenced bash block aggregates pwd + import + bd-list + base-freshness smokes"
fi

# =====================================================================
# 6. Anti-pattern: do NOT tell workers to "use relative paths"
# =====================================================================
#
# loom-ymc's Mode 4 showed relative-path guidance is wrong: relative
# paths can resolve OUTSIDE the worktree via symlinks. The rule file
# must not contain a bare "use relative paths" prescription.

echo "==> Anti-pattern: 'use relative paths' guidance is absent"
assert_not_contains "rule file does NOT say 'use relative paths'" \
  '[Uu]se relative paths?'

# =====================================================================
# 7. Bead lineage citations
# =====================================================================

echo "==> Bead-lineage citations present"
assert_contains "cites loom-g5k (this bead)" 'loom-g5k'
assert_contains "cites loom-rsk (Python sibling)" 'loom-rsk'
assert_contains "cites loom-ymc (pwd-guard mechanical fix)" 'loom-ymc'
assert_contains "cites loom-x4m (bd-worktree-preseed mechanical fix)" \
  'loom-x4m'
assert_contains "cites loom-6zi (base-freshness check origin)" 'loom-6zi'
assert_contains "cites loom-b1l (worker that surfaced the empty-branch no-op)" \
  'loom-b1l'
assert_contains "cites loom-azt (loom-rebase-worktree WIP-preserving wrapper)" \
  'loom-azt'

# =====================================================================
# 8. Base-freshness check section (loom-6zi)
# =====================================================================
#
# Empty-branch workers can pass `git rebase main` as a no-op (rc=0)
# even when the branch's merge-base trails main. The smoke battery
# must explicitly compare merge-base HEAD main against rev-parse main
# so staleness surfaces BEFORE work begins (not as confusing diff
# output post-commit, as in loom-b1l 2026-05-15).

echo "==> Base-freshness check section — risk + smoke + mechanical fix"
assert_contains "base-freshness risk names empty-branch rebase no-op" \
  'empty[- ]branch|no-op|fresh worker|rebase.*no-op|rebase is a no-op'
assert_contains "base-freshness smoke uses git merge-base HEAD main" \
  'git merge-base[[:space:]]+HEAD[[:space:]]+main'
assert_contains "base-freshness smoke uses git rev-parse main" \
  'git rev-parse[[:space:]]+main'
assert_contains "base-freshness section points at loom-rebase-worktree wrapper" \
  'loom-rebase-worktree'

# =====================================================================
# 9. Sampling-transparency return clause (loom-z3m.16)
# =====================================================================
#
# When a dispatched worker processes only a SAMPLE/subset of a larger
# set (it chose N-of-M items rather than all M), that fact must be
# surfaced explicitly in its return — the user must never have to ask
# "so you only did a sample?" (loom-z3m.1 f10, liza-base). The clause
# lives in BOTH the rule file's worker-report contract AND the
# dispatch-middle return contract, so codify presence in both.

echo "==> Sampling-transparency clause — rule file + dispatch-middle"
assert_contains "rule file names the Processed: X of Y report line" \
  'Processed:[[:space:]]*X of Y|Processed: X of Y'
assert_contains "rule file forbids silent sampling" \
  '[Nn]ever silently sample|do(es)? NOT silently sample|not silently sample'
assert_contains "rule file cites loom-z3m.16 sampling-transparency lineage" \
  'loom-z3m\.16|loom-z3m\.1'
assert_file_contains "dispatch-middle return contract carries Processed: X of Y" \
  "$SKILL_FILE" 'Processed:[[:space:]]*X of Y|Processed: X of Y'
assert_file_contains "dispatch-middle clause names sampled_of_total" \
  "$SKILL_FILE" 'sampled_of_total|sample.*total|sampled.*of.*total'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
