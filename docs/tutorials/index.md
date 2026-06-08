# Tutorials

Tutorials are guided walkthroughs. You follow along; the tutorial
picks the path. Each one takes you from a defined starting point to
a concrete, visible result, with the loom primitives firing at each
step so you see what the workflow actually does in motion.

> **What tutorials are not.** Tutorials are not how-to guides — those
> assume you already know what you want to do and need only the
> recipe. Tutorials are not reference — those describe the surface,
> not the journey. Tutorials are not explanation — those discuss the
> why, while tutorials stay focused on the doing.

## Start here

- [**Getting started: your first bead**](./getting-started.md) —
  install loom, open a session, claim a bead, ship it, file the
  decision drawer. About 3 minutes to read; about 10–20 minutes to
  do. Read this first if you have never used loom.

## Deeper walkthroughs

After your first shipped bead, the narrated walkthroughs show
the full shape of the workflow on real, non-trivial beads. They are
longer reads — sit down with one when you have time to absorb the
detail.

Both the bug and feature walkthroughs route their RED→GREEN middle
through `/dispatch-middle` — a test-author writes and commits the RED
test, then a *separate* implementer makes it GREEN from that committed
file alone. Central orchestrates and writes nothing in the middle. The
two-agent split is the anti-tautology guarantee, and it is the same on
both shapes; what differs is what the RED pins (a reproduced failure
for bugs, a desired contract for features).

- [**Bug walkthrough**](./bug-walkthrough.md) — a P3 cleanup bead
  from the Hundred Acre Woods project, end-to-end. Exercises the
  `bugfix-a-bead` recipe and the `bead-lifecycle-shell` phases. Has
  `[v1.5]` annotations showing where workflow modes, the per-project
  state file, and the status line participate.
- [**Feature walkthrough**](./feature-walkthrough.md) — a real loom
  bead (the v2 `/working-a-bead` router) from claim to close.
  Exercises the `feature-a-bead` recipe and shows how the variable
  middle of feature work differs from bug work (RED pins a contract,
  not a failure).
- [**Design-cycle walkthrough**](./design-cycle-walkthrough.md) — the
  layer *above* the leaf recipes. Walks `/design-a-cycle` from a bare
  topic through Plan→Research→Architect→Soundness to the handoff that
  spawns contract-bearing beads — the `RED:` lines the two
  walkthroughs above later consume. Read this when your work starts
  as a topic, not as a ready bead.

## Honesty caveat

The deeper walkthroughs were written close to the moment the
recipes were forged. Subagent dispatch — the test-author → implementer
pipeline the bug and feature walkthroughs show, and the research-bead
+ epic spawning the design-cycle walkthrough shows — is now observed
reality, not a design hope. A few peripheral details (settings.json
hot-reload timing) still vary by Claude Code version; where a
walkthrough is aspirational rather than observed, an inline note flags
it. Trust the prose where it claims live verification; treat the rest
as a faithful design document.
