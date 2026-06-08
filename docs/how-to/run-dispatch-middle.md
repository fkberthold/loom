# Run the dispatch-middle pipeline

To work a bead's RED→GREEN middle as a test-author → implementer
pipeline of independent subagents — so central invokes once and writes
nothing — follow these steps.

## Precondition

- A bead has been claimed and its variable middle is a RED→GREEN
  cycle (most feature/bugfix beads).
- **A locked CONTRACT exists.** The pipeline consumes a contract; it
  does not produce one. The contract is one of, in order of
  preference:
  - the bead's `RED:` line (a Given-When-Then scenario or
    `INVARIANT:`, emitted by a design cycle — see
    [Open a design cycle](./open-a-design-cycle.md));
  - an M1 spec;
  - an acceptance criterion.

  If none exists, do not guess — lock the contract first via the
  design/brainstorm phase, then return here.
- The change is non-trivial. The inline exception (below) still
  applies for genuinely small changes.

## Steps

1. **Invoke the command once.** Run `/dispatch-middle <bead>`. Central
   invokes the pipeline a single time and then **writes nothing in the
   middle** — no test, no line of implementation. Every test/code edit
   happens inside a subagent. (If you omit the bead-id, the command
   runs `bd ready` first and confirms which bead to work.)

2. **Confirm the contract.** Before dispatching, the command verifies
   a locked contract exists for the bead. If it cannot find a `RED:`
   line, M1 spec, or acceptance criterion, it stops and routes you to
   the design phase rather than fabricating one.

3. **Ensure one shared worktree.** The pipeline works in a single
   worktree `frank/<bead>`. Both the test-author and the implementer
   run in THIS worktree, so the implementer reads the test-author's
   committed RED test directly off disk.

4. **Let the TEST-AUTHOR run.** Central dispatches an `Agent`
   (isolation `worktree`) briefed with ONLY its slice: the locked
   contract verbatim plus the interface under test (names + shapes,
   not the implementation body). The test-author writes the RED test
   that pins the contract, confirms it fails, commits only the test
   file, and returns the test path plus the verbatim failure output.
   It does NOT implement.

5. **Let the IMPLEMENTER run.** Central dispatches a **separate**
   `Agent` into the same worktree, briefed with ONLY the RED-test file
   path plus the code area. The implementer reads the test as an
   **artifact** — it never sees the test-author's reasoning, mind, or
   conversation. This is the anti-tautology guarantee by construction:
   the implementation can only be shaped to satisfy the public
   artifact, not a private intent, so the test-author == code-author
   anti-pattern cannot recur. The implementer makes the minimal change
   to turn the test GREEN, never modifies or weakens the test, and
   returns the pass/fail counts plus the commit SHA. If the test looks
   wrong, the implementer STOPS and reports to central rather than
   "fixing" the test itself.

6. **Optionally verify.** For a change that warrants review, central
   dispatches the `requesting-code-review` / `code-reviewer` agent
   against the worktree diff. Skip for small middles.

7. **Hand back to central for integration.** The pipeline returns a
   summary (RED output, GREEN counts, commit SHAs, any stop-and-report
   flags). Central — and ONLY central, because integration is
   cwd-sensitive and bd-authoritative — then does **verify + merge
   `--no-ff` + close + capture** (see [Finish a bead](./finish-a-bead.md)).
   Central integrates what the pipeline produced; it does not re-do the
   middle.

8. **Record `dispatch=worker`.** The middle was dispatched, so the
   `workflow-state` `dispatch` field records `worker` (the default
   posture).

## The inline exception

Dispatch is the default for any RED→GREEN middle. Doing the middle
inline (central edits directly) is the explicit exception, waved
through only when the change is **≤ ~15 lines AND touches a single
non-test file AND adds no new test**. Even when a change qualifies,
dispatch is still preferred — the friction-inversion lever makes one
`/dispatch-middle` invocation cheaper than write-brief + wait + verify
+ merge, so the right thing is the easy thing.

## Bypass

To suppress the dispatch nudge for a turn, set
`LOOM_DISPATCH_NUDGE_SKIP=1`.

## Composition — within-bead vs across-bead

`/dispatch-middle` owns the **within-bead** test/code split — one
bead's division of labor between the test-author and the implementer.
**Across-bead** parallelism (multiple independent ready beads worked
as a wave) is a different axis: use the fan-out detector via
[`/working-a-bead`](./claim-a-bead.md), backed by
`scripts/loom-fanout-detect`, which proposes a wave of file-disjoint
beads. The two compose orthogonally — each bead in a fan-out wave runs
its own middle through `/dispatch-middle`.

## Outcome

The bead's RED→GREEN middle is complete with an independently authored
test and a separately written implementation, both committed in the
shared worktree. Central never wrote test or code; it briefed each
agent with its minimal slice and integrated the result. The
`workflow-state` `dispatch` field reads `worker`.

## Related

- For the command and skill specification, see
  [reference: dispatch-middle](../reference/dispatch-middle.md).
- For the recipe shapes whose middle this pipeline runs, see
  [reference: skills](../reference/skills/index.md).
- For the contract that seeds the test-author, see
  [Open a design cycle](./open-a-design-cycle.md).
- For central's integration step, see
  [Finish a bead](./finish-a-bead.md).
