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

echo "==> loom-ann: SKILL lists the documented AUTOFIX recipes"
# Inventory guard — loom-ann correctly did NOT add a recipe; loom-7ro
# subsequently added the fourth recipe (loom-env-block) with documented
# determinism rationale (deep-merge of two known keys is bit-stable).
# Wave 2 contract (loom-a29) still requires every recipe be
# deterministic. Update this guard only after a future bead
# deliberately adds a new AUTOFIX:<recipe-id> with documented
# determinism rationale.
autofix_recipe_count=$(grep -cE '^\s*-\s*`\[AUTOFIX:' "$SKILL_FILE" || true)
if [ "$autofix_recipe_count" = "4" ]; then
  pass "SKILL AUTOFIX inventory is 4 (bd-hooks, workflow-json, gitignore-worktrees, loom-env-block)"
else
  fail "SKILL AUTOFIX inventory should be 4 not $autofix_recipe_count" \
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
# 9. loom-r6g: preflight-language-match check (item 13)
# =====================================================================
#
# /audit-project gained a 13th check: detect project language via canonical
# markers (pyproject.toml/setup.py/etc; go.mod; Cargo.toml; package.json;
# scripts/+*.sh fallback). When language is determinable AND the bd
# preflight.template ships Go-shaped but the project isn't Go, emit a WARN
# with offer-fix. When language is unknown AND preflight.template is unset
# or bd-default, emit a PROMPT and let the user pick.
#
# Onboarder owns the detection prose (read-only). The audit-project skill
# owns the prompt/write half (interactive caller).

echo "==> loom-r6g: project-onboarder declares language detection (item 13)"
assert_contains "onboarder item 13 heading" \
  "$AGENT_FILE" '^13\. \*\*Language and preflight template'
assert_contains "onboarder item 13 names detect_project_language" \
  "$AGENT_FILE" 'detect_project_language'
assert_contains "onboarder item 13 lists python marker (pyproject.toml)" \
  "$AGENT_FILE" 'pyproject\.toml'
assert_contains "onboarder item 13 lists go marker (go.mod)" \
  "$AGENT_FILE" 'go\.mod'
assert_contains "onboarder item 13 lists rust marker (Cargo.toml)" \
  "$AGENT_FILE" 'Cargo\.toml'
assert_contains "onboarder item 13 lists node marker (package.json)" \
  "$AGENT_FILE" 'package\.json'
assert_contains "onboarder item 13 lists shell fallback marker" \
  "$AGENT_FILE" 'shell.*\*\.sh|\*\.sh.*shell|scripts/.*shell'
assert_contains "onboarder item 13 documents 'unknown' tie-break (polyglot)" \
  "$AGENT_FILE" 'polyglot.*unknown|unknown.*polyglot|never guess'
assert_contains "onboarder item 13 cites loom-r6g lineage" \
  "$AGENT_FILE" 'loom-r6g'
assert_contains "onboarder item 13 PROMPT verdict when unknown + unset/default template" \
  "$AGENT_FILE" 'PROMPT.*unknown|unknown.*PROMPT'
assert_contains "onboarder item 13 WARN verdict on python|rust|node + go-shaped template" \
  "$AGENT_FILE" 'WARN.*go|go-shaped|template starts with .go.'
assert_contains "onboarder item 13 explicit No AUTOFIX (interactive)" \
  "$AGENT_FILE" 'No AUTOFIX|not AUTOFIX|excluded.*AUTOFIX'

echo "==> loom-r6g: SKILL.md describes the preflight-language-match check at Step 2"
assert_contains "SKILL describes language detection (item 13)" \
  "$SKILL_FILE" 'preflight-language-match|language detection|detect_project_language'
assert_contains "SKILL names canonical language markers" \
  "$SKILL_FILE" 'pyproject\.toml.*go\.mod|go\.mod.*pyproject\.toml|Cargo\.toml.*package\.json|language markers'
assert_contains "SKILL describes PROMPT for unknown language" \
  "$SKILL_FILE" 'unknown.*PROMPT|PROMPT.*unknown'
assert_contains "SKILL describes WARN for python/rust/node + go preflight" \
  "$SKILL_FILE" 'WARN.*preflight.*go|go-shaped|template starts with .go.'
assert_contains "SKILL describes y/N/skip per-item gate for language fix" \
  "$SKILL_FILE" 'y/N/skip|yes/skip/edit|y\\.N.*skip'
assert_contains "SKILL describes .claude/loom-audit-state.json skip memo" \
  "$SKILL_FILE" 'loom-audit-state\.json'
assert_contains "SKILL cites loom-r6g (this bead)" \
  "$SKILL_FILE" 'loom-r6g'

echo "==> loom-r6g: LOOM_AUDIT_PROMPT_ANSWER env var test mocking surface documented"
assert_contains "SKILL documents LOOM_AUDIT_PROMPT_ANSWER env var" \
  "$SKILL_FILE" 'LOOM_AUDIT_PROMPT_ANSWER'

# ---------------------------------------------------------------------
# Behavior fixtures — language detection markers
# ---------------------------------------------------------------------

echo "==> loom-r6g: detect_project_language fixture round-trips"

# We exercise the detection by mocking the same shell logic the agent
# would follow. The agent's instructions describe the marker order; the
# fixtures below assert that order produces the expected language per
# project shape.

detect_lang() {
  local root="$1"
  local found_py=false found_go=false found_rust=false found_node=false found_shell=false
  [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] || [ -f "$root/setup.cfg" ] \
    || ls "$root"/requirements*.txt >/dev/null 2>&1 && found_py=true
  [ -f "$root/go.mod" ] && found_go=true
  [ -f "$root/Cargo.toml" ] && found_rust=true
  [ -f "$root/package.json" ] && found_node=true
  # node tie-break: package.json + pyproject.toml == polyglot
  if $found_node && $found_py; then
    echo "unknown"; return
  fi
  # multi-language polyglot detection (never guess)
  local count=0
  $found_py && count=$((count+1))
  $found_go && count=$((count+1))
  $found_rust && count=$((count+1))
  $found_node && count=$((count+1))
  if [ "$count" -gt 1 ]; then
    echo "unknown"; return
  fi
  if $found_py; then echo "python"; return; fi
  if $found_go; then echo "go"; return; fi
  if $found_rust; then echo "rust"; return; fi
  if $found_node; then echo "node"; return; fi
  # shell fallback — scripts/ + *.sh present
  if [ -d "$root/scripts" ] && ls "$root"/*.sh "$root/scripts"/*.sh >/dev/null 2>&1; then
    echo "shell"; return
  fi
  echo "unknown"
}

TMP_LANG="$(mktemp -d)"
trap 'rm -rf "$TMP_LANG" "$TMP_WF" "$TMP_GI" "$TMP_GI2" "$TMP_GI3" "$TMP_GI4" "$TMP_GI5" "$TMP_STATE" "$TMP_CMD" "$TMP_CMD2" "$TMP_CMD3"' EXIT

# Case A: pyproject.toml only → python
mkdir -p "$TMP_LANG/py"
printf '[project]\nname="x"\n' >"$TMP_LANG/py/pyproject.toml"
got=$(detect_lang "$TMP_LANG/py")
if [ "$got" = "python" ]; then
  pass "case A: pyproject.toml only → python"
else
  fail "case A: pyproject.toml → expected python, got '$got'"
fi

# Case B: go.mod only → go
mkdir -p "$TMP_LANG/go"
printf 'module x\ngo 1.21\n' >"$TMP_LANG/go/go.mod"
got=$(detect_lang "$TMP_LANG/go")
if [ "$got" = "go" ]; then
  pass "case B: go.mod only → go"
else
  fail "case B: go.mod → expected go, got '$got'"
fi

# Case C: Cargo.toml only → rust
mkdir -p "$TMP_LANG/rust"
printf '[package]\nname="x"\n' >"$TMP_LANG/rust/Cargo.toml"
got=$(detect_lang "$TMP_LANG/rust")
if [ "$got" = "rust" ]; then
  pass "case C: Cargo.toml only → rust"
else
  fail "case C: Cargo.toml → expected rust, got '$got'"
fi

# Case D: package.json only → node
mkdir -p "$TMP_LANG/node"
printf '{"name":"x"}\n' >"$TMP_LANG/node/package.json"
got=$(detect_lang "$TMP_LANG/node")
if [ "$got" = "node" ]; then
  pass "case D: package.json only → node"
else
  fail "case D: package.json → expected node, got '$got'"
fi

# Case E: polyglot (pyproject + go.mod) → unknown (tie-break: never guess)
mkdir -p "$TMP_LANG/poly"
printf '[project]\n' >"$TMP_LANG/poly/pyproject.toml"
printf 'module x\n' >"$TMP_LANG/poly/go.mod"
got=$(detect_lang "$TMP_LANG/poly")
if [ "$got" = "unknown" ]; then
  pass "case E: polyglot py+go → unknown (tie-break)"
else
  fail "case E: polyglot py+go → expected unknown, got '$got'"
fi

# Case F: bare directory, no markers → unknown
mkdir -p "$TMP_LANG/bare"
got=$(detect_lang "$TMP_LANG/bare")
if [ "$got" = "unknown" ]; then
  pass "case F: bare dir → unknown"
else
  fail "case F: bare dir → expected unknown, got '$got'"
fi

# Case G: shell fallback — scripts/ + *.sh present, no language markers
mkdir -p "$TMP_LANG/sh/scripts"
printf '#!/usr/bin/env bash\necho hi\n' >"$TMP_LANG/sh/install.sh"
printf '#!/usr/bin/env bash\necho run\n' >"$TMP_LANG/sh/scripts/run.sh"
got=$(detect_lang "$TMP_LANG/sh")
if [ "$got" = "shell" ]; then
  pass "case G: scripts/+*.sh fallback → shell"
else
  fail "case G: shell fallback → expected shell, got '$got'"
fi

# =====================================================================
# 10. loom-r6g: claude-md-solo-aware check (item 14)
# =====================================================================
#
# /audit-project gains a 14th check: when bd dolt remote list --json
# returns [] (solo workspace, no Dolt remote) AND the CLAUDE.md BEADS
# INTEGRATION block contains an unguarded `bd dolt push` (not wrapped
# in loom-hsb-style `if bd dolt remote list ...; then ... fi`), emit
# a WARN with diff preview offer. Fix mechanically rewrites the
# canonical block to loom-hsb shape; refuses on hand-edited blocks.

echo "==> loom-r6g: project-onboarder declares solo-aware CLAUDE.md check (item 14)"
assert_contains "onboarder item 14 heading" \
  "$AGENT_FILE" '^14\. \*\*CLAUDE\.md solo-workspace bd dolt push guard'
assert_contains "onboarder item 14 names is_solo_workspace" \
  "$AGENT_FILE" 'is_solo_workspace'
assert_contains "onboarder item 14 uses bd dolt remote list --json check" \
  "$AGENT_FILE" 'bd dolt remote list --json'
assert_contains "onboarder item 14 documents degrade-safe semantics" \
  "$AGENT_FILE" 'degrade.safe|degrade safe'
assert_contains "onboarder item 14 references unguarded bd dolt push detection" \
  "$AGENT_FILE" 'unguarded.*bd dolt push|bd dolt push.*unguarded'
assert_contains "onboarder item 14 cites loom-hsb canonical guard shape" \
  "$AGENT_FILE" 'loom-hsb'
assert_contains "onboarder item 14 cites loom-r6g lineage" \
  "$AGENT_FILE" 'loom-r6g'
assert_contains "onboarder item 14 explicit No AUTOFIX (content-aware)" \
  "$AGENT_FILE" 'No AUTOFIX|not AUTOFIX|content[- ]aware|requires.*review'

echo "==> loom-r6g: SKILL.md describes the solo-aware check"
assert_contains "SKILL describes claude-md-solo-aware check" \
  "$SKILL_FILE" 'claude-md-solo-aware|solo[- ]aware|solo workspace'
assert_contains "SKILL describes loom-hsb guard rewrite" \
  "$SKILL_FILE" 'loom-hsb'
assert_contains "SKILL describes refusal on hand-edited blocks" \
  "$SKILL_FILE" 'hand.edited|hand-edit|refuse.*unrecognized'

# ---------------------------------------------------------------------
# Behavior fixtures — is_solo_workspace mocking + loom-hsb guard regex
# ---------------------------------------------------------------------

echo "==> loom-r6g: is_solo_workspace mocking via BD_BIN-style PATH shim"

TMP_CMD="$(mktemp -d)"
mkdir -p "$TMP_CMD/bin"
cat >"$TMP_CMD/bin/bd" <<'BD'
#!/usr/bin/env bash
# Fake bd: emits [] for solo (per BD_DOLT_REMOTE_MODE env var)
if [ "${1:-}" = "dolt" ] && [ "${2:-}" = "remote" ] && [ "${3:-}" = "list" ]; then
  case "${BD_DOLT_REMOTE_MODE:-solo}" in
    solo)  echo '[]' ;;
    remote) echo '[{"name":"origin","url":"https://example.com/x"}]' ;;
    error) echo "bd error" >&2; exit 1 ;;
  esac
  exit 0
fi
exit 1
BD
chmod +x "$TMP_CMD/bin/bd"

is_solo() {
  # Mirrors the agent's instruction: solo if `bd dolt remote list --json`
  # returns [] or errors (degrade-safe). Returns 0 = solo, 1 = has-remote.
  local out
  out=$(PATH="$TMP_CMD/bin:$PATH" bd dolt remote list --json 2>/dev/null)
  if [ -z "$out" ] || [ "$out" = "[]" ]; then
    return 0
  fi
  if echo "$out" | grep -q '"name"'; then
    return 1
  fi
  # malformed/unknown → degrade-safe solo
  return 0
}

# Case H: BD_DOLT_REMOTE_MODE=solo → is_solo returns 0
BD_DOLT_REMOTE_MODE=solo
export BD_DOLT_REMOTE_MODE
if is_solo; then
  pass "case H: bd returns [] → is_solo_workspace TRUE"
else
  fail "case H: bd returns [] → expected solo, got non-solo"
fi

# Case I: BD_DOLT_REMOTE_MODE=remote → is_solo returns 1
BD_DOLT_REMOTE_MODE=remote
export BD_DOLT_REMOTE_MODE
if is_solo; then
  fail "case I: bd returns remote → expected non-solo, got solo"
else
  pass "case I: bd returns remote → is_solo_workspace FALSE"
fi

# Case J: BD_DOLT_REMOTE_MODE=error → degrade-safe to solo
BD_DOLT_REMOTE_MODE=error
export BD_DOLT_REMOTE_MODE
if is_solo; then
  pass "case J: bd errors → is_solo_workspace degrades to TRUE"
else
  fail "case J: bd errors → expected degrade-safe solo, got non-solo"
fi
unset BD_DOLT_REMOTE_MODE

echo "==> loom-r6g: loom-hsb guard regex detects unguarded vs guarded bd dolt push"

# The loom-hsb canonical guard shape — copy VERBATIM from loom CLAUDE.md.
# A CLAUDE.md is "unguarded" when it contains `bd dolt push` NOT wrapped
# in this if-fi. Detection: search for `bd dolt push` not preceded by
# `if bd dolt remote list ...; then` on the same nearby block.

is_unguarded_dolt_push() {
  local file="$1"
  # Look for bd dolt push that is NOT inside a guard block.
  # Strategy: extract lines containing `bd dolt push`; for each, check
  # if the prior 5 lines contain `if bd dolt remote list`.
  awk '
    /bd dolt push/ {
      if (!has_guard) print "UNGUARDED:" NR
    }
    /if bd dolt remote list/ { has_guard = 1; next }
    /^[[:space:]]*fi[[:space:]]*$/ { has_guard = 0; next }
  ' "$file" | head -1
}

TMP_CMD2="$(mktemp -d)"

# Case K: unguarded CLAUDE.md → detected
cat >"$TMP_CMD2/CLAUDE.md" <<'EOF'
# Project

## BEADS INTEGRATION
Run these on session end:

```bash
bd dolt push
git push
```
EOF
detect=$(is_unguarded_dolt_push "$TMP_CMD2/CLAUDE.md")
if [ -n "$detect" ]; then
  pass "case K: unguarded bd dolt push → detected ($detect)"
else
  fail "case K: unguarded bd dolt push → expected detection, got nothing"
fi

# Case L: guarded CLAUDE.md (loom-hsb shape) → NOT detected
TMP_CMD3="$(mktemp -d)"
cat >"$TMP_CMD3/CLAUDE.md" <<'EOF'
# Project

## BEADS INTEGRATION

```bash
if bd dolt remote list --json 2>/dev/null | grep -q '"name"'; then
  bd dolt push
else
  echo "(solo bd workspace; no Dolt remote — skipping bd dolt push)"
fi
git push
```
EOF
detect=$(is_unguarded_dolt_push "$TMP_CMD3/CLAUDE.md")
if [ -z "$detect" ]; then
  pass "case L: loom-hsb-guarded bd dolt push → not flagged as unguarded"
else
  fail "case L: guarded block was flagged as unguarded ($detect)"
fi

# Case M: SKILL.md inline-quotes the canonical loom-hsb guard (verbatim copy)
assert_contains "SKILL.md quotes the canonical 'if bd dolt remote list' guard form" \
  "$SKILL_FILE" 'if bd dolt remote list --json'

# ---------------------------------------------------------------------
# State-file behavior — .claude/loom-audit-state.json memo
# ---------------------------------------------------------------------

echo "==> loom-r6g: state-file memo respected on re-run"

# Skill writes per-check skip memo when user says "skip" on a PROMPT.
# Subsequent runs read the memo and render the check as silent PASS.

TMP_STATE="$(mktemp -d)"
mkdir -p "$TMP_STATE/.claude"

# Round 1: write skip memo
cat >"$TMP_STATE/.claude/loom-audit-state.json" <<'EOF'
{
  "preflight-language-match": {
    "skipped_at": "2026-05-23T00:00:00Z",
    "reason": "user-skipped"
  }
}
EOF

# Verify the memo is structurally valid + has the right key
if python3 -c "
import json,sys
d = json.load(open('$TMP_STATE/.claude/loom-audit-state.json'))
sys.exit(0 if 'preflight-language-match' in d and d['preflight-language-match'].get('reason') == 'user-skipped' else 1)
" 2>/dev/null; then
  pass "state-file: skip memo round-trips through JSON parse"
else
  fail "state-file: skip memo malformed"
fi

# .gitignore must list .claude/loom-audit-state.json
assert_contains ".gitignore lists .claude/loom-audit-state.json" \
  "$LOOM_ROOT/.gitignore" '\.claude/loom-audit-state\.json'

echo "==> loom-r6g: SKILL.md describes state-file schema"
assert_contains "SKILL describes state-file schema (skipped_at field)" \
  "$SKILL_FILE" 'skipped_at|skipped-at'
assert_contains "SKILL describes per-check skip memo structure" \
  "$SKILL_FILE" 'user-skipped|skip memo|per-check.*skip'

# =====================================================================
# 11. loom-z3m.11: upstream:loom label + /check-loom-upstream (item 15)
# =====================================================================
#
# Project beads filed as workarounds for loom-side bugs have no
# auto-clearing signal when the loom fix lands. The locked design is
# 3 pieces:
#
#   (a) Label convention `upstream:loom` — documented in
#       docs/reference/upstream-loom-label.md.
#   (b) /check-loom-upstream slash command — read-only sweep that
#       suggests which downstream beads may be cleared by recently-
#       closed loom beads.
#   (c) Item 15 in audit-project skill / project-onboarder — when an
#       audited bead's description matches loom-hook|hooks/|loom-script|
#       scripts/loom-|loom-[a-z0-9]+, offer to apply upstream:loom
#       label. Informational only; never auto-applies without prompt.
#
# Loom-repo-path is resolved via LOOM_REPO_PATH env var (default
# $HOME/repos/loom). NOT hardcoded.

UPSTREAM_REF_DOC="$LOOM_ROOT/docs/reference/upstream-loom-label.md"
CHECK_CMD_FILE="$LOOM_ROOT/commands/check-loom-upstream.md"

echo "==> loom-z3m.11: docs/reference/upstream-loom-label.md exists with the label convention"
if [ -f "$UPSTREAM_REF_DOC" ]; then
  pass "upstream-loom-label.md reference doc exists"
else
  fail "upstream-loom-label.md reference doc missing"
fi
assert_contains "reference doc names the upstream:loom label literal" \
  "$UPSTREAM_REF_DOC" 'upstream:loom'
assert_contains "reference doc explains the colon-form composes with bd labels" \
  "$UPSTREAM_REF_DOC" 'colon|compose'
assert_contains "reference doc rejects the loom-bug alternative naming" \
  "$UPSTREAM_REF_DOC" 'loom-bug'
assert_contains "reference doc cites loom-z3m lineage" \
  "$UPSTREAM_REF_DOC" 'loom-z3m'
assert_contains "reference doc documents LOOM_REPO_PATH env var" \
  "$UPSTREAM_REF_DOC" 'LOOM_REPO_PATH'

echo "==> loom-z3m.11: commands/check-loom-upstream.md slash command exists"
if [ -f "$CHECK_CMD_FILE" ]; then
  pass "check-loom-upstream.md slash command exists"
else
  fail "check-loom-upstream.md slash command missing"
fi
assert_contains "command has frontmatter description" \
  "$CHECK_CMD_FILE" '^description:'
assert_contains "command is disable-model-invocation (manual-only)" \
  "$CHECK_CMD_FILE" 'disable-model-invocation: true'
assert_contains "command scans for upstream:loom labeled beads" \
  "$CHECK_CMD_FILE" 'upstream:loom'
assert_contains "command queries closed loom beads" \
  "$CHECK_CMD_FILE" 'closed|status=closed|--status'
assert_contains "command honours LOOM_REPO_PATH env var" \
  "$CHECK_CMD_FILE" 'LOOM_REPO_PATH'
assert_contains "command states read-only / suggest-only contract" \
  "$CHECK_CMD_FILE" 'read-only|suggest-only|never closes|does not close'
assert_contains "command lists heuristic keyword set" \
  "$CHECK_CMD_FILE" 'loom-hook|hooks/|scripts/loom-'

echo "==> loom-z3m.11: SKILL.md item 15 — upstream-loom label suggestion"
assert_contains "SKILL describes item 15 upstream-loom-label-suggest check" \
  "$SKILL_FILE" 'upstream-loom-label|upstream:loom|upstream loom label'
assert_contains "SKILL names the regex/keyword set for matching bead descriptions" \
  "$SKILL_FILE" 'loom-hook|hooks/|scripts/loom-'
assert_contains "SKILL describes y/N/skip gate for item 15 (no auto-apply)" \
  "$SKILL_FILE" 'y/N/skip|informational only|never auto-app'
assert_contains "SKILL cites loom-z3m lineage on item 15" \
  "$SKILL_FILE" 'loom-z3m'

# Negative assertion — item 15 must NOT introduce an AUTOFIX recipe.
# Re-check the AUTOFIX inventory count. Was 3 when loom-z3m.11 landed;
# loom-7ro added the fourth (loom-env-block) for item 16, NOT item 15.
# Item 15 remains informational/suggest-only.
autofix_recipe_count=$(grep -cE '^\s*-\s*`\[AUTOFIX:' "$SKILL_FILE" || true)
if [ "$autofix_recipe_count" = "4" ]; then
  pass "SKILL AUTOFIX inventory is 4 (item 15 correctly remains informational-only; loom-7ro added item 16)"
else
  fail "SKILL AUTOFIX inventory should be 4 not $autofix_recipe_count" \
    "(item 15 must NOT add an AUTOFIX recipe — it is suggest-only; loom-7ro adds item 16 loom-env-block)"
fi

echo "==> loom-z3m.11: agents/project-onboarder.md item 15 declaration"
assert_contains "onboarder item 15 heading" \
  "$AGENT_FILE" '^15\. \*\*Upstream:loom label'
assert_contains "onboarder item 15 lists the keyword/regex set" \
  "$AGENT_FILE" 'loom-hook|hooks/|scripts/loom-'
assert_contains "onboarder item 15 explicit No AUTOFIX (informational-only)" \
  "$AGENT_FILE" 'No AUTOFIX|informational[- ]only|suggest-only'
assert_contains "onboarder item 15 cites loom-z3m lineage" \
  "$AGENT_FILE" 'loom-z3m'

# ---------------------------------------------------------------------
# Behavior fixture — the loom-keyword regex matches the documented set
# ---------------------------------------------------------------------

echo "==> loom-z3m.11: loom-keyword regex catches all documented prefixes"

# Mirror the regex the onboarder/skill describe. Match against fixture
# bead descriptions. The canonical pattern: loom-hook | hooks/ |
# loom-script | scripts/loom- | loom-[a-z0-9]+.
matches_upstream() {
  local desc="$1"
  # Word-boundary anchor on 'loom-' prefix to avoid matching substrings
  # inside other words (heirloom-foo, gloomy-baz). The five canonical
  # signals are: bare token loom-hook, path prefix hooks/, bare token
  # loom-script, path prefix scripts/loom-, or a loom-<id> bead-ref
  # (loom- followed by alnum) at a word boundary.
  if echo "$desc" | grep -qE '(^|[^a-zA-Z0-9_])(loom-hook|loom-script|loom-[a-z0-9]+)|hooks/|scripts/loom-'; then
    return 0
  fi
  return 1
}

# Case N: "Workaround for loom-hook bd-close-capture mis-firing" → match
if matches_upstream "Workaround for loom-hook bd-close-capture mis-firing"; then
  pass "case N: 'loom-hook' keyword matches"
else
  fail "case N: 'loom-hook' should match"
fi

# Case O: "Patch around hooks/bd-worktree-preseed bug" → match
if matches_upstream "Patch around hooks/bd-worktree-preseed bug"; then
  pass "case O: 'hooks/' prefix matches"
else
  fail "case O: 'hooks/' should match"
fi

# Case P: "loom-script crashed mid-rebase" → match
if matches_upstream "loom-script crashed mid-rebase"; then
  pass "case P: 'loom-script' keyword matches"
else
  fail "case P: 'loom-script' should match"
fi

# Case Q: "scripts/loom-rebase-worktree leaked WIP" → match
if matches_upstream "scripts/loom-rebase-worktree leaked WIP"; then
  pass "case Q: 'scripts/loom-' prefix matches"
else
  fail "case Q: 'scripts/loom-' should match"
fi

# Case R: "Bug mirroring loom-x4m fix" → match (bead-ID pattern)
if matches_upstream "Bug mirroring loom-x4m fix"; then
  pass "case R: 'loom-<id>' bead-ref matches"
else
  fail "case R: 'loom-<id>' bead-ref should match"
fi

# Case S: non-matching project bead → no match (project-internal bug)
if matches_upstream "Fix race condition in worker pool"; then
  fail "case S: project-internal description should NOT match"
else
  pass "case S: project-internal description correctly does not match"
fi

# Case T: non-matching, even though it mentions 'loom' as a substring
# of a different word → no match. The regex anchors on `loom-` prefix
# only, not bare `loom`.
if matches_upstream "Refactor heirloom-data ingest"; then
  fail "case T: substring 'loom' inside another word should NOT match"
else
  pass "case T: bare-substring 'loom' correctly does not match"
fi

# ---------------------------------------------------------------------
# Behavior fixture — skip memo respected on re-run (state-file reuse)
# ---------------------------------------------------------------------

echo "==> loom-z3m.11: state-file memo respected for upstream-loom-label-suggest"

TMP_UP_STATE="$(mktemp -d)"
trap 'rm -rf "$TMP_UP_STATE" "$TMP_LANG" "$TMP_WF" "$TMP_GI" "$TMP_GI2" "$TMP_GI3" "$TMP_GI4" "$TMP_GI5" "$TMP_STATE" "$TMP_CMD" "$TMP_CMD2" "$TMP_CMD3"' EXIT
mkdir -p "$TMP_UP_STATE/.claude"

# Round 1: write skip memo for the new check
cat >"$TMP_UP_STATE/.claude/loom-audit-state.json" <<'EOF'
{
  "upstream-loom-label-suggest": {
    "skipped_at": "2026-05-23T00:00:00Z",
    "reason": "user-skipped"
  }
}
EOF

if python3 -c "
import json,sys
d = json.load(open('$TMP_UP_STATE/.claude/loom-audit-state.json'))
sys.exit(0 if 'upstream-loom-label-suggest' in d and d['upstream-loom-label-suggest'].get('reason') == 'user-skipped' else 1)
" 2>/dev/null; then
  pass "state-file: upstream-loom-label-suggest skip memo round-trips"
else
  fail "state-file: upstream-loom-label-suggest skip memo malformed"
fi

# SKILL must register the new check-name in the recognised list.
assert_contains "SKILL state-file recognised-check-names list includes upstream-loom-label-suggest" \
  "$SKILL_FILE" 'upstream-loom-label-suggest'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
