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
CLAUDE_FILE="$LOOM_ROOT/CLAUDE.md"

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
# 5. Battery steps are DISCRETE, independently-runnable commands
#    (loom-ta1w)
# =====================================================================
#
# This section previously asserted the OPPOSITE — that a single fenced
# bash block aggregated all four smokes into one copy-pasteable "first
# bash call". That aggregator is exactly what the worktree-isolation
# harness REFUSES to run. Empirically, from inside an isolation
# worktree (evidence gathered by the loom-ta1w worker):
#
#   ACCEPTED  pwd
#   ACCEPTED  realpath .
#   ACCEPTED  git merge-base HEAD main
#   ACCEPTED  git show main:<path>
#   ACCEPTED  cat f 2>/dev/null || echo "..."      (simple || RHS)
#   ACCEPTED  python3 -c 'import x; print(x)'      (quoted ; in args)
#   REFUSED   realpath "$(pwd)"                    "too complex to verify"
#   REFUSED   cmd || { echo ...; exit 1; }         "too complex to verify"
#   REFUSED   git -C /home/frank/repos/loom ...    "redirects git ... via -C"
#
# So the harness rejects COMMAND SUBSTITUTION and BRACE-GROUPING, and
# rejects `git -C` into the shared checkout. A battery a worker cannot
# run gets improvised, and an improvised battery is one nobody
# verified. Per gate-don't-advise (loom-wj26.1) this is a correctness
# invariant, so it gates here rather than living as prose nobody
# re-checks.
#
# Scope: bash blocks inside the "Pre-flight smoke battery" section,
# plus any block introduced by a "Pre-flight smoke test" label. Source
# EXAMPLES elsewhere in the file (the Mode 6 source-ladder snippet, the
# loom-worktree-python before/after) are deliberately out of scope —
# they are code to read, not commands a worker runs.

echo "==> Battery steps are discrete, harness-runnable commands"
battery_violations=$(awk '
  /^## / { section = substr($0, 4); sub(/[[:space:]]+$/, "", section); next }
  /^```bash/ {
    inblock = 1
    checking = (section ~ /^Pre-flight smoke battery/ || smokelabel)
    cmdcount = 0
    blockno++
    next
  }
  /^```/ && inblock {
    if (checking && cmdcount != 1) {
      printf "block %d (section: %s) has %d command lines; expected exactly 1\n", blockno, section, cmdcount
    }
    inblock = 0; checking = 0; smokelabel = 0
    next
  }
  inblock {
    if (!checking) next
    if ($0 ~ /^[[:space:]]*#/) next
    if ($0 ~ /^[[:space:]]*$/) next
    cmdcount++
    if ($0 ~ /\$\(/)   printf "block %d: command substitution $( ): %s\n", blockno, $0
    if ($0 ~ /`/)      printf "block %d: backtick substitution: %s\n", blockno, $0
    if ($0 ~ /[{}]/)   printf "block %d: brace grouping: %s\n", blockno, $0
    if ($0 ~ /git -C/) printf "block %d: git -C redirect: %s\n", blockno, $0
    if ($0 ~ /^[[:space:]]*(if|then|elif|else|fi|for|while|do|done)([[:space:]]|$)/) \
      printf "block %d: multi-statement shell keyword: %s\n", blockno, $0
    next
  }
  /Pre-flight smoke test/ { smokelabel = 1 }
' "$RULE_FILE")

if [ -z "$battery_violations" ]; then
  pass "every battery/smoke block is a single harness-runnable command"
else
  fail "battery contains blocks the isolation harness would refuse" \
    "$battery_violations"
fi

# The file must not prescribe `git -C <absolute main path>` ANYWHERE —
# that is the refusal three workers (vr6k, 8ztk, qo4j) each improvised
# a different ad-hoc fallback around.
assert_not_contains "no git -C into an absolute main-checkout path" \
  'git -C[[:space:]]+/'

# Brief authors must be told to present the steps as separate calls,
# since every loom worker brief pastes this battery.
assert_contains "prose tells brief authors to present steps as separate calls" \
  '[Ss]eparate [Bb]ash call|separate calls|one call per step|its own Bash call'

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
# 10. Worker-side leak check is EXECUTABLE from the worktree (loom-ta1w)
# =====================================================================
#
# A worker cannot inspect the main checkout: `git -C <main>` is refused
# by the isolation harness, and any absolute main path is refused by
# hooks/edit-write-pwd-guard.sh on the write-class tools. The worker's
# leak check must therefore go through git REFS, which are visible from
# inside the worktree, not through the main WORKING TREE path.

echo "==> Worker-side leak check section — executable from the worktree"
assert_contains "section: worker-side leak check" \
  '^## Worker-side leak check'
assert_contains "leak check uses branch-footprint diff against main ref" \
  'git diff --stat main HEAD'
assert_contains "leak check uses git show against the main REF for absence" \
  'git show main:'
assert_contains "leak-check section names the -C refusal it replaces" \
  'git -C|shared checkout'
assert_contains "leak-check section cites loom-ta1w" 'loom-ta1w'

# The Bash-level `git -C` refusal (harness) and the Edit/Write pwd
# guard (loom's own hook) are DIFFERENT mechanisms. Conflating them
# would teach workers to bypass a guard that is doing its job.
assert_contains "keeps harness-refusal distinct from the edit-write-pwd-guard" \
  'DISTINCT from the Edit/Write'

# =====================================================================
# 11. Repo-identity battery step + cross-repo dispatch UNSUPPORTED
#     (loom-stdi)
# =====================================================================
#
# `isolation: "worktree"` worktrees the DISPATCHING SESSION's repo —
# never whatever repo the brief happens to name. On 2026-07-25 central
# (cwd /home/frank/repos/loom) dispatched a liza_base bead with a brief
# opening "an isolated git worktree of liza_base (NOT loom)". The
# harness made a worktree of LOOM. Nothing caught it: not the harness,
# not any loom hook, not any battery step. Had the worker followed the
# brief's relative-path instruction it would have overwritten loom's own
# CLAUDE.md with a liza_base reconciliation.
#
# So the battery needs a step whose job is repo IDENTITY: the worker
# asserts the checkout it is in IS the repo its brief names, and ABORTS
# on mismatch. And the convention files must say, where brief authors
# read them, that cross-repo dispatch is UNSUPPORTED.

echo "==> Repo-identity battery step (loom-stdi)"
assert_contains "section: Repo identity" '^## Repo identity'
assert_contains "battery carries a numbered repo-identity step" \
  '[Ss]tep [0-9]+ — repo identity'
assert_contains "repo-identity smoke uses git remote -v" \
  'git remote -v'
assert_contains "repo-identity step ABORTS on mismatch" \
  'ABORT'
assert_contains "risk names the wrong-repo silent-failure shape" \
  'wrong repo|WRONG REPO'
assert_contains "wrong-repo shape is numbered as a Mode alongside 1-6" \
  'Mode 7'
assert_contains "repo-identity section cites loom-stdi" 'loom-stdi'

echo "==> Cross-repo dispatch declared UNSUPPORTED where brief authors read"
assert_contains "rule file declares cross-repo dispatch UNSUPPORTED" \
  '[Cc]ross-repo dispatch[^.]*UNSUPPORTED'
assert_contains "rule file states the dispatching session must be in the target repo" \
  'dispatching session must'
assert_file_contains "dispatch-middle declares cross-repo dispatch UNSUPPORTED" \
  "$SKILL_FILE" '[Cc]ross-repo dispatch[^.]*UNSUPPORTED'
assert_file_contains "CLAUDE.md carries the cross-repo dispatch convention" \
  "$CLAUDE_FILE" '[Cc]ross-repo dispatch'
assert_file_contains "CLAUDE.md cites loom-stdi" "$CLAUDE_FILE" 'loom-stdi'

# The inversion is the point: relative-path discipline (loom-tag's
# headline mitigation for the absolute-path leak) is what would have
# CAUSED the damage here, because it aims writes at the wrong repo's
# real files. The rule file must say so, or the next reader will treat
# the two guards as unconditionally complementary.
echo "==> Relative-path inversion is named, not left implicit"
assert_contains "repo-identity section names the loom-tag inversion" 'loom-tag'

# Contrast with Mode 6 (loom-8ztk), which deliberately added NO battery
# step: a bash-lib shadow is a property of the hooks, settled once in
# the repo by a gate. Repo identity is the opposite — a PER-DISPATCH
# property no repo-side gate can settle, because it depends on where the
# dispatching session happened to be sitting. The file now holds one
# example of each, so it must make the contrast explicit.
echo "==> Mode-6 contrast: per-dispatch vs settled-once-by-a-gate"
assert_contains "repo identity framed as a per-dispatch property" \
  'per-dispatch'
assert_contains "contrast explicitly references the Mode 6 / loom-8ztk case" \
  'loom-8ztk'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
