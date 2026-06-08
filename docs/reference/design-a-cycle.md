# design-a-cycle — reference

> Above-bead campaign/arc orchestrator that drives a design cycle's
> Plan → Research → Architect → Soundness → Handoff cadence over the
> layered design substrate (L1 KG spine / L2 design-doc drawer / L3
> optional executable specs), gates on two-tier soundness, then hands
> off to `create-beads` to spawn the implementation epic.

`/design-a-cycle <topic>` is the unit loom never had — the generative
phase that sits ABOVE both beads and epics. It is **NOT a
bead-lifecycle activity recipe.** The sibling recipes
(`bugfix-a-bead`, `feature-a-bead`, `research-a-bead`, …) each work ONE
bead from claim to merged through a single RED→GREEN middle. A design
cycle has no single RED→GREEN: it ITERATES across many turns, SPAWNS
`research-a-bead`s to ground open questions, and ultimately SPAWNS an
implementation epic. Trying to claim/RED/GREEN/close a "design bead"
forces the iterative cadence into a leaf shape and loses the
spawn-children + spawn-epic arc.

It is **stateless beyond the substrate.** The orchestrator keeps no
private `.claude/` state file and no new bd entity. Its entire memory is
the L2 design-doc drawer's STATE HEADER (backed by the L1 KG). Each
invocation reads that state, decides the next cadence action, drives it,
and **precipitates** the result back into the substrate — reason in
prose, precipitate into structure.

**Two-tier soundness** gates the cadence (locked in `loom-5w6`). Tier-0
COHERENCE is the always-on floor: no unresolved `[CLARIFICATION]`
markers, every locked decision cites its grounding and names
options-considered + why-not, no decision violates a constitutional
invariant. Tier-1 EXECUTABLE-SPEC EMISSION is an OPTIONAL per-decision
ceiling — a locked decision with a natural testable altitude carries an
L3 spec (Given-When-Then or `INVARIANT:`). Forcing Tier-1 on every
decision would re-import the design→build mismatch the research
diagnosed, so it is optional by construction. The cycle loops until
Tier-0 is green before any handoff.

At **handoff**, once Tier-0 is green, the cycle runs
`beadpowers:create-beads` against the locked decisions to spawn the
implementation epic + its child beads. The handoff is enriched: each
bead carries a `Files:` line (the loom-asr fan-out convention), and each
bead spawned from a Tier-1 decision ALSO carries a `RED:` line holding
that decision's L3 spec verbatim. That `RED:` line is the contract
[`/dispatch-middle`](dispatch-middle.md)'s test-author consumes (the
loom-tdua → loom-5m94 interlock). The design cycle produces contracts;
it does not consume them — once the epic exists with contract-bearing
beads, the leaf recipes take it from there.

## Related

| Item | Page |
|---|---|
| The L2 drawer skeleton this scaffolds from | [design-doc template](design-doc-template.md) |
| The within-bead test→code pipeline that consumes its `RED:` lines | [dispatch-middle](dispatch-middle.md) |
| Recipe-family contrast (leaf recipes vs this orchestrator) | [Recipe family](../explanation/recipe-family.md) |
| Sibling research recipe (spawned per `[CLARIFICATION]`) | [All skills](skills/all-skills.md) |

## Skill source

The full orchestrator body is included verbatim below from
`skills/design-a-cycle/SKILL.md`. Edits go to the primitive, not this
page.

{%
  include-markdown "../../skills/design-a-cycle/SKILL.md"
  heading-offset=1
%}
