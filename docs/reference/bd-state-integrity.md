# bd-state integrity on merge & rewrite

> The machinery that keeps `.beads/issues.jsonl` aligned with the
> authoritative bd dolt store across git operations that would
> otherwise silently corrupt bead state: a custom merge driver for
> `git merge`, a `post-rewrite` hook for `git rebase` / `commit
> --amend`, and the `install.sh` wiring that activates them.

## Why this exists

bd stores bead state in two places: an embedded **dolt** store under
`.beads/embeddeddolt/` (local, not checked in — the authoritative source
of truth) and a checked-in **`.beads/issues.jsonl`** export (a view that
git tracks). Git's generic line-based merge/rebase machinery treats
`issues.jsonl` as ordinary text. It is not: a line-based three-way merge
can SILENTLY reconcile bead-state lines across semantic boundaries —
auto-merges look successful but revert closed beads to `in_progress`
because the JSONL rows happen to line up. The `--ours` conflict pattern
only fires on *textual* conflicts; these clean auto-merges slip past it.

The structural fix is to stop trusting git's text merge for this file and
instead regenerate it from dolt — the store that always knows the real
state — on every operation that touches it.

## The three layers

| Component | Git event it covers | Bead |
|---|---|---|
| `.gitattributes` + `scripts/bd-merge-driver.sh` | `git merge` | loom-4um |
| `hooks/post-rewrite.sh` | `git rebase`, `git commit --amend` | loom-yjo |
| `install.sh` wiring | activates both in the repo's `.git/config` + `.git/hooks/` | loom-4um / loom-yjo |

All three are orthogonal and share no runtime state — dolt is the source
of truth across all of them. They compose with the worktree-side
protection `hooks/bd-worktree-preseed.sh` (loom-x4m), which seeds a fresh
worktree's empty dolt before its first write-class bd call.

## Merge driver — `scripts/bd-merge-driver.sh` (loom-4um)

`.gitattributes` ships the line:

```
.beads/issues.jsonl merge=bd-export
```

This names a merge driver `bd-export` for that one file. Nothing resolves
the name until `install.sh` registers it (below). Git invokes a merge
driver as `<driver> %O %A %B %P`:

| Arg | Meaning |
|---|---|
| `%O` | ancestor's version |
| `%A` | current branch's version — the driver must overwrite this with the result |
| `%B` | other branch's version |
| `%P` | pathname being merged |

The driver intentionally **ignores `%O` and `%B`** — both sides derive
from dolt anyway. It runs `bd export` from the repo toplevel, validates
the output as JSONL (one JSON object per non-empty line, via `python3`),
and overwrites `%A` with the canonical export using `cat` redirect (to
preserve `%A`'s inode, which git reuses after the driver returns).

**Failure semantics are fail-closed.** If `bd export` fails or produces
malformed JSONL, the driver exits non-zero, leaving `%A` unchanged. Git
treats that as a merge conflict and stops with the file untouched,
surfacing the failure — the safer choice, since silently overwriting `%A`
with garbage would re-introduce the bug class being closed.

## post-rewrite hook — `hooks/post-rewrite.sh` (loom-yjo)

`git merge` is not the only path that can land a stale `issues.jsonl` in
HEAD. `git rebase` (especially `git pull --rebase=merges`) and `git
commit --amend` replay history and can leak a stale jsonl past the merge
driver. The canonical hand workaround was `bd export > .beads/issues.jsonl
&& git add && git commit -m 'bd: post-rebase re-export'`; this hook
automates exactly that, scoped to git's `post-rewrite` event.

Git invokes it as `post-rewrite <command>` (`rebase` or `amend`) and
pipes `<old-sha> <new-sha>` pairs on stdin. The hook drains and ignores
stdin — re-exporting from dolt makes the specific rewritten SHAs
irrelevant. It then re-exports, and if the result differs from the
working tree's `issues.jsonl`, writes it and auto-commits the delta.

The auto-commit uses `git -c core.hooksPath=/dev/null commit` to bypass
bd's own pre-commit hook (which would re-export and re-stage, recursing
through this same chain). From bd's perspective the commit is a no-op:
jsonl already matches dolt.

The hook **no-ops (exit 0) safely** in any of these conditions:

- `LOOM_BD_POST_REWRITE_SKIP=1` — explicit opt-out (full no-op).
- Not inside a git work tree.
- `.beads/` absent — not a bd workspace.
- `bd` binary unavailable — don't break non-loom repos.
- HEAD detached — can't safely create a follow-up commit.
- Other staged changes present — would entangle them in the auto-commit.
- jsonl already matches dolt — nothing to do.

### Bypass flags

| Flag | Effect |
|---|---|
| `LOOM_BD_POST_REWRITE_SKIP=1` | Full no-op — the hook does nothing. |
| `LOOM_BD_POST_REWRITE_NO_COMMIT=1` | Re-export into the working tree but skip the commit (leaves the tree dirty for the caller to commit). |

## install.sh wiring

The repo's `.gitattributes` references `merge=bd-export` and the
`hooks/post-rewrite.sh` file exists, but neither is active until
`install.sh` wires them into the local `.git/` (these are per-clone, not
checked in):

- **Merge driver** — `install.sh` runs, in loom's `.git/config`:

  ```bash
  git config merge.bd-export.name   'bd-export merge driver (loom-4um)'
  git config merge.bd-export.driver 'scripts/bd-merge-driver.sh %O %A %B %P'
  ```

  Until this runs, plain merges of `issues.jsonl` fall back to git's
  default line-merge — functionally fine but exposes the
  bd-state-auto-revert bug class.

- **post-rewrite hook** — `install.sh` symlinks
  `$GIT_COMMON_DIR/hooks/post-rewrite` →
  `hooks/post-rewrite.sh` (the same non-symlink-skip pattern used for
  `pre-push-mkdocs-strict.sh`). A pre-existing non-symlink at that path is
  skipped with a "integrate manually" note rather than clobbered.

Downstream loom-managed projects adopt the same wiring via
`/audit-project` on first run.

## Known hazard — dirty `issues.jsonl` blocking merges (loom-n1sk)

During parallel-worker dispatch + central integration, `.beads/issues.jsonl`
in MAIN's working tree has been observed going **dirty without central
having run a bd write** — `issues.jsonl` gets re-exported even when dolt
state is unchanged, and parallel-worker bd activity plus the
worktree-preseed / post-rewrite hooks churn the shared file. A dirty
`issues.jsonl` makes `git merge --no-ff <worker>` abort with the
working-tree-dirty pre-merge check ("Please commit your changes or stash
them before you merge. Aborting") — not a content conflict.

The real correctness hazard observed (overnight 2026-06-07, dispatch-v2
wave 2): a merge aborted on the dirty tree, but a chained command sequence
let a LATER `bd close` step still run — leaving a bead marked closed in
dolt while its code was NOT on main. This is tracked in bead **loom-n1sk**
(P1 bug). The proposed fixes: make export idempotent (no rewrite when
content-equal), apply the worktree `export.git-add=false` + `.git/info/exclude`
treatment to MAIN too, add a pre-merge guard that normalizes the file, and
**decouple the close step from the merge** so an aborted merge cannot be
followed by a close (verify the merge actually landed before closing; never
chain merge `&&` close).

## Files

- Merge driver: `scripts/bd-merge-driver.sh`
- Merge-driver tests: `lib/tests/bd-merge-driver.test.sh`
- post-rewrite hook: `hooks/post-rewrite.sh`
- Attribute registration: `.gitattributes` (`.beads/issues.jsonl merge=bd-export`)
- Activation: `install.sh` (merge-driver `git config` + post-rewrite symlink)

## Lineage

- Merge driver — loom-4um (bd-state auto-merge protection)
- post-rewrite hook — loom-yjo (follow-up to loom-4um, covers rebase/amend)
- Worktree-side companion — loom-x4m
  ([bd-worktree-preseed](bd-worktree-preseed.md))
- Worktree-export-to-root precedent — loom-22h
- Open hazard (main-side dirty-tree analogue) — loom-n1sk (P1, open)
