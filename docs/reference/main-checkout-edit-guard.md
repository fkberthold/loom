# main-checkout-edit-guard hook

> PreToolUse hook that blocks Edit/Write/MultiEdit calls on a
> source or test file in the MAIN checkout while a bead is
> `in_progress` — the work belongs in a worktree.

## Why this exists

Closes loom-vr6k.

`edit-write-pwd-guard.sh` (loom-ymc) is **inert from the main
checkout by design**. Its own resolution rules say "cwd is NOT in a
linked worktree → exit 0", because it models the *worker→MAIN leak*:
cwd sits inside a worktree and the target path escapes it. The exact
inverse — central sitting in the main checkout, editing main, when
loom's one-bead = one-branch = one-worktree convention says the edit
belonged in a worktree — was covered by nothing.

Live instance: 2026-07-24 in liza_base, central wrote a P0 bug's RED
test **directly into the main checkout**, caught itself only after the
fact, and the user had to say "put it on a working tree" on the very
next bead. Three gates were down at once; this hook is one of them.

Rule-discipline alone does not hold here. The main checkout is where
central *already is* — nothing about typing `Write tests/test_foo.py`
feels different from the correct worktree-relative version, so the
mistake is invisible at the moment it is made and only surfaces at
merge time (or, as in liza_base, when a human notices).

## Sibling hooks

The three worktree-hygiene guards partition the failure space by
*where cwd is* and *what is being issued*:

| Hook | cwd | Catches |
|---|---|---|
| `edit-write-pwd-guard.sh` (loom-ymc) | worktree | Edit/Write target escapes **out** of the worktree into MAIN |
| `main-checkout-edit-guard.sh` (this hook) | main checkout | Edit/Write target stays **in** MAIN when it should have been in a worktree |
| `cwd-drift-guard.sh` (loom-d2o) | worktree | central-context **Bash** op (`git merge`, `bd close`, …) issued from a worktree |

All three share the realpath canonicalization shape, the `exit 2`
convention, and the literal-`"1"` bypass-env convention (loom-b1l).
The first two are deliberately non-overlapping: when cwd is a linked
worktree this hook exits immediately, so a worker leak is blocked
once by `edit-write-pwd-guard`, never double-blocked.

## Posture — block, not nudge

**BLOCK with bypass**, per gate-don't-advise (loom-wj26.1). The work
either belongs in a worktree or it does not; that is a *correctness
invariant*, not an attended decision a human is supposed to weigh in
on. The dividing question from
[gate-dont-advise.md](../explanation/gate-dont-advise.md) — *is a
human supposed to weigh in?* — answers **no** here, so this is a gate,
not a nudge-not-block UX (loom-yb5).

The escape hatch is deliberately **prominent in the block message**.
CLAUDE.md waves inline work through when the change is ≤ ~15 lines
AND touches a single non-test file AND adds no new test; that
legitimate case must read as an obvious one-env-var step rather than
a wall.

Note that `workflow-state`'s `dispatch=inline:<reason>` field does
**not** suppress this hook. That field records the dispatch-vs-inline
call (whose nudge is `dispatch-nudge.sh`'s job); it says nothing about
*which tree* the inline work happens in. Honoring it here would open a
silent hole in the invariant.

## What the hook checks

For each Edit/Write/MultiEdit tool call, in order — every rung
fails **open**:

1. `LOOM_MAIN_CHECKOUT_GUARD_SKIP=1` (literal `"1"`) → exit 0.
2. `tool_name` not in {`Edit`, `Write`, `MultiEdit`} → exit 0.
3. Empty `tool_input.file_path` → exit 0 (the tool will reject it).
4. `lib/loom-hook-helpers.sh` / `lib/worktree-detect.sh`
   unresolvable → exit 0.
5. cwd **is** a linked worktree → exit 0. That is
   `edit-write-pwd-guard`'s domain; never double-block.
6. cwd is not inside a git repo → exit 0 (no main checkout to
   protect).
7. The path is not **source/test-eligible** → exit 0. See below.
8. The resolved target is **outside** the main checkout → exit 0.
9. The resolved target is under `.worktrees/` or
   `.claude/worktrees/` → exit 0. The edit *is* worktree work, just
   issued with a main-rooted path.
10. `bd` is absent from `PATH`, or `bd list --status=in_progress`
    is empty → exit 0. Without a claimed bead there is no "this
    belongs in a worktree" to assert; routine main-checkout
    maintenance stays unblocked.
11. Otherwise → **exit 2** with the message below.

### Source/test eligibility

Step 7 delegates to the shared `loom_is_source_or_test` predicate in
`lib/loom-hook-helpers.sh` (loom-p5ee) — the same language-aware
classifier `dispatch-nudge.sh` uses. It resolves the project's
source/test globs hybrid-style: from the constitution's
`language.runtime` when one is readable, else from a widened built-in
list covering py/sh/go/js/ts/rb/rs.

Its EXCLUDE layer is what makes the pass-throughs work: `*.md`,
anything under `docs/`, and `*.json` classify as `other` whatever the
runtime, so documentation and config edits in the main checkout are
never gated. TEST files **are** eligible alongside sources — central
hand-writing the RED test in main is precisely the liza_base
incident.

## Bypass

```bash
LOOM_MAIN_CHECKOUT_GUARD_SKIP=1
```

Per the loom-b1l literal-`"1"` convention: `=yes`, `=true`, `=0`,
empty, and other truthy-looking values are all rejected. Bypasses
should be explicit and conspicuous in transcripts.

Prefer creating the worktree over reaching for the bypass. Reserve it
for the CLAUDE.md inline threshold (≤ ~15 lines, single non-test file,
no new test) and for genuinely bead-adjacent main-checkout maintenance
that happens to land on a source file.

## Tools matched

- `Edit`
- `Write`
- `MultiEdit`

Not matched (intentionally): `Read` (read-only), `NotebookEdit`
(different `tool_input` shape — add if observed), and `Bash` / `Glob`
/ `Grep` (a different layer; `cwd-drift-guard` covers the Bash side).

## Failure message example

```
[main-checkout-edit-guard] BLOCKED: Write refused.

  file_path     = tests/test_alarm_ack.py
  resolves to   = /home/frank/repos/liza_base/tests/test_alarm_ack.py
  main checkout = /home/frank/repos/liza_base
  in_progress   = liza_base-9f2

You are editing a source/test file directly in the MAIN checkout while
liza_base-9f2 is in_progress. Loom's convention is one bead = one branch
(frank/liza_base-9f2) = one worktree — the work belongs in a worktree, not in
main's working tree. This is the inverse of the worker->MAIN leak
hooks/edit-write-pwd-guard.sh catches, and it is why a P0 bug's RED test
landed in main on 2026-07-24 (loom-vr6k).

Expected worktree:
  /home/frank/repos/liza_base/.worktrees/liza_base-9f2

To recover:
  git worktree add /home/frank/repos/liza_base/.worktrees/liza_base-9f2 -b frank/liza_base-9f2
  cd /home/frank/repos/liza_base/.worktrees/liza_base-9f2
  # re-issue the edit against the worktree copy

Or dispatch the middle instead (the cheaper default):
  /dispatch-middle liza_base-9f2

BYPASS — for legitimately-inline work. CLAUDE.md waves inline through
when the change is <= ~15 lines AND touches a single non-test file AND
adds no new test. Set in the session env and retry:

  LOOM_MAIN_CHECKOUT_GUARD_SKIP=1
```

### Which bead gets named

The message names the bead from `workflow-state`'s `bead` field when
it is set — that is the bead central is actually working. The
`bd list --status=in_progress` scan is only a **fallback** for when
the field is unset; keying on the first listed bead is wrong whenever
a project carries more than one concurrent claim (loom-p5ee D2/D3).
The fallback's id regex admits `_` and `-` inside the project prefix,
so prefixes like `liza_base-` and `tla-puzzles-` survive intact.

`workflow-state.sh` is **optional** to this hook: if the lib cannot be
resolved, the bd-list fallback still names a bead, so a missing lib
degrades the message, never the gate.

## Files

- Hook: `hooks/main-checkout-edit-guard.sh`
- Shared path classifier: `lib/loom-hook-helpers.sh`
  (`loom_is_source_or_test`, `loom_path_class`)
- Worktree detector (shared with `edit-write-pwd-guard` and
  `bd-worktree-preseed`): `lib/worktree-detect.sh`
- Tests: `lib/tests/main-checkout-edit-guard.test.sh` (38 fixture
  cases)
- Registration: `settings.snippet.json` → `PreToolUse` →
  `Edit|Write|MultiEdit`

## Lineage

- Closes loom-vr6k (2026-07-25)
- Inverse of loom-ymc
  ([edit-write-pwd-guard.md](edit-write-pwd-guard.md))
- Central-side Bash sibling: loom-d2o
  ([cwd-drift-guard.md](cwd-drift-guard.md))
- Shared source/test classifier: loom-p5ee (also consumed by
  [dispatch-nudge.md](hooks/dispatch-nudge.md))
- Literal-`"1"` bypass-env convention: loom-b1l / loom-0hi
- Posture: loom-wj26.1
  ([gate-dont-advise.md](../explanation/gate-dont-advise.md))
