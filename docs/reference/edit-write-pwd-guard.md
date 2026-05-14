# edit-write-pwd-guard hook

> PreToolUse hook that blocks Edit/Write/MultiEdit calls from a
> worktree-isolated worker when the target path resolves OUTSIDE
> the worktree.

## Why this exists

Closes loom-ymc. Recurring symptom: an agent dispatched via
`Agent({isolation: "worktree"})` Edits/Writes a path that resolves
to the parent repo (MAIN) instead of the worktree. The agent's
commits then land in MAIN's working tree or on a worktree branch
that's empty of the actual changes. Recovery is messy (stash,
patch, apply-in-worktree, verify-main-clean).

Five re-surfaces in the 2026-05-13 PM session alone. Rule-
discipline alone (relative paths, pwd verification) isn't enough —
the tool layer's path resolution can surprise even disciplined
workers.

## Failure modes covered

- **Mode 1 — absolute-path-in-brief leak.** Dispatcher's brief
  contains `/home/frank/repos/<project>/path/...` paths; agent
  dutifully uses them; edits land in MAIN.
- **Mode 2 — cwd-drift intentional main-side work.** Agent decides
  to operate on MAIN explicitly while still in worktree cwd; the
  guard catches the absolute-path target.
- **Mode 4 — relative-path resolution surprise.** Worker uses
  `tests/foo.py` (relative); the path resolves wrong due to symlink
  or `../` content; guard canonicalizes via realpath and catches.

**Out of scope**: Mode 3 (bd-state regression on auto-merge) —
covered by loom-x4m + loom-8vc (bd-worktree-preseed hook).

## What the hook checks

For each Edit/Write/MultiEdit tool call:

1. Source `lib/worktree-detect.sh` (loom-x4m). If cwd is NOT in a
   linked worktree → exit 0 (no guard in the main tree).
2. Resolve `tool_input.file_path`:
   - absolute → use as-is
   - relative → resolve against `$PWD`
3. Canonicalize via `python3 os.path.realpath` of the existing
   parent chain (Write may create new files, so the leaf needn't
   exist yet).
4. Compare resolved target against worktree root.
5. If target is under worktree root → exit 0 (allow).
6. Otherwise → exit 2 with explanatory message naming both paths.

## Bypass

```bash
LOOM_EDIT_WRITE_GUARD_SKIP=1
```

Set in the worker's env when an intentional cross-tree write is
needed (e.g. merge prep that legitimately touches both trees).
Should be rare — prefer `cd <other-tree>` then re-issue the Edit,
which makes the hook a no-op naturally.

## Tools matched

- `Edit`
- `Write`
- `MultiEdit`

Not matched (intentionally):

- `Read` — read-only, not dangerous (just informative leak).
- `NotebookEdit` — different `tool_input` shape; not commonly used.
  Add later if observed.
- `Bash`, `Glob`, `Grep`, etc. — different layer.

## Failure message example

```
[edit-write-pwd-guard] BLOCKED: Edit refused.

  file_path = /home/frank/repos/liza_base/tests/foo.py
  resolves to = /home/frank/repos/liza_base/tests/foo.py
  worktree root = /home/frank/repos/liza_base/.claude/worktrees/agent-abc123

The target is OUTSIDE the current worktree. This is the recurring
loom-path-leak (loom-ymc): a worker in an isolated worktree about
to write into the parent repo / MAIN.

To fix: recast the path relative to the worktree root, OR use an
absolute path under /home/frank/repos/liza_base/.claude/worktrees/agent-abc123.

To bypass intentionally (e.g. cross-tree merge prep), set
LOOM_EDIT_WRITE_GUARD_SKIP=1 in the worker env and retry.
```

## Files

- Hook: `hooks/edit-write-pwd-guard.sh`
- Detector (shared with bd-worktree-preseed): `lib/worktree-detect.sh`
- Tests: `lib/tests/edit-write-pwd-guard.test.sh` (14 fixture cases)

## Lineage

- Closes loom-ymc (P1 bug, 2026-05-13)
- Origin: `drawer_loom_decisions_df73c725b47dd67832935e3a` (loom-tag,
  2026-05-04) — first surfacing
- Cluster: loom-x4m + loom-8vc + loom-azt (worktree-isolation
  bd-state cluster, all closed 2026-05-13)
