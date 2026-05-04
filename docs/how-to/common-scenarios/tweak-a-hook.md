# I need to tweak a hook

To change a hook's behavior and verify the change before relying on
it, follow these steps.

## Precondition

- You know which hook you are editing
  (see [Where to update what](../where-to-update-what.md)).
- The hook is one of the loom-installed hooks under
  `~/.claude/hooks/`.

## Steps

1. **Edit the script.** Open the hook at `~/.claude/hooks/<name>.sh`
   (or the equivalent path in `~/repos/loom/hooks/`; the two are
   symlinked).

2. **Edit the registration if the matcher changed.** Hook
   registration lives in `~/.claude/settings.json` under
   `hooks.PreToolUse[matcher=Bash]` (and `hooks.SessionStart` for
   session hooks). If you changed which command the hook fires on,
   update the matcher pattern there.

3. **Smoke-test the script.** Pipe a synthetic event in and check
   the exit code:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"bd close foo"}}' \
     | bash ~/.claude/hooks/<name>.sh
   echo "EXIT: $?"
   ```
   Exit 0 = passed. Exit 2 = blocked. Any other exit = script error.

4. **Test mode-gated behavior.** If the hook reads workflow mode,
   run the smoke test once in each mode by setting the project's
   `.claude/workflow.json` (or `CLAUDE_WORKFLOW_OFF=1`).

5. **Confirm in a fresh session.** Settings hot-reload is
   unverified — `/clear` (or restart the session) and exercise the
   real command path that fires the hook.

## Outcome

The hook fires (or stays silent) as intended, in each mode, and the
smoke-test path documents the expected exit codes.

## Related

- For each hook's purpose and mode behavior, see
  [reference: hooks](../../reference/hooks/index.md).
- For why hooks (rather than skills) own deterministic guardrails,
  see [explanation: mental model](../../explanation/mental-model.md).
