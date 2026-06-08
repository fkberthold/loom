---
description: "Open or advance a design cycle for <topic>. Loads the design-a-cycle skill — the above-bead campaign/arc orchestrator that reads the design substrate's STATE (the L2 design-doc drawer header + L1 KG), scaffolds one from templates/design-doc/ if none exists, then drives the next cadence step: Plan (brainstorming) → Research (spawn research-a-beads for open [CLARIFICATION] markers) → Architect (precipitate locked decisions into L1 KG triples + L2 + optional L3 specs) → Soundness (Tier-0 coherence floor + optional Tier-1) → loop until green → Handoff (create-beads spawns the implementation epic; each Tier-1 decision's bead carries a RED: line). It produces contracts; the <activity>-a-bead recipes + /dispatch-middle consume them."
disable-model-invocation: true
---

Invoke the `design-a-cycle` skill and follow it exactly as presented.

If the user supplied a `<topic>` as the slash-command argument, treat
that as the design cycle's topic and start at the skill's Step 0 (read
the substrate STATE for `<topic>`). If no `<topic>` was supplied, ask
the user which topic to design before scaffolding or driving any step.

At Step 0: ALWAYS read the existing STATE HEADER first — do not assume
a fresh cycle. Re-scaffolding over an in-flight cycle wipes locked
decisions and spawned-bead tracking.

At Step 1: scaffold from `templates/design-doc/` (plain `sed`
substitution of `{{ topic }}` / `{{ wing }}`) into the project's
`<wing>/decisions` room ONLY when Step 0 found no existing drawer.

At the Soundness gate: do NOT hand off until Tier-0 (coherence) is
green — no unresolved `[CLARIFICATION]` markers, every locked decision
grounded + options/why-not + constitution-consistent. Loop the cadence
until green.

At Handoff: run `create-beads` against the locked decisions. Each bead
carries a `Files:` line; each bead from a Tier-1 decision ALSO carries
a `RED:` line (its Given-When-Then / `INVARIANT:`) parallel to the
`Files:` line — that line is the contract `/dispatch-middle` consumes.

This is an ABOVE-bead orchestrator, NOT a bead-lifecycle recipe. To
BUILD a bead whose contract is already locked, use the matching
`<activity>-a-bead` recipe or `/dispatch-middle <bead>` instead.
