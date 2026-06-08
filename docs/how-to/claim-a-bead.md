# Claim a bead

To take ownership of a bead and engage the matching activity recipe,
follow these steps.

## Precondition

- A bead has been picked (see [Open a session](./open-a-session.md)).
- The bead is unblocked (`bd ready` includes it, or its dependencies
  are closed).
- `git status` is clean on the branch you intend to leave.

## Steps

1. **Read the bead.** Run `bd show <bead-id>` to confirm scope, type,
   and acceptance criteria.

2. **Run the router.** Type `/working-a-bead <bead-id>`. The router
   inspects `bead.type` plus description keywords and dispatches to
   one of six activity recipes (`bugfix`, `feature`, `refactor`,
   `research`, `cleanup`, `docs`).

   - To override the auto-pick, pass `--recipe=<name>`.
   - To enter a recipe directly when you already know the shape, use
     `/bugfix-a-bead <bead-id>` or `/research-a-bead <bead-id>`.
     Other shapes are reachable only through the router or by
     description-match auto-discovery.

3. **Let the claim hook fire.** The recipe's phase A2 runs
   `bd update <bead-id> --claim`. The PreToolUse hook
   `bd-claim-research.sh` (in `full` mode) writes
   `bead`/`activity`/`stage=claim` to the per-project state file and
   reminds the agent to dispatch the bug-family-researcher subagent
   (or the shape-appropriate equivalent).

4. **Isolate the work for non-trivial changes.** The recipe creates a
   worktree at `.worktrees/<bead>` on branch `frank/<bead>`. Skip
   this only for the mechanical inline exception (below).

5. **Decide dispatch vs inline.** Any middle with a RED→GREEN cycle
   **defaults to `/dispatch-middle <bead>`** — central writes nothing
   and the test→code split runs as independent worker agents. Go
   inline (central edits directly) only for the mechanical exception:
   a change that is **≤ ~15 lines AND touches a single non-test file
   AND adds no new test** (pure docs/config/prose edits qualify).
   Record the choice in the state file — `dispatch=worker` for the
   default, or `dispatch=inline:<reason>` for a justified exception.
   The dispatch-nudge hook prompts if a RED→GREEN bead is about to be
   worked inline without a recorded reason. See
   [Run the dispatch-middle pipeline](./run-dispatch-middle.md).

6. **Run the variable middle.** Unless the inline exception applies,
   the recipe hands the middle to `/dispatch-middle <bead>`: it
   dispatches a test-author to write the RED test, then a *separate*
   implementer to make it GREEN, both in one shared worktree, and
   hands a summary back to central for verify + merge + close. Central
   writes no test and no line of code. For an inline exception,
   central makes the edit directly on the active branch.

## Outcome

The bead is `IN_PROGRESS` and assigned to you. The state file
records the active bead, activity, stage, and the `dispatch` choice.
The recipe's variable middle is in flight — as a `/dispatch-middle`
worker pipeline on a dedicated branch, or directly on the working
branch for an inline exception.

## Related

- For the within-bead test→code pipeline, see
  [Run the dispatch-middle pipeline](./run-dispatch-middle.md).
- For the recipe shapes themselves, see
  [reference: skills](../reference/skills/index.md).
- For the rationale behind the recipe split, see
  [explanation: workflow modes](../explanation/workflow-modes.md).
- When you reach the close step, follow
  [Finish a bead](./finish-a-bead.md).
