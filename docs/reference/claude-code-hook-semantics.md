# Claude Code hook semantics & harness reminders

> A curated anchor for *when* each Claude Code hook event fires and
> what the harness itself emits unprompted. Loom hooks register against
> these events; agents reason about their timing. The authority for
> both is the Claude Code harness — not loom — so this page records the
> behaviour loom has observed and depends on, and names the harness
> behaviours that are easy to misattribute to loom.

## What this page is (and is not)

This page documents hook **event semantics and timing** plus two
**harness-originated system-reminders** that look like they might come
from loom but do not. It exists because agents have repeatedly operated
on a stale or incomplete mental model of the harness — confidently
asserting the wrong firing condition for a hook event, or asking
whether a system-reminder was loom's doing.

It is a sibling of, not a duplicate of,
[Claude Code hook layering](claude-code-hook-layering.md): that page
covers how registrations from the four config layers **merge**
(additive union, never override); this page covers when the events
those registrations bind to actually **fire**, and the harness reminders
that are unrelated to any registration. Consult layering for "why does
my hook fire three times"; consult this page for "when does the Stop
hook fire at all."

Hook configuration and event names are owned by the Claude Code
harness. The primary documentation is
[code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks);
where this page and the upstream docs disagree, the upstream docs win
on the contract and this page should be corrected.

## Hook event timing

Each row is the firing condition loom registers against. The Stop /
SessionEnd caveat below the table is the one most likely to be
mis-asserted.

| Event | Fires when | Loom uses it for |
|---|---|---|
| `SessionStart` | A session begins (fresh start, resume, or clear). | `bd prime`, session-startup priming, active-exploration scan. |
| `UserPromptSubmit` | The user submits a prompt, before the model sees it. | Context injection / prompt-time nudges. |
| `PreToolUse` | Immediately **before** a tool call executes; can **block** the call (exit 2). | The guard family — `edit-write-pwd-guard`, `cwd-drift-guard`, `bd-worktree-preseed`, `constitution-enforce`, `context-budget-sensor`. |
| `PostToolUse` | Immediately **after** a tool call returns; cannot block (the call already ran). | `bd-close-capture` and other post-action capture. |
| `PreCompact` | Before the harness compacts the transcript. | Pre-compaction checkpointing. |
| `Stop` | The main agent's turn **finishes responding** (it has nothing more to say). | (Avoided for telemetry — see caveat.) |
| `SessionEnd` | The session **terminates** (e.g. `/exit`, clear, or close). | Session teardown. |

### Stop fires per response-turn, not at shutdown

A recurring mis-assertion (surfaced liza-base f9, 2026-05-18): the
`Stop` hook is **not** "the hook that fires when Claude is shut down
with `/exit`." `Stop` fires every time the **main agent finishes a
response turn** — i.e. each time it stops generating and yields control
back to the user. Session *shutdown* is `SessionEnd`. Treating `Stop`
as a shutdown signal leads to logic that fires on every turn instead of
once at the end.

### Stop / SessionEnd do NOT reliably fire on sidechains

**Caveat (loom-0ahj D7, codified by loom-z3m.9).** `Stop` and
`SessionEnd` do **not** reliably fire inside sidechains — the subagent
turns spawned by Task-tool dispatch (e.g. dispatched workers, design-
cycle research rounds). A hook bound to `Stop` will fire for the main
agent's turns but cannot be relied on to fire for a sidechain's turns.

The practical consequence: **do not build per-turn or per-sidechain
telemetry on a `Stop` hook.** This is exactly why loom's context-budget
sensor (loom-z3m.9) is a `PreToolUse` hook reading accumulated-context
tokens off the transcript via the `loom-stage-spend` reader mechanism,
rather than a `Stop` hook — `PreToolUse` fires dependably in both the
main thread and sidechains, so the sensor sees the whole session's
context pressure. Any future "measure each turn / each worker" need
should follow the same pattern: read telemetry on a dependable
`PreToolUse`/`PostToolUse` boundary, not on `Stop`.

## Harness reminders that are NOT loom

The Claude Code harness injects `system-reminder` messages of its own,
independent of any loom hook or skill. Two are easy to misattribute to
loom; both can be ignored in a loom project.

### The "consider using TodoWrite" / TaskCreate reminder

**Origin: the harness, not loom** (surfaced liza-base f8, 2026-05-17 —
the user asked "is that coming from Loom or something else in Claude?").
Claude Code periodically emits a `system-reminder` suggesting the
`TodoWrite` / `TaskCreate` tool for tracking progress. This is a
built-in harness nudge; loom neither emits it nor can suppress it from
the loom side.

**In a loom project, ignore it silently.** Loom's tracker is **bd
(beads)** — every task, plan item, and follow-up lives in `bd`, never
in `TodoWrite`/`TaskCreate` or a markdown TODO list (see the "Use `bd`
for ALL task tracking" rule in the project `CLAUDE.md`). When the
reminder appears, do not call `TodoWrite`/`TaskCreate` and do not
narrate the reminder to the user — just continue with `bd`.

> `/audit-project` installs a short "ignore the TaskCreate reminder; bd
> is the tracker" snippet into a project's `CLAUDE.md` when bd is the
> chosen tracker, so the instruction travels with the project.

### Why agents misattribute it

The reminder reads like an instruction from the local configuration, so
an agent (or user) reasonably wonders whether loom installed it. It did
not. The signal that something is loom-originated is that it traces to a
file in this repo — a hook in `hooks/`, a skill in `skills/`, a rule in
`.claude/rules/`, or a `settings` snippet. A bare `system-reminder` with
no such trace is the harness talking. When in doubt, the harness docs
(linked above) enumerate the reminders the harness itself emits.

## Lineage

- Surfaced by the loom-z3m retrospective dig: liza-base f9 (wrong
  `Stop`-hook timing asserted confidently) and f8 (TaskCreate-reminder
  noise — "is this coming from loom?").
- Stop/SessionEnd sidechain caveat: loom-0ahj D7, codified into the
  context-budget sensor by loom-z3m.9 (PreToolUse, not Stop).
- Companion page on registration merge semantics:
  [Claude Code hook layering](claude-code-hook-layering.md) (loom-jnn).
- Primary harness authority:
  [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks).
