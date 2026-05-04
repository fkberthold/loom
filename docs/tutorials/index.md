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

After your first shipped bead, the two narrated walkthroughs show
the full shape of the workflow on real, non-trivial beads. They are
longer reads — sit down with one when you have time to absorb the
detail.

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

## Honesty caveat

Both deeper walkthroughs were written close to the moment the
recipes were forged. Some details — settings.json hot-reload, slash
commands auto-dispatching subagents — are the *designed* shape, not
yet observed end-to-end at the time of writing. Where the
walkthroughs are aspirational rather than observed, an inline note
flags it. Trust the prose where it claims live verification; treat
the rest as a faithful design document.
