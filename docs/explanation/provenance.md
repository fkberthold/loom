# Provenance

> **Thesis.** Loom did not start as loom. It started inside another
> project — Hundred Acre Woods (HAW) — as a small set of hooks and
> skills that solved problems that project happened to have. It
> became its own repo when the abstractions outgrew their host.
> The lineage matters: it explains why some of loom's choices look
> arbitrary until you see the failure mode in HAW that motivated
> them, and it explains why HAW remains the design source-of-truth
> for everything pre-2026-05-03.

This page is the historical record. For the current design source
of truth, see the [mental model](./mental-model.md), the
[recipe family](./recipe-family.md), and the
[workflow modes](./workflow-modes.md). For the locked design
decisions themselves, the canonical home is MemPalace —
specifically the `hundred_acre_woods/decisions` wing for v1/v1.5
content, and the `loom/decisions` wing for everything since the
split.

## v1 — workflow infrastructure shipped (2026-05-02)

The original workflow infrastructure shipped 2026-05-02 in commit
`c5fa8dc` of HAW. It introduced:

- A single skill called `working-a-bead` with a fourteen-step recipe.
- Two PreToolUse hooks: `bd-claim-research` (advisory, fired on
  `bd update --claim`) and `bd-close-capture` (blocking, fired on
  `bd close`).
- One PreToolUse hook for `git push` warning about dirty `.beads/`.
- Three subagents: `bug-family-researcher`, `drawer-author`,
  `kg-relationship-extractor`.
- A session-startup skill walking nine cold-start steps.
- A `/wrap-up` slash command for close-time ritual.

The design was locked in MemPalace drawer "WORKFLOW INFRASTRUCTURE
PLAN" in the `hundred_acre_woods/decisions` wing. Eight of nine
children of epic `hundred-acre-woods-2st` closed at 88% completion.
The remaining child — Build 8, the agent-teams pilot — was
deferred to 2026-07-01 and remains deferred.

## v1.5 — workflow modes + state file + status line (2026-05-03)

Bead `hundred-acre-woods-jnd` introduced the v1.5 surface. The
delta:

- Three workflow modes: `full` / `light` / `off`. The triad came out
  of dogfooding the v1 workflow on a project where the full ceremony
  was too heavy but visibility was still wanted. See
  [workflow modes](./workflow-modes.md) for the rationale.
- Per-project `workflow.json` (committed; mode policy) and
  `workflow-state.json` (gitignored; per-session state).
- A status line reading both files and printing a one-line summary.
- A `workflow-mode-onboarding.sh` SessionStart hook that asks the
  user to pick a mode the first time it sees an unconfigured beads
  workspace.
- An `audit-project` skill + slash command for project onboarding +
  health check.

v1.5 was a refinement, not a rewrite. The v1 core stayed; modes
were added around it.

## v2 — sibling recipes + bead-lifecycle-shell extraction (2026-05-03)

The v2 split happened in epic `loom-0y6`, also on 2026-05-03,
shortly after v1.5. Loom shipped six activity recipes:

- `bugfix-a-bead` (renamed from `working-a-bead` in bead `loom-lzi`)
- `feature-a-bead` (loom-5rf)
- `refactor-a-bead` (loom-uca)
- `research-a-bead` (loom-0q0)
- `cleanup-a-bead` (loom-62x)
- `docs-a-bead` (loom-s0n)

The cross-activity scaffolding — search, claim, verify, commit,
finish branch, close, capture — moved into `bead-lifecycle-shell`,
an internal-only skill that the activity recipes inherit. The
`/working-a-bead <bead-id>` router shipped in `loom-1ab` and
dispatches by `bead.type` + description heuristics.

This is the central refactor that distinguishes loom from its v1
roots. See [the recipe family](./recipe-family.md) for the design
rationale.

## The repo split

For most of v1 and v1.5, the workflow infrastructure lived inside
the HAW repository. The skills, hooks, agents, commands, and
helpers were committed alongside HAW's application code. This was
fine while the abstractions were HAW-shaped, but became friction
once the workflow started being used on other projects.

The split into a dedicated `loom` repository came when:

- Other projects wanted the workflow infrastructure but not HAW's
  application code.
- Updates to the workflow infrastructure needed to ripple to every
  project that adopted it, which a per-project copy could not do.
- The design vocabulary diverged from HAW's domain vocabulary, and
  keeping them in one repo meant cross-talk that confused both.

Loom became its own repo with its own beads tracker (`.beads/` here
in this repository, distinct from HAW's), its own MemPalace wing
(`loom/`), and its own install script (`install.sh`) that symlinks
this repo's files into `~/.claude/`.

## Loom's relationship to HAW

HAW remains the original consumer of loom and the design
source-of-truth for the v1 / v1.5 era. The `hundred_acre_woods/decisions`
wing of MemPalace holds the locked decisions for that period. When
loom decisions diverge from those drawers — and they have, several
times — the rule is:

- **For v1 / v1.5 design intent**, the HAW drawers win on what was
  decided and why.
- **For current implementation**, the loom repo wins on what
  actually works.
- **For decisions made post-split**, the `loom/decisions` wing
  wins — and is cross-tunneled back to the HAW drawers when the
  lineage is HAW-rooted.

HAW is no longer loom's only consumer, but it remains the project
where most of loom's design lessons were learned. Several recent
loom features — the canonical-skills include convention, the
docs-surface check, the `/audit-project --check=docs` plan — exist
because of drift incidents in HAW (`loom-qj3`, `loom-469`,
`loom-22h`) where the v1 workflow's blind spots showed.

## Why this matters for current readers

Reading loom's current behaviour without the lineage produces
puzzles. Why does `bead-lifecycle-shell` exist as an internal-only
skill? Because v1 was one recipe that didn't generalise, and the
shell is the v2 extraction. Why are there exactly three workflow
modes? Because v1 had no modes and dogfooding produced two distinct
"don't fire all the hooks" use cases. Why does the
`bd-close-capture` hook block by default? Because the v1 dogfooding
showed that the most-skipped step was the closing decision drawer.

Each of these answers has a v1 incident behind it. The drawers in
`hundred_acre_woods/decisions` and `loom/decisions` are the long
form. This page is the short form.

## What this page is not

This page is not a changelog. The git log of the loom repo is the
changelog. This page is the *narrative* — the version of the
history a new reader needs in order to understand why current loom
looks the way it does.

For specific decisions, search the relevant MemPalace wing
(`loom/decisions` for post-split, `hundred_acre_woods/decisions`
for pre-split). For the current shape of loom, see the other
explanation pages or the [reference catalogue](xref:reference/index.md).
