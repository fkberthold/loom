---
description: Conventions for workers dispatched via Agent(isolation="worktree") to keep changes inside the worktree and verifications honest
---

# Dispatched-agent conventions

This file collects discipline that worker agents must follow when
running inside a `.claude/worktrees/agent-<id>/` worktree. The
Agent harness creates the worktree but does NOT fully sandbox the
worker — several failure modes leak changes into the main repo or
make verification dishonest. The conventions below mitigate each.

## Python import resolution

**Risk (loom-rsk, Mode 5).** If `pip install -e <main>` was ever
run against the main repo, MAIN's source becomes a site-package on
sys.path. A worker running `python3`, `python3 -m pytest`, or any
Python script from the worktree gets MAIN's modules instead of the
worktree's modifications — tests pass against MAIN's behavior while
pretending to verify the worktree's changes. Silent and
post-merge-only.

**Pre-flight smoke test** (run before any python work; loom-g5k
will fold this into the broader pre-flight battery):

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
