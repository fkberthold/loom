# Explanation

Explanation is the *acquisition + cognition* quadrant: the wider,
reflective view. It is where loom answers *why this and not that?* —
admitting opinion, weighing alternatives, and connecting current
design choices back to the constraints they were chosen against. The
pages here are meant to be read, not consulted. They have a thesis;
they argue for it.

> **What explanation is not.** It does not give direct instruction
> (that is [How-to](../how-to/index.md)) and does not catalogue
> surface area (that is [Reference](../reference/index.md)).
> Step-by-step belongs in [Tutorials](../tutorials/index.md).
> If you find yourself reaching for a procedure or an exhaustive
> list, you have drifted out of this quadrant.

## What's here

- [**Mental model**](mental-model.md) — the four-axis memory split
  (beads / MemPalace drawers / KG / diary) and the rule that holds it
  together: *the discipline can't be skipped because the primitives
  enforce it.* Why splitting "knowledge that survives sessions" into
  four axes was load-bearing rather than cosmetic — plus the layered
  design substrate (L1 KG spine / L2 design-doc drawer / L3 optional
  specs) and the blocking-vs-nudging hook distinction.
- [**The recipe family**](recipe-family.md) — the six activity recipes
  as the *middle* of a three-layer model: a design cycle above (it
  produces the contracts), the family in the middle (each shape owns
  only its variable middle), and a dispatch pipeline within (it runs
  the middle as two independent agents). Why six and not one, each
  shape's central inversion, and what was rejected. The per-recipe
  specs live in [Reference](../reference/skills/index.md).
- [**Workflow modes**](workflow-modes.md) — why `full` / `light` /
  `off` exist as a mode triad rather than a single boolean, why
  ask-once-and-remember beats per-session prompting, and what was
  considered before settling on the per-project state file.
- [**Provenance**](provenance.md) — loom's lineage: v1
  (working-a-bead in HAW), v1.5 (workflow modes + state file),
  v2 (sibling recipes + bead-lifecycle-shell extraction), v3 (the
  design phase + dispatch-v2 — the above-bead `/design-a-cycle`
  orchestrator and the `/dispatch-middle` pipeline), and the
  loom-as-its-own-repo split. What loom is to its parent project
  Hundred Acre Woods, and why it became its own thing.

The three-layer model threads through these pages. The
**design-cycle** concept — an above-bead campaign/arc orchestrator
that produces contracts via two-tier soundness — is introduced in the
[recipe family](recipe-family.md) (its layer-above section) and its
substrate explained in the [mental model](mental-model.md). The
**dispatch posture** — dispatch the variable middle by default, inline
only as a justified exception, via the test-author → implementer
`/dispatch-middle` pipeline — runs through both the
[recipe family](recipe-family.md) (its layer-within section) and the
[mental model](mental-model.md) (the push/pull nudge).

## How to read these

Each page has a thesis at the top. If a page reads like a manual, it
has drifted; file a bead. If a page reads like an instruction sheet,
it has *really* drifted; file a stronger bead. Cross-references into
[Reference](../reference/index.md) and [How-to](../how-to/index.md)
are deliberate — explanation does not duplicate the surface or the
recipe; it explains why the surface is shaped the way it is and why
the recipe is the recipe.
