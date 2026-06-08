---
description: "Run the dispatch-middle pipeline on the named bead. Loads the dispatch-middle skill, which orchestrates the bead's variable RED→GREEN middle as a test-author → implementer (→ optional verify) pipeline of INDEPENDENT subagents in one shared worktree — central invokes once and writes nothing, then integrates (verify + merge + close + capture). The friction-inversion lever: dispatch becomes cheaper than inline."
disable-model-invocation: true
---

Invoke the `dispatch-middle` skill and follow it exactly as presented.

If the user supplied a bead-id as the slash-command argument, treat
that `<bead>` as the bead whose middle to dispatch and start at the
skill's Step 1 (ensure a worktree `frank/<bead>`). If no bead-id was
supplied, run `bd ready` first and confirm with the user which bead to
work before dispatching.

Before dispatching, confirm a locked CONTRACT exists for `<bead>` —
the bead's `RED:` line, an M1 spec, or an acceptance criterion. The
pipeline consumes a contract; it does not produce one. If none exists,
say so and route to the design/brainstorm phase first rather than
guessing.

The skill drives the rest: dispatch the TEST-AUTHOR (Agent
isolation:worktree) with a brief built from ONLY the contract +
interface, dispatch the IMPLEMENTER (same worktree) with a brief built
from ONLY the RED-test-as-file + code area, optionally run a verifier,
then hand a summary back so central does verify + merge + close +
capture. Central writes nothing in the middle.

For across-bead parallelism (multiple independent ready beads), use
the fan-out detector via `/working-a-bead` (loom-yb5); `/dispatch-middle`
owns the within-bead test/code split, not the across-bead wave.
