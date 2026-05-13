# bd-worktree-preseed hook

> PreToolUse hook that pre-seeds bd state when a write-class `bd`
> command is about to run inside a fresh `git worktree`.

## Why this exists

Git worktrees created via `git worktree add` get a copy of the repo
tree, including `.beads/`. But the bd embedded-dolt DB under
`.beads/embeddeddolt/` is local-not-checked-in — so the dolt is
**empty** in the fresh worktree.

When an agent runs `bd update --claim` inside the worktree, bd
writes one-issue state to the empty dolt AND auto-exports it to
`.beads/issues.jsonl`, overwriting the worktree's full checked-in
copy. On merge to main, **all other issues in issues.jsonl are
lost**.

Reproduced 2026-05-11 twice in dispatched workers on `liza_base`
(e6i + da0). Closing fix: loom-x4m + superseded sibling loom-14w.

## What the hook does

When a write-class `bd` subcommand is about to run AND the cwd is
inside a linked worktree (not the main tree) AND the worktree has
no pre-seed sentinel yet, the hook applies three layers (idempotent,
memoized via `.beads/.loom-preseeded`):

1. **`bd import .beads/issues.jsonl`** — populates the worktree's
   local dolt DB from its own checked-in jsonl. Subsequent bd writes
   now reflect the full state and auto-export the full state back
   to issues.jsonl.

2. **`bd config set export.git-add false`** — tells bd not to
   auto-stage `issues.jsonl` during commits. Worktree-local bd
   writes don't sneak into worker commits.

3. **`.beads/issues.jsonl` → `.git/info/exclude`** — belt-and-
   suspenders defense. Even if layers 1-2 fail, git won't stage
   the file from the worktree.

The sentinel ensures the hook fires exactly once per worktree — UNLESS
the dolt has been wiped since the sentinel was created (loom-8vc:
`git stash -u` + rebase can wipe the embedded-dolt blob while leaving
the untracked sentinel in place). When the sentinel exists but the
dolt directory is empty (no files), the hook self-heals by
re-preseeding. The sentinel is refreshed at the end of the re-preseed.

## What the hook does NOT do

- **Does not fire for read-only bd commands** (`bd show`, `bd list`,
  `bd ready`, `bd stats`, etc.) — those don't risk wiping state.
- **Does not fire in the main working tree.** A `.git` directory
  (not file) means we're in main; the hook exits silently.
- **Does not fire for non-Bash tools** (Edit, Write, etc.).
- **Does not block** — exits 0 always. Failures during pre-seed
  are silent (logged via bd's own stderr if anything).

## Write-class bd subcommands matched

```
update, close, create, reopen, dep, delete, defer,
supersede, epic, label, comment, remember, forget,
import, export
```

## Environment variables

- `LOOM_BD_WORKTREE_PRESEED_SKIP=1` — disable the hook entirely
  (for testing or one-off cases where the pre-seed isn't wanted).
- `BD_BIN` — override the bd binary path (default: `bd`).

## Sentinel file

`<worktree>/.beads/.loom-preseeded`. Touch this file to skip the
pre-seed (e.g. if you've manually populated the dolt). Remove it
to force a re-seed on the next write-class bd call.

## Reset / re-run

```bash
# Force re-seed on next bd write in this worktree.
rm <worktree>/.beads/.loom-preseeded

# Disable for a single call.
LOOM_BD_WORKTREE_PRESEED_SKIP=1 bd update <id> --claim
```

## Files

- Hook: `hooks/bd-worktree-preseed.sh`
- Detector helper: `lib/worktree-detect.sh`
- Tests: `lib/tests/bd-worktree-preseed.test.sh` (10 fixture cases)

## Lineage

- Closes: loom-x4m (P1 bug, superseded loom-14w)
- Related: loom-22h (bd pre-commit hook pollution → `/issues.jsonl`
  gitignore defense in loom CLAUDE.md), loom-26w (BEADS_DIR
  override pattern in `lib/loom-bd-env.sh`)
- Sibling worktree bugs that remain open: loom-35b (rebase wipe),
  loom-0hi (cwd drift)
