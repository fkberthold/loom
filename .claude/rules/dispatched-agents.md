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
# 0. Constitution — cat the project's tooling profile into context
#    (information, not action; loom-ld4). The worker inherits the
#    agreed shell/package-manager/runtime/canonical-commands instead
#    of guessing. Absent file is fine — this is an info read, NOT a
#    gate; never abort on its result.
cat .claude/project-constitution.md 2>/dev/null \
  || echo "(no .claude/project-constitution.md — proceeding without a pinned profile)"

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

# 4. Base — branch base matches main tip (catches empty-branch
#    rebase no-op when base is stale)
merge_base=$(git merge-base HEAD main)
main_tip=$(git rev-parse main)
if [ "$merge_base" != "$main_tip" ]; then
  echo "BASE STALE: $merge_base != $main_tip — rebasing"
  git rebase main || { echo "FAIL: rebase failed — escalate"; exit 1; }
fi
```

Each section below documents the failure mode that motivates one
smoke test, plus the mechanical-fix hook that backstops it. The
sections form a single pre-flight battery: step 0 (constitution
read) + pwd + import + bd state + base-freshness.

## Step 0 — read the constitution (loom-ld4)

**Information, not action.** Step 0 of the battery `cat`s
`.claude/project-constitution.md` into the worker's context BEFORE
any verification step. It is the one battery step that is purely
informational — it pins NOTHING, gates NOTHING, and never aborts on
its result. Its job is to load the project's agreed tooling profile
(shell envelope, package manager, language runtime, the canonical
build/test/lint/gen/dev commands, and the `forbidden:` /
`bypass_patterns:` lists) so the worker runs the project's
*canonical* test/lint command instead of guessing one — the same
recurring guess (pip-on-uv, npm-on-pnpm, wrong test command) that the
constitution epic (loom-6f8) exists to kill.

An absent file is NOT a failure: a project may not have a
constitution yet, and a dispatched worker is the wrong place to nudge
`/audit-project` (that nudge lives at session-startup, step 1f). When
the file is missing, the `cat` falls through to a one-line note and
the battery proceeds. Step 0 runs first precisely because it is
information for every step that follows: the worker reads the profile,
THEN verifies pwd / import / bd-state / base-freshness.

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

**Sentinel absence at smoke-time is expected.** The preseed hook
fires on the first *write-class* bd call; the smoke battery's
`bd list -n 1` is read-class and does NOT trigger it. A fresh
worktree will not yet carry `.beads/.loom-preseeded` when smoke
runs — that's correct behavior, not a regression. The smoke check's
job is verifying dolt non-empty, not sentinel presence. See the
"Sentinel timing" section of the reference page.

## Base-freshness check

**Risk (loom-6zi, surfaced 2026-05-15 by loom-b1l worker).** A
dispatched worker on a fresh branch with NO commits yet runs
`git rebase main` and gets a no-op return code 0 — even when the
branch's merge-base trails main by N intervening merges. The
rebase is a no-op on an empty branch because there's nothing to
replay; it nonetheless returns success. The staleness only surfaces
post-commit when `git diff --stat main HEAD` shows unrelated files
(the intervening merges' contents). By then the worker has already
done work against a stale base; recovery requires a stash-bracketed
rebase against a partially-typed change set. Catch it pre-flight by
comparing merge-base against main's tip directly, before any work
begins.

**Pre-flight smoke test** (part of the aggregator above):

```bash
merge_base=$(git merge-base HEAD main)
main_tip=$(git rev-parse main)
if [ "$merge_base" != "$main_tip" ]; then
  echo "BASE STALE: $merge_base != $main_tip — rebasing"
  git rebase main || { echo "FAIL: rebase failed — escalate"; exit 1; }
fi
```

For an empty branch the rebase fast-forwards the branch tip to
main; for a branch with commits it replays them onto main. Either
way the worker proceeds on a known-fresh base AND knows its
starting point shifted (the diagnostic the silent no-op was
hiding).

**Mechanical fix.** Use `scripts/loom-rebase-worktree main`
(loom-azt) instead of plain `git rebase main` when untracked WIP
from a prior crash needs preserving across the rebase. The wrapper
refuses outside a linked worktree, snapshots untracked files,
pre-detects collisions, and restores files post-rebase. See
[`docs/reference/loom-rebase-worktree.md`](../../docs/reference/loom-rebase-worktree.md).

## Central-side cwd verification (after worker dispatch returns)

**Risk (loom-d2o, surfaced 2026-05-27 by the loom-7p6 + loom-cuk
parallel-completion sequence).** This is the worker-side battery's
mirror failure mode, on the CENTRAL agent's persistent-bash
session. After 7 background workers were dispatched and one
returned (loom-7p6.7), central's persistent-bash cwd silently
resolved into the returned worker's
`.claude/worktrees/agent-a36b96c117ccefeda/` — no explicit `cd`
was issued. The next two ops mis-routed:

- `bd close loom-7p6.7` ran in the worktree's bd context. The
  worktree's `.beads/` permissions warning (`0775 != 0700`)
  surfaced first; the close itself wrote to the worktree's dolt
  and propagated through bd's sync layers from the wrong tree.
- `git merge --no-ff frank/loom-7p6.7` returned 'Already up to
  date' because from the worktree, the branch tip IS HEAD —
  central thought it was merging into main, but was effectively
  no-op'ing against the worker branch.

The drift is silent: no notification, no banner, no diagnostic.
Pre-completion `pwd` looked correct; post-worker-return `pwd`
silently changed. Mechanism is opaque from the Claude Code
harness's outside (persistent-bash cwd state may leak across the
worker dispatch boundary, or the completion-notification path may
propagate cwd back).

**Mechanical fix.** The `hooks/cwd-drift-guard.sh` PreToolUse
hook (loom-d2o) intercepts five central-context Bash commands
when cwd resolves inside `.claude/worktrees/agent-*/`:

- `git merge` (any options)
- `git push` (any options)
- `bd close` (any options)
- `bd update` (any options)
- `bd dolt push`

It refuses with `exit 2` and emits a stderr message naming the
worktree root, the inferred main root, and the recovery command
(`cd <main-root> && <retry>`). Bypass via
`LOOM_CWD_DRIFT_GUARD_SKIP=1` (literal-"1" match per loom-b1l;
`=yes`/`=true`/`=0`/empty all rejected). See
[`docs/reference/cwd-drift-guard.md`](../../docs/reference/cwd-drift-guard.md).

Read-only ops (`git status`/`log`/`diff`/`branch`, `bd
list`/`show`/`ready`) are NOT in the allowlist — they're safe
from any cwd and pass through silently.

**Convention fallback.** After any parallel-dispatch wave
returns, central should verify cwd before the first
merge/push/bd-close:

```bash
pwd                            # should be the main repo root
git branch --show-current      # should be `main` (or central's branch)
```

If `pwd` shows a `.claude/worktrees/agent-<id>/` path, run
`cd <main-root>` before any central-context op. The hook will
also catch it mechanically; the convention is the read-only
diagnostic.

The hook composes with the worker-side battery: workers use the
four-section pre-flight smoke test above; central uses the
cwd-drift hook on returning from each dispatch wave. Defense in
depth.

## Background dispatch is the DEFAULT (loom-li8h)

**Central dispatches workers with `run_in_background: true` by
default.** This is the central-side dispatch posture that the
worker-side battery above presupposes: workers run while central is
free to do other things.

**Risk (the foreground-wait anti-pattern).** A foreground dispatch
holds central's turn idle until the worker returns — central sits and
waits, doing nothing, for the whole RED→GREEN cycle. Observed all
session 2026-06-08 (the parallel wave + both `/dispatch-middle`
pipelines ran foreground). It contradicts dispatch-v2's lean-central
goal: central should not be *blocked* during the middle, only
*write-nothing*.

**Default.** Dispatch with **`run_in_background: true`**. Central
**yields the turn** the moment it dispatches and **resumes on the
worker's completion event** — free meanwhile to converse with the
user, plan, pre-stage the next bead, or revise the in-flight contract.
Foreground is the explicit **exception**, reserved for the narrow case
where the **next step is immediate integration with nothing else
interleavable** (a single short dispatch central will merge + close the
instant it lands, with no conversation/planning/staging to fill the
gap). When in doubt, background it. See the Dispatch-mode sections of
`skills/dispatch-middle/SKILL.md` and
`skills/bead-lifecycle-shell/SKILL.md`.

## Concurrency caution — never two full-suite loops in one repo at once

Backgrounding makes multiple agents in flight cheap and is the default
above — but there is one hard concurrency rule: **never run two
full-suite loops in the same repo at the same time.** Two suite runs
racing in one working tree contend on shared git/bd state and produce
nonsense numbers.

**Risk (loom-fx9m close detour, 2026-06-08).** A foreground-wait
combined with the harness auto-backgrounding a long-running loop
produced **two suite runs racing in one repo**. When the duplicate
suite task was `TaskStop`'d, it left **orphan `bd-post-rewrite` child
processes** behind: `TaskStop` reaps the task it targets but **may not
reap that task's grandchildren**, so the orphaned children kept racing
on git/bd state and yielded a **false `63/2` suite result**.

**Convention.** One suite loop per repo at a time. After any
`TaskStop` on a suite/loop task, confirm no orphan `bd-post-rewrite`
(or other grandchild) processes survived — e.g.
`pgrep -fa bd-post-rewrite` should be empty — before trusting any
suite number. Treat a suite result obtained while a second loop or a
just-`TaskStop`'d task was live as untrustworthy until re-run clean.
