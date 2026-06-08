# explore — reference

> Above-bead, SUB-design collaborative-exploration primitive.
> `/explore <idea>` opens an exploration that blends four source tiers
> — self, repo+docs, web, and peer-reviewed literature — to converge
> WITH the user on shared understanding. It is the front-door to
> [`/design-a-cycle`](design-a-cycle.md) the way `/design-a-cycle` is
> the front-door to `create-beads`. It is **NOT a bead** and **NOT a
> design cycle** — no soundness gate, no epic emission.

`/explore <idea>` (filed as epic `loom-ld1q`) is the phase loom never
had below design. Where [`brainstorming`](skills/all-skills.md) runs
the Socratic method to diverge-from-then-converge-on YOUR intent,
`/explore` diverges across FOUR source tiers first and then converges
with you on a shared understanding. The unit it opens is called **an
exploration**.

It is a **SUB-design primitive**: it sits one rung below
`/design-a-cycle` on the ladder. The full progression is
**explore → design → build** — an exploration converges on shared
understanding, a design cycle locks that understanding into sound
decisions + a handoff epic, and the activity recipes
(`bugfix-a-bead`, `feature-a-bead`, …) build each emitted bead. An
exploration produces no design, no epic, and no code; its only durable
artifact is the exploration drawer it accretes.

## The four tiers

The blend is the point. An exploration draws on four source tiers, and
the gap it fills is Tier 4 — none of the adjacent tools (brainstorming,
research-a-bead, deep-research, design-a-cycle) target peer-reviewed
literature.

| Tier | Source | Where it runs |
|---|---|---|
| **Tier 1** | Self / current context — the agent's own reasoning over what's already in the thread | In-thread (light) |
| **Tier 2** | Repo + docs — grep/read of this repository and its documentation | In-thread (light) |
| **Tier 3** | Web — common usage and knowledge on the open web | Dispatched (heavy) |
| **Tier 4** | Peer-reviewed literature — academic research | Dispatched (heavy) |

## The hybrid loop

The loop rhythm is **hybrid** (honors the dispatch-v2 lean-central
discipline, `loom-5m94`):

- **Light tiers (1 + 2) stay in-thread.** Self-reasoning and the
  repo/docs dig happen inline (or via an Explore subagent returning
  conclusions), turn by turn.
- **Heavy tiers (3 + 4) are dispatched as a `deep-research` round**
  when the conversation calls for one — NOT every turn. A round invokes
  the existing [`deep-research`](skills/all-skills.md) harness against
  the specific surfaced sub-question (web fan-out → adversarial verify →
  cited synthesis, peer-review-inclusive). It is **one round per
  surfaced question** — deep-research fans out internally, so there is
  no per-tier worker sprawl.
- **Central writes nothing but the capture.** It synthesizes returns
  back into the conversation and precipitates only firm findings into
  the drawer + KG.

## The exploration drawer

An exploration's entire memory is ONE drawer in the `loom` wing,
`decisions` room, tagged **`exploration`**. The tag — not a dedicated
room — is deliberate: it keeps the drawer inside the `decisions` room
where **bug-family search** reaches it, while still being filterable.
(The precedent is `loom-mine-history`'s `provenance:mined` tag.)

The drawer is created at open (seeded with the question) and updated
incrementally after each research round. It is prose-light: a machine-
read STATE HEADER above human-and-agent-readable reasoning sections.

**STATE HEADER fields:** `question` · `status` (`active` | `rested` |
`promoted`) · `tiers-touched` · `open-threads` ·
`current-understanding` · `opened` · `last-touched` ·
(`rested-on` | `promoted-to`).

**Sections:**

- `## Inquiry log` — the prose reasoning surface (reason-in-prose).
- `## Findings` — precipitated firm findings, each carrying its
  provenance (source + tier).
- `## Lineage` — links to upstream/downstream artifacts.

KG triples are written **only for firm findings** (lean, mirroring the
design-a-cycle capture cadence). Even a rested exploration therefore
leaves a real drawer plus KG facts — the minimal MemPalace artifact, by
construction.

## Discovery

`session-startup` gains a cheap active-explorations scan beside the
existing design-cycle scan. It surfaces explorations with
`status=active` only, INFO-only — it skips `rested` and `promoted`
explorations and degrades gracefully when MemPalace is offline.

## The two exits

Exits are **user-declared** — there is no gate. Either exit clears the
exploration from session-startup's active scan.

- **REST** → `status=rested`. The drawer stands on its own as a
  standing-understanding artifact. No design cycle is opened; the
  exploration's value is the shared understanding it captured.
- **PROMOTE** → opens [`/design-a-cycle`](design-a-cycle.md). The new
  cycle's decisions are wired `grounded_in` this exploration drawer
  (reusing the existing grounding predicate), and the exploration's
  `status` becomes `promoted` with a `promoted-to` pointer.

## KG predicates

The recommended exploration-predicate vocabulary is a **soft
recommendation, not a locked schema** (mirroring the design-cycle
predicate set, `loom-tdua`). It reuses `grounded_in` and
`surfaced_finding`, and adds:

- `explores` — an exploration explores an idea.
- `surfaced_finding` — an exploration round surfaced a finding.
- `has_open_thread` — an exploration carries an unresolved thread.
- `informs_design_of` — an exploration informs a downstream design
  cycle.
- `grounded_in` — a promoted cycle's decisions rest on the exploration
  drawer.

Because the KG is open, these compose with whatever project-local
predicates already exist; an exploration that needs a different shape is
free to deviate.

## v1 scope

v1 deliberately ships the recipe + convention + template only (mirroring
the design-a-cycle v1 posture): `skills/explore/SKILL.md` +
`commands/explore.md`, a `templates/exploration/` skeleton, the
session-startup active-explorations scan, and this convention + reference
docs. It has **NO soundness gate** (it is lighter than a design cycle by
design) and **NO hook backstop** — it is prompt/skill-only, a
nudge-not-block primitive (`loom-yb5`). Auto-triggering, an
exploration→Diátaxis projection, and a drawer↔KG drift-check are all
deferred as dogfood-gated.

## How it relates

| Adjacent primitive | Difference |
|---|---|
| [`brainstorming`](skills/all-skills.md) | Socratic; extracts YOUR intent, brings in no outside knowledge. `/explore` blends four evidence tiers and co-explores. |
| [`research-a-bead`](skills/all-skills.md) | Dispatch-and-report; bead-shaped (claim + deliverable ceremony), solo, not a back-and-forth. `/explore` is collaborative and bead-less. |
| [`deep-research`](skills/all-skills.md) | Autonomous web fan-out → adversarial verify → cited report; one-shot, web-centric. `/explore` *uses* it as the Tier-3/4 round, wrapped in a collaborative loop. |
| [`design-a-cycle`](design-a-cycle.md) | Heavyweight above-bead orchestrator that PRODUCES a locked design + impl epic, gated on soundness. `/explore` sits UPSTREAM of it — promoting an exploration opens a design cycle `grounded_in` the drawer. |

## Related

| Item | Page |
|---|---|
| The design cycle an exploration promotes into | [design-a-cycle](design-a-cycle.md) |
| Recipe-family contrast (where explore/design/build sit) | [Recipe family](../explanation/recipe-family.md) |
| Sibling skills (brainstorming / research-a-bead / deep-research) | [All skills](skills/all-skills.md) |
