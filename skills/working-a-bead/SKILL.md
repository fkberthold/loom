---
name: working-a-bead
description: Use when claiming a beads issue and starting implementation work. Establishes the canonical sequence from claim to merged with explicit skill invocations at each step. Triggers on phrases like "let's work on <bead-id>", "claim <bead-id>", or right after the session-startup skill picks a bead.
disable-model-invocation: true
---

# Working a Bead — End-to-End Workflow

The project CLAUDE.md tells you to use beads for tracking, beadpowers
for brainstorming-to-beads, and superpowers:using-git-worktrees for
isolation — but doesn't connect them into a sequence. This skill is the
connection. It codifies the ladder that worked on the 2026-05-02
deploy-day cleanup (t92 / 0qw / bi2) and names the dormant skills that
should fire at specific moments.

`disable-model-invocation: true` means this skill only runs when
explicitly invoked (via `/working-a-bead <bead-id>` slash command or
direct user request). The recipe is opinionated; running it on every
bug fix would be heavyweight.

## When to use

Right after `session-startup` picks a bead, OR whenever you start
implementation on a claimed bead. Each step in the sequence below
maps to a specific skill or command — invoke them in order.

## Workflow modes (v1.5)

This skill respects three workflow modes resolved from
`<project>/.claude/workflow.json` `.mode` (env `CLAUDE_WORKFLOW_OFF=1`
forces `off`). Check the resolved mode before claiming via
`~/.claude/scripts/workflow-state mode`:

- **full** — run the recipe as written. Default behavior.
- **light** — run the recipe but emit a one-line warning to the user
  ("workflow mode is light; recipe ceremony reduced — TDD/review
  optional, drawer-capture still recommended"). Don't refuse work.
- **off** — REFUSE. Print: "workflow mode is off; the recipe skill is
  disabled for this project. Bypass via `CLAUDE_WORKFLOW_OFF=0` env or
  edit `<project>/.claude/workflow.json`. To work the bead anyway,
  drive it manually." Stop.

The bd-claim-research hook auto-skips in light/off modes; the
bd-close-capture hook never blocks in light/off. The status line
suppresses output entirely in off.

## Stage updates (v1.5 best-effort)

The shared state file at `<project>/.claude/workflow-state.json`
exposes recipe progress to the status line. Hooks reliably write
`stage=claim` (on bd update --claim) and `stage=close` (on bd close).
You should write the intermediate stages as work progresses — these
are best-effort, not enforced:

```bash
~/.claude/scripts/workflow-state set stage=<stage>
```

Stage map per recipe step:

| Step | Stage to write |
|---|---|
| After step 1 (MemPalace search) | `research` |
| After step 4 (RED test pasted) | `tdd-red` |
| After step 5 (GREEN — instance test passes) | `tdd-green` |
| After step 7 (full suite green) | `verify` |
| After step 9 (per-task code review) | `review` |
| After step 11 (commit) | `commit` |
| At step 14 (drawer + KG capture) | `wrap-up` |

Compliance is imperfect; the `updated` timestamp on the status line
makes staleness visible. v2 activity-shaped recipes (epic
`hundred-acre-woods-bng`) will mandate these writes at structured
checkpoints.

## Skip when

- Trivial fix (≤ 1-line, well-understood). Steps 4 (worktree) and 12
  (finishing-a-development-branch) skipped; everything else still
  applies (TDD discipline scales down).
- Pure spike or exploratory work. Use `superpowers:brainstorming`
  (or `beadpowers:brainstorming`) until the spike yields a concrete
  bead, then re-engage this recipe.
- Mid-task interruption. This skill is for new bead starts, not for
  context recovery within a bead.

## The Ladder (visual)

```
                bead chosen (from session-startup)
                            ↓
            [1. MemPalace bug-family search]
            mempalace_search + kg_query + bd memories
                            ↓
            superpowers:brainstorming         ← if bead lacks design
            or beadpowers:brainstorming         (beadpowers when output
                            ↓                    is beads; superpowers
                                                 when output is docs/)
            superpowers:writing-plans         ← if multi-task implementation
                            ↓
            [2. bd update --claim]
                            ↓
            superpowers:using-git-worktrees   ← isolation per bead
                            ↓
            superpowers:systematic-debugging  ← Phase 1 read code (bugs)
                            ↓
            superpowers:test-driven-development  ← RED first, then GREEN
                            ↓
            [bug-class coverage test (Frank's deploy-day rule)]
                            ↓
            [full pytest — find tests that enshrined the bug]
                            ↓
            superpowers:subagent-driven-development  ← if multiple
                            ↓                          independent tasks
                                                       in same session
            superpowers:requesting-code-review  ← per task, not per epic
                            ↓
            superpowers:verification-before-completion  ← evidence
                            ↓
            [git commit on frank/<bead> branch]
                            ↓
            superpowers:finishing-a-development-branch  ← merge/PR/cleanup
                            ↓
            [bd preflight + bd close + bd dolt push + git push]
                            ↓
            [MemPalace decision drawer + KG triples + diary entry]
```

## The Sequence (numbered)

1. **Search MemPalace for the bug family.** BEFORE claiming, search
   for prior decision drawers that share the bug's shape. This is the
   step most often skipped — and the step that on 2026-05-02 caught
   the huu.15.2 lineage that reshaped the 0qw fix mid-design. Concrete
   query patterns:
   - Classifier/validator/prompt convention bugs:
     `mempalace_search "classifier validator demotion <symptom>"` +
     `mempalace_kg_query("<entity-name>")` for any entity in the bead.
   - Schema/migration: `<area> migration decision`.
   - Voice/prompt drift: `prompt convention <signal>`.
   - Project tribal knowledge: `bd memories <keyword>`.
   If a sibling fix exists, restate the design in terms of that
   lineage BEFORE writing code or tests.

2. **Claim and isolate.** `bd update <id> --claim`, then invoke
   `superpowers:using-git-worktrees` to create `.worktrees/<bead>` on
   `frank/<bead>` branch from `main`. One bead = one worktree =
   one branch.

3. **Phase 1 — verify the bug's read.** Invoke
   `superpowers:systematic-debugging`. Read the actual code paths the
   bead names. Confirm or correct the bead's hypothesis BEFORE writing
   any fix code. Bug fixes drift from filing date to claim date.

4. **TDD — RED first.** Invoke
   `superpowers:test-driven-development`. Write the failing test that
   reproduces the symptom (verbatim string from a transcript where
   possible — those make the most stable regression tests). Run it,
   watch it fail with the expected message, paste the failure to
   user-facing output before any implementation lands.

5. **GREEN — minimal fix.** Smallest change that makes the test pass.
   Re-run just the new test to confirm GREEN.

6. **Bug-class coverage.** Add a second test exercising the bug
   *class*, not just the instance. For convention-mismatch bugs:
   parameterize over every value in the affected set. For state
   machines: unit-test the machine in isolation. Frank's durable rule
   from 13p.3.11 deploy day: *"write a test for the bug AND for the
   bug class."*

7. **Full suite — find tests that enshrined the bug.** Run the full
   test suite. Failures here are usually tests that locked in the
   buggy contract — update them, don't work around them. The 0qw fix
   surfaced 14 such tests; each was evidence the workaround had
   spread.

8. **(Multi-task only) Delegate via subagent-driven-development.**
   When the plan contains multiple independent tasks, invoke
   `superpowers:subagent-driven-development`. Fresh subagent per task,
   automatic two-stage review (spec compliance, then code quality)
   between tasks. This is the same-session alternative to
   `executing-plans` (which expects async review checkpoints).

9. **(Per task) Code review.** Invoke
   `superpowers:requesting-code-review` after each task — not at
   end-of-implementation. Catches issues task-by-task before they
   compound.

10. **Verification before completion.** Invoke
    `superpowers:verification-before-completion`. Re-run full suite
    from a clean shell, confirm exact counts, check
    `git diff --stat` matches intended scope. State results with
    evidence in user-facing output.

11. **Commit on the branch.** Descriptive subject + body that names
    symptom, root cause, fix, test counts, bug-family lineage if
    applicable. Co-author trailer.

12. **Finish the branch.** Invoke
    `superpowers:finishing-a-development-branch`. Presents the four
    options (merge locally / push & PR / keep branch / discard) and
    handles cleanup correctly per option. For batched multi-bead
    sessions: merge sequentially in dependency order, run full
    suite once after all merges, fix any cross-branch collateral
    in a single follow-up commit.

13. **Preflight + close + push.**
    `bd preflight` (PR-readiness checks) →
    `bd close <id1> <id2> ... --reason="..."` →
    `bd dolt push` →
    `git push` →
    verify `git status` shows "up to date with origin".

14. **Capture the decision in MemPalace.** For each closed bead,
    file a decision drawer in the project's `decisions` room with:
    symptom, root cause, options-considered + which-chosen + why,
    bug-family lineage, verification at decision time. For
    convention-or-design-family bugs, add KG triples
    (`subject → predicate → object`) so future sessions see the
    family on the next step-1 search. Optional: `bd remember "<one-line
    insight>"` for project tribal knowledge that should auto-inject at
    `bd prime` time. Boundary (per 2026-05-02 decision): one-line
    tribal facts → `bd remember`; multi-paragraph decisions →
    MemPalace drawer.

## Decision: parallel vs sequential

Use `superpowers:dispatching-parallel-agents` when 2+ beads have
independent root causes (different code paths, no shared state). The
2026-05-02 t92/0qw/bi2 session was a textbook missed case: three
unrelated bugs, fixed sequentially, when each could have been a
parallel agent. Trigger: `bd ready` shows multiple unblocked bugs that
touch disjoint files.

Stay sequential when beads share files, when a fix on one depends on
another, or when the fix needs interactive judgment per step.

## Choosing brainstorming variant

- **`beadpowers:brainstorming`** — when the design will land as
  beads (epics + tasks). Refuses to write `docs/plans/` files.
- **`superpowers:brainstorming`** — when the design will land as a
  spec or plan in `docs/`.

For HAW: bead work uses beadpowers; architectural specs use
superpowers (they go in `docs/`).

## Skill cheatsheet — when each fires

| Skill | Fires at | Replaces |
|---|---|---|
| `superpowers:writing-plans` | step 1.5, before any multi-task feature | implicit mental plans |
| `superpowers:subagent-driven-development` | step 8, multiple independent tasks | manual sequential execution |
| `superpowers:requesting-code-review` | step 9, per task | self-review at end |
| `superpowers:dispatching-parallel-agents` | session-level, 2+ independent beads | sequential bead-by-bead |
| `superpowers:finishing-a-development-branch` | step 12 | manual merge/PR commands |

## Failure modes (concrete examples)

- **Skip step 1 (MemPalace search):** design lands without seeing
  prior art; fix is non-canonical and requires rework when reviewer
  spots the lineage. Caught on 2026-05-02 by Frank's "are you using
  MemPalace fully?" question. The 0qw fix design pivoted from
  defensive coercion to convention alignment after the search
  surfaced huu.15.2.
- **Skip step 6 (bug-class coverage):** fix passes the test you wrote
  but the same class of bug returns 6 weeks later in a different
  symptom. Caught repeatedly in the huu.7.1 / huu.15.2 / huu.19.3 /
  0qw family.
- **Skip step 7 (full suite to find enshrined tests):** legacy tests
  silently keep passing because they pin the buggy contract; bug
  reappears under different conditions. Caught on 0qw via 14 such
  tests surfaced after the fix.
- **Skip step 14 (MemPalace capture):** the next session repeats the
  research from scratch; the bug-family lineage stays implicit.

## Related infrastructure

This skill is part of the workflow-infrastructure plan locked
2026-05-02. Full design + decisions live in the MemPalace drawer
"WORKFLOW INFRASTRUCTURE PLAN" (hundred_acre_woods/decisions room).
Build queue tracked under beads epic
`hundred-acre-woods-2st`. Slash commands `/working-a-bead`,
`/lineage`, `/wrap-up` and three custom subagents
(`bug-family-researcher`, `drawer-author`,
`kg-relationship-extractor`) are companion builds.
