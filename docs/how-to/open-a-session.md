# Open a session

To start working in a beads workspace with full context primed,
follow these steps.

## Precondition

- A beads workspace exists at the project root (`.beads/issues.jsonl`
  present).
- Loom is installed (see [Install loom](./install.md)).
- You are at a fresh prompt — either a new Claude Code session or
  immediately after `/clear`.

## Steps

1. **Let the SessionStart hooks run.** When the session opens, hooks
   fire automatically:
   - `bd prime` injects the ready queue, in-progress beads, and
     persistent memories.
   - `mempal-stop-hook` from the previous session has already
     persisted the diary + drawer state.
   - The superpowers and beadpowers session-start hooks load the
     `using-superpowers` and `using-beadpowers` meta-skills.

2. **Trigger `/session-startup`.** Type the slash command, or paste
   "let's pick up where we left off." The skill walks its priming
   ritual: `bd stats`, `bd ready -n 10`, in-progress inspection,
   MemPalace status + KG stats, recent diary read, stale bead
   surfacing, queue reconciliation, and bead pick. Several sub-steps
   surface context a serial `bd ready` pop would miss:

   - **1a — RESUME? header.** In-progress beads are listed first and
     **outrank fresh-ready work** — a half-finished bead is almost
     always the right next move. The header is skipped when nothing
     is in_progress.
   - **1b — long-gap digest.** On a gap of more than 3 days since the
     last session, a "Since you were last here:" block combines what
     closed, recent diary notes, and recent `main` commits.
   - **1c — CI health.** If any of the last 3 `main` CI runs failed,
     a one-line warning surfaces the workflow, commit, and failing
     job so a red build from a prior session does not sit unnoticed.
   - **1d — ACTIVE DESIGN CYCLE header.** A `/design-a-cycle`
     orchestrator is *above-bead* — it never appears in `bd ready`.
     Any active design cycle (a design-doc drawer with unresolved
     `[CLARIFICATION]` markers or non-green soundness) surfaces here
     so a cold start can resume the design, not just the bead queue.
     Resume it the same way an in-progress bead outranks ready work.
     See [Open a design cycle](./open-a-design-cycle.md).
   - **6a — parallel-wave proposal.** When two or more ready beads
     are independent (no dependency edge and disjoint `Files:`
     lines), the skill proposes dispatching a parallel worker wave
     as the **default** before falling back to a serial single-bead
     pick. Answer `y` to dispatch, `edit` to prune or add beads, or
     `serial` to take one bead at a time.

3. **Confirm the bead pick.** The skill surfaces a candidate bead
   plus a one-line "because" rationale. Approve, override, or ask for
   the next candidate before any claim happens. If a parallel wave
   (step 6a) or an active design cycle (step 1d) was proposed,
   confirm that route instead — central never fans out workers or
   advances a cycle without your go-ahead.

## Outcome

You are oriented: ready queue understood, in-progress beads checked
for staleness, MemPalace state visible, any active design cycle
surfaced, and a candidate bead (or parallel wave) chosen but not yet
claimed. Hand off to [Claim a bead](./claim-a-bead.md), or — for an
above-bead design — to [Open a design cycle](./open-a-design-cycle.md).

## Related

- The full session-startup ritual is referenced in
  [reference: skills](../reference/skills/index.md).
- For why session priming exists in this shape, see
  [explanation: mental model](../explanation/mental-model.md).
