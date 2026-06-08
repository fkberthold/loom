# The recipe family

> **Thesis.** Six activity recipes is the right shape, not because
> six is special, but because the *variable middle* of a recipe is
> shape-specific while the surrounding lifecycle phases are not.
> Splitting the cross-activity scaffolding into a `bead-lifecycle-shell`
> and letting per-shape recipes own only their middle was loom v2's
> central refactor — and it inverted the v1 assumption that
> "working a bead" was one recipe with parameters. But the family is
> the *middle layer* of a three-layer model, not the whole story: a
> design cycle sits **above** the family (it produces the contracts the
> recipes consume) and a dispatch pipeline runs **within** each
> bead (it executes the variable middle as two independent agents). The
> recipe owns the *shape* of the middle; it no longer owns the
> *execution* of the middle.

The per-recipe specs (M-step lists, trigger phrases, exact
invocations) live in [Reference: skills](../reference/skills/index.md).
This page is about *why* the family is shaped the way it is, what
was considered, and what the central inversion is for each shape —
and where the family sits in the layer above it (the design cycle)
and the layer within it (the dispatch pipeline).

## The three-layer model

The six-recipe family is the **middle** of three layers, each at a
different altitude:

1. **Above the beads — `/design-a-cycle`.** An above-bead campaign/arc
   orchestrator (a new conceptual unit, sitting above both beads and
   epics) that drives a Plan → Research → Architect → Soundness →
   Handoff cadence over a layered design substrate, gates on two-tier
   soundness, and *produces the contracts* the leaf recipes later
   consume. It is **not** a bead-lifecycle recipe.
2. **The middle — the six activity recipes.** Each works one bead from
   claim to merged, owning only its shape-specific variable middle and
   deferring the rest to `bead-lifecycle-shell`.
3. **Within each bead — `/dispatch-middle`.** A test-author →
   implementer pipeline that runs the variable RED → GREEN middle as
   two *independent* subagents in one shared worktree. Central invokes
   it once and writes nothing in the middle.

The rest of this page works outward from the middle layer (the family
proper) to the layer within (the dispatch pipeline) and the layer
above (the design cycle).

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

**The recipe names the middle's *shape*, not its *execution*.** A
subtlety the original v2 framing glossed: a recipe like `bugfix-a-bead`
describes a shape-specific middle (RED test reproduces a symptom →
minimal GREEN fix → bug-class coverage), but it does **not** mean
central types that RED test and GREEN fix in-thread. By default the
middle is **dispatched** via `/dispatch-middle`, where a test-author
agent writes the RED test and a *separate* implementer agent makes it
GREEN — and central writes nothing. The recipe owns the **contract +
shape** of the middle (what the test must pin, what "done" looks like
for this shape); the dispatch pipeline owns the **RED/GREEN
execution**. The two are different responsibilities: the recipe is the
shape spec, the pipeline is the runtime.

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

## The within-bead middle: `/dispatch-middle`

The recipe says *what shape* the middle is. `/dispatch-middle` says
*how the middle runs* — as a pipeline of two **independent** subagents
in one shared worktree, so central invokes it once and writes nothing
between bead-claim and bead-close.

The pipeline is deliberately split into a **test-author** and a
**separate implementer**:

- The **test-author** is briefed with *only* the locked contract (the
  bead's `RED:` line / spec / acceptance criterion) plus the interface
  under test. It writes the RED test, commits it, and returns the
  failure output. It does not implement.
- The **implementer** is briefed with *only* the RED test *as a file
  on disk* — it never sees the test-author's reasoning, mind, or
  conversation. It makes the minimal change that turns the test GREEN.
  If the test looks wrong, it stops and reports rather than weakening
  it.

This split solves the **test-author == code-author anti-pattern by
construction.** When one agent writes both the test and the code, the
test is a tautology shaped by the implementation — there is no
independent verification. Because the implementer inherits the test as
an *artifact* and not a shared mind, the code can only be shaped to
satisfy the public test, not a private intent. The independence is
mechanical, not a matter of discipline.

`/dispatch-middle` is the **pull** half of loom's dispatch posture; the
`dispatch-nudge` hook is the **push**. The push alone wasn't enough:
dispatching used to mean write-a-brief + wait + verify + merge — high
friction — so central kept defaulting to inline. The pull inverts that
friction: one cheap command runs the whole middle. Make the right
thing the easy thing and the behaviour flips on its own. (For the
nudge mechanics, see the [mental model](./mental-model.md); the nudge
*pressures* toward dispatch but never *blocks*.)

**Dispatch is the default; inline is the justified exception.** Any
bead whose middle has a RED → GREEN cycle defaults to
`/dispatch-middle`. Working the middle inline (central edits directly)
is waved through without justification only when the change is ≤ ~15
lines **and** touches a single non-test file **and** adds no new test
— and even then dispatch is still preferred. Going inline outside that
threshold is a deliberate override central records as
`dispatch=inline:<reason>`.

**Within-bead vs across-bead fan-out.** `/dispatch-middle` owns the
*within-bead* split (one bead's test/code division of labour). A
separate **fan-out detector** owns *across-bead* parallelism —
multiple independent ready beads, each worked via its own
`/dispatch-middle`. The two compose orthogonally: the detector
proposes a wave of N file-disjoint beads (no dependency edge between
them, disjoint `Files:` footprints), and each bead in the wave runs
its own within-bead pipeline.

## The layer above: `/design-a-cycle`

Above the whole family sits `/design-a-cycle` — an **above-bead
campaign/arc orchestrator**, a conceptual unit loom never had,
sitting above both beads *and* epics. It is explicitly **not** a
bead-lifecycle recipe: it has no single claim-to-merged arc and no
single RED → GREEN middle. Instead it *iterates*, spawning research
beads and ultimately spawning an implementation epic — the generative
phase the leaf recipes feed from.

The reason it can't be a recipe is that the leaf recipes are
*leaf-shaped*: each works ONE bead through ONE RED → GREEN middle. A
design cycle has no single middle to own; it drives a multi-turn
cadence (Plan → Research → Architect → Soundness → Handoff) and
maintains its state in a layered substrate rather than in a single
bead. Cramming the generative phase into the leaf bead model is the
"make the generative phase rigid" trap the design grounding warned
against.

**It produces the contracts the recipes consume.** When a design cycle
locks a decision, it precipitates that decision into structure — and
at handoff, `beadpowers:create-beads` spawns the implementation epic's
child beads carrying those contracts. The leaf recipes then work those
beads. The design cycle is upstream; the family is downstream.

**Build soundness vs design soundness.** The leaf recipes verify with
RED → GREEN (and fitness functions): a bead is done when a test that
failed now passes. That is the **build** layer's notion of soundness.
But a design decision has no red-green test — which is exactly why the
design phase had no loom home for so long. `/design-a-cycle` replaces
RED → GREEN with **two-tier soundness** for the design phase:

- **Tier-0 — the coherence floor (always on).** A cycle is sound only
  when no open `[CLARIFICATION]` markers remain, every locked decision
  cites its grounding and names its options + why-not, and nothing
  violates a recorded constitutional invariant.
- **Tier-1 — the executable-spec ceiling (optional, per-decision).** A
  decision with a natural testable altitude may emit a Given-When-Then
  scenario or an `INVARIANT:` line — which becomes a spawned bead's RED
  test. Tier-1 is optional by construction; forcing it on every
  decision would re-import the very RED → GREEN mismatch the design
  research diagnosed.

So the two layers have *different* notions of "done": the build layer
uses RED → GREEN, the design layer uses two-tier soundness. Tier-1 is
where the design layer hands a real RED test down to the build layer.

## The connective tissue: the `RED:` / `Files:` interlock

The three layers are stitched together by two structured lines on a
bead's description — each a single line a downstream consumer reads:

- **`Files:`** lists the paths the bead is expected to touch. The
  fan-out detector reads it to decide which ready beads are
  *footprint-disjoint* and therefore safe to dispatch as one parallel
  wave. A bead with no `Files:` line degrades conservative — it is
  excluded from any proposed wave, so it silently never gets
  parallelised.
- **`RED:`** carries a Tier-1 decision's executable spec verbatim (its
  Given-When-Then scenario or `INVARIANT:` line). It is parallel to
  `Files:`. This is the **design → dispatch interlock**: the design
  cycle *emits* the `RED:` line at handoff; `/dispatch-middle`'s
  test-author *consumes* it as the contract to pin. A bead from a
  Tier-0-only decision carries `Files:` but no `RED:` — that's
  expected, not a gap.

Together, `Files:` connects the across-bead fan-out to the family, and
`RED:` connects the design cycle above to the dispatch pipeline within.
Without `RED:`, a Tier-1 decision's spec is stranded and the
test-author has no contract to pin; without `Files:`, a bead is never
provably disjoint and never parallelised.

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

Two commands from the *other* layers are direct entry points by
design, because they sit outside the family's leaf shape:

- **`/design-a-cycle <topic>`** opens or advances a design cycle in
  the layer above. The router does not dispatch it — a design cycle is
  generative, not a single bead, so it has no `bead.type` for the
  router to score.
- **`/dispatch-middle <bead>`** runs a single bead's within-bead
  test → code pipeline. It is invoked directly (or by an activity
  recipe when its middle reaches the RED → GREEN step), not via the
  router.

The router also leans on the **fan-out detector** at selection time: it
surfaces which ready beads are wave-compatible (no dependency edge, and
disjoint `Files:` footprints) so an across-bead parallel wave can be
proposed, with each bead in the wave then running its own
`/dispatch-middle`.

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

The two newer layers — `/design-a-cycle` above and `/dispatch-middle`
within — arrived in loom's v3 era (the design-phase + dispatch-v2
work, 2026-06-07). For the lineage of all three layers and why loom
grew a unit *above* beads, see [provenance](./provenance.md).

For the operational specs of each recipe — exact M-step list,
trigger phrases, slash command, frontmatter flags — see
[Reference: skills](../reference/skills/index.md). For a
walked-through bugfix end-to-end, see the
[bug walkthrough tutorial](../tutorials/bug-walkthrough.md).
For a feature, see the
[feature walkthrough tutorial](../tutorials/feature-walkthrough.md).
