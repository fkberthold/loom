# Finish a bead

To close a bead, capture its decision in MemPalace, and push the
work to the remote, follow these steps.

## Precondition

- The bead is `IN_PROGRESS` and assigned to you.
- The variable middle of the activity recipe is complete (tests
  pass, code is committed, branch is in a finishable state).
- `git status` shows no uncommitted changes you intend to ship.

## Steps

1. **Run `/wrap-up`.** This is the close-time ritual; the bead-id is
   implicit from the current claim. The command sequences the steps
   below.

2. **Pass preflight.** `bd preflight` runs lint, stale, and orphan
   checks. Fix any reported issues before continuing.

3. **Run the full test suite from a clean shell.** Confirm exact
   pass/skip/fail counts. The wrap-up command surfaces the numbers
   for review.

4. **Confirm the working tree is clean.** `git status` must show no
   modified files.

5. **Dispatch the capture subagents.** `/wrap-up` fires
   `drawer-author` and `kg-relationship-extractor` in parallel. Each
   returns a reviewable artifact.

6. **Review and file the drawer.** Run `mempalace_check_duplicate`
   against the proposed drawer body, then `mempalace_add_drawer` to
   commit it.

7. **Add the KG triples.** Call `mempalace_kg_add` for each approved
   triple from the extractor's output.

8. **Write the diary entry.** Call `mempalace_diary_write` with an
   AAAK-compressed summary of the session.

9. **Close the bead.** Run `bd close <bead-id> --reason="..."`. The
   `bd-close-capture` hook lets the close through because capture
   is done. (To bypass when capture is intentionally skipped, see
   [Bypass workflow ceremony](./bypass-workflow-ceremony.md).)

10. **Push everything.** Run `bd dolt push` to publish the beads
    state, then `git push` to publish the branch. Verify
    `git status` reports "up to date with origin."

11. **Suggest follow-ups.** If the work surfaced new beads, file
    them now — but do not auto-create. The `/wrap-up` flow proposes;
    you approve.

## Outcome

The bead is closed. The decision lives in MemPalace as a drawer
plus KG triples plus a diary entry. The branch is pushed. The
state file records `stage=close`, `activity=idle`, `bead=null`.

## Related

- For the close-capture hook's full behavior in each mode, see
  [reference: hooks](../reference/hooks/index.md).
- When you cannot or should not capture, see
  [Bypass workflow ceremony](./bypass-workflow-ceremony.md).
- To stop the session afterward, follow
  [Stop a session](./stop-a-session.md).
