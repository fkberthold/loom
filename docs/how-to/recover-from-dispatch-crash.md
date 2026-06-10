# Recover from a dispatch crash (API 529 burst)

When the Anthropic API is overloaded it returns **529**, and every
agent call the Claude Code harness makes routes through that same
backend — so a 529 burst can kill several parallel-dispatched agents at
once and leave their work stranded in unmerged worktrees. To bring a
parked bead back to life without losing work, follow the
resume-from-WIP flow below.

This page is the operator-facing companion to the
`## API 529 / overload resilience` playbook in the dispatched-agent
conventions (`.claude/rules/dispatched-agents.md`).

## Recognize the failure

You are in a 529 burst — not a run of independent agent bugs — when:

- **Two or more agents in one wave crash in a short window** with a 529.
- A **resume agent dies in ~4 seconds with 0 tool uses** — no
  smoke-battery output, no Edit, nothing. That near-instant, empty
  death is the tell of a resume *into a still-sick API*, distinct from
  a normal agent failure (which gets somewhere first).

When you see this, stop dispatching. Each fresh agent thrown at the
burst just dies in ~4s burning context, and rapid-fire retries can
deepen the overload. Announce an **API health pause** and note which
beads are parked mid-flight.

## Precondition

- A mid-flight agent crashed on a 529, leaving its work in the worktree
  `frank/<bead-id>` (committed, staged, and/or bare-on-disk).
- The bead's **decision drawer was filed before the dispatch** (the
  drawer-first mandate). If it was, the drawer is your intact source of
  *intent* even though the worktree is half-finished. If it was not,
  reconstruct intent from the bead description + the test-author's RED
  test before proceeding.

## Steps

1. **Wait out the burst with a health probe + exponential backoff.**
   Do not resume straight into a sick API — a blind re-dispatch just
   reproduces the ~4s/0-tool-use death. Send one cheap probe (a
   one-line throwaway agent or any minimal model request) as a canary.
   If it 529s, back off and try again, doubling the wait each time
   (~30s → 1m → 2m → 4m), capped at a few minutes. Resume too early and
   the agent dies again; resume too late and the parked worktree's WIP
   drifts staler against `main`. Exponential backoff threads between
   the two.

2. **Resume only after a clean probe.** Once a probe completes
   normally, dispatch the real resume-from-WIP agent. If *it* 529s, the
   burst is still live — fall back to the next backoff interval and
   re-probe.

3. **Read the drawer first.** The resume agent (or you) reads the
   decision drawer to reconstruct what the dead agent was *trying* to
   build: the locked contract, the `RED:` spec, the chosen approach,
   and the file plan. The drawer is the only artifact guaranteed to
   survive the crash — the worktree may be unmerged and bd state may be
   mid-flight, but the drawer lives in MemPalace, outside both.

4. **Inventory the worktree WIP.** In the crashed worktree, run
   `git status`, `git diff`, and `git log --oneline main..HEAD` to see
   what was committed, plus `git status --porcelain` to see what is
   only on disk. The crash froze the worktree at an arbitrary point;
   committed, staged, and bare-on-disk work can all coexist.

5. **Rebase with WIP preservation if the base is stale.** The parked
   worktree's base may now trail `main`. Do **not** plain
   `git rebase main` — on a branch with bare untracked files that can
   lose them. Use `scripts/loom-rebase-worktree main`, which snapshots
   untracked files, pre-detects collisions, rebases, and restores the
   files afterward. See
   [reference: loom-rebase-worktree](../reference/loom-rebase-worktree.md).

6. **Verify before extending.** Re-run the bead's RED test (or the
   suite) against the recovered state to learn exactly how far the dead
   agent got — what is already GREEN, what is still RED. Trust the
   test, not the dead agent's last (possibly truncated) report.

7. **Finish only the remainder.** Implement the still-RED slice, commit
   on the same `frank/<bead-id>` branch, and hand back to central for
   integration as usual (see [Finish a bead](./finish-a-bead.md)). A
   resume agent runs the worker-side pre-flight smoke battery at the
   top of its session like any dispatched worker.

8. **Update the drawer at close.** Because the drawer was filed first,
   the phase-D capture *updates* it with verification-at-close +
   landing SHAs rather than authoring it from scratch.

## Outcome

The parked bead is brought back from the crashed worktree's WIP rather
than redone from zero: the resume agent reconstructed intent from the
drawer, reconciled it against whatever the dead agent left on disk,
verified against the test, and finished the remainder — all without
resuming into a still-sick API.

## Related

- [Run the dispatch-middle pipeline](./run-dispatch-middle.md) — the
  pipeline whose worktree this flow recovers.
- [Finish a bead](./finish-a-bead.md) — central's integration step
  after the resume agent hands back.
- [reference: loom-rebase-worktree](../reference/loom-rebase-worktree.md)
  — the WIP-preserving rebase wrapper used in step 5.
