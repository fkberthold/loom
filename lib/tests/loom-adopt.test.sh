#!/usr/bin/env bash
# Locking-spec (RED) contract test for the /loom-adopt orchestrator
# (loom-bn7.6).
#
# /loom-adopt is the one-shot "make this repo fully loom-standard"
# orchestrator. It COMPOSES existing loom primitives into a
# dependency-ordered phase machine; it does NOT re-implement any of
# them. This test pins the bead's locked contract against the skill
# prose + command wrapper so the contract cannot silently regress.
#
# CONTRACT (from loom-bn7.6 description):
#   P1 workflow-infra  — DELEGATE to audit-project --apply (DRY — do NOT
#                        re-enumerate the checklist).
#   P2 scripts/ scaffold — skip if loom-oxs not landed.
#   P3 docs-scaffold.
#   P4 history-mine    — needs the wing from P1; nests its OWN
#                        cost-preview gate.
#   P5 constitution + onboarding beads + wing tunnels — skip if
#      constitution (loom-8jz/ld4) not landed.
#   P2/P3 are order-independent.
#
#   Behavior: PER-PHASE CHECKPOINT interactivity (announce -> confirm ->
#   run -> show -> proceed; NOT one-shot autonomous, NOT per-file nag).
#   GRACEFUL DEGRADATION: unbuilt-primitive phases skipped with a logged
#   reason; the phase list is enumerated DYNAMICALLY from what is
#   installed. IDEMPOTENT + RESUMABLE: re-run = re-audit skip-satisfied +
#   incremental mine via watermark; interrupted -> resume the unfinished
#   phase. OUTPUT: an adoption report (installed / scaffolded / mined /
#   skipped-why / beads-filed).
#
# Primary target: skills/loom-adopt/SKILL.md (the phase machine prose).
# Secondary:      commands/loom-adopt.md (the thin slash-command wrapper)
#                 — where a clause is naturally documented in the wrapper
#                 too, the "_either" assertions accept a match in EITHER
#                 file.
#
# This is a grep-contract test (mirrors explore-contract.test.sh): it
# asserts each clause is DOCUMENTED in the prose, specific enough to pin
# the contract but loose enough not to forbid reasonable phrasing.
#
# Run:  bash lib/tests/loom-adopt.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/loom-adopt/SKILL.md"
CMD_FILE="$LOOM_ROOT/commands/loom-adopt.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert pattern is present in the skill prose. Required file: SKILL_FILE.
assert_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qiE "$pattern" "$SKILL_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in skill prose: $pattern)"
  fi
}

# Assert pattern is present in EITHER the skill prose or the command
# wrapper — used for clauses the thin wrapper may legitimately carry.
assert_contains_either() {
  local name="$1" pattern="$2"
  local files_present=0
  for f in "$SKILL_FILE" "$CMD_FILE"; do
    [ -f "$f" ] && files_present=$((files_present + 1))
  done
  if [ "$files_present" -eq 0 ]; then
    fail "$name" "(both files missing: $SKILL_FILE , $CMD_FILE)"
    return
  fi
  for f in "$SKILL_FILE" "$CMD_FILE"; do
    if [ -f "$f" ] && grep -qiE "$pattern" "$f"; then
      pass "$name"
      return
    fi
  done
  fail "$name" "(pattern not found in skill or command: $pattern)"
}

# Assert pattern is ABSENT from the skill prose — used to enforce the DRY
# anti-scope (do NOT re-enumerate the delegated checklist).
assert_absent() {
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qiE "$pattern" "$SKILL_FILE"; then
    fail "$name" "(pattern present but should be absent: $pattern)"
  else
    pass "$name"
  fi
}

# =====================================================================
echo "==> 0. Files exist + are shaped as a skill + a command"
# =====================================================================
if [ -f "$SKILL_FILE" ]; then pass "skills/loom-adopt/SKILL.md exists"
else fail "skills/loom-adopt/SKILL.md missing"; fi

if [ -f "$CMD_FILE" ]; then pass "commands/loom-adopt.md exists"
else fail "commands/loom-adopt.md missing"; fi

# Skill front-matter carries a name key.
assert_contains "skill front-matter has name key" '^name:[[:space:]]*loom-adopt'

# Command is manual-only (disable-model-invocation), matching the
# sibling write-heavy primitives (audit-project, docs-scaffold).
if [ -f "$CMD_FILE" ] && grep -qE '^disable-model-invocation:[[:space:]]*true' "$CMD_FILE"; then
  pass "command is manual-only (disable-model-invocation: true)"
else
  fail "command missing disable-model-invocation: true"
fi

# Command wrapper loads the skill rather than re-implementing it.
assert_contains_either "command wrapper invokes the loom-adopt skill" \
  'loom-adopt.*skill|invoke the .loom-adopt|`loom-adopt`'

# =====================================================================
echo "==> 1. Phase sequencing: P1..P5 dependency-ordered, P2/P3 order-independent"
# =====================================================================
# All five phases are named with their responsibility.
assert_contains "P1 workflow-infra phase named" \
  'P1.*(workflow.?infra|audit)|workflow.?infra.*P1'
assert_contains "P2 scripts scaffold phase named" \
  'P2.*scripts|scripts.*scaffold.*P2|scripts/ scaffold'
assert_contains "P3 docs-scaffold phase named" \
  'P3.*docs.?scaffold|docs.?scaffold.*P3'
assert_contains "P4 history-mine phase named" \
  'P4.*(history.?mine|mine.?history)|history.?mine.*P4'
assert_contains "P5 constitution phase named" \
  'P5.*constitution|constitution.*P5'

# P1 DELEGATES to audit-project --apply (the DRY composition seam).
assert_contains "P1 delegates to audit-project --apply" \
  'audit-project.*--apply|--apply-onboarding|/audit-project'

# P4 depends on the wing resolved in P1.
assert_contains "P4 history-mine needs the wing from P1" \
  'wing.*(from P1|P1)|P1.*wing'

# P2/P3 order-independence is documented.
assert_contains "P2 and P3 are order-independent" \
  'order.?independent|P2.?/.?P3|P2 and P3.*(either order|independent)'

# DRY anti-scope: the skill must NOT re-enumerate the audit checklist as
# its OWN enumerated work. P1 delegates wholesale; the onboarding items
# (bd-hooks / workflow.json / gitignore / env-block) live in
# audit-project, not here. The anti-pattern is the checklist copied in as
# this skill's own per-item AUTOFIX recipe list — signalled by the
# bracketed [AUTOFIX:<recipe>] form being PRESCRIBED here (which would
# mean the skill re-runs the recipes itself) rather than merely named in
# a delegate/do-not clause. We pin: the skill must explicitly state it
# does NOT re-enumerate the audit checklist, and must NOT carry the
# audit's [AUTOFIX:<id>] recipe-token form (that form belongs to
# audit-project's own report-walk, not here).
assert_contains "DRY: states it does not re-enumerate the audit checklist" \
  'do(es)? NOT re-enumerate|not re-enumerate the audit checklist|re-enumerate.*audit checklist'
assert_absent "DRY: does not carry the audit's [AUTOFIX:<id>] recipe-token form" \
  '\[AUTOFIX:'

# =====================================================================
echo "==> 2. Graceful degradation: dynamic phase list + skip-with-reason"
# =====================================================================
# The phase list is enumerated DYNAMICALLY from what is installed.
assert_contains "phase list enumerated dynamically from installed primitives" \
  'dynamic|enumerat.*install|install.*enumerat|detect.*(installed|present)'

# Unbuilt-primitive phases are SKIPPED with a LOGGED REASON.
assert_contains "unbuilt phases skipped" \
  'skip(ped)?'
assert_contains "skip carries a logged reason" \
  'logged reason|skip.*reason|reason.*skip|skipped-why'

# P2 skip condition (loom-oxs not landed) is documented.
assert_contains "P2 skip if scripts-scaffold (loom-oxs) not landed" \
  'loom-oxs|scripts.?scaffold.*(not (landed|installed|built|present|shipped))'

# P5 skip condition (constitution loom-8jz/ld4 not landed) is documented.
assert_contains "P5 skip if constitution (loom-8jz/ld4) not landed" \
  'loom-8jz|loom-ld4|constitution.*(not (landed|installed|built|present|shipped))'

# =====================================================================
echo "==> 3. Per-phase checkpoint interactivity (not autonomous, not per-file nag)"
# =====================================================================
# announce -> confirm -> run -> show -> proceed.
assert_contains "checkpoint loop: announce" 'announce'
assert_contains "checkpoint loop: confirm" 'confirm'
assert_contains "checkpoint loop: per-phase checkpoint named" \
  'per.?phase checkpoint|checkpoint.*phase|phase.*checkpoint'
# It is NOT one-shot autonomous AND NOT a per-file nag — the two
# explicitly-rejected extremes.
assert_contains "rejects one-shot autonomous extreme" \
  'not.*(one.?shot|autonomous)|one.?shot autonomous'
assert_contains "rejects per-file nag extreme" \
  'per.?file nag|not.*per.?file'

# =====================================================================
echo "==> 4. History-mine phase nests its OWN cost-preview gate"
# =====================================================================
assert_contains "P4 nests its own cost-preview / two-pass gate" \
  'cost.?preview|two.?pass.*gate|dry.?run.*go.?ahead|nests? (its )?own.*gate'
# Delegates to the loom-mine-history skill (does not re-implement the gate).
assert_contains "P4 delegates to loom-mine-history (does not re-implement)" \
  'loom-mine-history|/loom-mine-history'

# =====================================================================
echo "==> 5. Idempotent + resumable"
# =====================================================================
assert_contains "idempotent re-run documented" 'idempotent'
assert_contains "resumable documented" 'resum'
# Re-run = re-audit skip-satisfied + incremental mine via watermark.
assert_contains "re-run re-audits skip-satisfied items" \
  'skip.?satisfied|re.?audit|already.?(done|satisfied)'
assert_contains "incremental mine via watermark on re-run" \
  'watermark|incremental.*mine|incremental.*history'
# Interrupted -> resume the unfinished phase.
assert_contains "interrupted run resumes the unfinished phase" \
  'resume.*(unfinished|interrupted|phase)|interrupted.*resume|unfinished phase'

# =====================================================================
echo "==> 6. Output: adoption report (installed/scaffolded/mined/skipped-why/beads-filed)"
# =====================================================================
assert_contains "emits an adoption report" 'adoption report'
assert_contains "report covers installed" 'installed'
assert_contains "report covers scaffolded" 'scaffold'
assert_contains "report covers mined" 'mined'
assert_contains "report covers skipped-why" 'skipped.?why|skipped.*reason|skip.*reason'
assert_contains "report covers beads-filed" 'beads.?filed|beads filed|filed.*bead'

# =====================================================================
echo "==> 7. Composition discipline: composes primitives, does not re-implement"
# =====================================================================
assert_contains "names itself a composing orchestrator" \
  'orchestrat|compose|composition'
# It explicitly delegates each phase to the owning primitive rather than
# doing the work itself (the friction the bead's DRY clause guards).
assert_contains "delegates each phase to the owning primitive" \
  'deleg'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
