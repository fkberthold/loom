# Open a design cycle

To open or advance an above-bead design cycle — the generative phase
that locks decisions and emits contract-bearing beads — follow these
steps.

## Precondition

- The work is generative and will eventually become beads, but the
  contracts aren't locked yet (so there's nothing for an
  `<activity>-a-bead` recipe to consume).
- You have a `<topic>` for the cycle. A design cycle is an above-bead
  orchestrator, **NOT a bead or epic** — do not file it as one. Its
  state lives in the layered substrate.

If a contract is already locked and you just need to BUILD it, skip
this and go to the matching `<activity>-a-bead` recipe (or
[`/dispatch-middle <bead>`](./run-dispatch-middle.md) for the
within-bead test→code split).

## Steps

1. **Invoke the command.** Run `/design-a-cycle <topic>`. The
   orchestrator drives the cadence over the layered substrate (L1 KG
   spine / L2 design-doc drawer / L3 optional executable specs).

2. **Let Step 0 read existing STATE first.** On every invocation the
   orchestrator FIRST reads the current state — it never assumes a
   fresh cycle. It searches MemPalace for an existing design-doc drawer
   for `<topic>` and reads its **STATE HEADER** (cycle-number,
   soundness-status, locked-decisions, open `[CLARIFICATION]` markers,
   spawned research-bead IDs, target epic ID), plus the L1 KG. This
   guards against re-scaffolding over an in-flight cycle, which would
   wipe locked decisions and spawned-bead tracking.

3. **Scaffold only when none exists.** If Step 0 finds no design-doc
   drawer for `<topic>`, the orchestrator scaffolds one from
   `templates/design-doc/` via plain `sed` substitution of
   `{{ topic }}` and `{{ wing }}`, then files it as a drawer in the
   project's `<wing>/decisions` room. A fresh drawer starts at
   cycle-number 0, soundness-status red, one seed `[CLARIFICATION]`
   marker.

4. **Drive the cadence from state.** The orchestrator reads the state
   and proposes the next action rather than running a fixed script. The
   cadence is **Plan → Research → Architect → Soundness → (loop until
   green) → Handoff**:

   - **Plan** — set or refine direction via brainstorming; each
     unresolved fork becomes a `[CLARIFICATION]` marker.
   - **Research** — for each open `[CLARIFICATION]` marker that needs
     external or prior-art grounding, spawn a `research-a-bead` and
     record its ID in the STATE HEADER. When the research bead closes,
     its decision drawer becomes the grounding the Architect step
     cites. A marker answerable from the palace alone can be resolved
     inline without a bead.
   - **Architect** — precipitate each newly-locked decision into all
     three layers: L1 KG triples (using the soft recommended
     design-predicate set — `supersedes_design_of`, `grounded_in`,
     `emits_bead`, `soundness_tier`, `depends_on_invariant`), the L2
     drawer's Decisions-locked section, and — when the decision has a
     natural testable altitude — an optional L3 executable spec.

5. **Pass the Tier-0 soundness gate before handoff.** Run the
   soundness check after each Architect pass and loop the cadence until
   it is green. **Tier-0 (coherence)** is the always-on floor and is
   green only when:

   - no unresolved `[CLARIFICATION]` markers remain in the STATE
     HEADER;
   - every locked decision cites its grounding (a research drawer, a
     sibling bead, or a source URL);
   - every locked decision names options-considered + why-not;
   - no locked decision violates a recorded constitutional invariant.

   **Tier-1 (executable-spec emission)** is an OPTIONAL per-decision
   ceiling — a locked decision MAY carry an L3 spec at its natural
   altitude. Do NOT force Tier-1 on every decision and do NOT hand off
   until Tier-0 is green.

6. **Hand off via create-beads.** Once Tier-0 is green, the
   orchestrator runs `create-beads` against the locked decisions to
   spawn the implementation epic plus its child beads. Each bead
   carries a **`Files:` line** (the fan-out convention naming the paths
   it touches). Each bead spawned from a **Tier-1 decision** ALSO
   carries a **`RED:` line** holding the decision's L3 spec verbatim
   (its Given-When-Then scenario or `INVARIANT:`). That `RED:` line IS
   the contract [`/dispatch-middle`](./run-dispatch-middle.md)'s
   test-author later consumes. A bead from a Tier-0-only decision
   carries `Files:` but no `RED:` line — that is expected, not a gap.

7. **Resume on cold start.** `session-startup` (step 1d) surfaces
   active design cycles — open design-doc drawers with unresolved
   `[CLARIFICATION]` markers — alongside in-progress beads, so a fresh
   session can resume a cycle where it paused. Re-invoke
   `/design-a-cycle <topic>` to advance it.

## Outcome

The design cycle's state is precipitated into the substrate: locked
decisions live as L1 KG triples plus L2 drawer blocks, optional L3
specs are written, and — once Tier-0 is green — an implementation epic
exists with contract-bearing beads. The leaf `<activity>-a-bead`
recipes and `/dispatch-middle` take it from there.

## Related

- For the command and skill specification, see
  [reference: design-a-cycle](../reference/design-a-cycle.md).
- For the design-doc drawer skeleton the cycle scaffolds from, see
  [reference: design-doc template](../reference/design-doc-template.md).
- For the leaf recipes that build the emitted beads, see
  [reference: skills](../reference/skills/index.md).
- To run an emitted bead's middle, see
  [Run the dispatch-middle pipeline](./run-dispatch-middle.md).
