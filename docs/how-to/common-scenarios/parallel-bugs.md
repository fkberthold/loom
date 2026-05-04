# I have several unrelated bugs to fix

To work multiple unblocked, file-disjoint bugs in parallel agents,
follow these steps.

## Precondition

- Two or more bugs are unblocked (`bd ready` lists them).
- The bugs touch disjoint files (verify with `bd show <id>` on each).
- You have time to merge and run a single full-suite check across
  the merged state at the end.

## Steps

1. **Confirm independence.** Run `bd show <id>` for each candidate.
   If any two bugs share files, do not parallelize them — work them
   sequentially via [Claim a bead](../claim-a-bead.md) instead.

2. **Engage the parallel-dispatch skill.** Invoke
   `superpowers:dispatching-parallel-agents`. The skill spawns one
   subagent per bug; each subagent runs the `bugfix-a-bead` recipe in
   its own worktree at `.worktrees/<bead-id>` on branch
   `frank/<bead-id>`.

3. **Wait for all subagents to return.** Each closes its bead and
   pushes its branch.

4. **Merge in dependency order.** From the main worktree, fast-merge
   each branch:
   ```bash
   cd ~/repos/<project>
   git pull --rebase
   git merge --no-ff frank/<bead-1>
   git merge --no-ff frank/<bead-2>
   # ...
   ```

5. **Run the full suite once across the merged state.** Fix any
   cross-branch collateral damage in a single follow-up commit.

6. **Wrap up the batch.** Run `/wrap-up` once. The drawer-author
   subagent handles each bead's drawer separately; the KG extractor
   runs once across the combined diff.

## Outcome

Each bug has its own decision drawer + branch + close record. The
combined merge is on `main` and pushed. The state file is back to
idle.

## Related

- For when *not* to parallelize (shared files, logical dependency),
  see [reference: skills](../../reference/skills/index.md).
- For the rationale behind disjoint-file gating, see
  [explanation: mental model](../../explanation/mental-model.md).
