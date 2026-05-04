# Mental model

> **Thesis.** Loom is not one tool. It is a layered set of memory
> axes plus a layer of process discipline plus a connective tissue
> of primitives that fire on lifecycle events. The synergy is in
> the hand-offs, and the load-bearing decomposition is the *split* —
> not any individual axis's depth. Flatten the split, and the next
> compaction event will teach you why it existed.

## The four-axis memory model

Each tool persists a different axis of "knowledge that survives
sessions." The synergy is in their hand-offs, not in any single
tool's depth.

| Tool                       | Owns                                              | Surfaces at                |
|----------------------------|---------------------------------------------------|----------------------------|
| **beads**                  | task state + project tribal knowledge             | `bd prime`, explicit query |
| **MemPalace drawers**      | verbatim decisions, lineage, quotes               | manual queries             |
| **MemPalace KG**           | structured S→P→O facts (time-windowed)            | `kg_query` / `kg_timeline` |
| **MemPalace diary**        | per-agent introspective continuity (AAAK)         | `diary_read` (manual)      |
| **superpowers** skills     | process discipline (TDD, debugging, verify)       | when invoked correctly     |
| **beadpowers** skills      | design → bead pipeline                            | when invoked correctly     |
| **Claude Code primitives** | the connective tissue between all of the above    | various lifecycle events   |

## The rule

> **The discipline can't be skipped because the primitives enforce it.**

Slash commands fire skills; skills load on demand; hooks fire on
lifecycle events automatically; subagents handle isolated work
without bloating the main context. Each tool's output should feed
the next tool's input via a primitive — if you have to remember to
do it, the plan failed. This is loom's first design commitment, and
the rest of loom's structure is downstream of it.

## Why four axes and not one

Combining task state with verbatim decisions produced the v1
"working-a-bead" model and the failure mode it taught: mid-session
zealous compaction silently dropped the design intent because the
bead description couldn't carry it. Splitting decisions out into
MemPalace drawers, structured facts into the KG, and introspective
continuity into the diary meant each axis could grow at its own
rate and decay (or persist) on its own schedule.

The four-axis split is a load-bearing decomposition. The temptation
is always to flatten it back down — "why don't drawers just live in
beads?", "why do we need a KG when we have drawers?", "why a diary
when we have drawers?" — and the answer is the same in every case:
because each axis fails differently and at a different cadence, and
collapsing them couples the failure modes.

- **beads** are queue-shaped: optimised for "what's next?" and "is
  this blocked?", lossy on rationale by design.
- **MemPalace drawers** are essay-shaped: optimised for verbatim
  decision capture, terrible at "what's next?".
- **MemPalace KG** is graph-shaped: optimised for "what's related
  to X over time?", lossless on structure, lossy on prose.
- **MemPalace diary** is journal-shaped: optimised for the agent's
  own continuity ("what did I think was worth remembering when I
  was working on this?"), invisible until explicitly read.

A drawer cannot be queried by S→P→O cheaply. The KG cannot carry
verbatim quotes well. Beads cannot hold an essay without ballooning.
The diary is private to its agent and to its read ritual. Each axis
is bad at the others' job. That is the point.

## Why discipline is in the primitives

The other choice — discipline lives in the agent, who is asked to
remember to do the right thing — is the configuration loom most
explicitly does not ship. Hooks fire on real lifecycle events:
`bd update --claim` reminds the agent to dispatch the bug-family
researcher; `bd close` blocks (in `full` mode) until the decision
drawer has been written; `git push` warns if the beads workspace is
dirty. Skills load on demand when the agent's context matches a
trigger phrase or when a slash command names them. Subagents are
spawned with their own context budget so the main conversation stays
clean.

The agent is not asked to remember any of this. The primitives
remember it. That is what makes the discipline reliable.

## When the mental model matters

- **Cold start.** The four axes tell you where to look first: beads
  for queue, MemPalace drawers for design intent, KG for structured
  facts, diary for what your past self thought was worth remembering.
- **Mid-bead.** Process skills (superpowers, beadpowers) keep the
  discipline tight; the activity-shaped recipes choose *which*
  discipline applies.
- **Capture.** Each axis has a destination at close: tribal one-liners
  → `bd remember`; multi-paragraph decisions → MemPalace drawers;
  structured facts → KG triples; introspective continuity → diary.

The [recipe family](./recipe-family.md) builds on this model — each
recipe is a different shape of "which axes feed which axes when?"
The [workflow modes](./workflow-modes.md) page explains why the
discipline has a volume knob.
