# Something about the workflow feels broken

To diagnose hooks, settings, or mode-resolution issues that look
like the workflow is not behaving as expected, follow these steps.

## Precondition

- You expected a hook or skill to fire and it did not (or vice
  versa).
- You have access to a shell where you can run hook scripts
  directly.

## Steps

1. **Check whether `settings.json` hot-reloaded.** It is unverified
   whether Claude Code reloads settings mid-session. Run `/clear`
   and re-test the failing path.

2. **Smoke-test the hook script.** Pipe a synthetic event into the
   hook and check the exit code:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"bd close foo"}}' \
     | bash ~/.claude/hooks/bd-close-capture.sh
   echo "EXIT: $?"
   ```
   Exit 2 = hook blocked. Exit 0 = hook passed through.

3. **Verify the resolved mode.** Run
   `~/.claude/scripts/workflow-state mode`. Mismatch between
   expected and actual mode often explains a missing hook fire
   (off mode silences hooks; light mode never blocks).

4. **Inspect the state file.** Run
   `~/.claude/scripts/workflow-state show` for the full JSON. A
   stale `bead` or wrong `stage` indicates a recipe step was
   skipped.

5. **Check the master plan drawer for known limitations.** Run
   `mempalace_search "WORKFLOW INFRASTRUCTURE PLAN"` and read the
   status table.

6. **File a bead if the gap is real.** Use the loom beads tracker;
   reference the smoke-test output and the resolved mode in the
   description.

## Diagnose a blocking guard hook

When a tool call is refused unexpectedly, identify which guard fired
from its stderr message — each guard names itself and prints its
bypass. Common ones:

- **dispatch-nudge** — prompts when a RED→GREEN bead is about to be
  worked inline without a recorded `dispatch=inline:<reason>`. Either
  record the reason (`~/.claude/scripts/workflow-state set
  dispatch=inline:<reason>`) or switch to `/dispatch-middle`. Bypass:
  `LOOM_DISPATCH_NUDGE_SKIP=1`.
- **edit-after-failure-guard** — blocks an Edit/Write that follows a
  failing test run. It now ignores **zero-count GREEN summaries**
  (a `0 failed` / `0 failures` line no longer trips it), so a passing
  run does not falsely block the next edit. With no `transcript_path`
  in the event it **fails open** (passes through — it cannot tell).
  Bypass: `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1`, or the in-session
  marker `touch .claude/no-edit-after-failure-guard`.
- **cwd-drift-guard** — symptom is a `git merge` / `git push` /
  `bd close` / `bd update` refused with a message naming a
  `.claude/worktrees/agent-*/` worktree root. It fires when central's
  cwd silently drifted into a returned worker's worktree. Run
  `cd <main-root>` (the message prints it) and retry. Bypass:
  `LOOM_CWD_DRIFT_GUARD_SKIP=1`.

All bypass env vars require the literal value `1`. See
[Bypass workflow ceremony](../bypass-workflow-ceremony.md) for the
full guard-bypass table.

## Outcome

The misbehavior is either explained (mode resolution, hot-reload
caveat, known limitation) or filed as a tracked bead with
reproduction evidence.

## Related

- For each hook's mode-by-mode behavior, see
  [reference: hooks](../../reference/hooks/index.md).
- For when to bypass a misbehaving hook while waiting for a fix,
  see [Bypass workflow ceremony](../bypass-workflow-ceremony.md).
