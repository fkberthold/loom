# Bypass workflow ceremony

To skip a hook, recipe step, or mode-gated discipline when the
default ceremony does not fit the work, pick the narrowest bypass
that lets you proceed.

## Precondition

- You have a concrete reason to bypass (trivial fix, batch close of
  already-captured work, exploratory spike, project that does not
  warrant the recipe).
- You understand which guard you are skipping and accept the loss
  of its enforcement.

## Bypass `bd close` blocking

The close-capture hook blocks `bd close` in `full` mode unless
capture has happened. To proceed without capturing:

```bash
bd close <id> --force
# or
BD_CLOSE_FORCE=1 bd close <id>
```

The `--force` flag is more discoverable. The env var is faster for
batch closes of already-captured work.

## Lower the project's workflow mode

Change the project's mode to disable hooks at the source instead of
bypassing per-call.

```bash
# Disable everything for this project
echo '{"v":1, "mode":"off"}' > .claude/workflow.json

# Informational only — recipe still runs, hooks never block
echo '{"v":1, "mode":"light"}' > .claude/workflow.json

# Session-scoped, no file change
CLAUDE_WORKFLOW_OFF=1 claude
```

The env var beats the file (resolution priority: env var → file →
default `full`).

## Skip the recipe for a trivial fix

For a ≤1-line, well-understood change:

1. Skip phase A2 (worktree creation). Work directly on the active
   branch.
2. Skip phase C3
   (`superpowers:finishing-a-development-branch`). Commit on main
   directly.
3. Keep TDD discipline (the M-steps that include RED/GREEN). Trivial
   fixes still get tests.

## Skip the recipe for a spike

For pure exploratory work with no concrete bead yet:

1. Use `superpowers:brainstorming` (or `beadpowers:brainstorming`
   if the output will be beads).
2. Iterate through dialogue until a concrete bead emerges.
3. File the bead via `beadpowers:create-beads`, then engage the
   matching recipe via [Claim a bead](./claim-a-bead.md).

## Outcome

The blocking primitive (hook, recipe step, ceremony) is bypassed
for the narrowest scope that solves the problem. The ceremony you
did keep still ran.

## Related

- For the full mode-resolution logic, see
  [reference: hooks](../reference/hooks/index.md).
- For why each hook blocks by default, see
  [explanation: workflow modes](../explanation/workflow-modes.md).
- For the `--force` flag and other escape hatches in the bd CLI,
  see [reference: bd CLI](../reference/bd-cli.md).
