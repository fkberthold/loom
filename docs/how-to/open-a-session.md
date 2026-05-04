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
   "let's pick up where we left off." The skill walks its 9-step
   priming ritual: `bd stats`, `bd ready -n 10`, in-progress
   inspection, MemPalace status + KG stats, recent diary read, stale
   bead surfacing, queue reconciliation, and bead pick.

3. **Confirm the bead pick.** The skill surfaces a candidate bead
   plus a one-line "because" rationale. Approve, override, or ask for
   the next candidate before any claim happens.

## Outcome

You are oriented: ready queue understood, in-progress beads checked
for staleness, MemPalace state visible, and a candidate bead chosen
but not yet claimed. Hand off to [Claim a bead](./claim-a-bead.md).

## Related

- The full session-startup ritual is referenced in
  [reference: skills](xref:reference/skills/index.md).
- For why session priming exists in this shape, see
  [explanation: mental model](xref:explanation/mental-model.md).
