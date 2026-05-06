---
description: "Manage guest mode for the current repo. Activates loom's no-host-tree-pollution guardrails: skips docs-scaffold, refuses AUTOFIX in-tree writes, hides .claude/workflow.json from host's git via .git/info/exclude. Use when working in a repo where you're a guest contributor and shouldn't leave loom artifacts in the host tree."
disable-model-invocation: true
---

Run `bash scripts/loom-guest <subcommand>` from the repo root (or
`~/.claude/scripts/loom-guest <subcommand>` if loom is installed
globally — both resolve to the same script).

## Subcommands

- `on [--personal-bd | --no-bd]` — activate guest mode.
- `off` — deactivate; restore non-guest state.
- `status` — report current state, what's suppressed, info/exclude state.

## Activation flow

**Step 1.** Run `scripts/loom-guest on`.

**Step 2.** If it errors with "no host .beads/ found", ask the user:

> No host bd workspace was detected. How should bd integration work?
>
> - **personal**: external personal bd workspace at
>   `~/.loom/guests/<repo-key>/.beads/` (gitignored, not visible to
>   host). Choose this if you want bd-tracked work that doesn't bleed
>   into the host's repo.
> - **none**: skip bd integration entirely. Recipes that require a
>   bead won't have one to operate on.

Then re-run with the chosen flag (`--personal-bd` or `--no-bd`).

If the host *does* have its own `.beads/`, `on` defaults silently to
`bd_mode=host`. In that case your bd commands operate on the host's
tracker (you're a contributor) and `bd remember` is refused (would
commit a one-liner to the host's `issues.jsonl`). Use a MemPalace
drawer instead — see loom-n7x. To override (use a personal external
workspace even though host has bd), pass `--personal-bd`.

**Step 3.** Run `scripts/loom-guest status` to confirm: marker
written, info/exclude block populated, suppression list rendered.

## Deactivation

```bash
scripts/loom-guest off
```

Both the marker and the info/exclude block are removed. The
underlying lib helpers (`workflow_config_guest_off`,
`info_exclude_remove`) are idempotent, so re-running `off` on an
already-inactive repo is a safe no-op.

## What guest mode actually changes

When active:
- `.claude/workflow.json` and `.claude/settings.json` are listed in
  `.git/info/exclude` (per-clone, never committed). The marker
  `{guest: {active: true, bd_mode, repo_key}}` lives inside
  `workflow.json`.
- `/docs-scaffold` refuses (would create `docs/` in host tree).
- `/audit-project` AUTOFIX in-tree writes skip per-item with a warn.
- `bd remember` is refused when `bd_mode=host` (would commit).
- Statusline shows `[GUEST]` prominently (loom-b8z) — pending.

What does NOT change:
- Activity recipes, MemPalace capture, code-review skills.
- The actual work files (source, tests) you're writing for the host
  repo — those aren't loom artifacts.

## Critical

- **Guest mode is a guardrail, not a sandbox.** It refuses footguns
  but doesn't prevent `git add .claude/`. The protection is "loom
  won't *help* you pollute the host tree."
- **Don't activate guest mode in your own repos.** It's specifically
  for repos where you're a contributor, not the owner.
- **Reversible.** `off` cleans up everything; the host repo returns
  to its pre-guest state.

Design: drawer_loom_decisions_12d7f8163e8855be037a007c.
