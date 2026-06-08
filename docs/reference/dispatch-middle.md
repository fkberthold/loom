# dispatch-middle — reference

> Orchestrates a bead's variable middle as a test-author → implementer
> (→ optional verify) pipeline of INDEPENDENT subagents in ONE shared
> worktree, so the central session invokes once and writes nothing —
> no test, no line of code, no accumulated junk context.

`/dispatch-middle <bead>` runs the within-bead RED→GREEN cycle as a
two-stage subagent pipeline. The **test-author** receives only the
locked CONTRACT (the bead's `RED:` line, an M1 spec, or an acceptance
criterion) plus the interface under test; it writes the RED test,
commits it, and returns the failure output. The **implementer** runs in
the SAME worktree, inherits the committed RED test **as an artifact** —
it never sees the test-author's reasoning — and makes the minimal change
that turns it GREEN. Because the two roles are different agents and the
implementer cannot read the author's mind, the test-author == code-author
anti-pattern is solved by construction: the implementation can only
satisfy the public artifact, not a private intent.

This is the **pull half** of loom's dispatch posture. The
`dispatch-nudge` hook (loom-yb5) is the **push** — it pressures central
toward dispatch. The push alone wasn't enough because dispatching used
to mean write-a-brief + wait + verify + merge (high friction), so
central kept defaulting to inline. `/dispatch-middle` is the
friction-inversion lever: one invocation runs the whole middle, making
the right thing the easy thing so the behavior flips on its own.

The **inline exception** still applies — a genuinely trivial change
(≤ ~15 lines, one non-test file, no new test) is waved through inline
without a pipeline; see the "Dispatch discipline" section of
`bead-lifecycle-shell`. There is no skip env var: dispatch-middle is a
skill invoked by choice, not a hook that fires automatically, so it is
declined by simply not invoking it. (The `dispatch-nudge` *hook* that
points at it can be suppressed with `LOOM_DISPATCH_NUDGE_SKIP` — that is
the push side, documented with the env-var catalogue, not this skill.)

Central — and only central — does the cwd-sensitive, bd-authoritative
integration (verify + merge + close + capture) after the pipeline hands
back its summary; the pipeline never integrates.

## Related

| Item | Page |
|---|---|
| Across-bead parallelism (the push + fan-out detector) | [helper-scripts](helper-scripts.md) (`loom-fanout-detect`) |
| The design phase that emits the `RED:` contract this consumes | [design-a-cycle](design-a-cycle.md) |
| Lifecycle shell (claim / verify / merge / close / capture) | [All skills](skills/all-skills.md) |
| Worker-side worktree discipline | `.claude/rules/dispatched-agents.md` |
| Environment variables | [loom env vars](loom-env-vars.md) |

## Skill source

The full pipeline body is included verbatim below from
`skills/dispatch-middle/SKILL.md`. Edits go to the primitive, not this
page.

{%
  include-markdown "../../skills/dispatch-middle/SKILL.md"
  heading-offset=1
%}
