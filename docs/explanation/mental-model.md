# Mental model

> Lifted from `docs/manual.md` §1 (commit `90baa32`). Subsequent
> restructure beads (loom-9z1.5) split the rationale half of §4 into
> a sibling page; for now, this is the only explanation page.

## The four-axis memory model

Each tool persists a different axis of "knowledge that survives
sessions." The synergy is in their hand-offs, not in any single
tool's depth.

| Tool                     | Owns                                                | Surfaces at                |
|--------------------------|-----------------------------------------------------|----------------------------|
| **beads**                | task state + project tribal knowledge               | `bd prime`, explicit query |
| **MemPalace drawers**    | verbatim decisions, lineage, quotes                 | manual queries             |
| **MemPalace KG**         | structured S→P→O facts (time-windowed)              | `kg_query` / `kg_timeline` |
| **MemPalace diary**      | per-agent introspective continuity (AAAK)           | `diary_read` (manual)      |
| **superpowers** skills   | process discipline (TDD, debugging, verify)         | when invoked correctly     |
| **beadpowers** skills    | design → bead pipeline                              | when invoked correctly     |
| **Claude Code primitives** | the connective tissue between all of the above    | various lifecycle events   |

## The rule

> **The discipline can't be skipped because the primitives enforce it.**

Slash commands fire skills; skills load on demand; hooks fire on
lifecycle events automatically; subagents handle isolated work
without bloating the main context. Each tool's output should feed
the next tool's input via a primitive — if you have to remember to
do it, the plan failed.

## When the mental model matters

- **Cold start.** The four axes tell you where to look first: beads
  for queue, MemPalace drawers for design intent, KG for structured
  facts, diary for what your past self thought was worth remembering.
- **Mid-bead.** Process skills (superpowers, beadpowers) keep
  discipline tight; the recipe-shaped activity skills choose
  *which* discipline applies.
- **Capture.** Each axis has a destination at close: tribal one-liners
  → `bd remember`; multi-paragraph decisions → MemPalace drawers;
  structured facts → KG triples; introspective continuity → diary.

## Why four axes and not one

Combining task state with verbatim decisions produced the v1
"working-a-bead" model and the failure mode it taught: mid-session
zealous compaction silently dropped the design intent because the
bead description couldn't carry it. Splitting decisions out into
MemPalace drawers and structured facts into the KG meant each axis
could grow at its own rate and decay (or persist) on its own
schedule. The four-axis split is a load-bearing decomposition; if
you flatten it back into one tool, the next compaction event will
teach you why it was split.
