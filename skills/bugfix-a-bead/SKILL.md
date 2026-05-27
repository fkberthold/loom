---
name: bugfix-a-bead
description: Activity recipe for working a bug-shaped beads issue. Owns the bug-specific variable middle — systematic debugging → RED test → minimal GREEN fix → bug-class coverage → enshrined-test sweep. Defers to the bead-lifecycle-shell skill for claim/isolate/verify/close/capture. Triggers on phrases like "let's work on <bug-bead-id>", "fix <bead-id>", or right after the session-startup or /working-a-bead router picks a bug bead.
---

# Bugfix-a-Bead — Variable Middle for Bug-Shaped Beads

This skill owns ONLY the bug-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim + worktree,
verification, commit, finish-branch, close + capture — lives in the
`bead-lifecycle-shell` skill. This recipe cites those phases by letter
and supplies the variable middle that runs between phase A (pre-middle)
and phase B (verification).

It codifies the bug-fix middle that worked on the 2026-05-02 deploy-day
cleanup (HAW t92 / 0qw / bi2). The discipline is: verify the bug's
read BEFORE writing tests, RED the symptom verbatim, GREEN minimally,
cover the bug *class* not just the instance, and run the full suite to
surface tests that enshrined the buggy contract.

Invocation: explicit only — either directly (`/bugfix-a-bead <bead-id>`)
or via the `/working-a-bead` router that selects an activity recipe by
bead shape. The Skill tool may surface this recipe via auto-discovery
when a message strongly matches the trigger phrases above; if that
happens at the wrong moment (e.g., the bead isn't bug-shaped), decline
and switch to the right recipe.

## When to use

Right after `session-startup` (or the `/working-a-bead` router) picks a
bug-shaped bead, OR whenever you start implementation on a claimed bug.
Use the bug heuristic loosely: a bead is bug-shaped when it has a
reproducible failing symptom and you'd write a regression test for it.

## Skip when

- The bead is feature/refactor/research/cleanup/docs-shaped — use the
  matching activity recipe instead.
- Pure spike or exploratory debugging without a chosen fix yet — use
  `superpowers:systematic-debugging` directly until the diagnosis
  yields a concrete bead, then re-engage this recipe.
- Mid-task interruption. This recipe is for new bug-fix starts, not
  for context recovery within an in-flight bead.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written. RED
  before GREEN, bug-class coverage mandatory, full-suite sweep
  mandatory.
- **light** — RED-then-GREEN discipline still recommended, but
  bug-class coverage and the full-suite enshrined-test sweep become
  optional. The shell's warning covers the recipe-ceremony reduction;
  no separate warning here.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds activity-specific intermediate stages between phase A
and phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (verify bug's read) | `debugging` |
| Entering step M2 (bead-assumption audit) | `assumption-audit` |
| Entering step M3 (RED test) | `tdd-red` |
| Entering step M4 (GREEN fix) | `tdd-green` |
| Entering step M5 (bug-class coverage) | `bug-class` |
| Entering step M6 (full-suite sweep) | `enshrined-sweep` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>` at
the moment the step starts. The status line surfaces these so future
cold-start sessions can see exactly where work paused.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:
- **A1.** MemPalace search for the bug family (sets stage `research`).
  For bugs the query patterns are `mempalace_search "<symptom> <area>"`
  + `mempalace_kg_query("<entity-name>")` for any entity in the bead +
  `bd memories <keyword>` for tribal one-liners.
- **A2.** `bd update <id> --claim`, then optional worktree on
  `frank/<bead>` from `main`.

If the search surfaces a sibling fix (e.g., a prior bug in the same
family resolved via convention alignment), restate the design in terms
of that lineage BEFORE writing tests. The 2026-05-02 huu.15.2 → 0qw
pivot is the canonical example: defensive coercion → convention
alignment after the search caught the family.

### Variable middle — M1 → M6 (recipe owns the scope, worker owns the work)

**Dispatch posture.** The variable middle is worker territory. Brief
ONE worker via `Agent` + `isolation: "worktree"` covering M1 → M6 in
a single dispatch; do NOT Edit/Write in the central session between
bead-claim and bead-close. See `bead-lifecycle-shell` §Dispatch
discipline for the worker-brief template, the allowed/forbidden
central-session actions while the worker runs, the re-dispatch
decision rule, and the full Phase A/B/C/D ownership table.

The M-steps below are **scope items for the worker brief**, not a
to-do list for central. Translate each into one sentence in the
brief's Scope section (the template targets ≤ 250 words total).
Preserve the discipline verbatim — RED before GREEN, bug-class
coverage, enshrined-test sweep — that's WHAT the worker does, not
WHO does it. Stage transitions named below are written by the worker
inside the worktree as each step begins; the worker's return summary
should call them out so central can spot-check the lineage.

#### M1. Verify the bug's read

Have the worker set stage `debugging`, invoke
`superpowers:systematic-debugging`, and read the actual code paths
the bead names — confirming or correcting the bead's hypothesis
BEFORE writing any test or fix code. Bug fixes drift from filing
date to claim date; the bead's symptom may now reproduce differently
or come from a different layer. The worker should surface its
diagnosis in the return summary so central can compare against the
bead's stated cause.

#### M2. Bead-assumption audit

Have the worker set stage `assumption-audit` and, with M1's diagnosis
in hand, compare the root cause against the bead description's stated
cause before writing the RED test. If they materially diverge, the
worker runs `bd update <id> --description "<corrected framing>"`
(preferred — overwrites the stale framing); to preserve the original
hypothesis as history, `bd comment <id> "<correction>"` is the
minimum. Future sessions read the bead, not the transcript; stale
descriptions become load-bearing-but-wrong (HAW yho, 2026-05). The
worker's return summary should note any reframing so central can
review the new framing.

#### M3. TDD — RED first

Have the worker set stage `tdd-red`, invoke
`superpowers:test-driven-development`, and write the failing test
that reproduces the symptom — using a verbatim string from a
transcript or log line where possible, since those make the most
stable regression tests. The worker runs the test, watches it fail
with the expected message, and surfaces the failure output in its
return summary as evidence that RED preceded GREEN.

#### M4. GREEN — minimal fix

Have the worker set stage `tdd-green` and make the smallest change
that turns the test green, then re-run just the new test to confirm
GREEN. The worker should resist the urge to clean up adjacent code —
keep the diff focused so the bug-fix lineage stays legible. Pass/fail
counts and the diff summary go in the worker's return.

#### M5. Bug-class coverage

Have the worker set stage `bug-class` and add a second test
exercising the bug *class*, not just the instance:
- For convention-mismatch bugs: parameterize over every value in the
  affected set.
- For state machines: unit-test the machine in isolation across each
  transition that could exhibit the same shape.
- For boundary bugs: test both sides of the boundary plus the
  on-boundary case.

Frank's durable rule from HAW 13p.3.11 deploy day: *"write a test for
the bug AND for the bug class."* The worker should name the class
shape in its return summary so central can confirm the coverage
matches the bug's family.

#### M6. Full suite — find tests that enshrined the bug

Have the worker set stage `enshrined-sweep` and run the full test
suite. Failures here are usually tests that locked in the buggy
contract — **update them, don't work around them.** The 0qw fix
surfaced 14 such tests; each was evidence the workaround had spread.

If a previously-passing test now fails because it asserted the buggy
behavior, the worker fixes the test to assert the correct contract.
If the worker can't tell whether a test was wrong or right, it should
stop and escalate to central via its return summary rather than
silently weaken or skip the test — that's a stop-and-report trigger
in the brief.

### Phase B — verification (delegate to shell)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Re-run the full suite from a clean shell, confirm exact pass/fail
counts, check `git diff --stat` matches intended scope. State results
with evidence in user-facing output BEFORE moving to phase C.

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:
- **C1.** Code review (per task if multiple).
- **C2.** Commit on the branch (sets stage `commit`). Subject + body
  should name symptom, root cause, fix, test counts, family lineage
  if applicable. Co-author trailer.
- **C3.** `superpowers:finishing-a-development-branch` — pick from
  the four options (merge / push & PR / keep / discard).

### Phase D — closeout (delegate to shell)

Follow `bead-lifecycle-shell` phase D:
- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push` →
  `git push` (sets stage `close`).
- **D3.** Drawer + KG triples + diary capture (sets stage `wrap-up`).
  For convention-or-design-family bugs, the KG triples are load-
  bearing — they're what future phase A1 searches will surface.

## Choosing brainstorming variant (rare for bug fixes)

A bug fix occasionally reveals that the design itself is wrong, not
just the implementation. When that happens, pause this recipe at M1
and invoke:

- **`beadpowers:brainstorming`** — when the design will land as new
  beads (epics + tasks).
- **`superpowers:brainstorming`** — when the design will land as a
  spec or plan in `docs/`.

Resume bugfix-a-bead at M2 (assumption audit) once the design lands,
or hand off to `feature-a-bead` if the work is now feature-shaped.

## Failure modes (concrete)

- **Skip phase A1 (MemPalace search):** design lands without seeing
  prior art; fix is non-canonical and requires rework when reviewer
  spots the lineage. The 2026-05-02 0qw fix would have been defensive
  coercion (wrong) instead of convention alignment (right) had the
  search been skipped.
- **Skip M1 (verify the read):** RED test reproduces an old symptom
  while the actual current bug has shifted; GREEN fixes the wrong
  thing; the original symptom returns under different conditions.
- **Skip M2 (bead-assumption audit):** bead description's stated root
  cause stays stale even though M1 diagnosed something different;
  future sessions read the bead, take the stale framing as truth,
  and re-derive the wrong fix. HAW yho (2026-05) — filed as
  "validator gap" but actually a prompt-tightening fix; staleness
  caught only by user noticing mid-session.
- **Skip M5 (bug-class coverage):** fix passes the test you wrote but
  the same class of bug returns 6 weeks later in a different symptom.
  Repeated through the huu.7.1 / huu.15.2 / huu.19.3 / 0qw family
  before the rule was articulated.
- **Skip M6 (enshrined-test sweep):** legacy tests silently keep
  passing because they pin the buggy contract; bug reappears under
  different conditions. Caught on 0qw via 14 such tests surfaced
  after the fix.
- **Skip phase D3 (capture):** the next session repeats the research
  from scratch; the bug-family lineage stays implicit.

## Related infrastructure

This recipe is the v2 successor to the v1 `working-a-bead` skill,
narrowed to the bug-shaped variable middle. The cross-activity
lifecycle scaffolding lives in `bead-lifecycle-shell`. Sibling
activity recipes:

- `feature-a-bead` (loom-5rf) — feature-shaped middle
- `refactor-a-bead` (loom-uca) — characterization tests + restructure
- `research-a-bead` (loom-0q0) — define → search → synthesize → file
- `cleanup-a-bead` (loom-62x) — scope → remove → verify
- `docs-a-bead` (loom-s0n) — gap → draft → review

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + description heuristics.

Full design + locked decisions live in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02). Build queue tracked under loom epic `loom-0y6`.
