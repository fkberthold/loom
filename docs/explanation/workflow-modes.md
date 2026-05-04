# Workflow modes

> **Thesis.** Not every project wants the full workflow ceremony.
> Loom's three-mode triad (`full` / `light` / `off`) exists because a
> single boolean ("workflow on / workflow off") was insufficient and a
> per-step granularity ("disable hook X, keep skill Y") was excessive.
> Three modes is the smallest set that captures *visibility without
> blocking*, which is the use case a binary cannot express.

## What a single boolean got wrong

The natural first design was binary: workflow on, workflow off. On
fires hooks, runs the recipe, populates the status line, blocks
`bd close` without a captured drawer. Off does none of that.

The problem is the middle. There are projects where the recipe is
genuinely too heavy — a one-script utility repo, a personal scratch
project, an exploratory spike — but where the agent still benefits
from *seeing* what's happening (which bead is claimed, what stage
the recipe is in, whether `.beads/` is dirty before a push). Off
hides all of that. On forces ceremony that doesn't fit the project.

A binary cannot say "show me the state but don't block on it." That
is what `light` is for.

## The three modes

| Mode    | Hooks | Skills | Status line | Use case |
|---------|-------|--------|-------------|----------|
| **full**  | all fire | recipe runs | populated | Active project, want all the discipline |
| **light** | informational only (close-capture never blocks) | recipe runs with reduced ceremony + warning | populated | Project where the recipe is too heavy but you want the visibility |
| **off**   | silent | recipe refuses; session-startup skipped | empty | Quick edits, exploratory spikes, projects where the workflow doesn't fit |

The exact resolution rules and CLI for setting modes live in
[Reference: installed files](../reference/installed-files.md) and
the per-project [how-to](../how-to/index.md) on switching modes.

## Why ask-once-and-remember

Loom asks the user to pick a mode the first time it sees an
unconfigured beads workspace. The choice is written to
`<project>/.claude/workflow.json` and remembered for future sessions.
The alternative — prompting every session — was rejected for two
reasons.

First, the question is *project-shaped*, not session-shaped. The
right answer depends on what the project is, not what the agent is
doing today. A scratch project should be `off` always; an active
production codebase should be `full` always. Asking every session
treats the question as if the answer changes, which is wrong.

Second, prompts that fire every session train the user to dismiss
them without reading. A prompt that fires once gets attention.

## Why state lives in two files

Loom v1.5 introduced two related per-project files:

- `<project>/.claude/workflow.json` — committed to git. Holds the
  *policy* (`{"v":1, "mode":"full"}`). Project-shaped, not
  session-shaped.
- `<project>/.claude/workflow-state.json` — gitignored. Holds the
  per-session *state* (current activity, current bead, current
  recipe stage, last-updated timestamp). Session-shaped.

Splitting policy from state was deliberate. A committed mode lets
collaborators inherit the project's choice without re-answering the
prompt. A gitignored state file means session ephemera doesn't
leak into commits, doesn't trigger merge conflicts, and doesn't
need to survive a session boundary.

The state file is updated continuously by hooks (which write `claim`
and `close` reliably) and by skills (which update intermediate
stages on a best-effort basis). The status line reads both files
and prints a one-line summary so staleness is visible. If
`workflow-state.json` is from yesterday, the status line shows it,
and the agent can decide whether to clear it.

## Why hooks are mode-aware, not mode-conditional

Each hook checks the resolved mode internally rather than being
registered conditionally in `settings.json`. The reason is that
`settings.json` is user-machine-specific and cannot be changed
per-project. If hook registration were per-project, switching modes
would require editing the global settings file, which defeats the
purpose of a per-project policy.

Hooks therefore live in one place (registered in `settings.json`)
and resolve their own mode at fire-time. This makes the mode
*tunable* without the registration ceremony.

It also enables a useful failure mode: if `workflow.json` is missing
or malformed, hooks default to `full`. The conservative default is
on. A broken config does not silently disable the discipline.

## What was considered and rejected

- **Two modes (`on` / `off`).** The original design. Rejected
  because the middle case — visibility without blocking — is real
  and frequent and a binary cannot express it.
- **Per-hook toggles.** Considered: let users disable individual
  hooks (`bd-close-capture` off, `bd-claim-research` on). Rejected
  because the toggles are too fine-grained — the user has to
  understand each hook to set them, which inverts loom's
  "discipline lives in the primitives" rule (if the user has to
  curate, the primitives are no longer enforcing).
- **Mode as a session env var only.** Considered: `CLAUDE_WORKFLOW_MODE=light`
  per session, no committed state. Rejected because it doesn't
  survive a `/clear` and doesn't propagate to collaborators. The
  env var still exists as a session-scoped escape hatch
  (`CLAUDE_WORKFLOW_OFF=1`), but it is the bypass, not the policy.
- **Mode auto-detected from project shape.** Considered: detect
  whether the project has a `.beads/`, a CI config, a test suite —
  use those to infer mode. Rejected because the inference is
  unreliable and surprising. A project with `.beads/` could still
  reasonably be `light` (it's a scratch repo with a beads tracker)
  and a project without `.beads/` could reasonably be `full`
  (someone's about to add it). Asking is faster than guessing.

## How this connects to the rest of loom

Workflow modes are downstream of the [mental model](./mental-model.md):
*the discipline can't be skipped because the primitives enforce it.*
Modes are the volume knob on that enforcement. They do not change
*what* the discipline is — they change *how forcefully* it is
applied.

They are also downstream of the [recipe family](./recipe-family.md):
each recipe runs in its current mode. A bugfix in `light` mode is
still a bugfix; the M4 review-against-code step in docs-a-bead is
still non-negotiable in `light`. Modes affect ceremony around the
recipe, not the recipe's central inversion.

For the exact semantics of each mode (what each hook does in each
mode, what `light` actually relaxes), see
[Reference: hooks](../reference/hooks/index.md). For the operational
how-to of switching modes per-project, see the
[How-to quadrant](../how-to/index.md).
