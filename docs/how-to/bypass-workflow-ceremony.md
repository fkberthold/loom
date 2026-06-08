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

## Skip dispatch for a mechanical inline fix

The variable middle defaults to `/dispatch-middle <bead>` (central
writes nothing; a test-author then a separate implementer run the
RED→GREEN split). Going inline — central edits directly, no dispatch
— is the explicit exception, waved through without justification only
when **ALL** of these hold:

- the change is **≤ ~15 lines**, AND
- it touches a **single non-test file**, AND
- it adds **no new test**.

Pure docs/config/prose edits qualify. Anything with a RED→GREEN cycle
defaults to dispatch regardless of size. For a qualifying inline fix:

1. Skip phase A2 (worktree creation). Work directly on the active
   branch.
2. Skip phase C3
   (`superpowers:finishing-a-development-branch`). Commit on main
   directly.
3. Record the exception in the state file:
   ```bash
   ~/.claude/scripts/workflow-state set dispatch=inline:<reason>
   ```
   Without this, the dispatch-nudge hook prompts when a RED→GREEN
   bead is about to be worked inline.

Going inline on a bead that fails any clause above is a deliberate
override, not a freebie — record the reason and own it.

## Bypass a guard hook

Each guard hook honors a literal-`1` environment-variable skip for
the one intentional case it would otherwise block:

| Guard | Bypass |
|---|---|
| dispatch-nudge (inline without a recorded reason) | `LOOM_DISPATCH_NUDGE_SKIP=1` |
| edit-after-failure-guard (editing after a failing run) | `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1` |
| edit-write-pwd-guard (write resolving outside the worktree) | `LOOM_EDIT_WRITE_GUARD_SKIP=1` |
| bd-worktree-preseed (first write-class `bd` call in a worktree) | `LOOM_BD_WORKTREE_PRESEED_SKIP=1` |
| cwd-drift-guard (merge/push/bd-close from a worktree cwd) | `LOOM_CWD_DRIFT_GUARD_SKIP=1` |

The skip must be the literal string `1` — `=yes`/`=true`/`=0`/empty
are all rejected.

For the edit-after-failure-guard, there is also an in-session marker
escape: `touch .claude/no-edit-after-failure-guard` suppresses it for
the rest of the session without setting an env var on every call.

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
