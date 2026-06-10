---
name: explore
description: Above-bead SUB-design exploration primitive — the front-door to /design-a-cycle the way /design-a-cycle is the front-door to create-beads (the ladder is explore → design → build). Opens "an exploration" that blends FOUR source tiers (self · repo+docs · web · peer-reviewed literature) to converge WITH the user on shared understanding, via a HYBRID loop: light tiers in-thread, heavy tiers dispatched as a deep-research round, central writes nothing but the capture. NOT a bead and NOT a design cycle — no soundness gate, no epic emission. Two user-declared exits: REST and PROMOTE. Triggers on "/explore <idea>", or when the user has a nascent idea to think through before it's design-ready.
---

# Explore — Above-Bead SUB-Design Exploration Primitive

This skill is loom's **sub-design exploration primitive** (loom-ld1q)
— the unit that sits UPSTREAM of the design cycle. `/explore <idea>`
opens "an exploration": the front-door to `/design-a-cycle` the way
`/design-a-cycle` is the front-door to `create-beads`. The ladder is
**explore → design → build**.

It is deliberately **lighter than `design-a-cycle`.** Where a design
cycle iterates a Plan→Research→Architect cadence and GATES on two-tier
soundness before spawning an epic, an exploration just *converges with
the user on shared understanding*. There is **NO soundness gate** and
**NO epic emission** — those are the design cycle's job, downstream.
An exploration's only deliverable is the understanding itself, captured
in one drawer.

It is **NOT a bead and NOT a design cycle.** An exploration has no
single RED→GREEN of its own (so `bd ready` will never surface it — it
is discovered through `session-startup`'s active-explorations scan
instead, step 1e). It is also not a design cycle: no `[CLARIFICATION]`
markers, no soundness status, no `create-beads` handoff. Cramming an
exploration into either of those shapes re-imports rigidity the early,
nascent-idea phase can't afford.

It is **prompt/skill-only** (v1). There is no hook backstop — the
nudge-not-block posture (loom-yb5) applies: this skill nudges the
right cadence, nothing blocks you from deviating. Architecture locked
in the exploration design drawer
(`drawer_loom_decisions_2ee82f47ed6bc219866cd5c4`, `loom/decisions`,
2026-06-07); honors dispatch-v2 lean-central (loom-5m94) and mirrors
the soft-recommendation posture of the design-cycle KG predicate set
(loom-tdua).

## When to use

- The user has a **nascent idea** they want to think through before
  it's design-ready ("/explore event-sourced facility state", "let's
  explore whether X is even the right framing").
- The user wants to ADVANCE an in-flight exploration (a drawer tagged
  `exploration` with `status=active` already exists;
  `session-startup` step 1e surfaces these on cold start).
- The thinking would benefit from grounding in **peer-reviewed
  literature** — the gap none of brainstorming / research-a-bead /
  deep-research / design-a-cycle fill on their own.

## Skip when

- The idea is already design-ready (the question and scope are clear,
  the forks are framed) — go straight to `/design-a-cycle <topic>`,
  which opens the design substrate and gates on soundness. Explore
  feeds design; it does not duplicate it.
- The contract is already locked and you just need to BUILD — use the
  matching `<activity>-a-bead` recipe (or `/dispatch-middle <bead>`).
- The question is a single durable lookup answerable from the palace +
  one doc fetch — use `research-a-bead` directly. An exploration earns
  its keep when the understanding is *nascent* and needs the
  multi-tier, multi-turn convergence; a one-shot answer doesn't.
- Pure brainstorming with no anchoring question yet — use
  `superpowers:brainstorming` (or `beadpowers:brainstorming`) until a
  thread worth chasing across the four tiers emerges.

## The FOUR source tiers (what the exploration blends)

An exploration converges by blending **four source tiers**, weighting
each as the conversation calls for it:

- **Tier 1 — self.** The agent's own reasoning over the current
  context (the repo state in view, the conversation so far, prior
  knowledge). The cheapest tier; always available.
- **Tier 2 — repo + docs.** A dig through the repository and its
  documentation — `Grep`/`Glob`/`Read` over the code, the `docs/`
  tree, the project's MemPalace wing. A larger dig may use an
  `Explore` subagent.
- **Tier 3 — web.** Common usage / general web knowledge — how the
  wider world frames and solves this, beyond what the repo encodes.
- **Tier 4 — peer-reviewed literature.** Academic / **peer-reviewed**
  / **scholarly** literature. This is the distinguishing tier — the
  gap none of brainstorming / research-a-bead / deep-research /
  design-a-cycle fill. When an idea has a research literature behind
  it, Tier 4 is what grounds the exploration in what's actually
  known rather than what's merely popular.

## The HYBRID loop (cadence)

The loop is **HYBRID** — it splits the four tiers by weight:

- **Light tiers (1 + 2) run IN-THREAD** with the user. Self-reasoning
  and the repo+docs dig happen directly in the conversation, turn by
  turn, so the user stays in the loop while understanding builds.
- **Heavy tiers (3 + 4) are DISPATCHED as a `deep-research` round**
  — invoked WHEN the conversation surfaces a question that needs one,
  not every turn. The `deep-research` harness fans out web searches +
  literature lookups internally; central synthesizes the returns back
  into the dialogue. Tier 2 may also use an `Explore` subagent for a
  larger dig.

**Central writes nothing but the capture.** This honors dispatch-v2
**lean-central** (loom-5m94): the heavy fan-out happens in the
dispatched `deep-research` round, and central's only writes are to the
exploration drawer (the capture). Central does not burn its own
context running the heavy searches inline — it briefs the round,
receives the synthesis, and precipitates the firm parts into the
drawer.

The cadence, each turn:

1. Reason in-thread over Tiers 1 + 2 with the user.
2. When a thread needs heavier grounding, dispatch a `deep-research`
   round (Tiers 3 + 4) on that specific question — not on every turn.
3. Synthesize the returns back into the dialogue; converge the
   `current-understanding` with the user.
4. Precipitate the FIRM findings into the drawer + KG triples (below).
5. Repeat until the user declares an exit.

## The substrate (drawer + template + KG)

An exploration's memory is **ONE MemPalace drawer**, in the `loom`
wing's `decisions` room (a downstream project's own `<wing>/decisions`
room), tagged **`exploration`**. The **tag — not a dedicated room** —
is load-bearing: tagging the drawer `exploration` keeps it inside the
`decisions` room where bug-family search already reaches, so an
exploration's findings surface in prior-art searches the same way
decision drawers do. (Precedent: `loom-mine-history`'s
`provenance:mined` tag — capability via tag, not via a separate room.)

Seed the drawer from `templates/exploration/EXPLORATION.md.template`
(plain `sed` substitution of `{{ question }}` / `{{ wing }}`, mirroring
the `templates/design-doc/` mechanism):

```bash
mkdir -p /tmp/explore-seed
cp templates/exploration/EXPLORATION.md.template /tmp/explore-seed/EXPLORATION.md
sed -i \
  -e "s|{{ question }}|<the exploration question>|g" \
  -e "s|{{ wing }}|<project-wing>|g" /tmp/explore-seed/EXPLORATION.md
# After substitution, grep -r '{{' must return nothing.
```

Then file the populated body via `mempalace_add_drawer` into
`<wing>/decisions`, and tag it `exploration` via `mempalace_tag_drawer`
(the tag is what makes it discoverable).

**Reason in prose; precipitate firm findings into structure.** The
drawer's `## Inquiry log` is the permissive prose surface — think out
loud there as the tiers come in. As a point of understanding settles,
PRECIPITATE it into `## Findings` (each finding carrying its
provenance: source + which tier) and revise the STATE HEADER's
`current-understanding` + `open-threads` in place.

The STATE HEADER fields the loop reads + updates every touch:

- **question** · **status** (`active` | `rested` | `promoted`) ·
  **tiers-touched** · **open-threads** · **current-understanding** ·
  **opened** · **last-touched** · (**rested-on** | **promoted-to**).

Sections: `## Inquiry log` (prose reasoning), `## Findings` (each with
provenance source + tier), `## Lineage` (the exploration's anchors).

### KG triples (firm findings only)

Add KG triples ONLY for **firm** findings — not for in-flight prose.
The soft-recommended predicate vocabulary (a *recommendation*, NOT a
locked schema — mirroring the loom-tdua design-predicate posture):

- `explores` — the exploration explores a topic/question.
- `grounded_in` — a finding rests on a source (a repo path, a doc, a
  URL, a paper).
- `surfaced_finding` — the exploration surfaced a specific finding.
- `has_open_thread` — the exploration still has an unresolved thread.
- `informs_design_of` — set on PROMOTE; this exploration informs the
  design of the spawned `/design-a-cycle` topic.

These compose with whatever project-local predicates exist; a
particular exploration is free to deviate.

### Capture cadence

- **At open** — create the drawer, seeding the STATE HEADER with the
  question (status `active`, `opened` set).
- **After each research round** — precipitate the round's firm
  finding into `## Findings`, revise `current-understanding` +
  `open-threads` in place, add `tiers-touched`. Add KG triples for the
  firm findings only.
- **Batch clustered touches.** `mempalace_update_drawer` replaces the
  full drawer body (no append/patch — `loom-n2b9` tracks the upstream
  fix), so each precipitation resends the whole drawer. When touches
  cluster — several rounds return close together, or one round yields
  several firm findings at once — fold them into **one** `update_drawer`
  call rather than one rewrite each. Tradeoff: batching trades
  crash-safety for fewer rewrites, so batch only *tightly-clustered*
  touches — never defer a whole exploration's capture to the end, which
  a mid-session crash would lose.
- **At exit** — flip `status` (below).

## Discovery

`session-startup` **step 1e** (ALREADY SHIPPED in
`skills/session-startup/SKILL.md`) surfaces active explorations —
drawers tagged `exploration` with `status=active` — under an `ACTIVE
EXPLORATION` header on cold start, so a fresh session resumes the
*thinking*, not just the bead queue. This skill does NOT duplicate
that scan; it relies on it. `rested` and `promoted` explorations are
terminal and are correctly skipped by that scan.

## The two exits (user-declared, NO gate)

An exploration ends only when the **user declares** an exit. There is
no soundness gate, no automatic promotion — the agent surfaces the two
options; the user picks.

### REST

Set `status=rested` and `rested-on=<date>` in the STATE HEADER. The
drawer stands as a **standing understanding artifact** — a parked,
durable record of where the thinking got to. A rested exploration can
be resumed later (re-flip to `active`) or left as reference. REST
clears it from `session-startup`'s active scan.

### PROMOTE

The idea is design-ready. **Open `/design-a-cycle`** on the topic this
exploration converged on. Wire the lineage so the design cycle's
locked decisions are **`grounded_in` this exploration drawer** — add
the `grounded_in` KG edge (and the design doc's substrate cites the
drawer as grounding). Set `status=promoted` and `promoted-to=<the
/design-a-cycle topic / design-doc drawer ID>` in the STATE HEADER.
PROMOTE clears it from the active scan; from here the design cycle
takes over (and eventually hands off to `create-beads` → the build
recipes).

## Example

> **User:** /explore should facility state be event-sourced?
>
> 1. **Open.** Seed `templates/exploration/EXPLORATION.md.template`
>    with `question="should facility state be event-sourced?"`,
>    `wing=loom`; file the drawer into `loom/decisions`; tag it
>    `exploration`. STATE HEADER: status `active`, the question, today
>    as `opened`.
> 2. **Tiers 1 + 2 in-thread.** Reason over what "facility state"
>    means here (Tier 1); `Grep`/`Read` the current state-management
>    code + `docs/` (Tier 2, optionally via an `Explore` subagent).
>    Precipitate F1 ("today's model is a mutable snapshot, no event
>    log") into `## Findings`.
> 3. **Heavy round when a thread needs it.** The user asks "what does
>    the literature say about event-sourcing for real-time state?" —
>    dispatch a `deep-research` round (Tiers 3 + 4): web common-usage
>    + **peer-reviewed** literature on event sourcing / CQRS for
>    real-time systems. Central synthesizes the returns into the
>    dialogue and precipitates F2 + F3 (with paper-citation
>    provenance) into `## Findings`; revises `current-understanding`.
> 4. **Converge.** A couple more in-thread turns sharpen the shared
>    understanding; `open-threads` shrinks.
> 5. **Exit.** The user is satisfied the idea is design-ready and says
>    "promote." Open `/design-a-cycle facility event-sourcing`, wire
>    its decisions `grounded_in` this drawer, set `status=promoted` +
>    `promoted-to`. (Had the user said "rest", set `status=rested`
>    instead and stop.)

## Composition

- **Above** this primitive: nothing — `/explore` is the top of the
  ladder (explore → design → build).
- **Below / downstream**: `/design-a-cycle` (opened on PROMOTE, wired
  `grounded_in` this drawer), which in turn spawns `create-beads` →
  the `<activity>-a-bead` recipes + `/dispatch-middle`.
- **Dispatched by** this primitive: a `deep-research` round for the
  heavy tiers (3 + 4); optionally an `Explore` subagent for a larger
  Tier-2 dig.
- **Discovered by**: `session-startup` step 1e (active-explorations
  scan).
- **Grounded in**: the exploration design drawer
  (`drawer_loom_decisions_2ee82f47ed6bc219866cd5c4`); honors loom-5m94
  (lean-central), loom-yb5 (nudge-not-block), loom-tdua (soft KG
  predicate posture).

## Critical

- **It is NOT a bead and NOT a design cycle.** No claim, no RED→GREEN,
  no `[CLARIFICATION]` markers, no soundness gate, no epic. Treating an
  exploration as either re-imports rigidity the nascent-idea phase
  can't afford. If you find yourself gating, you've drifted into
  `/design-a-cycle` — PROMOTE instead.
- **The loop is HYBRID — don't run the heavy tiers inline.** Tiers 1 +
  2 run in-thread; Tiers 3 + 4 go out as a `deep-research` round only
  when a thread needs grounding. Running web + literature search inline
  on every turn burns central's context and violates lean-central
  (loom-5m94). Central writes nothing but the capture.
- **Tier 4 is the point.** Peer-reviewed literature is the
  distinguishing tier — skipping it collapses `/explore` into ordinary
  brainstorming. When the idea has a research literature, ground in it.
- **The drawer is tagged `exploration`, not housed in its own room.**
  The tag is what keeps the exploration's findings reachable by
  bug-family search. Filing it in a dedicated room would hide it from
  prior-art search.
- **Precipitate FIRM findings only.** In-flight prose stays in the
  `## Inquiry log`; only settled understanding precipitates into
  `## Findings` + KG triples. Don't add a triple for a thread you're
  still chasing — that's what `has_open_thread` / `open-threads` are
  for.
- **Exits are USER-declared.** The agent surfaces REST vs PROMOTE; it
  never auto-promotes or auto-rests. Either exit clears the exploration
  from `session-startup`'s active scan.
- **v1 has no hook backstop.** This is prompt/skill-only
  (nudge-not-block, loom-yb5). The discipline above is convention, not
  enforcement.
