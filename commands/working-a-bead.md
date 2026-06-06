---
description: "Router for the activity-shaped recipes. Takes a bead-id (and optional --recipe=<name> override), runs `bd show`, scores by bead.type + description heuristics, and dispatches to the matching `<activity>-a-bead` recipe. On ambiguity (2+ recipes tied at top score), lists candidates with a one-line 'because' for each and prompts the user to pick or re-invoke with --recipe=<name>. Direct invocation of a specific recipe (`/bugfix-a-bead`, `/feature-a-bead`, etc.) still works and bypasses the router."
disable-model-invocation: true
---

You are the **/working-a-bead router**. Pick the right activity recipe
for the user's bead, then dispatch.

## Step 1 — Resolve the bead

Parse the slash-command argument. Two cases:

- **Bead-id given** (e.g., `/working-a-bead loom-foo`): treat that as
  the chosen bead. Continue to Step 2.
- **No argument**: run `bd ready` and surface the top of the queue.
  Before confirming a single bead, run `scripts/loom-fanout-detect`
  (the fan-out detector). If it emits a wave of ≥2 independent ready
  beads (no dep edge between them + disjoint `Files:`), propose
  parallelizing them as the **default** —
  "loom-X / loom-Y / loom-Z are independent — dispatch N parallel
  workers? [y / edit / serial]" — handing `y` off to
  `superpowers:dispatching-parallel-agents`. On `serial` (or if the
  detector emits no wave), confirm with the user which single bead to
  work BEFORE dispatching, then re-enter Step 2 with the chosen
  bead-id. The detector is a proposal, never an auto-dispatch; if it's
  absent or errors, skip silently and fall back to the single-bead
  flow. (See session-startup SKILL.md step 6a for the full contract.)

Optional second argument: `--recipe=<name>` (where `<name>` is one of
`bugfix`, `feature`, `refactor`, `research`, `cleanup`, `docs`).
If present, **skip Step 3 entirely** and dispatch directly to the
named recipe (Step 4). The override exists for cases where the user
disagrees with the router's pick or where the bead's text is
genuinely ambiguous.

## Step 2 — Inspect the bead

Run `bd show <id>` (and optionally `bd show <id> --json` if you need
to parse the type field cleanly). Capture:

- `type` (one of `bug`, `feature`, `task`, `epic`)
- `status` — if already `closed`, warn and ask whether to reopen
  before proceeding. If `blocked`, list the blockers and ask whether
  to proceed anyway.
- `title` and `description` — the keyword-match surface for tasks.

If `bd show` fails (bead doesn't exist), tell the user and stop.

## Step 3 — Score against the six recipes

Apply rules in order; first match wins (except `task` which uses the
keyword-scoring sub-routine below):

| `bead.type` | Recipe |
|---|---|
| `bug` | `bugfix-a-bead` |
| `feature` | `feature-a-bead` |
| `epic` | **no recipe** — see "Epic case" below |
| `task` | run keyword-scoring on title + description |

### Keyword scoring (for `type=task`)

Score each recipe by counting keyword matches in the bead's title
plus description. Keyword sets:

- **refactor-a-bead**: `refactor`, `extract`, `rename`, `consolidate`,
  `restructure`, `decompose`, `split` (when followed by "into" or
  "across"), `move` (file/module/package)
- **cleanup-a-bead**: `remove`, `delete`, `drop` (a dep / a file / a
  feature), `rip out`, `retire`, `deprecate`, `prune`, `unused`,
  `orphan`, `dead code`
- **docs-a-bead**: `document`, `docs`, `documentation`, `guide`,
  `README`, `walkthrough`, `tutorial`, `explainer`, `manual`
- **research-a-bead**: `research`, `investigate`, `what do we know`,
  `find out`, `survey`, `audit` (the codebase, not the project),
  `explore` (a question, not a directory)

Determine the winner:

- **One recipe scores strictly higher than all others** → dispatch to it.
- **Zero recipes scored** (no keywords matched) → fallback to
  `bugfix-a-bead`. The bead title is probably a symptom-style
  description ("X is broken", "Y returns wrong value"), which is
  bug-shaped by default.
- **Two or more recipes tied at the top** → ambiguity case (see below).

### Ambiguity case

Surface a numbered list of the tied candidates, each with a one-line
"because" naming the matched keywords. Example:

```
Bead loom-foo (task) matches two recipes equally:
  1. refactor-a-bead — matched: "refactor", "extract"
  2. cleanup-a-bead — matched: "remove", "deprecated"

Pick a number, or re-invoke with `--recipe=<name>`.
```

Wait for the user's pick before dispatching. Do **not** guess.

### Epic case

Epics are containers, not work units. If `bead.type=epic`, **do not
dispatch** to any recipe. Tell the user:

> `<bead-id>` is an epic. Epics don't get claimed directly; they hold
> child beads that do. Run `bd show <bead-id>` to see the children,
> then `/working-a-bead <child-id>` to route the actual work.

If the user really wants to plan or restructure the epic itself, they
should invoke `superpowers:brainstorming` (or `beadpowers:brainstorming`
if the output is more child beads) directly.

## Step 4 — Dispatch

Once a recipe is chosen, **invoke it via the Skill tool**:

```
Skill(<recipe>-a-bead)
```

The activity recipe takes over from there — it loads its own
SKILL.md content and walks its variable middle (M1→M5), citing
`bead-lifecycle-shell` for phases A/B/C/D. Pass the bead-id as
context in your invocation message so the recipe doesn't have to
re-resolve it.

If the user supplied `--recipe=<name>` at Step 1, dispatch to that
recipe verbatim — even if Step 3's scoring would have picked
something else.

## Step 5 — Hand off cleanly

After dispatching, the conversation belongs to the activity recipe.
The router's job is done. Don't continue narrating the recipe's
phases yourself; let the recipe's SKILL.md drive.

If the recipe's first action would be inappropriate (e.g., it wants
to claim a bead that's already closed), the recipe will surface that
itself and prompt for direction.

## Notes

- **Direct recipe invocation still works.** Users who already know
  which recipe they want can type `/bugfix-a-bead loom-foo` (or any
  sibling) and bypass the router. The router is the convenience
  layer, not a gate.
- **The router does not claim or modify the bead.** It only inspects
  (`bd show`) and dispatches. The recipe handles `bd update --claim`
  in its phase A2.
- **Workflow mode is honored downstream.** Each recipe checks
  `~/.claude/scripts/workflow-state mode` at phase A and refuses
  cleanly if mode is `off`. The router doesn't need to pre-check.
- **Skill auto-discovery is a backstop, not the primary path.** With
  `disable-model-invocation: true` removed from the recipe SKILL.mds
  (loom-7z1, 2026-05-03), the Skill tool can surface a recipe via
  description match. But the router's deterministic scoring is the
  intended dispatch path; auto-discovery is just a safety net for
  the case where the user described the work conversationally
  without typing a slash command.
