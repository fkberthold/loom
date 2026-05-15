---
description: Conventions for workers dispatched via Agent(isolation="worktree") to keep changes inside the worktree and verifications honest
---

# Dispatched-agent conventions

This file collects discipline that worker agents must follow when
running inside a `.claude/worktrees/agent-<id>/` worktree. The
Agent harness creates the worktree but does NOT fully sandbox the
worker — several failure modes leak changes into the main repo or
make verification dishonest. The conventions below mitigate each.

## Pre-flight smoke battery

**Run this as the first bash call of every dispatched-worker
session, before touching any file** (loom-g5k). Catches the most
common worktree-isolation failure modes at their cheapest detection
point. Abort and ask for guidance if any check fails.

```bash
# 1. Path — pwd resolves to the worktree's git toplevel
pwd_real=$(realpath "$(pwd)")
top_real=$(realpath "$(git rev-parse --show-toplevel)")
[ "$pwd_real" = "$top_real" ] || { echo "FAIL: pwd=$pwd_real top=$top_real"; exit 1; }

# 2. Import — project's Python (if any) resolves inside the worktree
#    (substitute <project_name>; skip if the project has no Python)
python3 -c 'import <project_name>; print(<project_name>.__file__)' 2>/dev/null \
  | grep -q "$top_real" || echo "WARN: python import does NOT resolve inside worktree"

# 3. bd state — worktree's bd dolt is non-empty
bd list -n 1 >/dev/null 2>&1 || { echo "FAIL: bd list returned empty"; exit 1; }
```

Each section below documents the failure mode that motivates one
smoke test, plus the mechanical-fix hook that backstops it. The
three sections form a single pre-flight battery: pwd + import +
bd state.

## Pwd verification

**Risk (Mode 1 — absolute-path-in-brief leak).** The dispatcher's
brief contains `/home/frank/repos/<project>/path/...` paths. The
worker dutifully uses them as the `file_path` argument to Edit/
Write. Those paths resolve to MAIN, not the worktree — commits
either land on MAIN's working tree, or land on a worktree branch
that's empty of the actual changes.

**Risk (Mode 4 — relative-path resolution surprise).** Even with a
brief that uses only relative paths (`tests/foo.py`), the path can
resolve OUTSIDE the worktree through symlinks or `../` traversal.
This is why the older "prefer-relative-paths-in-briefs" prescription
was dropped: relative paths alone are not sufficient. Verify the cwd
directly, canonicalized through realpath.

**Pre-flight smoke test** (part of the aggregator above):

```bash
pwd_real=$(realpath "$(pwd)")
top_real=$(realpath "$(git rev-parse --show-toplevel)")
[ "$pwd_real" = "$top_real" ] || exit 1
```

`realpath` normalization handles symlink-resolved worktree roots
(common when `.claude/worktrees/` sits behind a symlinked checkout
or when the worktree path itself contains `..` segments).

**Mechanical fix.** The `hooks/edit-write-pwd-guard.sh` PreToolUse
hook (loom-ymc) catches Mode 1 + Mode 2 + Mode 4 at write time: it
intercepts Edit/Write/MultiEdit calls in a worktree and refuses any
target that resolves outside the worktree root. Bypass with
`LOOM_EDIT_WRITE_GUARD_SKIP=1` when an intentional cross-tree write
is needed. See
[`docs/reference/edit-write-pwd-guard.md`](../../docs/reference/edit-write-pwd-guard.md).

## Python import resolution

**Risk (loom-rsk, Mode 5).** If `pip install -e <main>` was ever
run against the main repo, MAIN's source becomes a site-package on
sys.path. A worker running `python3`, `python3 -m pytest`, or any
Python script from the worktree gets MAIN's modules instead of the
worktree's modifications — tests pass against MAIN's behavior while
pretending to verify the worktree's changes. Silent and
post-merge-only.

**Pre-flight smoke test** (part of the aggregator above):

```bash
python3 -c 'import <project_name>; print(<project_name>.__file__)'
```

The printed path MUST start with the worktree's toplevel
(`.claude/worktrees/agent-<id>/...`). If it points at MAIN, the
shadow is active — escalate to the wrapper below.

**Mechanical fix.** Use `scripts/loom-worktree-python` instead of
plain `python3` for any python invocation inside a worktree:

```bash
# Instead of:
python3 -m pytest tests/

# Use:
scripts/loom-worktree-python -m pytest tests/
```

The wrapper prepends the worktree's git toplevel to `PYTHONPATH`,
so the worktree's copy of the project always wins sys.path
resolution. It refuses to run in the main repo (the shadow doesn't
apply there) and passes through python3's exit code unchanged. See
[`docs/reference/loom-worktree-python.md`](../../docs/reference/loom-worktree-python.md).

## bd state preseed

**Risk (Mode 3 — bd-state-empty fresh worktree).** Git worktrees
created via `git worktree add` get a copy of the repo tree
including `.beads/`, but the bd embedded-dolt DB under
`.beads/embeddeddolt/` is local-not-checked-in. The fresh worktree
inherits an empty dolt. The first write-class `bd` call inside the
worktree (`bd update --claim`, `bd close`, etc.) writes one-issue
state to the empty dolt AND auto-exports `.beads/issues.jsonl`,
overwriting the worktree's full checked-in copy. On merge to main,
**all other issues in issues.jsonl are silently lost**.

**Pre-flight smoke test** (part of the aggregator above):

```bash
bd list -n 1 >/dev/null 2>&1 || exit 1
```

A non-zero exit, or an empty result, means the embedded dolt is
empty and the next write-class bd call will wipe issues.jsonl on
merge. Stop and escalate.

**Mechanical fix.** The `hooks/bd-worktree-preseed.sh` PreToolUse
hook (loom-x4m) pre-seeds the worktree's bd dolt on the first
write-class `bd` call inside a worktree. It runs `bd import
.beads/issues.jsonl`, sets `export.git-add=false`, and adds
`.beads/issues.jsonl` to the worktree's `.git/info/exclude`. The
sentinel `.beads/.loom-preseeded` memoizes the seed; self-heals if
the dolt is later wiped. Bypass with
`LOOM_BD_WORKTREE_PRESEED_SKIP=1`. See
[`docs/reference/bd-worktree-preseed.md`](../../docs/reference/bd-worktree-preseed.md).
