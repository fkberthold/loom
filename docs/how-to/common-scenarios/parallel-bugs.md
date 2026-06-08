# I have several unrelated bugs to fix

To work multiple unblocked, file-disjoint bugs in parallel agents,
follow these steps.

## Precondition

- Two or more bugs are unblocked (`bd ready` lists them).
- Each candidate bug declares a `Files:` line in its description (the
  fan-out detector excludes beads with no `Files:` line — footprint
  unknown means not provably disjoint).
- You have time to merge and run a single full-suite check across
  the merged state at the end.

## Steps

1. **Let the fan-out detector confirm independence.** Run
   `scripts/loom-fanout-detect` (or take the wave from session-startup
   step 6a / `/working-a-bead`). It reads each ready bead's
   dependencies and `Files:` line and emits one wave per line: a group
   of beads with **no dependency edge between them AND disjoint
   `Files:` paths**. Beads with no `Files:` line are excluded — declare
   the line on those beads, do not eyeball independence by hand. If no
   wave of two or more emerges, work the bugs sequentially via
   [Claim a bead](../claim-a-bead.md) instead.

2. **Engage the parallel-dispatch skill.** Invoke
   `superpowers:dispatching-parallel-agents` on the wave. The skill
   spawns one subagent per bug; each subagent runs the `bugfix-a-bead`
   recipe in its own worktree at `.worktrees/<bead-id>` on branch
   `frank/<bead-id>`. Within each bug, the RED→GREEN middle is itself a
   `/dispatch-middle` pipeline (test-author then separate implementer)
   — the fan-out wave is across-bead parallelism; `/dispatch-middle`
   is the within-bead split, and the two compose.

3. **Wait for all subagents to return.** Each closes its bead and
   pushes its branch.

4. **Merge in dependency order.** From the main worktree, fast-merge
   each branch. First confirm your cwd is the main repo root, not a
   returned worker's worktree — the cwd-drift-guard hook refuses
   `git merge` / `git push` / `bd close` when cwd resolves inside a
   `.claude/worktrees/agent-*/` path and prints the `cd <main-root>`
   recovery command:
   ```bash
   cd ~/repos/<project>          # main root, NOT a worker worktree
   git pull --rebase=merges
   git merge --no-ff frank/<bead-1>
   git merge --no-ff frank/<bead-2>
   # ...
   ```
   If a worker branched off a stale base, rebase it onto current main
   with `scripts/loom-rebase-worktree main` (preserves untracked WIP)
   before merging.

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
