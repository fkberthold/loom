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

## Outcome

The misbehavior is either explained (mode resolution, hot-reload
caveat, known limitation) or filed as a tracked bead with
reproduction evidence.

## Related

- For each hook's mode-by-mode behavior, see
  [reference: hooks](../../reference/hooks/index.md).
- For when to bypass a misbehaving hook while waiting for a fix,
  see [Bypass workflow ceremony](../bypass-workflow-ceremony.md).
