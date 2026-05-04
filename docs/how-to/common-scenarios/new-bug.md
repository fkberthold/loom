# I just got assigned a new bug

To take a freshly-assigned bug bead from claim to merged, follow
these steps.

## Precondition

- A bead of `type=bug` is assigned to you and unblocked.
- You are inside the project's workspace.

## Steps

1. **Prime the session.** Run `/session-startup` if you have not
   already (see [Open a session](../open-a-session.md)).

2. **Read the bead.** Run `bd show <bead-id>` to absorb the symptom,
   any reproduction notes, and the user's hypothesis (if any).

3. **Claim and dispatch.** Type `/working-a-bead <bead-id>`. The
   router routes a `type=bug` bead to the `bugfix-a-bead` recipe.
   Equivalent direct entry point: `/bugfix-a-bead <bead-id>`.

4. **Let the family-research subagent fire.** The
   `bd update --claim` PreToolUse hook reminds the agent to dispatch
   `bug-family-researcher`. Wait for the prior-art report; it surfaces
   sibling bugs, prior fixes, and known patterns.

5. **Run the recipe's M-steps.** The bug-shaped middle: systematic
   debugging → RED test pinning the symptom → minimal GREEN fix →
   bug-class coverage → enshrined-test sweep.

6. **Wrap up.** When the suite is green and the diff is the intended
   scope, follow [Finish a bead](../finish-a-bead.md).

## Outcome

The bug is fixed, the fix is captured as a decision drawer + KG
triples, the bead is closed, and the branch is pushed. Most bugs
finish in 1–3 hours; some span sessions.

## Related

- For the family-researcher subagent's interface, see
  [reference: subagents](../../reference/subagents/index.md).
- For why TDD on bugs writes a RED test before any fix, see
  [explanation: workflow modes](../../explanation/workflow-modes.md).
