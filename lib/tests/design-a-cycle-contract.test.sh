#!/usr/bin/env bash
# Locking-spec test for the /design-a-cycle orchestrator skill + command.
#
# loom-k0s8 (T2 of epic loom-tdua, design-phase system): the above-bead
# campaign/arc orchestrator that drives the Plan→Research→Architect
# cadence over the layered design substrate (L1 KG spine / L2 design-doc
# drawer / L3 optional executable specs) and hands off to create-beads.
#
# NOT a bead-lifecycle recipe — it ORCHESTRATES (spawns research-a-beads
# + an implementation epic) and is itself STATELESS beyond the substrate.
#
# Architecture locked in the /design-a-cycle build brainstorm CHECKPOINT
# drawer (loom/decisions, 2026-06-07), grounded in the three converged
# research drawers loom-l0f / loom-5w6 / loom-dwn. Key locked decisions:
#   D1 — v1 = recipe + convention + 1 template (templates/design-doc/);
#        no new helpers/hooks/generators.
#   D2 — /design-a-cycle is an ABOVE-BEAD ORCHESTRATOR (new conceptual
#        unit), NOT a bead — it iterates, spawns beads + an epic, has no
#        single RED→GREEN.
#   D3 — orchestrator state = SUBSTRATE-AS-STATE (the L2 design-doc
#        drawer's STATE HEADER + L1 KG); no new bd entity.
# Two-tier soundness (loom-5w6): Tier-0 coherence (always-on floor) +
# Tier-1 executable-spec emission (optional ceiling, per-decision).
#
# The skill + command are prose, not code. These tests are doc-presence
# guards: SKILL.md must NAME each cadence step, the soundness gate, the
# scaffold-from-template behavior, and the RED:-line handoff; the command
# must be a disable-model-invocation pass-through user door for <topic>.
# If the prose evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/design-a-cycle-contract.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/design-a-cycle/SKILL.md"
CMD_FILE="$LOOM_ROOT/commands/design-a-cycle.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Assert a pattern is present in a given file.
assert_in() {
  local file="$1" name="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qiE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

# =====================================================================
# 0. The two files exist
# =====================================================================
echo "==> Files exist"
[ -f "$SKILL_FILE" ] && pass "skills/design-a-cycle/SKILL.md exists" \
  || fail "skills/design-a-cycle/SKILL.md exists" "(missing: $SKILL_FILE)"
[ -f "$CMD_FILE" ] && pass "commands/design-a-cycle.md exists" \
  || fail "commands/design-a-cycle.md exists" "(missing: $CMD_FILE)"

# =====================================================================
# 1. Above-bead orchestrator framing (D2) — NOT a bead-lifecycle recipe
# =====================================================================
echo "==> Above-bead orchestrator framing (D2)"
assert_in "$SKILL_FILE" "names itself an above-bead orchestrator" \
  'above[- ]bead'
assert_in "$SKILL_FILE" "campaign/arc primitive framing" \
  'campaign|arc'
assert_in "$SKILL_FILE" "explicitly NOT a bead-lifecycle recipe" \
  '(not|isn.t).*(a )?(bead[- ]lifecycle )?(activity )?recipe|orchestrat'
assert_in "$SKILL_FILE" "stateless beyond the substrate (D3 substrate-as-state)" \
  'stateless|substrate[- ]as[- ]state|state.*(lives|in).*substrate'

# =====================================================================
# 2. Read-substrate-state-first + scaffold-from-template behavior
# =====================================================================
echo "==> Read substrate state; scaffold from templates/design-doc/ if none"
assert_in "$SKILL_FILE" "reads the design-substrate STATE on invocation" \
  '(read|reads).*(state|STATE HEADER|substrate)'
assert_in "$SKILL_FILE" "state = L2 drawer STATE HEADER + L1 KG" \
  'STATE HEADER'
assert_in "$SKILL_FILE" "scaffolds from templates/design-doc/ when none exists" \
  'templates/design-doc'
assert_in "$SKILL_FILE" "scaffold lands in the project wing" \
  '(project )?wing|decisions room|<wing>'
assert_in "$SKILL_FILE" "names the layered substrate (L1/L2/L3)" \
  'L1.*L2.*L3|L1 KG|layered substrate'

# =====================================================================
# 3. The cadence steps: Plan / Research / Architect / Soundness / Handoff
# =====================================================================
echo "==> Cadence steps documented"
assert_in "$SKILL_FILE" "cadence step: Plan (brainstorming)" \
  '(^|[^a-z])Plan([^a-z]|$)'
assert_in "$SKILL_FILE" "Plan invokes brainstorming to set/refine direction" \
  'brainstorm'
assert_in "$SKILL_FILE" "cadence step: Research (spawn research-a-beads)" \
  '(^|[^a-z])Research([^a-z]|$)'
assert_in "$SKILL_FILE" "Research spawns a research-a-bead per open marker" \
  'research-a-bead'
assert_in "$SKILL_FILE" "open [CLARIFICATION] markers drive Research" \
  '\[CLARIFICATION'
assert_in "$SKILL_FILE" "records spawned research-bead ID in the header" \
  '(record|records|write).*(research|bead).*(ID|id|header)|spawned research-bead'
assert_in "$SKILL_FILE" "cadence step: Architect (precipitate locked decisions)" \
  '(^|[^a-z])Architect([^a-z]|$)'
assert_in "$SKILL_FILE" "Architect precipitates into structure" \
  'precipitat'

# =====================================================================
# 4. Architect precipitation targets: L1 KG triples + L2 + optional L3
# =====================================================================
echo "==> Precipitation targets (L1 KG triples / L2 Decisions-locked / optional L3)"
assert_in "$SKILL_FILE" "precipitates into L1 KG triples" \
  'KG triple|kg triple|L1 KG'
assert_in "$SKILL_FILE" "soft recommended design-predicate set" \
  '(design[- ]predicate|predicate set|grounded_in|emits_bead|supersedes_design_of|soundness_tier)'
assert_in "$SKILL_FILE" "precipitates into the L2 Decisions-locked section" \
  'Decisions-locked|Decisions locked'
assert_in "$SKILL_FILE" "optional L3 executable spec" \
  'L3.*(spec|executable)|executable spec'

# =====================================================================
# 5. Soundness gate — Tier-0 floor (+ optional Tier-1) — loop until green
# =====================================================================
echo "==> Soundness gate (Tier-0 coherence + optional Tier-1; loop until green)"
assert_in "$SKILL_FILE" "names the soundness check" \
  'soundness'
assert_in "$SKILL_FILE" "Tier-0 coherence floor" \
  'Tier[- ]?0|tier 0|coherence'
assert_in "$SKILL_FILE" "Tier-0: no unresolved [CLARIFICATION] markers" \
  '(no|zero).*(unresolved|open).*(marker|CLARIFICATION)|markers.*resolved'
assert_in "$SKILL_FILE" "Tier-0: every locked decision cites grounding" \
  '(cite|cites|grounding).*(decision|grounding)|grounding'
assert_in "$SKILL_FILE" "Tier-0: constitution-consistent" \
  'constitution'
assert_in "$SKILL_FILE" "Tier-1 optional executable-spec ceiling" \
  'Tier[- ]?1|tier 1'
assert_in "$SKILL_FILE" "loop until green" \
  '(loop|iterate).*(until|till).*green|until green|green'

# =====================================================================
# 6. Handoff — create-beads with a RED: line per Tier-1 decision's bead
# =====================================================================
echo "==> Handoff to create-beads (RED: line parallel to Files: line)"
assert_in "$SKILL_FILE" "names the handoff step" \
  'handoff|hand[- ]off|hand off'
assert_in "$SKILL_FILE" "handoff runs create-beads against locked decisions" \
  'create-beads'
assert_in "$SKILL_FILE" "spawns an implementation epic" \
  'implementation epic'
assert_in "$SKILL_FILE" "each Tier-1 decision's bead carries a RED: line" \
  'RED:.*line|RED: line|a `RED:`|carries a RED'
assert_in "$SKILL_FILE" "RED: line is parallel to the Files: line" \
  'Files:.*line|parallel.*Files|Files: line'
assert_in "$SKILL_FILE" "RED: line content = Given-When-Then / invariant" \
  'Given.*When.*Then|invariant'

# =====================================================================
# 7. Drives ONE cadence step (or loop) from substrate state
# =====================================================================
echo "==> Drives the next action from state (one step or loop)"
assert_in "$SKILL_FILE" "proposes the next action from substrate state" \
  '(next action|next step|propose).*(state|cadence)|drive.*(one|next).*(step|action)'

# =====================================================================
# 8. Grounding / lineage cites
# =====================================================================
echo "==> Lineage cites (loom-tdua epic + grounding research)"
assert_in "$SKILL_FILE" "cites the loom-tdua epic" \
  'loom-tdua'

# =====================================================================
# 9. The command file is a disable-model-invocation pass-through door
# =====================================================================
echo "==> Command file: disable-model-invocation pass-through door for <topic>"
assert_in "$CMD_FILE" "command sets disable-model-invocation: true" \
  '^disable-model-invocation:[[:space:]]*true'
assert_in "$CMD_FILE" "command has a description frontmatter key" \
  '^description:'
assert_in "$CMD_FILE" "command passes through the <topic> argument" \
  '<topic>'
assert_in "$CMD_FILE" "command invokes the design-a-cycle skill" \
  'design-a-cycle'

# =====================================================================
# Summary
# =====================================================================
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
