# Claude Workflow Walkthrough — Design Cycle

> A narrative walkthrough of the layer *above* the leaf recipes. The
> [bug](./bug-walkthrough.md) and [feature](./feature-walkthrough.md)
> walkthroughs each work ONE bead from claim to merged. This file shows
> what happens *before* those beads exist — the design cycle that turns
> a bare topic into contract-bearing beads the recipes can consume.
>
> Format: "**You:**" lines are what you type; "**Claude:**" lines are
> the assistant's response (sometimes summarized, sometimes verbatim);
> indented italic blocks are commentary on what's happening behind the
> scenes. Hook output appears in `[brackets]` when relevant.
>
> Honesty caveat: the design-cycle system shipped 2026-06-07 (epic
> `loom-tdua`). The `templates/design-doc/` skeleton (T1, `loom-dhra`)
> and the `/design-a-cycle` orchestrator (T2) exist; the substrate it
> reads and writes is ordinary MemPalace infrastructure (KG + drawers),
> so no new tooling was needed. The cadence below is the orchestrator's
> designed shape; spawning research-beads and an implementation epic via
> subagent dispatch + `create-beads` is observed reality. Where a step
> is aspirational rather than observed, a note flags it.

---

## 1. Why a design cycle at all

There is a gap the leaf recipes cannot fill. `bugfix-a-bead`,
`feature-a-bead`, and their siblings each take ONE bead with a locked
contract and drive it through a single RED→GREEN middle to merged. They
are *consumers* of contracts. They do not produce them.

But most real work does not start as a bead with a locked contract. It
starts as a *topic*: "we should rework auth," "the dispatch model needs
a v2," "figure out how design should feed the build phase." Between "I
have a topic" and "I have a set of beads each carrying a `RED:` line a
test-author can pin against" sits a whole phase of work — converging the
question, grounding the open uncertainties in research, locking
decisions, checking they cohere, and only then spawning the
implementation epic.

Cramming that phase into a leaf bead is a trap (the grounding research,
`loom-l0f`, named it the "make the generative phase rigid" failure). A
design cycle is not a bead. It is an **above-bead orchestrator** that
ITERATES across many turns, SPAWNS research-beads as it goes, and
ultimately SPAWNS the implementation epic. It sits above both beads and
epics.

This walkthrough follows one design cycle for the topic `dispatch`
(loom's own dispatch-architecture-v2 work — the real cycle that
produced the `/dispatch-middle` you saw in the other two walkthroughs).

---

## 2. Opening a cycle

### 0. Launch, prime, invoke

```
$ cd ~/repos/loom
$ claude
```

**[v1.5]** *Status line:* `WORKFLOW: light | idle | 2h`.

**You:**
```
/design-a-cycle dispatch
```

*The slash command loads the `design-a-cycle` skill. Unlike a recipe,
it does not claim a bead — there is no bead yet. Its first move is
always to read state, never to assume a fresh start.*

### Step 0 — read the substrate STATE

**Claude:** *(Step 0 — read the substrate)*

> Reading the substrate for `dispatch` before doing anything.

```
mempalace_search "dispatch design"   (room: decisions)
mempalace_kg_query "dispatch"
```

> No existing DESIGN DOC drawer for `dispatch`. The KG has a few prior
> dispatch facts (the loom-yb5 fan-out detector, the dispatch-nudge
> hook) but no in-flight cycle. This is a fresh cycle — I'll scaffold
> the design-doc drawer before driving any cadence step.

*The design cycle keeps **no private state file** and **no new bd
entity**. Its entire memory is "substrate-as-state": the L2 design-doc
drawer's STATE HEADER, backed by the L1 KG. On every invocation it
reads that header first. If a cycle already existed, Claude would read
its cycle-number, soundness-status, locked-decisions, open
`[CLARIFICATION]` markers, and spawned-bead IDs, then resume where it
paused. Skipping Step 0 and re-scaffolding over an existing cycle would
wipe locked decisions — so it never does.*

### Step 1 — scaffold from `templates/design-doc/`

**Claude:** *(Step 1 — scaffold)*

> Scaffolding from `templates/design-doc/`. Same mechanism as the
> Diataxis scaffolder — plain `sed` substitution, no Python.

```bash
cp -r templates/design-doc/. /tmp/design-dispatch/
find /tmp/design-dispatch -type f -exec sed -i \
  -e "s|{{ topic }}|dispatch|g" \
  -e "s|{{ wing }}|loom|g" {} +
find /tmp/design-dispatch -type f -name '*.template' \
  -exec sh -c 'mv "$1" "${1%.template}"' _ {} \;
grep -r '{{' /tmp/design-dispatch || echo "no tokens left"
```

```
no tokens left
```

*Two tokens get substituted: `{{ topic }}` (the cycle's topic) and
`{{ wing }}` (the project wing, here `loom`). After substitution,
`grep -r '{{'` must come back empty.*

**Claude:**

> Filing the populated body as a drawer in `loom/decisions`.

```
mempalace_add_drawer(wing="loom", room="decisions",
  content="DESIGN DOC — dispatch ...", added_by="claude-opus")
```

*The fresh drawer starts at cycle-number 0, soundness-status **red**,
with one seed `[CLARIFICATION]` marker. Its STATE HEADER looks like:*

```
## STATE HEADER
- cycle-number: 0
- soundness-status: red
- locked-decisions:
  - (none yet)
- open [CLARIFICATION] markers:
  - [CLARIFICATION: what is the actual root failure of inline-middle work?]
- spawned research-bead IDs:
  - (none yet)
- target implementation-epic ID:
  - (none yet)
```

*That header is the orchestrator's whole memory. Everything below it —
Question/Scope, Decisions-locked, Grounding-checklist, Lineage — is the
prose working-surface where reasoning happens before it precipitates
into structure.*

---

## 3. One cadence pass

*The orchestrator does not run a fixed script. It reads the state and
PROPOSES the next action, then drives ONE step (or loops a few when you
ask it to run the cycle forward). The cadence is:*

> **Plan → Research → Architect → Soundness → (loop until green) → Handoff.**

*It picks the step the state calls for. A fresh drawer with an open
`[CLARIFICATION]` marker and no direction set calls for Plan.*

### Plan — set direction (brainstorming)

**You:**
```
run the cycle forward
```

**Claude:** *(Plan — invokes `beadpowers:brainstorming`, since this
design will land as beads)*

> The Question is sharpening: "How should a bead's variable middle be
> structured so that (a) central doesn't drown in test/code churn and
> (b) the test isn't a tautology of the implementation?" Scope: the
> within-bead RED→GREEN division of labor. Out of scope (the YAGNI
> cut): across-bead parallelism — that's already owned by the loom-yb5
> fan-out detector.
>
> Two forks surfaced that I can't settle from the palace alone:
>
> 1. `[CLARIFICATION: is the test-author == code-author problem real
>    enough to force two agents, or is one disciplined agent enough?]`
> 2. `[CLARIFICATION: does one shared worktree or two separate
>    worktrees give the implementer the RED test as an artifact?]`

*Plan converges the Question/Scope and surfaces forks; each unresolved
fork becomes a `[CLARIFICATION]` marker in the STATE HEADER. Plan does
not lock decisions by itself — it frames them for Research and
Architect. The seed marker is replaced by these two sharper ones, and
cycle-number ticks to 1.*

### Research — ground each open marker

**Claude:** *(Research — for each marker that needs real grounding)*

> Marker 1 needs prior-art grounding — it's the crux of the design.
> Spawning a `research-a-bead` for it.

```bash
bd create -t task "research: is test-author==code-author a real anti-pattern?" \
  --description "[CLARIFICATION] grounding for dispatch cycle. ..."
# → loom-dwn
```

> Spawned `loom-dwn`. Recording it in the STATE HEADER's spawned
> research-bead IDs. Marker 2 is answerable from the palace + a quick
> git-worktrees doc check — resolving it inline without a bead.

*For each open `[CLARIFICATION]` marker that needs external or
prior-art grounding, the orchestrator **spawns a research-a-bead** and
records its ID in the STATE HEADER, so the cycle tracks which markers
are in-flight. When that research bead closes, its decision drawer
becomes the grounding the Architect step cites. A marker answerable
from the palace alone gets resolved inline — no bead for a one-off
lookup.*

*Time passes — possibly a separate session. `loom-dwn` gets worked via
`research-a-bead` (its own claim → search → synthesize → file-findings
cycle, no code). It closes with a decision drawer: "yes, when one agent
writes both test and code the test is shaped to match the code it
already has in mind; independence must be structural." `session-startup`
surfaces the still-open `dispatch` cycle on the next cold start, so you
resume it.*

### Architect — precipitate each locked decision

**You:**
```
/design-a-cycle dispatch
```

**Claude:** *(Step 0 re-reads state: `loom-dwn` is now closed; marker 1
is grounded. Proposes Architect.)*

> `loom-dwn` closed — marker 1 is grounded. Marker 2 (worktree shape)
> resolved inline: one shared worktree, so the implementer reads the
> test-author's committed RED file directly on disk. Two decisions are
> ready to lock. Precipitating each into all three layers.

*When a decision locks, the orchestrator PRECIPITATES it — this is the
governing posture, **reason in prose, precipitate into structure**:*

- **L1 — KG triples**, using the soft recommended design-predicate set
  (advisory, not a locked schema): `grounded_in`, `supersedes_design_of`,
  `emits_bead`, `soundness_tier`, `depends_on_invariant`.
- **L2 — the Decisions-locked section** of the drawer (Decision /
  Grounding / Options + why-not / optional L3 spec), with the
  decision's short handle added to the STATE HEADER's locked-decisions
  list and the answered `[CLARIFICATION]` marker removed.
- **L3 — an optional executable spec**, when the decision has a natural
  testable altitude.

**Claude:**

```
mempalace_kg_add(subject="D1-two-agent-split",
  predicate="grounded_in", object="drawer_loom_decisions_<loom-dwn-id>")
mempalace_kg_add(subject="D1-two-agent-split",
  predicate="soundness_tier", object="tier-1")
```

> **D1 — two-agent split (test-author ≠ implementer).**
> *Decision.* The RED→GREEN middle runs as two independent dispatched
> agents in one shared worktree; the implementer inherits the RED test
> as an artifact and never sees the author's reasoning.
> *Grounding.* `loom-dwn` decision drawer (test==code is a real
> anti-pattern).
> *Options / why-not.* (a) one disciplined agent — rejected, the
> tautology is structural not a discipline problem. (b) two separate
> worktrees — rejected, the implementer then can't read the committed
> RED file directly.
> *L3 spec (Tier-1, behavioral altitude):*
> ```
> Given a bead with a locked RED: contract
> When  /dispatch-middle runs its test-author then its implementer
> Then  the implementer's brief contains the RED test file path and
>       NOT the test-author's reasoning
> ```

*D1 has a natural testable altitude, so it carries a Tier-1 L3 spec —
that spec becomes the spawned bead's RED test. A second decision, D2
("central writes nothing in the middle"), is structural with no clean
executable altitude, so it locks with Tier-0 coherence only and no L3
spec. A Tier-0-only decision is expected and fine — not a gap.*

---

## 4. The two-tier soundness gate

*After each Architect pass the orchestrator runs the soundness check
and loops the cadence until it's green. There are two tiers (locked in
`loom-5w6`):*

### Tier-0 — coherence (the always-on floor)

**Claude:** *(Soundness — Tier-0 check)*

> Running the Tier-0 coherence gate (the Grounding-checklist in the
> drawer, mechanized as a checklist — checklists act as unit tests for
> specifications):

```
- [x] Every locked decision cites its grounding.        (D1 → loom-dwn; D2 → loom-l0f)
- [x] Every locked decision names options + why-not.
- [ ] No unresolved [CLARIFICATION] markers remain.      ← marker 2 still listed!
- [x] No locked decision violates a constitutional invariant.
- [x] Each Tier-1 decision's L3 spec is ready to seed its bead's RED test.
```

> One box unchecked: marker 2 is resolved in prose but I never removed
> it from the STATE HEADER. soundness-status stays **amber**. Removing
> the stale marker and re-running.

*Tier-0 is the always-on floor. The cycle is green only when: no
unresolved `[CLARIFICATION]` markers remain, every locked decision
cites grounding, every locked decision names options-considered +
why-not, and no decision violates a recorded constitutional invariant.
The loop matters — this pass caught a marker the Architect step
resolved in prose but forgot to clear from the header. Fix, re-run.*

**Claude:** *(second Soundness pass)*

> Marker 2 cleared. All five boxes checked. soundness-status →
> **green**. Tier-0 satisfied.

```
mempalace_update_drawer(... soundness-status: green ...)
```

### Tier-1 — executable-spec emission (the optional ceiling)

*Tier-1 is OPTIONAL by construction, per-decision. A locked decision
MAY carry an L3 executable spec at its natural altitude (D1 does; D2
doesn't). Forcing Tier-1 on every decision would re-import exactly the
RED→GREEN mismatch the grounding research diagnosed — so it's a ceiling
a decision can reach, never a gate every decision must pass. Soundness
is enforced as a recipe-STEP (a nudge, per loom's nudge-not-block
posture), not a hard hook.*

> Do NOT hand off until Tier-0 is green. Tier-0 is green and D1 carries
> its Tier-1 spec. Ready for Handoff.

---

## 5. Handoff — spawn the implementation epic

*Once Tier-0 is green, the orchestrator hands off: it runs
`beadpowers:create-beads` against the locked decisions to spawn the
implementation **epic** plus its child beads. The handoff is enriched
beyond the plain create-beads shape.*

**You:**
```
hand off
```

**Claude:** *(Handoff — `beadpowers:create-beads`)*

> Tier-0 green. Spawning the implementation epic from the locked
> decisions.

```bash
bd create -t epic "dispatch architecture v2: /dispatch-middle"   # → loom-5m94
bd create -t feature "the /dispatch-middle skill (test-author → implementer)" \
  --description "Files: skills/dispatch-middle/SKILL.md, commands/dispatch-middle.md
RED:
Given a bead with a locked RED: contract
When  /dispatch-middle runs its test-author then its implementer
Then  the implementer's brief contains the RED test file path and NOT
      the test-author's reasoning"
# → loom-8crd  (blocked on nothing; child of loom-5m94)
```

> Epic `loom-5m94` with child beads. Each bead carries:
>
> - a **`Files:` line** (the loom-asr fan-out convention — the paths it
>   is expected to touch, so the fan-out detector can decide which
>   beads are wave-compatible);
> - and, for every bead spawned from a **Tier-1 decision**, a **`RED:`
>   line** carrying that decision's L3 spec verbatim.

*That `RED:` line IS the contract `/dispatch-middle`'s test-author
consumes — the loom-tdua → loom-5m94 interlock. A bead spawned from a
Tier-0-only decision carries `Files:` but no `RED:` line; that's
expected, not a gap. Forgetting the `RED:` line on a Tier-1 bead would
strand its L3 spec — the test-author would then have no contract to pin
and the cycle's executable-spec work would be wasted.*

**Claude:**

```
mempalace_kg_add(subject="D1-two-agent-split", predicate="emits_bead",
  object="loom-8crd")
mempalace_update_drawer(... target implementation-epic ID: loom-5m94 ...)
```

> Recorded the epic ID in the STATE HEADER and added `emits_bead`
> triples to L1. The design cycle's job is done — the epic exists with
> contract-bearing beads. The leaf recipes take it from here.

### What happens to each spawned bead next

*This is the seam between this walkthrough and the others. Each child
bead of `loom-5m94` now re-enters the leaf-recipe world. When you claim
`loom-8crd`, `/working-a-bead` routes it to `feature-a-bead`, and its
RED→GREEN middle runs through `/dispatch-middle` — the test-author pins
the bead's `RED:` line (the very L3 spec this cycle wrote), and a
separate implementer makes it GREEN. That is exactly the pipeline the
[feature walkthrough](./feature-walkthrough.md) narrates end-to-end.
Read it next to see one of these spawned beads carried to merged.*

---

## What you noticed during the walkthrough

### Things the orchestrator did (that a leaf recipe cannot)

- **Iterated across turns and sessions** — Plan → Research → Architect
  → Soundness → Handoff is a cadence, not a single RED→GREEN. The cycle
  paused after spawning `loom-dwn` and resumed on a later cold start.
- **Spawned children** — a `research-a-bead` for the grounded marker,
  then an implementation epic at handoff. A leaf recipe works one bead;
  this one *creates* beads.
- **Kept its state in the substrate, not a file** — the L2 drawer's
  STATE HEADER + the L1 KG were the entire memory. Step 0 re-read it on
  every invocation.
- **Precipitated reasoning into structure** — prose decisions in the
  drawer became KG triples and (for Tier-1) L3 specs, and those specs
  became `RED:` lines on the emitted beads.

### Things you did manually

- Gave the topic (`/design-a-cycle dispatch`).
- Approved spawning the research bead (an expensive step — the
  orchestrator surfaces the proposal before driving it).
- Confirmed direction at the Plan forks.
- Approved the handoff to `create-beads`.

### Things the orchestrator enforced

- Step 0 read-state-first, every invocation (never re-scaffold over a
  live cycle).
- Grounding on every locked decision (Tier-0 coherence floor).
- Loop-until-green before handoff (the amber→green marker-cleanup pass).
- A `Files:` line on every emitted bead; a `RED:` line on every Tier-1
  bead.

---

## Variations

### If the topic is too small to earn a cycle

Skip the orchestrator. A single trivial decision just gets made and
captured as a drawer; the cadence earns its keep only when the design
space is wide enough to iterate over. Likewise, if a locked contract
already exists and you just need to BUILD it, go straight to the
matching `<activity>-a-bead` recipe (or `/dispatch-middle <bead>` for
the within-bead split). This orchestrator *produces* contracts; it does
not consume them.

### If a `[CLARIFICATION]` marker is answerable from the palace

Resolve it inline — no research bead. Spawn a `research-a-bead` only
when the answer needs real research (external docs, prior-art
synthesis, a comparison that doesn't already live in the KG or a
drawer).

### If you hand off before Tier-0 is green

Don't. Spawning the epic with unresolved `[CLARIFICATION]` markers or
ungrounded decisions ships an incoherent design into the build phase.
The Soundness step is the gate; loop the cadence until Tier-0 is green.
(The amber→green pass above is the system working as intended — it
caught a stale marker before handoff.)

### If you try to file the cycle as a bead or epic

Don't. A design cycle is an above-bead orchestrator, NOT a bead or
epic. Filing it as one forces the iterative cadence into a leaf shape
and loses the spawn-children + spawn-epic arc. Its state lives in the
substrate (the L2 drawer header + the L1 KG); it *emits* beads, it is
not itself one.

---

## Where to update what (quick recap)

| Friction | Edit |
|---|---|
| The cadence / soundness gate is wrong | `~/.claude/skills/design-a-cycle/SKILL.md` |
| The scaffolded design-doc shape is wrong | `templates/design-doc/DESIGN-DOC.md.template` |
| Within-bead test→code split is wrong | `~/.claude/skills/dispatch-middle/SKILL.md` |
| The leaf recipe that works a spawned bead | `~/.claude/skills/<shape>-a-bead/SKILL.md` |
| Bead-creation / `Files:`+`RED:` convention | `beadpowers:create-beads` + project `CLAUDE.md` |
| A locked decision worth re-capturing | `mempalace_add_drawer` / `mempalace_kg_add` |

The [where-to-update-what guide](../how-to/where-to-update-what.md)
has the full matrix.

---

## Honesty caveat (recap)

The design-cycle system shipped 2026-06-07 (epic `loom-tdua`,
brainstorm locked in the `/design-a-cycle build brainstorm CHECKPOINT`
drawer, `loom/decisions`, grounded in the three converged research
drawers `loom-l0f`, `loom-5w6`, `loom-dwn`). The orchestrator and the
`templates/design-doc/` skeleton exist, and the substrate it reads and
writes is ordinary MemPalace infrastructure — no new tooling. The
specific `dispatch` cycle narrated here is reconstructed to illustrate
the cadence faithfully; the real loom dispatch-v2 work it mirrors did
ship as epic `loom-5m94`. Where a step is the orchestrator's designed
shape rather than something observed end-to-end, the inline notes flag
it.
