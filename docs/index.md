# loom

Workflow infrastructure for Claude Code that weaves together
**beads** (issue tracker), **MemPalace** (memory), **superpowers**
(skills), and **beadpowers** (design→bead pipeline) into a single
disciplined developer workflow.

## What you're looking for

These docs are organised by intent. Pick the entry point that matches
why you're here.

<div class="grid cards" markdown>

-   :material-school:{ .lg .middle } **New to loom — teach me**

    ---

    Follow a guided narrative end-to-end. You'll install loom, claim
    a bead, walk through claim → verify → close → capture, and see
    every primitive fire on real work.

    [:octicons-arrow-right-24: Tutorials](tutorials/index.md)

-   :material-tools:{ .lg .middle } **I'm trying to do a specific thing**

    ---

    Task-oriented recipes for the already-competent user. Install
    loom, configure a hook, write a new skill, troubleshoot a stuck
    workflow.

    [:octicons-arrow-right-24: How-to guides](how-to/index.md)

-   :material-book-open-variant:{ .lg .middle } **Look up a fact**

    ---

    The austere catalogue. Every skill, slash command, subagent,
    hook, helper script, and CLI surface — auto-included from the
    primitives that ship with loom.

    [:octicons-arrow-right-24: Reference](reference/index.md)

-   :material-lightbulb:{ .lg .middle } **Help me understand why**

    ---

    The mental model. Why the four-axis memory split, why the recipe
    discipline, why the workflow modes. Design rationale, not
    instruction.

    [:octicons-arrow-right-24: Explanation](explanation/index.md)

</div>

## Status

v1.5 (workflow modes + state file + status line, shipped 2026-05-03).
All six activity-shaped recipes ship — `bugfix-a-bead`,
`feature-a-bead`, `refactor-a-bead`, `research-a-bead`,
`cleanup-a-bead`, `docs-a-bead` — plus the `upstream-a-bead`
contribution recipe and the `/working-a-bead` router.

The current frontier is two above-bead pieces (2026-06-07): the
`/design-a-cycle` orchestrator (epic loom-tdua) that drives a design
cycle's Plan→Research→Architect cadence over the layered design
substrate and gates on two-tier soundness before handing off to
`create-beads`; and the `/dispatch-middle` friction-inversion
pipeline (epic loom-5m94) that runs a bead's RED→GREEN middle as a
test-author → implementer pipeline of independent subagents so
dispatch becomes cheaper than inline.

The canonical loom design wing is now `loom/decisions` in MemPalace;
lineage to the v1/v1.5/v2 drawers in
`hundred_acre_woods/decisions` is carried by cross-project tunnels.
When the docs and the design diverge, MemPalace is design truth.
