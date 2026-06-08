---
name: design-a-cycle
description: Above-bead campaign/arc orchestrator that drives a design cycle's Plan→Research→Architect cadence over the layered design substrate (L1 KG spine / L2 design-doc drawer / L3 optional executable specs), gates on two-tier soundness, then hands off to create-beads to spawn the implementation epic. NOT a bead-lifecycle activity recipe — it iterates, spawns research-a-beads + an epic, and is stateless beyond the substrate it maintains. Triggers on "/design-a-cycle <topic>", or when the user wants to open or advance a design cycle for a topic that will eventually become beads.
---

# Design-a-Cycle — Above-Bead Design Orchestrator

This skill is loom's **above-bead campaign/arc primitive** — the unit
loom never had, sitting ABOVE both beads and epics. A design cycle
ITERATES, SPAWNS research-a-beads, and ultimately SPAWNS an
implementation epic. It is the generative phase that the leaf-shaped
bead-lifecycle recipes feed from.

It is **NOT a bead-lifecycle activity recipe.** The sibling recipes
(`bugfix-a-bead`, `feature-a-bead`, `research-a-bead`, …) each work ONE
bead from claim to merged through a single RED→GREEN middle. This skill
has no single RED→GREEN: it ORCHESTRATES a cadence across many turns,
producing the contracts those recipes later consume. Cramming a design
cycle into the leaf bead model is the "make the generative phase rigid"
trap the grounding research warned against.

It is **stateless beyond the substrate.** The orchestrator keeps no
private `.claude/` state file and no new bd entity. Its entire memory
is **substrate-as-state**: the L2 design-doc drawer's STATE HEADER
(backed by the L1 KG). On each invocation it READS that state, decides
the next cadence action, drives it, and PRECIPITATES the result back
into the substrate. Reason in prose → precipitate into structure.

Architecture locked in the `/design-a-cycle build brainstorm
CHECKPOINT` drawer (`loom/decisions`, 2026-06-07), grounded in three
converged research drawers: `loom-l0f` (design-phase survey),
`loom-5w6` (two-tier soundness + living-doc home), and `loom-dwn`
(agent-optimal representation — the layered KG-spine substrate). This
skill is T2 of epic **loom-tdua**; T1 (`loom-dhra`) shipped the
`templates/design-doc/` skeleton this skill scaffolds from.

## When to use

- The user wants to OPEN a design cycle for a topic ("let's design the
  X rework", "/design-a-cycle auth").
- The user wants to ADVANCE an in-flight cycle (a design-doc drawer
  already exists with open `[CLARIFICATION]` markers; `session-startup`
  surfaces these).
- The work is generative and will eventually become beads, but the
  contracts aren't locked yet — so there's nothing for a
  `<activity>-a-bead` recipe to consume.

## Skip when

- A locked contract already exists and you just need to BUILD it — go
  straight to the matching `<activity>-a-bead` recipe (or
  `/dispatch-middle <bead>` for the within-bead test→code split). This
  skill produces contracts; it does not consume them.
- The question is pure prior-art research with no design output yet —
  use `research-a-bead` directly. (This orchestrator will SPAWN such
  research beads when a `[CLARIFICATION]` marker needs grounding, but
  a one-off lookup doesn't need the cadence.)
- A single trivial decision — just make it and capture a drawer; the
  cadence earns its keep only when the design space is wide enough to
  iterate over.

## The layered substrate (what the orchestrator reads + writes)

The design cycle's state lives across three layers, all on existing
MemPalace infrastructure — no new tooling (D1 YAGNI cut):

- **L1 — the KG spine.** The durable, agent-optimized source-of-truth.
  Locked decisions PRECIPITATE into KG triples. Wins on queryable
  CURRENT-STATE.
- **L2 — the design-doc drawer.** The prose working-surface (this is
  the `templates/design-doc/` skeleton, populated). Carries the
  STRUCTURED STATE HEADER the orchestrator reads/updates each cycle,
  above the prose reasoning sections. Wins on narrative INTENT. Reason
  HERE, then precipitate.
- **L3 — optional executable specs.** Given-When-Then scenarios or
  `INVARIANT:` lines that a locked decision emits at its natural
  altitude. Each becomes a spawned bead's RED test (the Tier-1
  soundness ceiling).

## Central's sequence

### Step 0 — Read the substrate STATE for `<topic>`

On every invocation, FIRST read the current state — do not assume a
fresh cycle:

1. `mempalace_search "<topic> design"` (and `room: decisions`) to find
   an existing DESIGN DOC drawer for `<topic>`.
2. If found, read its **STATE HEADER**: cycle-number, soundness-status
   (red/amber/green), locked-decisions, open `[CLARIFICATION]` markers,
   spawned research-bead IDs, target implementation-epic ID.
3. `mempalace_kg_query("<topic>")` and any named concept, to pull the
   L1 current-state the prose may lag behind.

The STATE HEADER + L1 KG ARE the orchestrator's memory. There is no
other state to load.

### Step 1 — Scaffold from `templates/design-doc/` if none exists

If Step 0 found no design-doc drawer for `<topic>`, SCAFFOLD one before
driving any cadence step. Mirror the `templates/diataxis/` mechanism —
plain `sed` substitution, no Python:

```bash
cp -r templates/design-doc/. /tmp/design-<topic>/
find /tmp/design-<topic> -type f -exec sed -i \
  -e "s|{{ topic }}|<topic>|g" \
  -e "s|{{ wing }}|<project-wing>|g" {} +
find /tmp/design-<topic> -type f -name '*.template' \
  -exec sh -c 'mv "$1" "${1%.template}"' _ {} \;
```

Then file the populated body as a drawer via `mempalace_add_drawer`
into the project's **`<wing>/decisions`** room. The two tokens are
`{{ topic }}` (the cycle's topic) and `{{ wing }}` (the project wing,
e.g. `loom`). After substitution, `grep -r '{{'` must return nothing.
The fresh drawer starts at cycle-number 0, soundness-status red, one
seed `[CLARIFICATION]` marker.

### Step 2 — Propose the next cadence action FROM STATE

The orchestrator does not run a fixed script — it READS the state and
PROPOSES the next action, then drives ONE step (or loops a few when the
user asks to run the cycle forward). The cadence is:

**Plan → Research → Architect → Soundness → (loop until green) → Handoff.**

Pick the step the state calls for:

- Open `[CLARIFICATION]` markers with no spawned bead? → **Research**.
- Direction unclear / scope unset / a fork needs a human call? →
  **Plan**.
- A decision just locked but not yet precipitated? → **Architect**.
- Everything precipitated? → **Soundness** check, then **Handoff** if
  green.

Surface the proposal to the user before driving an expensive step
(spawning beads, running create-beads).

#### Plan — set or refine direction (brainstorming)

Invoke `beadpowers:brainstorming` (the design will land as beads) or
`superpowers:brainstorming` (it will land as a spec/plan) to set or
refine the cycle's direction. Plan converges the Question/Scope and
surfaces the forks; each unresolved fork becomes a `[CLARIFICATION]`
marker in the STATE HEADER. Plan does not lock decisions by itself — it
frames them for Research/Architect.

#### Research — ground each open `[CLARIFICATION]` marker

For each open `[CLARIFICATION]` marker that needs external or prior-art
grounding, **spawn a `research-a-bead`** (via `bd create` + the
research recipe / `/research-a-bead`). Record the spawned bead's ID in
the STATE HEADER's "spawned research-bead IDs" list so the cycle can
track which markers are in-flight. When the research bead closes, its
decision drawer becomes the grounding the Architect step cites. A
marker answerable from the palace alone can be resolved inline without
a bead; spawn a bead when the answer needs real research.

#### Architect — precipitate each newly-locked decision

When a decision locks, PRECIPITATE it into all three layers:

- **L1 — KG triples.** Add triples using the **soft recommended
  design-predicate set** (advisory, not a locked schema):
  `supersedes_design_of`, `grounded_in`, `emits_bead`, `soundness_tier`,
  `depends_on_invariant`. e.g. `<decision> grounded_in <research-drawer>`,
  `<decision> emits_bead <bead-handle>`.
- **L2 — the Decisions-locked section.** Write the decision's prose
  block (Decision / Grounding / Options + why-not / optional L3 spec)
  in the design-doc drawer, and add its short handle to the STATE
  HEADER's locked-decisions list. Remove the now-answered
  `[CLARIFICATION]` marker.
- **L3 — optional executable spec.** When the decision has a natural
  testable altitude, write its spec NOW (Given-When-Then for
  behavioral, `INVARIANT:` for structural) so the spawned bead inherits
  its RED test. A decision with no testable altitude carries Tier-0
  only — expected and fine.

#### Soundness — the two-tier gate (loop until green)

Run the soundness check after each Architect pass; loop the cadence
until it's green. Two tiers (locked in `loom-5w6`):

- **Tier-0 — COHERENCE (always-on floor).** The cycle is green only
  when:
  - No unresolved `[CLARIFICATION]` markers remain in the STATE HEADER.
  - Every locked decision cites its grounding (a research drawer, a
    sibling bead, a source URL). No grounding ⇒ not yet sound.
  - Every locked decision names options-considered + why-not.
  - No locked decision violates a recorded constitutional invariant
    (constitution-consistent).
  This is the Grounding-checklist in the L2 drawer, mechanized as a
  checklist (checklists act as unit tests for specifications).
- **Tier-1 — EXECUTABLE-SPEC EMISSION (optional ceiling,
  per-decision).** A locked decision MAY carry an L3 executable spec at
  its natural altitude. Tier-1 is OPTIONAL by construction — forcing it
  on every decision would re-import the RED→GREEN mismatch the research
  diagnosed.

Update `soundness-status` (red/amber/green) in the STATE HEADER each
pass. Do NOT hand off until Tier-0 is green. Soundness is enforced as a
recipe-STEP (a nudge, per the loom-yb5 nudge-not-block posture), not a
hard hook.

#### Handoff — create-beads spawns the implementation epic

Once Tier-0 is green, hand off: run `beadpowers:create-beads` against
the locked decisions to spawn the implementation **epic** + its child
beads. The handoff is enriched beyond the plain create-beads shape:

- Each bead carries a **`Files:` line** (the loom-asr fan-out
  convention — the paths it's expected to touch).
- Each bead spawned from a **Tier-1 decision** ALSO carries a
  **`RED:` line** parallel to the `Files:` line, holding the decision's
  L3 spec verbatim (its Given-When-Then scenario or `INVARIANT:`). That
  `RED:` line IS the contract `/dispatch-middle`'s test-author consumes
  (the loom-tdua → loom-5m94 interlock). A bead from a Tier-0-only
  decision carries `Files:` but no `RED:` line — that's expected.

Record the spawned epic's ID in the STATE HEADER's "target
implementation-epic ID" field, and add `<decision> emits_bead <bead>`
triples to L1. The design cycle's job is done once the epic exists with
contract-bearing beads; the leaf recipes take it from there.

## Decisions / posture

- **Opinionated** about the structured destination (L1 KG triples +
  optional L3 specs) and the cadence (Plan/Research/Architect/Soundness/
  Handoff).
- **Permissive** about the prose reasoning surface (L2 drawer — reason
  however the topic wants).
- **Generative** about human-facing Diátaxis docs — DEFERRED (loom-dwn:
  NOT full auto-render). A docs/explanation page may be a downstream
  rendering after the design stabilizes, governed by the precedence
  rule system/beads/MemPalace > docs.

## Discovery

`session-startup` surfaces active design cycles — open design-doc
drawers with unresolved `[CLARIFICATION]` markers — alongside
in-progress beads, so a cold-start session can resume a cycle where it
paused.

## Composition

- **Below** this orchestrator: the `<activity>-a-bead` recipes work the
  beads it spawns; `/dispatch-middle` runs each bead's within-bead
  test→code split, consuming the `RED:` line as its contract.
- **Spawned by** this orchestrator: `research-a-bead` (one per grounded
  `[CLARIFICATION]` marker) and `create-beads` (the implementation
  epic at handoff).
- **Grounded in**: `loom-l0f`, `loom-5w6`, `loom-dwn` (the three
  converged research drawers); design source-of-truth is the
  `/design-a-cycle build brainstorm CHECKPOINT` drawer.

## Failure modes (concrete)

- **Treat it as a bead-lifecycle recipe.** Trying to claim/RED/GREEN/
  close a "design bead" forces the iterative cadence into a leaf shape
  and loses the spawn-children + spawn-epic arc. It's an orchestrator,
  not a recipe.
- **Skip Step 0 (read state).** Re-scaffolding over an existing cycle
  wipes locked decisions and spawned-bead tracking. ALWAYS read the
  STATE HEADER first.
- **Hand off before Tier-0 green.** Spawning the epic with unresolved
  `[CLARIFICATION]` markers or ungrounded decisions ships an incoherent
  design into the build phase. Loop until Tier-0 green.
- **Force Tier-1 on every decision.** Re-imports the RED→GREEN
  mismatch. Tier-1 is an optional per-decision ceiling, not a gate.
- **Forget the `RED:` line at handoff.** A Tier-1 decision's bead with
  no `RED:` line strands its L3 spec; `/dispatch-middle`'s test-author
  then has no contract to pin and the cycle's executable-spec work is
  wasted.
