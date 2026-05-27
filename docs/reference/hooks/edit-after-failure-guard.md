# edit-after-failure-guard hook

> PreToolUse hook that blocks Edit/Write/MultiEdit on a non-test
> file when the recent transcript shows a test/build failure and
> no test file has been edited since.

## Why this exists

Closes loom-z3m.6. The recurring symptom is TDD discipline slipping
under multi-stepper pressure: a bash command (test runner, build,
lint) exits non-zero, surfacing a NEW failure mode that wasn't
already pinned by an existing test — and the agent's very next move
is an Edit/Write to the source file, writing the fix before the
failing test is captured.

Surfaced verbatim from liza f3 (2026-05-07): *"Ok, your discipline
is slipping. First you need to write a test that will fail until
you get this right. _then_ do the fix."*

Skill-text reminders alone are not enough — the slip happens fast
enough that the agent commits to the source edit before the next
re-read of the recipe text would catch it. The hook gives the slip
a mechanical floor.

## Failure mode covered

**Mid-recipe TDD slip.** After a fresh test/build failure inside an
activity recipe's variable middle, the agent jumps straight to a
fix instead of routing through `superpowers:test-driven-development`
to pin the symptom with a RED test first. The hook fires on the
Edit, refuses, and reminds the agent to write the test first.

This is the mechanical backstop for the
[`bead-lifecycle-shell` mid-recipe branchpoint](../skills/all-skills.md#bead-lifecycle-shell-cross-activity-scaffolding)
shipped in the same bead.

## What the hook checks

For each Edit/Write/MultiEdit tool call:

1. Read `tool_input.file_path` and `transcript_path` from the PreToolUse
   payload. If `transcript_path` is empty or unreadable → exit 0
   (fail open; the guard cannot tell without transcript visibility).
2. If the target file_path is itself a test file → exit 0. Common
   test-file conventions matched: `tests/`, `test/`, `__tests__/`,
   `*.test.{sh,bash,py,js,ts,jsx,tsx}`, `*_test.{sh,bash,py,go}`,
   `test_*.{sh,py}`, `*.spec.{js,ts,jsx,tsx}`, `conftest.py`.
3. Tail the last 80 JSONL records of the transcript. Build a
   `tool_use_id → name` map from every `tool_use` block seen, so
   each `tool_result` can be source-discriminated (loom-7j5 fix
   #1). Walk forward through Bash-originated `tool_result` blocks
   in order; each one decides the current latch state
   ("last-Bash-only" — loom-n1q). A Bash result matching any
   failure-marker regex below LATCHES; a subsequent clean Bash
   result CLEARS the latch:
   - `^FAIL\s`
   - `^FAIL:\s`
   - `\bFAILED\s+\S+(?:::|/)` (pytest brief, e.g. `FAILED tests/foo.py::test_bar`)
   - `^--- FAIL:` (Go test verbose)
   - `\b\d+\s+(?:tests?\s+)?failed\b` (pytest summary, e.g. `1 failed`)
   - `\bassertion\s+(?:failed|error)\b`
   - `^Error:\s`
   - `\bTraceback \(most recent call last\)`
   - `^panic:\s` (Go panic)
   - `\bTests?:.*\bfailed\b`
   - `\bexit code:\s*[1-9]`

   Two whitelist classes never latch and never clear (skipped
   entirely, leaving the prior state intact):
   - Texts containing the literal substring `edit-after-failure-guard`
     (loom-7j5 fix #3: hook self-reference whitelist, prevents
     recursive self-trigger when a prior BLOCKED message lands in
     the tail).

   One whitelist class always CLEARS the latch (treated as a clean
   Bash result, since the next Edit IS the work):
   - Texts containing `CONFLICT (content):` or
     `Automatic merge failed; fix conflicts` (loom-n1q: git-merge
     conflict-resolution opportunity. The Bash framing adds
     `Exit code: 1` which would otherwise trip `\bexit code:\s*[1-9]`).
4. After the latched failure (if any), scan forward for a `tool_use`
   of `Edit`/`Write`/`MultiEdit` whose `file_path` matches the
   test-file conventions above. If found → exit 0 (RED captured;
   guard cleared).
5. Otherwise → exit 2 with the TDD reminder message.

## Bypass

Three reachable bypasses, in order of preference:

### Per-project marker file (loom-n1q, recommended for interactive sessions)

```bash
touch .claude/no-edit-after-failure-guard
```

Hook walks up from the target file's directory (and from `$PWD`)
looking for `.claude/no-edit-after-failure-guard`. If found,
exit 0 silently. Per-project, reachable from any agent Bash call,
visible in `git status` (commit it or `.gitignore` it per your
policy).

This bypass is the answer to the env-var bypass not propagating
from in-session `export` calls — the env-var freezes at `claude`
fork time, so agents that decide *during* a session to step around
the guard can't `export` their way out. The marker file always
works.

### Environment variable (loom-z3m.6, original bypass)

```bash
LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1
```

Set in the worker's env BEFORE `claude` launches when the recent
failure is unrelated to the current edit (incidental flake,
pre-existing lint warning, unrelated test failure in a CI batch).
In-session `export` is a no-op — the env is frozen at fork time.
Prefer to file a follow-up bead for the unrelated failure rather
than silently absorb it.

### Auto-allow on test-file targets

The hook auto-allows when the target file_path is itself a test
file — writing/fixing the failing test IS the desired next move,
so no bypass is needed for that case.

## Tools matched

- `Edit`
- `Write`
- `MultiEdit`

Not matched (intentionally):

- `Read` — informational, can't slip TDD discipline.
- `NotebookEdit` — different `tool_input` shape; add later if
  observed in flow.
- `Bash`, `Glob`, `Grep`, etc. — different layer.

## Failure message example

```
[edit-after-failure-guard] BLOCKED: Edit refused.

  file_path = /home/frank/repos/proj/src/foo.py

A test or build failure was observed in recent Bash output, and
no test file has been edited since. The next Edit/Write to a
non-test file would be a TDD discipline slip — fixing the source
before pinning the failure with a RED test.

To proceed, do ONE of:

  1. Write/edit the failing test first (RED), then re-attempt the
     source edit. The test edit clears this guard.
  2. If the failure is unrelated to this edit (e.g. flaky test,
     unrelated lint warning surfaced incidentally), set
     LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1 in the env and retry.
  3. If you've already considered the test and consciously chose
     not to add one (trivial typo fix, doc edit), use the bypass
     env var above.

Reference: superpowers:test-driven-development. The bead-lifecycle-
shell's mid-recipe branchpoint (post-loom-z3m.6) mandates routing
through TDD when a NEW failure mode surfaces during the variable
middle.
```

## Detection heuristic notes

The failure-marker regex aims to match real test/build framing
(pytest brief and summary, Go test verbose and panic, assertion
errors, Python tracebacks, generic `^Error:`/`^FAIL:` lines, and
non-zero `exit code:` reports) while skipping prose that merely
mentions "fail" / "failure" / "failed". Before loom-7j5 the regex
included a lax `\bFAIL(?:ED|URE)?\b` substring match that fired
on doc / drawer / source / bead-description text containing those
words; that case is now handled by source-discrimination (only
Bash-originated `tool_result` blocks are scanned) plus tighter
framing patterns.

The auto-clear (a test edit after the failure) is one relief valve;
a subsequent clean Bash call ("last-Bash-only" TTL — loom-n1q) is
a second; the marker file is a third; the bypass env var is the
safety net.

The 80-record transcript tail balances "catch recent failures" with
"don't pay reading cost on every Edit". Multi-failure sessions
(e.g. a long debug loop) are handled correctly: only the
**most-recent Bash result** matters. A clean Bash call between a
failure and the next Edit clears the latch (loom-n1q TTL). A test
edit after a failure also clears.

False-positive seams worth watching:

- `Error:` in a stack trace context that the agent is intentionally
  documenting (e.g. writing a doc that quotes an error). Bypass
  is the correct escape; the auto-allow on test-path targets does
  not cover docs.
- A bash command that prints "FAIL" as part of its normal output
  (rare; some scripts have FAIL-prefixed verbose logs). Bypass is
  the correct escape.
- An incidental lint failure in a batch run where the actual edit
  target is unrelated. Either fix the lint failure first
  (mechanically the right move) or bypass.

## Files

- Hook: `hooks/edit-after-failure-guard.sh`
- Tests: `lib/tests/edit-after-failure-guard.test.sh` (45 fixture cases)
- Marker file path: `<project>/.claude/no-edit-after-failure-guard`
- Skill mid-recipe branchpoint: `skills/bead-lifecycle-shell/SKILL.md`
  (Variable middle → Mid-recipe branchpoint subsection)

## Lineage

- Closes loom-z3m.6 (P1 feature, 2026-05-19) — initial hook ship
- Bug-class follow-up: loom-7j5 (P2 bug, 2026-05-19) — three-axis
  refinement (tool_use_id source-discrimination, tighter framing,
  hook self-reference whitelist)
- Bug-class follow-up: loom-n1q (P2 bug, 2026-05-26) — three-axis
  refinement (git-merge CONFLICT whitelist, "last-Bash-only" TTL,
  per-project marker-file bypass). Test fixture also unsets
  `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP` at startup so tests are
  hermetic from the user's shell env.
- Origin: loom-z3m retrospective dig (Phase 1, 14 improvement beads
  filed)
- Companion (out of scope for loom; upstream PRs in loom-ki5):
  - `superpowers:verification-before-completion` tool-inventory
    pre-check (HAW f1 verbatim)
  - `superpowers:systematic-debugging` alt-hypothesis gate
    (liza f7 verbatim)
- Sibling pattern: `hooks/edit-write-pwd-guard.sh` (loom-ymc) —
  same PreToolUse-on-Edit/Write/MultiEdit shape, different failure
  family (worktree path leak vs. TDD slip).
