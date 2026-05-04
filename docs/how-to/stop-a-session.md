# Stop a session

To end a Claude Code session cleanly so nothing useful is stranded
in volatile context, follow these steps.

## Precondition

- All in-flight beads are at a coherent stopping point (committed,
  pushed, or explicitly deferred).
- You intend to close the conversation, not start new work.

## Steps

1. **Wrap up any closeable bead.** If a bead is ready to close, run
   `/wrap-up` first — see
   [Finish a bead](./finish-a-bead.md). Don't end a session with a
   bead at "ready to close but not captured" state.

2. **Watch for the AUTO-SAVE message.** The `mempal-stop-hook` fires
   automatically at conversation end. The AUTO-SAVE checkpoint is
   the trigger to capture anything not already wrapped up.

3. **Write a diary entry.** Run `mempalace_diary_write` with an
   AAAK summary of what shipped, what stalled, and what to surface
   next session.

4. **File a decision drawer if needed.** If the session produced a
   decision that wasn't captured by a `/wrap-up` (e.g., a deferred
   design choice, a partial spike), call
   `mempalace_check_duplicate` then `mempalace_add_drawer`.

5. **Add KG triples if needed.** For any new
   sibling-of/superseded-by/caused-by relationships, run
   `mempalace_kg_add`.

6. **Push outstanding state.** Run `bd dolt push` and `git push` if
   you committed anything since the last push. Confirm
   `git status` is "up to date with origin."

7. **End the conversation.** Close the session.

## Outcome

The diary, drawers, and KG reflect what happened. Remote and local
beads/git state agree. The next session's `bd prime` and
`/session-startup` will surface the right context.

## Related

- For a fresh start tomorrow, follow
  [Open a session](./open-a-session.md).
- For why diary capture is the load-bearing step at session end,
  see [explanation: mental model](xref:explanation/mental-model.md).
