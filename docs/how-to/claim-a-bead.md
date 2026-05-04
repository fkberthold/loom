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
   this only for ≤1-line tweaks.

5. **Run the variable middle.** The recipe walks its M-steps (the
   bug-shaped, feature-shaped, refactor-shaped, etc. middle).

## Outcome

The bead is `IN_PROGRESS` and assigned to you. The state file
records the active bead, activity, and stage. The recipe's variable
middle is in flight on a dedicated branch (or directly on the
working branch for trivial fixes).

## Related

- For the recipe shapes themselves, see
  [reference: skills](xref:reference/skills/index.md).
- For the rationale behind the recipe split, see
  [explanation: workflow modes](xref:explanation/workflow-modes.md).
- When you reach the close step, follow
  [Finish a bead](./finish-a-bead.md).
