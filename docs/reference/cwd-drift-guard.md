# cwd-drift-guard hook

> PreToolUse hook that blocks central-context Bash operations
> (`git merge`, `git push`, `bd close`, `bd update`, `bd dolt push`)
> when the current working directory has silently drifted into a
> worker worktree.

## Why this exists

Closes loom-d2o. Observed 2026-05-27 during the loom-7p6 + loom-cuk
parallel-dispatch session (7 background workers dispatched in one
batch). Central agent's persistent-bash cwd silently resolved into a
returned worker's `.claude/worktrees/agent-a36b96c117ccefeda/`
without any explicit `cd`. Two ops then mis-routed:

1. `bd close loom-7p6.7` ran from the worktree's bd context — the
   worktree's permissions warning (`0775 != 0700`) surfaced first;
   the close itself propagated through bd's dolt/jsonl sync but
   wrote to the worktree's local dolt.
2. `git merge --no-ff frank/loom-7p6.7` returned 'Already up to
   date' because the worktree's HEAD *is* the branch tip — central
   thought it was merging into main but was effectively no-op'ing
   against the worker branch.

Recovery required cd back to main, stash the bd-state drift,
re-merge from main, `bd export` to regenerate canonical
issues.jsonl, and commit bd state separately.

Rule-discipline alone (verify `pwd` before merge/push) isn't enough
under parallel-dispatch session pressure — the drift is silent,
invisible at notification time. This hook catches it mechanically
at the `PreToolUse` boundary.

## Sibling hooks

- `edit-write-pwd-guard.sh` (loom-ymc) — WORKER-SIDE variant. Worker
  in a worktree Edits/Writes a path resolving into MAIN.
- `cwd-drift-guard.sh` (this hook) — CENTRAL-SIDE variant. Central
  emits a central-context op from a worktree cwd.

Both share the realpath canonicalization shape, exit-2 convention,
and literal-"1" bypass-env (loom-b1l).

## What the hook checks

For each Bash tool call:

1. `LOOM_CWD_DRIFT_GUARD_SKIP=1` (literal "1") → exit 0.
2. `tool_name != "Bash"` → exit 0.
3. Empty command → exit 0.
4. Resolve `$PWD` via `python3 os.path.realpath`.
5. cwd realpath does NOT contain `.claude/worktrees/agent-<id>` →
   exit 0.
6. Command does NOT match the central-op allowlist → exit 0.
7. Otherwise → exit 2 with a recovery message naming the worktree
   root, the inferred main root, and the matched verb.

## Central-op allowlist

The regex is anchored on **command intent**, whitespace-tolerant,
and allows git options between `git` and the subcommand:

| Verb | Pattern shape |
|---|---|
| `git merge` | `git [opts...] merge` |
| `git push` | `git [opts...] push` |
| `bd close` | `bd [opts...] close` |
| `bd update` | `bd [opts...] update` |
| `bd dolt push` | `bd [opts...] dolt push` |

Read-only ops (`git status`/`log`/`diff`/`branch`, `bd
list`/`show`/`ready`, etc.) are NOT in the allowlist and pass
through from any cwd.

### Known limitation — composite `cd` commands

A command like `cd /tmp && git merge ...` runs the `cd` AFTER the
hook fires (the hook sees the parent shell's `$PWD`, which is still
the worktree). So the guard refuses based on the pre-cd cwd. This
is rare in practice — central rarely chains `cd` into central ops —
but documented so reviewers don't expect the hook to model shell
semantics it can't see. Workaround: split the command, or use the
`LOOM_CWD_DRIFT_GUARD_SKIP=1` bypass.

## Bypass

```bash
LOOM_CWD_DRIFT_GUARD_SKIP=1
```

Per the loom-b1l literal-"1" convention: `=yes`, `=true`, `=0`,
empty, and other truthy-looking values are all rejected. This is
deliberate — bypasses should be explicit and conspicuous in
transcripts.

Use when an intentional cross-tree op is needed (e.g. merging FROM
a worktree on purpose during a split-history maneuver). Prefer
`cd <main-root> && <retry>` over the bypass whenever possible.

## Failure message example

```
[cwd-drift-guard] BLOCKED: Bash refused.

  command  = git merge --no-ff frank/loom-7p6.7
  cwd      = /home/frank/repos/loom/.claude/worktrees/agent-a36b96c117ccefeda
  worktree = /home/frank/repos/loom/.claude/worktrees/agent-a36b96c117ccefeda
  matched  = git merge

Central-context operation (git merge) emitted from inside a worker
worktree. This is the loom-d2o silent-cwd-drift: central's persistent-
bash cwd has resolved into a returned worker's worktree without an
explicit `cd`. Running this here will mis-route (bd state writes to
the worktree's dolt; `git merge` targets the worktree's own HEAD
instead of main; `git push` pushes the worker branch, not main).

To recover:
  cd /home/frank/repos/loom && <retry command>

To bypass intentionally (rare — e.g. merging FROM the worktree on
purpose), set:
  LOOM_CWD_DRIFT_GUARD_SKIP=1 <command>
```

## Files

- Hook: `hooks/cwd-drift-guard.sh`
- Tests: `lib/tests/cwd-drift-guard.test.sh` (30 fixture cases)
- Registration: `settings.snippet.json` → `PreToolUse` → `Bash`
- Worker-side companion convention:
  `.claude/rules/dispatched-agents.md` section
  "Central-side cwd verification (after worker dispatch returns)"

## Lineage

- Closes loom-d2o (P3 bug, 2026-05-27)
- Sibling worker-side hook: loom-ymc
  ([edit-write-pwd-guard.md](edit-write-pwd-guard.md))
- Subcommand-matching precedent: loom-x4m
  ([bd-worktree-preseed.md](bd-worktree-preseed.md))
- Literal-"1" bypass-env convention: loom-b1l / loom-0hi
- Worker-side smoke-battery companion: loom-g5k
  (the pre-flight battery in `.claude/rules/dispatched-agents.md`)
