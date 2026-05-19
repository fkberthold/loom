# bd-preflight-docs-strict hook

> PreToolUse hook that runs `mkdocs build --strict` before
> `bd close` and `bd preflight`, refusing the call when the docs
> tree would break on push.

## Why this exists

Closes loom-cya. The recurring "broken-markdown-link-in-`docs/`
caught-only-by-`mkdocs --strict`-in-CI" bug class hit loom three
times in four days (loom-59w, loom-tx7) — twice with a 2-day silent
gap before the red Deploy-docs workflow was noticed, once with a
17-minute gap thanks to the session-startup CI-health check
(loom-z3m.1). Recipe-text alone (loom-bm2 precedent) did not
prevent the third recurrence.

This hook gives the bug class a mechanical floor at *bead-close
time* — earlier than the sibling pre-push hook (loom-kbo) and
earlier than CI. Defense-in-depth: close → push → origin.

## Failure mode covered

**Broken `docs/` link slips past local review.** An author edits a
markdown file in `docs/` (or a primitive `skills/`, `commands/`,
`agents/`, `hooks/` file the docs include-glob mirrors), introduces
a link or nav target the strict-mode link-checker can't resolve,
runs `bd close` without first running `mkdocs build --strict`
locally, and ships a red Deploy-docs run. The hook refuses the
close, surfaces the first WARNING line inline, and tells the agent
exactly which env var bypasses it for emergencies.

## What the hook checks

On every Bash tool call:

1. Bypass: if `LOOM_BD_PRECLOSE_STRICT_SKIP=1`, exit 0 silently.
2. Tool dispatch: ignore non-Bash tools; ignore Bash commands that
   are not `bd close` or `bd preflight` (word-boundary matched, so
   `bd closeable-thing` does not trigger).
3. Project shape: if no `mkdocs.yml` in cwd, exit 0 (not a
   docs-bearing project).
4. Mode: if `<project>/.claude/workflow.json` resolves to `off`,
   exit 0 silently.
5. Tool availability: if `mkdocs` is not installed (or `$MKDOCS_BIN`
   override points at a non-executable path), exit 0 (graceful
   skip — no nag in pre-mkdocs environments).
6. File-relevance gate: run `git diff --name-only main...HEAD`; if
   no path matches `docs/`, `mkdocs.yml`, `requirements.txt`,
   `skills/`, `commands/`, `agents/`, or `hooks/`, exit 0 (do not
   pay the mkdocs build cost when nothing relevant changed).
7. Build: run `mkdocs build --strict`. On pass, exit 0 silent.

On strict-mode failure:

- Workflow mode `full` → exit 2 with stderr containing the first
  WARNING/ERROR line, the bypass env-var hint, and the full mkdocs
  output indented for readability. Claude Code surfaces stderr and
  blocks the tool call.
- Workflow mode `light` → exit 0 with a `WARN:`-prefixed stderr
  message. Informational only; does not block. Use this when
  iterating on docs and the strict-mode build is expected to fail
  intermittently.

## Bypass

Two layers:

```bash
# One-shot bypass at call time:
LOOM_BD_PRECLOSE_STRICT_SKIP=1 bd close <id>

# Per-session bypass:
export LOOM_BD_PRECLOSE_STRICT_SKIP=1
```

Or lower the project's workflow mode from `full` to `light`
(warns) or `off` (silent) via `<project>/.claude/workflow.json`.

## Test injection points

For fixture-test isolation (see
`lib/tests/bd-preflight-docs-strict.test.sh`):

- `LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1` — skip the
  git-diff relevance check (assume the branch touched
  docs-relevant paths). Used to exercise the build-and-classify
  paths without a real git history.
- `MKDOCS_BIN=<path>` — override the mkdocs binary path. Used to
  point fixtures at a passing no-op stub or a failing stub.

## Related infrastructure

- **Sibling hook (loom-kbo, pre-push):** catches the same bug class
  one layer later, at `git push` time. Pre-push composes with this
  hook for two-layer defense before CI sees the change.
- **Regression test fixture (`lib/tests/docs-mkdocs-strict.test.sh`,
  loom-tx7):** loom-specific assertion that the repo's own docs/
  tree builds strict-clean. Run via the `lib/tests/` sweep.
- **Bug-class lineage:** loom-59w (2026-05-15, original instance +
  deferred-options drawer), loom-tx7 (2026-05-19, 3rd recurrence +
  follow-ups unblocked), loom-cya (this hook).

## See also

- [`bead-lifecycle-shell` D1](../skills/all-skills.md#bead-lifecycle-shell-cross-activity-scaffolding) —
  references this hook in the close-time guidance.
