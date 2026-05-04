# Reference

Reference is the *application + cognition* quadrant: the austere,
factual catalogue of what loom ships. Reference pages are consulted,
not read sequentially. The voice is neutral; opinion lives in
[Explanation](../explanation/index.md).

> **What reference is not.** It does not teach, instruct, or argue.
> Recipes belong in [How-to](../how-to/index.md). Rationale belongs
> in [Explanation](../explanation/index.md). If a reference page
> grows opinions, file a bead.

## Canonical primitives

loom's primitives — skills, commands, agents, hooks, helpers — live
in this repository under `skills/`, `commands/`, `agents/`, `hooks/`,
`lib/`, and `scripts/`. The reference pages auto-include those files
via the `mkdocs-include-markdown` plugin, so the **primitive on disk
is the reference page**. Add a primitive, get a doc page; remove a
primitive, the page disappears. No hand-written summaries to drift.

## What's here

- [**Skill: session-startup**](skills/session-startup.md) — cold-start
  ritual, included verbatim from `skills/session-startup/SKILL.md`.

This page is currently a single-skill demonstration of the
include-markdown convention. Subsequent restructure beads
(loom-9z1.3) replace the explicit list above with a glob over
`skills/**/SKILL.md`, `commands/*.md`, `agents/*.md`, and
`hooks/*.sh`, so every primitive auto-publishes without nav edits.
