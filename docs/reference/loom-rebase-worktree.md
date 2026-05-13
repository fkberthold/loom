# loom-rebase-worktree

> `git rebase` wrapper that preserves untracked WIP files when
> rebasing a linked worktree.

## Why this exists

Closes loom-azt (split from loom-35b symptom 2). An agent that
crashes mid-flight in a worktree (e.g. API 529) leaves untracked
WIP on disk. A resume agent that recovers by running
`git stash + rebase + pop` wipes the untracked WIP — `git stash`
includes untracked only with `-u`, and various stash/clean
choreographies lose files silently.

Observed in liza_base 2026-05-06 on 9uo's resume agent: 328-LOC
`background.py` + 365-LOC `test_background.py` from a previous
crash did not survive the stash/rebase recovery. (The 9uo case
was rescued by a thorough decision drawer enabling reconstruction
— that's tribal knowledge dependent. This wrapper is the
mechanical fix.)

## Usage

```bash
loom-rebase-worktree <upstream-ref> [git-rebase-args...]
```

Same arg shape as `git rebase`. The first arg is required (used
to pre-detect file collisions).

Example:

```bash
cd ~/repos/loom/.claude/worktrees/agent-abc123
loom-rebase-worktree main
```

## What the wrapper does

1. **Refuses to run in the main working tree.** Detects via
   `git rev-parse --git-common-dir` vs `--show-toplevel`. Use plain
   `git rebase` there — no WIP loss risk in the main tree.
2. **Snapshots untracked files** to `$(mktemp -d)`, excluding
   `.beads/embeddeddolt/*` (the bd-worktree-preseed hook's
   self-heal already covers that path).
3. **Pre-detects collisions**: for each WIP path, checks if
   that path exists at `<upstream-ref>` via
   `git cat-file -e <ref>:<path>`. Colliding files are saved as
   `<path>.wip` and removed from the worktree BEFORE rebase — so
   git's "untracked file would be overwritten" abort doesn't fire.
4. **Runs `git rebase <args>`** with all wrapper args forwarded.
5. **Restores snapshotted files**. Post-rebase logic:
   - File exists in worktree + content matches snapshot → no-op
     (git preserved it)
   - File exists + content differs → save WIP as `<path>.wip`
     (post-collision case — rare since pre-detection catches most)
   - File doesn't exist → restore from snapshot
6. **Snapshot retention**: cleaned up on clean exit; retained on
   rebase failure OR any collisions. Path printed to stderr.

## Exit codes

- Wrapper passes through `git rebase`'s exit code.
- `2` = wrapper-level refusal (e.g. not in a linked worktree).

## What survives, what becomes `.wip`

| Scenario | Outcome |
|---|---|
| WIP file at path `X`, upstream has no `X` | Restored as-is |
| WIP file at `X`, upstream has different `X` | Incoming `X` wins; WIP saved as `X.wip` (pre-collision) |
| WIP file at `X`, vanilla rebase preserves it | No-op (snapshot matches existing) |
| WIP under `.beads/embeddeddolt/` | Skipped — bd-worktree-preseed handles |

## Files

- Script: `scripts/loom-rebase-worktree` (157 lines, +x)
- Tests: `lib/tests/loom-rebase-worktree.test.sh` (9 fixture cases)

## When to use this vs plain `git rebase`

Use this wrapper:
- In any `.claude/worktrees/agent-*` worktree, especially after a
  mid-flight crash (resume agent flow)
- Whenever the worktree has untracked WIP files you can't afford
  to lose

Use plain `git rebase`:
- In the main working tree (the wrapper refuses anyway)
- In a worktree with no untracked WIP (the wrapper short-circuits
  to a passthrough, so this is just a slight efficiency win)

## Worker-brief convention

For dispatched agents using `Agent({isolation: "worktree"})`, the
brief should recommend the wrapper when rebase is needed:

```
If rebasing onto a newer base ref, use
  scripts/loom-rebase-worktree <upstream>
instead of plain `git rebase`. This preserves any untracked WIP
files (test reconstructions, draft files) across the rebase.
```

## Lineage

- Closes loom-azt (P2 feature)
- Split from: loom-35b (3-way split, 2026-05-13)
- Sibling done: loom-8vc (bd-worktree-preseed dolt-empty self-heal)
- Sibling open: loom-ecf (stale-base convention)
- Related: loom-x4m (bd-worktree-preseed hook, the partner fix)
