# loom-worktree-python

> `python3` wrapper that makes the worktree's copy of a project
> win sys.path resolution over a `pip install -e <main>` editable
> install.

## Why this exists

Closes loom-rsk (Mode 5 of the worktree-isolation failure cluster).

If `pip install -e ~/repos/<project>` has ever been run against the
main repo, that install lays down a `.pth` entry in site-packages
that puts MAIN's source directory on `sys.path`. A worker
dispatched into `.claude/worktrees/agent-<id>/` that invokes
`python3`, `python3 -m pytest`, or any Python script silently gets
MAIN's modules instead of the worktree's modifications:

- Tests "pass" because they exercise MAIN's behavior, not the
  worktree's changes.
- The worker reports "tests pass" with full confidence.
- The leak is INVISIBLE during the session — `sys.path[0]` for `-c`
  is just `""` (cwd), and for installed entry-points like `pytest`
  sys.path starts with the pytest script's directory, not the
  worktree. The site-package wins.
- Surfaces only post-merge, when worktree changes become live and
  behavior diverges.

First documented in the e87k agent report 2026-05-14, surfaced as
Mode 5 in Frank's 2026-05-13 PM writeup. The "most insidious"
failure mode because the verification mechanism itself is the
failure surface.

## Usage

```bash
loom-worktree-python <python-args...>
```

Drop-in replacement for `python3` inside a worktree. Examples:

```bash
# Pytest
scripts/loom-worktree-python -m pytest tests/

# One-liner smoke test
scripts/loom-worktree-python -c 'import myproj; print(myproj.__file__)'

# Run a script
scripts/loom-worktree-python tools/migrate.py
```

## What the wrapper does

1. **Refuses to run in the main working tree** (or outside any git
   tree). Detects via `git rev-parse --git-common-dir` vs
   `--show-toplevel`. In the main tree the shadow doesn't apply —
   use plain `python3` there.
2. **Prepends the worktree toplevel to `PYTHONPATH`.** If
   `PYTHONPATH` was already set, the worktree path is prepended
   with `:` separator — existing entries are preserved as a suffix.
3. **`exec python3 "$@"`** — the wrapper's exit code is python3's.

## Exit codes

- Passes through python3's exit code.
- `2` = wrapper-level refusal (not in a linked worktree).

## When to use this vs plain `python3`

Use this wrapper whenever:

- You're inside a `.claude/worktrees/agent-*` worktree
- You're about to run `python3` or anything that imports the
  project's modules (pytest, scripts, REPL probes)

Use plain `python3`:

- In the main working tree (the wrapper refuses anyway — the shadow
  cannot exist when MAIN is also the cwd)
- In a non-loom project where no editable install of MAIN exists
  (the wrapper still works, just adds an unnecessary PYTHONPATH
  prepend)

## Pre-flight smoke test (Option A complement)

The wrapper is the mechanical fix (Option B from loom-rsk's three
options). It pairs with a rule-convention smoke test that catches
the failure before any real work happens:

```bash
python3 -c 'import <project>; print(<project>.__file__)'
```

If the path does NOT start with the worktree's toplevel, the
shadow is active — switch to `loom-worktree-python` for the
session. loom-g5k tracks landing this smoke test in the broader
pre-flight battery for dispatched workers.

## Files

- Script: `scripts/loom-worktree-python`
- Tests: `lib/tests/loom-worktree-python.test.sh` (13 fixture cases)
- Worker convention: `.claude/rules/dispatched-agents.md`

## Why not per-worktree venv (Option C)?

The bead lists three fix shapes of increasing weight: Option A
(brief convention only), Option B (PYTHONPATH wrapper — what this
ships), Option C (per-worktree venv with `pip install -e $(pwd)`).
Option C makes Mode 5 structurally impossible but adds ~30s per
dispatch. The liza_base 2026-05-07 hook venv-python precedent —
which resolved a similar import-shadow class with an explicit
interpreter path — suggests Option B is sufficient. Option C is
held in reserve as a follow-up if workers continue to hit Mode 5
after Option A+B land.

## Lineage

- Closes loom-rsk (P1 bug, 2026-05-15)
- Sibling open: loom-g5k (P2 pre-flight smoke tests)
- Sibling done: loom-ymc (edit-write-pwd-guard, Modes 1/2/4),
  loom-x4m (bd-worktree-preseed, Mode 3),
  loom-azt (loom-rebase-worktree, base-staleness)
- Cluster drawer: `drawer_loom_decisions_df73c725b47dd67832935e3a`
  (loom-tag, 2026-05-04 — worktree-isolation 5-mode finding)
