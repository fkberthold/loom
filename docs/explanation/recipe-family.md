# The recipe family

> **Thesis.** Six activity recipes is the right shape, not because
> six is special, but because the *variable middle* of a recipe is
> shape-specific while the surrounding lifecycle phases are not.
> Splitting the cross-activity scaffolding into a `bead-lifecycle-shell`
> and letting per-shape recipes own only their middle was loom v2's
> central refactor — and it inverted the v1 assumption that
> "working a bead" was one recipe with parameters.

The per-recipe specs (M-step lists, trigger phrases, exact
invocations) live in [Reference: skills](xref:reference/skills/index.md).
This page is about *why* the family is shaped the way it is, what
was considered, and what the central inversion is for each shape.

## The v1 mistake: one recipe with parameters

Loom v1 shipped a single skill called `working-a-bead` with a
fourteen-step recipe that tried to handle every kind of bead. The
steps were ordered roughly: search prior art → claim → worktree →
RED test → GREEN fix → bug-class coverage → enshrined-test sweep →
verification → review → commit → finish branch → preflight → close
→ capture.

That recipe worked beautifully for bugs. It worked tolerably for
features (the RED-test-first step had to be re-interpreted because
there is no symptom to reproduce). It worked badly for refactors
(the RED-test-first step was actively *wrong* — refactors must keep
tests green throughout). It did not work at all for research beads
(no code, no worktree, no test). It half-worked for cleanup and
docs.

The fourteen-step recipe was load-bearing on a structure that did
not generalise. The steps that *did* generalise — search, claim,
verify, commit, finish branch, close, capture — were tangled
together with the steps that did not — RED test, GREEN fix,
bug-class coverage. Inheriting the recipe meant inheriting the
contradiction.

## The v2 split: shell + middle

Loom v2 (epic `loom-0y6`, 2026-05-03) extracted the cross-activity
phases into `bead-lifecycle-shell` and let each shape own only its
own *variable middle*. The shell owns:

- **Phase A.** Search MemPalace family, claim the bead, optionally
  isolate via a worktree.
- **Phase B.** Verification with a clean shell + diff scope check.
- **Phase C.** Per-task code review, commit on branch, and
  finishing-a-development-branch (the four-option merge / push /
  keep / discard prompt).
- **Phase D.** Preflight, close, push, and capture
  (drawer + KG triples + diary).

Every recipe runs A then B then C then D, in order, with no
interpretation. A recipe's whole job is to supply the *middle* —
the steps between A and B that are shape-specific. That middle is
what differs.

This is the inversion: v1 made the middle the recipe and the
surroundings parameters; v2 made the surroundings the recipe and
the middle the parameter.

## Why six and not three (or twelve)

Three would have been too few: it would have collapsed *bug* +
*feature* + *refactor* into a single "code-shaped" recipe, which is
the v1 mistake at smaller scale. Twelve would have been too many:
the difference between a "bugfix" and a "regression-fix" is a
sub-genre, not a shape, and shouldn't fork the recipe.

The six shapes are differentiated by their *central inversion* —
the one thing that is true for that shape and not for any other.
They are not differentiated by domain (frontend / backend / infra)
or by size (small / medium / large) or by urgency. Domain and size
and urgency don't change the shape of the work. The central
inversion does.

| Shape | Central inversion |
|---|---|
| **bugfix** | RED test reproduces a *symptom* (the bug exists; the test must capture its specific failure). |
| **feature** | RED test pins a *desired contract* (the feature does not exist; the test fails because the code is absent, not because behaviour is wrong). |
| **refactor** | There is **no RED state**. Tests stay green throughout; a test going red during a refactor is either a behaviour change (bug introduced) or a test that pinned implementation detail (smell). |
| **research** | There is **no code**. The closing decision drawer + KG triples *are* the deliverable; phase D3 is not a postscript, it is the work. |
| **cleanup** | The diff goes **negative**. Identifying every site that holds a reference (the orphan-reference grep) is the load-bearing step, because lint and tests miss broken docs / stale config keys / dead symlinks. |
| **docs** | The deliverable is a **tracked file**. M4 review-against-code is non-negotiable even in `light` mode — lying docs (snippets that don't run, links that rot, signatures that drifted) are the failure mode this recipe exists to prevent. |

Each inversion is genuinely different. A bug recipe with no symptom
to reproduce is not a feature recipe with extra steps; it is a
broken bug recipe. A refactor recipe that allows RED is not a
better refactor recipe; it is a recipe that has stopped being a
refactor recipe.

## Why the shell is internal-only

`bead-lifecycle-shell` does not have a slash command. Its SKILL.md
asks the model to decline if invoked directly. This is deliberate.
The shell is a contract that activity recipes inherit; if it could
be invoked directly, agents would invoke it directly *instead* of
the activity recipe and lose the variable middle, which is exactly
the v1 mistake re-emerging in v2 clothing.

The activity recipe is the only legitimate entry point. The shell
is an implementation detail.

## What was considered and rejected

- **One recipe with shape-aware branching.** Considered: keep one
  `working-a-bead` skill that branches on `bead.type` and runs the
  right sequence. Rejected because it re-tangles the variable
  middle with the phases. The branch logic itself is the v1 recipe
  in compressed form, and it inherits all v1's contradictions.
- **No shell — every recipe inlines its own A/B/C/D.** Considered:
  duplicate the shell into each recipe. Rejected because it
  guarantees drift between recipes. A change to the close-capture
  ritual in one recipe would have to be propagated to five others
  by hand.
- **Sub-shapes (regression-fix, hotfix, security-fix).** Considered:
  finer-grained recipes for bug sub-genres. Rejected because the
  central inversion is the same — RED test reproduces symptom — and
  the variations are sub-genre seasoning, not shape.
- **A free-form "task" recipe for whatever doesn't fit.** Considered
  briefly. Rejected because the absence of a shape *is* a shape: if
  a bead doesn't fit one of the six recipes, it usually means the
  bead is mis-described, and the right move is to re-describe the
  bead, not to invent a seventh recipe.
- **Recipe-as-data (YAML manifest of steps).** Considered. Rejected
  because the agent's interpretation of a step matters more than
  the step's literal text — a YAML manifest would have lost the
  "Frank's deploy-day rule: 'test for the bug AND for the bug
  class'" prose that frames step M4 of bugfix.

## The router

Six recipes plus a dispatcher (`/working-a-bead <bead-id>`) is
better than six slash commands. The router runs `bd show`, scores
the bead against the six recipes by `bead.type` + description-keyword
heuristics, and dispatches the winner via `Skill(<recipe>-a-bead)`.
On ambiguity it surfaces a numbered candidate list with one-line
"because" rationale per candidate.

Direct slash commands ship for `/bugfix-a-bead` and
`/research-a-bead` only — the two most-used shapes. The other four
(`feature`, `refactor`, `cleanup`, `docs`) are reached via the
router or via Skill auto-discovery on description match. This is
not capricious: shipping six slash commands plus a router would
have created six entry points where one is sufficient.

## How this connects to the rest of loom

The recipe family is downstream of the [mental model](./mental-model.md)
— each recipe is a different shape of "which axes feed which axes
when?" Bugfix's RED test pins a beads symptom into a tracked file;
research's closing drawer pins a bead's question into a MemPalace
drawer; cleanup's orphan grep crosses every axis at once.

The recipe family is also upstream of the [workflow modes](./workflow-modes.md)
— `light` mode lets a recipe run with reduced ceremony, `off` mode
lets the recipe refuse to run at all. The modes exist because not
every project wants the full discipline.

For the operational specs of each recipe — exact M-step list,
trigger phrases, slash command, frontmatter flags — see
[Reference: skills](xref:reference/skills/index.md). For a
walked-through bugfix end-to-end, see the
[bug walkthrough tutorial](xref:tutorials/bug-walkthrough.md).
For a feature, see the
[feature walkthrough tutorial](xref:tutorials/feature-walkthrough.md).
