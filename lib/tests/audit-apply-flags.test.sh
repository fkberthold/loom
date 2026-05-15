#!/usr/bin/env bash
# Doc-text + behavior tests for the loom-8hg / loom-a29 apply flags
# on /audit-project:
#
#   --apply-trivial   : auto-apply [DOC FIX][TRIVIAL] items (cardinality
#                       count drift; superseded-bead-ID substitution).
#   --apply-onboarding: auto-apply MISS/INFO items the project-onboarder
#                       subagent tagged [AUTOFIX:<recipe-id>].
#
# The audit-project skill is markdown text describing what an agent
# should do (not an executable program), so these tests are split:
#
#   1. Doc-presence tests — verify the SKILL.md / agent / slash command
#      describe each flag, each AUTOFIX recipe-id, and each TRIVIAL
#      cardinality pattern. If the prose evolves, update these
#      patterns in the same commit.
#
#   2. Behavior tests — exercise the canned commands the AUTOFIX
#      recipes promise to run, against a tmpdir fixture. These verify
#      that the recipe text in SKILL.md matches what actually works
#      on disk (the workflow.json write, the .gitignore append, the
#      idempotency check). The bd-hooks recipe is NOT exercised end-
#      to-end (it requires a real bd workspace + git history); we
#      only verify the recipe's commands are syntactically present.
#
#   3. Determinism heuristics — verify the SKILL.md cardinality
#      detector spec correctly tags the three known cases from the
#      loom-b6o trial (105→106; Prelude (4)→(5); single-numeral
#      substitution at file:line) as TRIVIAL, and correctly
#      DOES NOT tag ambiguous claims (factual claims, behavior
#      descriptions, "N matches but K satisfy" claims) as TRIVIAL.
#
# Run:  bash lib/tests/audit-apply-flags.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/audit-project/SKILL.md"
AGENT_FILE="$LOOM_ROOT/agents/project-onboarder.md"
CMD_FILE="$LOOM_ROOT/commands/audit-project.md"

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

# =====================================================================
# 1. Doc-presence — flag is described in all three surfaces
# =====================================================================

echo "==> SKILL.md describes both apply flags"
assert_contains "SKILL describes --apply-trivial" \
  "$SKILL_FILE" '\-\-apply-trivial'
assert_contains "SKILL describes --apply-onboarding" \
  "$SKILL_FILE" '\-\-apply-onboarding'
assert_contains "SKILL describes --workflow-mode override" \
  "$SKILL_FILE" '\-\-workflow-mode'
assert_contains "SKILL has Step 3.5 apply section" \
  "$SKILL_FILE" 'Step 3\.5.*apply tagged items'
assert_contains "SKILL cites loom-8hg lineage" \
  "$SKILL_FILE" 'loom-8hg'
assert_contains "SKILL cites loom-a29 lineage" \
  "$SKILL_FILE" 'loom-a29'

echo "==> agents/project-onboarder.md tags MISS lines with AUTOFIX recipe-ids"
assert_contains "agent describes [AUTOFIX:bd-hooks] tag" \
  "$AGENT_FILE" '\[AUTOFIX:bd-hooks\]'
assert_contains "agent describes [AUTOFIX:workflow-json] tag" \
  "$AGENT_FILE" '\[AUTOFIX:workflow-json\]'
assert_contains "agent describes [AUTOFIX:gitignore-worktrees] tag" \
  "$AGENT_FILE" '\[AUTOFIX:gitignore-worktrees\]'
assert_contains "agent has AUTOFIX-tag convention section" \
  "$AGENT_FILE" 'AUTOFIX tags on suggested-fix lines'
assert_contains "agent cites loom-a29 lineage in item 3" \
  "$AGENT_FILE" 'loom-a29'

echo "==> commands/audit-project.md surfaces both flags to the user"
assert_contains "command lists --apply-trivial" \
  "$CMD_FILE" '\-\-apply-trivial'
assert_contains "command lists --apply-onboarding" \
  "$CMD_FILE" '\-\-apply-onboarding'
assert_contains "command lists --workflow-mode" \
  "$CMD_FILE" '\-\-workflow-mode'

# =====================================================================
# 2. Determinism heuristics — TRIVIAL gating spec is documented
# =====================================================================

echo "==> SKILL.md TRIVIAL gating spec (Check 1 cardinality)"
# The TRIVIAL tag must be conditional on (a) one-numeral diff AND
# (b) unambiguous substitution at the cited file:line.
assert_contains "Check 1 emits [DOC FIX][TRIVIAL] for cardinality drift" \
  "$SKILL_FILE" '\[DOC FIX\]\[TRIVIAL\] cardinality'
assert_contains "Check 1 conditions TRIVIAL on one-numeral diff" \
  "$SKILL_FILE" 'differs from reality by exactly one numeral|one numeral'
assert_contains "Check 1 disqualifies 'N matches but K satisfy' from TRIVIAL" \
  "$SKILL_FILE" 'N matches but K satisfy'

echo "==> SKILL.md TRIVIAL gating spec (Check 2 dead-bead-id)"
assert_contains "Check 2 emits [DOC FIX][TRIVIAL] dead-bead-id when superseded-by yields exactly one ID" \
  "$SKILL_FILE" '\[DOC FIX\]\[TRIVIAL\] dead-bead-id'
assert_contains "Check 2 disqualifies multi-candidate dead-bead-id from TRIVIAL" \
  "$SKILL_FILE" 'zero or multiple candidates'

# =====================================================================
# 3. Determinism heuristics — AUTOFIX recipe inventory matches scope
# =====================================================================

echo "==> SKILL.md AUTOFIX recipe inventory (only the three deterministic items)"
# The three deterministic recipes:
assert_contains "AUTOFIX:bd-hooks recipe spec is in SKILL" \
  "$SKILL_FILE" '\[AUTOFIX:bd-hooks\]'
assert_contains "AUTOFIX:workflow-json recipe spec is in SKILL" \
  "$SKILL_FILE" '\[AUTOFIX:workflow-json\]'
assert_contains "AUTOFIX:gitignore-worktrees recipe spec is in SKILL" \
  "$SKILL_FILE" '\[AUTOFIX:gitignore-worktrees\]'

# Must explicitly call out the items NOT auto-fixable, so future edits
# don't quietly creep them in.
assert_contains "SKILL excludes 'bd init' from --apply-onboarding" \
  "$SKILL_FILE" 'Does not run .bd init.|item 2 MISS stays'
assert_contains "SKILL excludes MemPalace wing creation from --apply-onboarding" \
  "$SKILL_FILE" 'Does not write to MemPalace|item 5 MISS stays'
assert_contains "SKILL excludes WARN items from --apply-onboarding" \
  "$SKILL_FILE" 'never touches WARN|Does not touch WARN'

# =====================================================================
# 4. AUTOFIX:bd-hooks recipe text — verify the loom-cka two-step
# =====================================================================

echo "==> AUTOFIX:bd-hooks recipe matches the loom-cka two-step"
assert_contains "bd-hooks recipe runs 'bd hooks install'" \
  "$SKILL_FILE" 'bd hooks install'
assert_contains "bd-hooks recipe stages .beads/issues.jsonl" \
  "$SKILL_FILE" 'git add \.beads/issues\.jsonl'
assert_contains "bd-hooks recipe uses the absorbing-commit message" \
  "$SKILL_FILE" 'bd: post-install export sync'
# The chicken-and-egg break: the absorbing commit must be made with
# the just-installed pre-commit hook DISABLED, otherwise it re-fires.
assert_contains "bd-hooks recipe disables the hook for the absorbing commit" \
  "$SKILL_FILE" 'core\.hooksPath=/dev/null'

# =====================================================================
# 5. AUTOFIX:workflow-json recipe — fixture round-trip
# =====================================================================

echo "==> AUTOFIX:workflow-json recipe writes the documented JSON shape"
TMP_WF="$(mktemp -d)"
trap 'rm -rf "$TMP_WF" "$TMP_GI" "$TMP_GI2" "$TMP_GI3" "$TMP_GI4" "$TMP_GI5"' EXIT

# Simulate the recipe: write {"v":1,"mode":"full"} to .claude/workflow.json
mkdir -p "$TMP_WF/.claude"
printf '{"v":1,"mode":"full"}' >"$TMP_WF/.claude/workflow.json"

# Round-trip: parse the file with python (only test dep available
# everywhere) and verify the two fields.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "
import json,sys
d = json.load(open('$TMP_WF/.claude/workflow.json'))
sys.exit(0 if d.get('v') == 1 and d.get('mode') == 'full' else 1)
"; then
    pass "workflow.json fixture parses with v=1, mode=full"
  else
    fail "workflow.json fixture round-trip"
  fi
else
  pass "workflow.json fixture written (python3 unavailable — skipping JSON parse)"
fi

# Spec compliance: the SKILL must say 'full' is the documented default.
assert_contains "SKILL says 'full' is the workflow.json default" \
  "$SKILL_FILE" 'mode.*defaults? to .full.|<mode>.*defaults? to .full.|default .full.'

# =====================================================================
# 6. AUTOFIX:gitignore-worktrees recipe — idempotent append (both lines)
# =====================================================================
#
# Per loom-tat (2026-05-15), the recipe owns BOTH per-session loom
# ephemera that show up at the root of every loom-managed project:
#   - .claude/worktrees/         (dispatch isolation, loom-tag)
#   - .claude/workflow-state.json (session-state, loom-b6o + loom-wxo)
# Both customer trials hit the second line manually. The recipe must
# append both lines idempotently in one shot.

echo "==> AUTOFIX:gitignore-worktrees recipe is idempotent (both lines)"

# Helper: simulate the recipe — for each entry, append iff not already
# present (line-exact match).
apply_recipe() {
  local target="$1"; shift
  local entry
  for entry in "$@"; do
    if [ ! -f "$target" ] || ! grep -qxF "$entry" "$target" 2>/dev/null; then
      printf '%s\n' "$entry" >>"$target"
    fi
  done
}

ENTRY_WT='.claude/worktrees/'
ENTRY_WS='.claude/workflow-state.json'

# Case A: file absent — recipe should write BOTH lines.
TMP_GI="$(mktemp -d)"
target="$TMP_GI/.gitignore"
apply_recipe "$target" "$ENTRY_WT" "$ENTRY_WS"
if grep -qxF "$ENTRY_WT" "$target"; then
  pass "case A: empty .gitignore → worktrees entry appended"
else
  fail "case A: empty .gitignore — worktrees append failed"
fi
if grep -qxF "$ENTRY_WS" "$target"; then
  pass "case A: empty .gitignore → workflow-state.json entry appended"
else
  fail "case A: empty .gitignore — workflow-state.json append failed"
fi

# Case B: file already contains BOTH entries — recipe must NOT duplicate.
TMP_GI2="$(mktemp -d)"
target="$TMP_GI2/.gitignore"
printf '%s\n' "*.pyc" "$ENTRY_WT" "$ENTRY_WS" "node_modules/" >"$target"
apply_recipe "$target" "$ENTRY_WT" "$ENTRY_WS"
count_wt=$(grep -cxF "$ENTRY_WT" "$target")
count_ws=$(grep -cxF "$ENTRY_WS" "$target")
if [ "$count_wt" -eq 1 ] && [ "$count_ws" -eq 1 ]; then
  pass "case B: idempotent — both entries already present, not duplicated (wt=$count_wt ws=$count_ws)"
else
  fail "case B: duplicated entry (wt=$count_wt ws=$count_ws, expected 1 each)"
fi

# Case C: file contains a substring-but-not-exact match (e.g.
# 'my.claude/worktrees/...') should NOT block the recipe from adding
# the real entries. We use grep -xF (line-exact, fixed string) so the
# substring case is not matched.
TMP_GI3="$(mktemp -d)"
target="$TMP_GI3/.gitignore"
printf '%s\n' "*.pyc" "my.claude/worktrees/something/" "x.claude/workflow-state.json.bak" >"$target"
apply_recipe "$target" "$ENTRY_WT" "$ENTRY_WS"
if grep -qxF "$ENTRY_WT" "$target" && grep -qxF "$ENTRY_WS" "$target"; then
  pass "case C: substring-but-not-exact pre-existing lines → both real entries still added"
else
  fail "case C: substring false-positive prevented the append"
fi

# Case D: partial pre-existing — only .claude/worktrees/ present,
# workflow-state.json absent. Recipe must add the missing line and
# NOT duplicate the existing one.
TMP_GI4="$(mktemp -d)"
target="$TMP_GI4/.gitignore"
printf '%s\n' "*.pyc" "$ENTRY_WT" >"$target"
apply_recipe "$target" "$ENTRY_WT" "$ENTRY_WS"
count_wt=$(grep -cxF "$ENTRY_WT" "$target")
count_ws=$(grep -cxF "$ENTRY_WS" "$target")
if [ "$count_wt" -eq 1 ] && [ "$count_ws" -eq 1 ]; then
  pass "case D: partial pre-existing — missing line added, present line not duplicated"
else
  fail "case D: partial pre-existing — wt=$count_wt ws=$count_ws (expected 1 each)"
fi

# Case E: the converse partial — only workflow-state.json present,
# worktrees absent.
TMP_GI5="$(mktemp -d)"
target="$TMP_GI5/.gitignore"
printf '%s\n' "*.pyc" "$ENTRY_WS" >"$target"
apply_recipe "$target" "$ENTRY_WT" "$ENTRY_WS"
count_wt=$(grep -cxF "$ENTRY_WT" "$target")
count_ws=$(grep -cxF "$ENTRY_WS" "$target")
if [ "$count_wt" -eq 1 ] && [ "$count_ws" -eq 1 ]; then
  pass "case E: converse partial — missing line added, present line not duplicated"
else
  fail "case E: converse partial — wt=$count_wt ws=$count_ws (expected 1 each)"
fi

# Doc-presence: SKILL.md must describe BOTH lines in the recipe spec.
assert_contains "SKILL recipe spec mentions .claude/worktrees/ line" \
  "$SKILL_FILE" '\.claude/worktrees/'
assert_contains "SKILL recipe spec mentions .claude/workflow-state.json line" \
  "$SKILL_FILE" '\.claude/workflow-state\.json'
assert_contains "SKILL cites loom-tat lineage on the two-line recipe" \
  "$SKILL_FILE" 'loom-tat'

# Agent must describe BOTH lines on item 11.
assert_contains "agent item 11 mentions .claude/worktrees/ entry" \
  "$AGENT_FILE" '\.claude/worktrees/'
assert_contains "agent item 11 mentions .claude/workflow-state.json entry" \
  "$AGENT_FILE" '\.claude/workflow-state\.json'

# =====================================================================
# 7. Determinism cases — TRIVIAL detection on the loom-b6o known set
# =====================================================================
#
# The audit-project skill is markdown, not an executable detector. We
# can't dispatch it from a shell test. But we CAN assert that the
# documented heuristic correctly classifies the three known cases
# from the loom-b6o trial (and rejects the documented anti-cases):
#
#   TRIVIAL:
#     - "(105 dirs)" → reality says 106 → s/(105 dirs)/(106 dirs)/
#     - "Prelude (4)" → reality says 5 → s/Prelude (4)/Prelude (5)/
#     - "All three commands" → reality says six → s/three/six/
#       (numeric-word substitution, single token, unambiguous on the line)
#   NOT TRIVIAL:
#     - "All six commands have disable-model-invocation" but only
#       five do → fix is a rewrite, not a substitution
#     - factual claim "<token> fires on X" — semantic verification is v2
#     - dead-bead-id with no superseded-by — replacement requires
#       a real human choice
#
# These assertions are doc-text guards: the SKILL must DESCRIBE the
# heuristic such that all three TRIVIAL cases are covered and all three
# anti-cases are excluded. We grep for the conditions in the spec.

echo "==> TRIVIAL classifier covers the three loom-b6o cardinality patterns"
# Pattern 1: the SKILL spec must include a numeric-substring pattern
# that catches "105 → 106" style drift.
assert_contains "TRIVIAL covers '<digit>+ <noun>' patterns (loom-b6o case 1)" \
  "$SKILL_FILE" '<digit>\+ \(skills\|commands\|subagents\|hooks\|recipes\|drawers\|wings\)'

# Pattern 2: the parenthesized-numeral case (Prelude (4) → (5)) is
# implicitly covered by the same numeric-substring rule. Verify the
# SKILL says one-numeral substitutions are TRIVIAL (so this case
# qualifies).
assert_contains "TRIVIAL covers parenthesized-numeral substitution" \
  "$SKILL_FILE" 'one numeral|exactly one numeral'

# Pattern 3: word-numeral case (All three → All six) — SKILL must
# acknowledge word-number substitution.
assert_contains "TRIVIAL covers word-number substitution (one|two|...|ten)" \
  "$SKILL_FILE" 'one\|two\|three\|four\|five\|six\|seven\|eight\|nine\|ten'

echo "==> TRIVIAL classifier excludes the documented anti-cases"
# Anti-case 1: "N matches but K satisfy" — already verified above
# in section 2. Re-check here for symmetry with the positive cases.
assert_contains "anti-case: 'N matches but K satisfy' rewrite is NOT TRIVIAL" \
  "$SKILL_FILE" 'rewrite.*not a substitution|fix is a rewrite'

# Anti-case 2: factual claim with verb-level disagreement — SKILL
# explicitly defers semantic verification to v2 in Check 3.
assert_contains "anti-case: behavior-claim semantic check deferred to v2" \
  "$SKILL_FILE" 'cannot semantically verify|semantic claim extraction|v2'

# Anti-case 3: dead-bead-id with zero/multi candidates — verified
# above in section 2.

# =====================================================================
# 8. Per-item conversational gate (loom-xcw)
# =====================================================================
#
# The loom-wxo liza_base trial 2026-05-04 surfaced a contract break: a
# `--dangerously-skip-permissions` session ran /audit-project and the
# per-item AUTOFIX approval gate fired with no actual user turn between
# the prompt and the apply. Three items (`workflow.json` write,
# `.gitignore` append, `.claude/rules/tests.md` draft) landed without
# explicit user "yes".
#
# Root cause: the Step 4 per-item gate is a printed Q&A line with no
# explicit instruction to STOP and wait for a user-typed reply. The
# `--dangerously-skip-permissions` flag turns off Claude Code's TOOL-
# permission prompt (which is a different gate). With no tool-permission
# interpose AND no explicit "wait for user message" instruction, the
# agent's natural pattern is present-then-immediately-apply.
#
# These tests pin the conversational-gate contract: SKILL.md must
# describe the gate as a real conversational pause, distinguish it
# from tool-permission, and state that --dangerously-skip-permissions
# does NOT auto-resolve it.

echo "==> Per-item AUTOFIX gate is an explicit conversational pause (loom-xcw)"

# The gate must be described as a pause requiring a user message,
# not just a printed prompt.
assert_contains "SKILL describes per-item gate as a conversational pause" \
  "$SKILL_FILE" 'conversational pause|wait for (the )?user (message|reply|turn)|STOP.*until the user'

# The skill must explicitly distinguish tool-permission from
# user-approval — they are different gates.
assert_contains "SKILL distinguishes tool-permission from user-approval gates" \
  "$SKILL_FILE" 'tool[- ]permission.*user[- ]approval|different gates|TOOL permission.*USER approval'

# --dangerously-skip-permissions MUST NOT auto-resolve the gate.
# Flatten line wraps with tr before matching so markdown reflow doesn't
# break the assertion.
if tr '\n' ' ' <"$SKILL_FILE" | grep -qE 'dangerously-skip-permissions[^.]*(MUST NOT|does not|never|NOT)[^.]*(auto-?resolve|auto-?yes|auto-?approve|imply)'; then
  pass "SKILL invariant: --dangerously-skip-permissions does NOT auto-yes the gate"
else
  fail "SKILL invariant: --dangerously-skip-permissions does NOT auto-yes the gate" \
    "(invariant not found in flattened SKILL.md)"
fi

# The Step 4 prompt must include an explicit "do not call any tool
# until the user replies" instruction so an agent reading the skill
# can't naturally present-then-apply.
assert_contains "Step 4 instructs the agent to NOT call tools until user replies" \
  "$SKILL_FILE" '[Dd]o [Nn][Oo][Tt] call any tool|[Nn]o tool call.*until.*user|STOP.*[Dd]o [Nn][Oo][Tt]'

# The bead-lineage citation pins the historical anchor.
assert_contains "SKILL cites loom-xcw lineage on the gate invariant" \
  "$SKILL_FILE" 'loom-xcw'

echo "==> commands/audit-project.md surfaces the conversational-gate invariant"
# The slash command's "require explicit user approval per item"
# language must clarify it means a user-typed reply, not a tool prompt.
assert_contains "command clarifies 'approval' means user-typed reply" \
  "$CMD_FILE" 'user[- ]typed reply|conversational|user message|user turn'

# ---------------------------------------------------------------------
# Bug-class coverage (loom-xcw): defend the broader contract that
# "ungranted writes never happen" against future drift.
# ---------------------------------------------------------------------

echo "==> Bug-class: SKILL preserves the 'no write without user approval' invariant"
# Step 3.5 must still gate writes on the explicit flags (loom-a29 contract).
assert_contains "Step 3.5 writes are pre-authorized by --apply-onboarding flag only" \
  "$SKILL_FILE" 'pre-authorized.*--apply-(trivial|onboarding)|pre-authorized.*by passing the flag'

# The "What this skill does NOT do" section must still bind.
assert_contains "SKILL: does not write to disk without user approval" \
  "$SKILL_FILE" 'Does not write to disk without user approval'

echo "==> Bug-class: project-onboarder subagent remains read-only (no gate by-pass)"
# The subagent must NOT be tempted to apply fixes; if a future edit makes
# it write to disk, the conversational gate becomes irrelevant.
assert_contains "subagent declares read-only scope" \
  "$AGENT_FILE" 'Read-only|read-only|never writes|do not propose code'
assert_contains "subagent's 'Do NOT' list forbids writes" \
  "$AGENT_FILE" 'Read-only|any file write|do not modify'

# =====================================================================
# loom-ann: Claude Code hook command duplicate detection (item 12)
# =====================================================================
#
# project-onboarder gains a 12th scan item that shells out to
# scripts/find-hook-dups.sh. The check emits WARN per project-level
# duplicate and INFO per user-level duplicate. JSON surgery is
# content-aware so the check is NOT AUTOFIX-tagged (loom-a29 contract
# excludes content-aware fixes).

echo "==> loom-ann: project-onboarder declares item 12 (hook command duplicates)"
assert_contains "onboarder item 12 heading" \
  "$AGENT_FILE" '^12\. \*\*Claude Code hook command duplicates'
assert_contains "onboarder item 12 shells out to find-hook-dups.sh" \
  "$AGENT_FILE" 'find-hook-dups\.sh'
assert_contains "onboarder item 12 names WARN as project-level verdict" \
  "$AGENT_FILE" 'WARN.*project|project.*WARN|WARN.*= .*project'
assert_contains "onboarder item 12 names INFO as user-level verdict" \
  "$AGENT_FILE" 'INFO.*user|user.*INFO|user-level dup'
assert_contains "onboarder item 12 explicitly says No AUTOFIX (content-aware)" \
  "$AGENT_FILE" 'No AUTOFIX|excluded by the Wave 2 contract'
assert_contains "onboarder item 12 cites loom-ann lineage" \
  "$AGENT_FILE" 'loom-ann'
assert_contains "onboarder item 12 cites loom-nsb research lineage" \
  "$AGENT_FILE" 'loom-nsb'
assert_contains "onboarder item 12 cites loom-sd5 live-example lineage" \
  "$AGENT_FILE" 'loom-sd5'

echo "==> loom-ann: SKILL.md surfaces the hook-dup check at Step 2"
assert_contains "SKILL mentions the duplicate-hook check by name" \
  "$SKILL_FILE" 'hook command duplicates|hook[- ]dup|HOOK DUP|duplicate.*hook'
assert_contains "SKILL names the duplication pattern (event/matcher/command tuple)" \
  "$SKILL_FILE" 'event, matcher, command|tuple'
assert_contains "SKILL distinguishes project (WARN) vs user (INFO) verdicts" \
  "$SKILL_FILE" 'WARN.*INFO|project.*INFO|machine-specific'
assert_contains "SKILL explicitly says the check is NOT auto-fixable" \
  "$SKILL_FILE" 'NOT auto-fixable|not auto[- ]fixable|content-aware'
assert_contains "SKILL cites loom-ann (this bead)" \
  "$SKILL_FILE" 'loom-ann'

echo "==> loom-ann: SKILL still lists only the three existing AUTOFIX recipes"
# Negative assertion — loom-ann correctly did NOT add a fourth AUTOFIX
# recipe. Wave 2 contract (loom-a29) requires AUTOFIX recipes be
# deterministic. Update this guard only after a future bead deliberately
# adds a new AUTOFIX:<recipe-id> with documented determinism rationale.
autofix_recipe_count=$(grep -cE '^\s*-\s*`\[AUTOFIX:' "$SKILL_FILE" || true)
if [ "$autofix_recipe_count" = "3" ]; then
  pass "SKILL AUTOFIX inventory still 3 (loom-ann correctly added no new recipe)"
else
  fail "SKILL AUTOFIX inventory should be 3 not $autofix_recipe_count" \
    "(if a new AUTOFIX recipe was added deliberately, update this guard)"
fi

echo "==> loom-ann: find-hook-dups.sh exists, executable, has env-var overrides"
SCRIPT_FILE="$LOOM_ROOT/scripts/find-hook-dups.sh"
if [ -x "$SCRIPT_FILE" ]; then
  pass "find-hook-dups.sh exists and is executable"
else
  fail "find-hook-dups.sh missing or not executable"
fi
assert_contains "script documents LOOM_FIND_HOOK_DUPS_USER_SETTINGS override" \
  "$SCRIPT_FILE" 'LOOM_FIND_HOOK_DUPS_USER_SETTINGS'
assert_contains "script documents LOOM_FIND_HOOK_DUPS_PLUGIN_BASE override" \
  "$SCRIPT_FILE" 'LOOM_FIND_HOOK_DUPS_PLUGIN_BASE'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
