---
description: "Router for the activity-shaped recipes. Takes a bead-id (and optional --recipe=<name> override), runs `bd show`, scores by bead.type + description heuristics, and dispatches to the matching `<activity>-a-bead` recipe. On a keyword tie (2+ recipes level at top score), breaks the tie by reading the bead text against the tied recipes' definitions, dispatches, and says in one line which it picked and why (--recipe=<name> overrides). Direct invocation of a specific recipe (`/bugfix-a-bead`, `/feature-a-bead`, etc.) still works and bypasses the router."
disable-model-invocation: true
---

You are the **/working-a-bead router**. Pick the right activity recipe
for the user's bead, then dispatch.

## Step 1 — Resolve the bead

Parse the slash-command argument. Two cases:

- **Bead-id given** (e.g., `/working-a-bead loom-foo`): treat that as
  the chosen bead. Continue to Step 2.
- **No argument**: run `bd ready` and take the top of the queue.
  Before settling on a single bead, run `~/.claude/scripts/loom-fanout-detect`
  (the fan-out detector). If it emits a wave of ≥2 independent ready
  beads (no dep edge between them + disjoint `Files:`), dispatch that
  wave through `superpowers:dispatching-parallel-agents`, one worker
  per bead, then say in one line what you dispatched and what the wave
  assumed. If the detector emits no wave, take the top bead, name it,
  and re-enter Step 2 with it. Neither route waits for a go-ahead:
  both read from the tracker, and the line you print is what the user
  redirects against. If the detector is absent or errors, skip
  silently and fall back to the single-bead flow. (See session-startup
  SKILL.md step 6a for the full contract.)

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
- `status` — a `closed` or `blocked` bead gets its evidence read
  first (see below)
- `title` and `description` — the keyword-match surface for tasks.

If `bd show` fails (bead doesn't exist), tell the user and stop.

**A `closed` or `blocked` status is answerable by reading.** For a
closed bead, open the closing comment and the commits it names, then
decide whether they cover the work being asked for now. Reopen when
they don't, carry on when they do, and say which way you read it in
one line. A blocked bead works the same way: read each blocker, route
past the ones already satisfied, and stop on the first one that's
still real, naming it. Neither call needs the user, because `bd show`
and the log hold the whole answer (loom-42cw, D8).

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

A tie in the keyword count is not a tie in the bead. Read the title and
description against the tied recipes' own definitions and take the one
whose variable middle matches the work being asked for:

- **refactor-a-bead** restructures without changing behavior
- **cleanup-a-bead** removes something and hunts its orphan references
- **docs-a-bead** produces a tracked document
- **research-a-bead** answers a question and files findings

If the bead's text still doesn't separate them, take the recipe whose
keywords land in the title rather than only in the description. The
title is what the filer wrote to name the work.

Dispatch, then say what you took and why, in one line:

```
Bead loom-foo (task) tied on keywords between refactor-a-bead and
cleanup-a-bead. Routing to cleanup-a-bead: the bead removes the flag
and its call sites, and the restructuring is what's left behind.
Re-invoke with `--recipe=refactor` to override.
```

This doesn't stop to ask. Both inputs to the tie-break, the bead's own
text and the six recipe definitions, are already in front of you, so
there's nothing here the user knows that you don't (loom-42cw, D8).
The one-line note is what makes the override cheap (D9).

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

If the recipe's first action turns out to be wrong for this bead, the
recipe surfaces that itself. The router doesn't pre-empt it. Step 2
has already settled the closed-and-blocked cases by reading, so those
never reach the recipe as an open question.

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
