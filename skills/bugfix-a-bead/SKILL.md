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

**Dispatch posture — RED and GREEN are SEPARATE agents.** The
variable middle is dispatch territory, and its RED→GREEN core runs
through **`/dispatch-middle`** (loom-8crd / epic loom-5m94): the RED
test and the GREEN fix are authored by **two different, independent
dispatched agents** in one shared worktree — NOT one worker doing
both. This is the anti-tautology guarantee. When the same agent
writes the test and the fix, the test is shaped to match the
implementation that agent already has in mind, and the RED→GREEN
cycle verifies nothing. `/dispatch-middle` solves it by construction:
the implementer inherits the RED test as an **artifact** (a committed
file), never the test-author's reasoning. Do NOT Edit/Write in the
central session between bead-claim and bead-close.

The middle therefore splits into roles:
- **M1–M2** (verify the read + assumption audit) — diagnosis work.
  Run inline in central or as a short scout dispatch; this is *not*
  the RED→GREEN core, so it stays out of the `/dispatch-middle`
  pipeline.
- **M3 (RED)** — dispatch the **test-author** via `/dispatch-middle`.
  It writes the RED test from the bug's reproduction/contract
  (verbatim symptom string) and commits it; it does NOT implement.
- **M4 (GREEN)** — dispatch the **implementer** via the same
  `/dispatch-middle` pipeline, in the same worktree, **independent of
  the test-author** — it sees only the committed RED test file, never
  the author's reasoning. It makes the minimal GREEN change.
- **M5–M6** (bug-class coverage + enshrined sweep) — extend the test
  surface and sweep. Keep as the **implementer** for tightly-coupled
  bug-class tests, or hand to a **follow-on test-author** when the
  class coverage is a fresh contract worth independent authoring.

See `skills/dispatch-middle/SKILL.md` for the test-author and
implementer brief templates + central's sequence, and
`bead-lifecycle-shell` §Dispatch discipline for the allowed/forbidden
central-session actions while the pipeline runs, the re-dispatch
decision rule, and the full Phase A/B/C/D ownership table.

The M-steps below are **scope items for the dispatched briefs**, not
a to-do list for central. Preserve the discipline verbatim — RED
before GREEN, bug-class coverage, enshrined-test sweep — that's WHAT
each agent does, not WHO. Stage transitions named below are written
inside the worktree as each step begins; each agent's return summary
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

#### M3. TDD — RED first (dispatch the TEST-AUTHOR)

Dispatch the **test-author** via `/dispatch-middle` (the test-author
brief template lives in `skills/dispatch-middle/SKILL.md`). Its
contract slot is the bug's reproduction/contract — the verbatim
symptom string from the M1 diagnosis. The test-author sets stage
`tdd-red`, invokes `superpowers:test-driven-development`, writes the
failing test that reproduces the symptom (preferring a verbatim
string from a transcript or log line, since those make the most
stable regression tests), runs it to confirm RED, commits ONLY the
test, and returns the failure output verbatim as evidence that RED
preceded GREEN. It does NOT implement the fix.

#### M4. GREEN — minimal fix (dispatch the IMPLEMENTER, independent of the author)

Dispatch the **implementer** via the same `/dispatch-middle` pipeline,
in the same shared worktree so the committed RED test is on disk. The
implementer is a **different agent** that **never sees the
test-author's reasoning** — it inherits the RED test as an artifact
(the file), which is what makes the RED→GREEN cycle a real
verification rather than a tautology. It sets stage `tdd-green`,
reads the RED test, makes the smallest change that turns it green, and
re-runs just that test to confirm GREEN. It must NOT modify, weaken,
or skip the test; if the test looks wrong it STOPS and reports to
central rather than "fixing" the test itself. It resists cleaning up
adjacent code — keep the diff focused so the bug-fix lineage stays
legible. Pass/fail counts + the diff summary go in its return.

#### M5. Bug-class coverage

The implementer (or a follow-on test-author — see the dispatch
posture above) sets stage `bug-class` and adds a second test
exercising the bug *class*, not just the instance:
- For convention-mismatch bugs: parameterize over every value in the
  affected set.
- For state machines: unit-test the machine in isolation across each
  transition that could exhibit the same shape.
- For boundary bugs: test both sides of the boundary plus the
  on-boundary case.

Frank's durable rule from HAW 13p.3.11 deploy day: *"write a test for
the bug AND for the bug class."* The agent should name the class
shape in its return summary so central can confirm the coverage
matches the bug's family.

#### M6. Full suite — find tests that enshrined the bug

The implementer sets stage `enshrined-sweep` and runs the full test
suite. Failures here are usually tests that locked in the buggy
contract — **update them, don't work around them.** The 0qw fix
surfaced 14 such tests; each was evidence the workaround had spread.

If a previously-passing test now fails because it asserted the buggy
behavior, the implementer fixes the test to assert the correct
contract. If it can't tell whether a test was wrong or right, it
stops and escalates to central via its return summary rather than
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
