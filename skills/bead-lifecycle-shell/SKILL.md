---
name: bead-lifecycle-shell
description: Cross-activity lifecycle scaffolding for working a beads issue from claim to merged. Owns MemPalace bug-family search, claim, optional worktree, verification, commit, finishing-a-development-branch, preflight + close + push, and decision drawer + KG triples + diary capture. Each activity recipe (bugfix-a-bead, feature-a-bead, refactor-a-bead, research-a-bead, etc.) references the lettered phases below and supplies its own VARIABLE MIDDLE between phase B and phase C. Internal building block — invoked indirectly via an activity recipe, not directly by the user.
disable-model-invocation: true
---

# Bead Lifecycle Shell — Cross-Activity Scaffolding

The lifecycle steps that surround any bead work — search, claim,
isolate, verify, commit, close, capture — are the same regardless of
what activity sits in the middle. This skill owns those steps. Each
activity recipe (bugfix / feature / refactor / research / cleanup /
docs) references the phases here and only specifies its own VARIABLE
MIDDLE between phase B and phase C.

`disable-model-invocation: true` — the shell is an internal building
block. Activity recipes call into it by reference; the user never
invokes it directly. Triggering: an activity recipe (or the
`/working-a-bead` router that picks one) cites this skill in its body
and instructs you to follow specific phases.

## When to use

You are reading this because an activity recipe pointed you here. Run
the cited phase(s) verbatim, write the mandated stage transitions,
then return to the activity recipe to execute the variable middle.

## Skip when

An activity recipe MAY skip phase A2 (worktree) for trivial fixes (≤ 1
line, well-understood) or for user-global edits where there is no
project worktree to create (the jnd / bmi precedent). Activity recipes
MUST NOT skip phases A1 (MemPalace search) or D (capture); skipping
those breaks the cross-session memory loop the workflow is designed
around.

The shell is not used for spikes or pure exploratory work — those
should run `superpowers:brainstorming` (or `beadpowers:brainstorming`)
until they yield a concrete bead.

## Workflow modes (v1.5)

The shell respects three workflow modes resolved from
`<project>/.claude/workflow.json` `.mode` (env `CLAUDE_WORKFLOW_OFF=1`
forces `off`). Check the resolved mode at the START of phase A via
`~/.claude/scripts/workflow-state mode`:

- **full** — run every phase as written.
- **light** — emit a one-line warning (`workflow mode is light;
  recipe ceremony reduced — TDD/review optional, drawer-capture still
  recommended`), then continue. Phase D (capture) stays recommended,
  not mandatory.
- **off** — REFUSE. Print: `workflow mode is off; the recipe skill is
  disabled for this project. Bypass via CLAUDE_WORKFLOW_OFF=0 env or
  edit <project>/.claude/workflow.json. To work the bead anyway, drive
  it manually.` Stop.

The `bd-claim-research` hook auto-skips in light/off; the
`bd-close-capture` hook never blocks in light/off. The status line
suppresses output entirely in off.

## Stage updates (MANDATORY)

The shared state file at `<project>/.claude/workflow-state.json`
exposes recipe progress to the status line and to future cold-start
sessions. Stage writes are NOT optional in this shell — every phase
boundary below MUST call:

```bash
~/.claude/scripts/workflow-state set stage=<stage>
```

Hooks reliably write `stage=claim` (on `bd update --claim`) and
`stage=close` (on `bd close`). Every other stage transition is yours
to write at the moment the phase boundary is crossed. The `updated`
timestamp on the status line makes staleness visible: a stale stage
is a sign the shell discipline broke down.

Stage map:

| Phase boundary | Stage to write |
|---|---|
| Entering A1 (MemPalace search) | `research` |
| After A2 (claimed + isolated) | `claim` (hook-written; verify it stuck) |
| Entering the activity's first verification step | `verify` |
| Entering C2 (commit) | `commit` |
| After D2 (closed + pushed) | `close` (hook-written; verify it stuck) |
| Entering D3 (drawer + KG + diary) | `wrap-up` |

Activity recipes add their own intermediate stages to this map (e.g.,
`tdd-red`, `tdd-green`, `review`, `characterization`, `synthesizing`).
Recipes are the source of truth for stages that name an activity-
specific step; the shell only mandates the boundary stages above.

**Failure mode:** if the status line shows a stage that hasn't
matched reality for >10 minutes, the shell discipline broke. Read the
current `workflow-state.json`, advance the stage to where work
actually is, and continue.

## The lifecycle (visual)

```
                bead chosen (from session-startup or /working-a-bead)
                            ↓
            ╔═══════════════════════════════════════╗
            ║ PHASE A — PRE-MIDDLE (shell owns)     ║
            ║   A1. MemPalace bug-family search     ║
            ║   A2. claim + (optional) worktree     ║
            ╚═══════════════════════════════════════╝
                            ↓
            ┌───────────────────────────────────────┐
            │ VARIABLE MIDDLE (activity recipe owns)│
            │   bugfix:   debug → RED → GREEN →     │
            │             bug-class → full-suite    │
            │   feature:  brainstorm → spec → TDD   │
            │             on new contract → wire    │
            │   refactor: characterization tests →  │
            │             restructure → preserve    │
            │   research: define → search →         │
            │             synthesize → file         │
            │   cleanup:  scope → remove → verify   │
            │   docs:     gap → draft → review      │
            └───────────────────────────────────────┘
                            ↓
            ╔═══════════════════════════════════════╗
            ║ PHASE B — VERIFICATION (shell owns)   ║
            ║   B1. verification-before-completion  ║
            ╚═══════════════════════════════════════╝
                            ↓
            ╔═══════════════════════════════════════╗
            ║ PHASE C — INTEGRATION (shell owns)    ║
            ║   C1. (per task) requesting-code-rev. ║
            ║   C2. commit on branch                ║
            ║   C3. finishing-a-development-branch  ║
            ╚═══════════════════════════════════════╝
                            ↓
            ╔═══════════════════════════════════════╗
            ║ PHASE D — CLOSEOUT (shell owns)       ║
            ║   D1. bd preflight                    ║
            ║   D2. bd close + dolt push + git push ║
            ║   D3. drawer + KG triples + diary     ║
            ╚═══════════════════════════════════════╝
```

## Phase A — PRE-MIDDLE

Set stage `research` at the start of A1.

### A1. Search MemPalace for the bug family

BEFORE claiming, search for prior decision drawers that share the
bead's shape. This is the step most often skipped — and the step that
on 2026-05-02 caught the huu.15.2 lineage which reshaped the 0qw fix
mid-design. Concrete query patterns by activity:

- **Bug:** `mempalace_search "<symptom> <area>"` plus
  `mempalace_kg_query("<entity-name>")` for any entity in the bead.
  Look for sibling fixes; if one exists, restate the design in terms
  of that lineage BEFORE writing tests or code.
- **Feature:** search for prior architectural decisions in the same
  area; the family is "design conventions for <area>" rather than
  "previous bugs."
- **Refactor:** search for the original decision that introduced the
  shape being refactored — preserving its intent matters.
- **Research:** search the palace first; the answer often already
  exists. The `bug-family-researcher` subagent does this well.
- **Project tribal knowledge:** `bd memories <keyword>` for one-line
  facts that auto-inject at `bd prime` time.

The PreToolUse hook on `bd update --claim` automatically dispatches
the `bug-family-researcher` subagent (see
`~/.claude/agents/bug-family-researcher.md`). If you have already done
the search inline before claiming, the hook output is informational
overlap — fine, not blocking.

### A2. Claim and (optionally) isolate

```bash
bd update <id> --claim
```

This fires the `bd-claim-research` hook and writes `stage=claim`.

For project-side code changes, invoke
`superpowers:using-git-worktrees` to create `.worktrees/<bead>` on
`frank/<bead>` branch from `main`. One bead = one worktree = one
branch.

**Skip the worktree** for:
- Trivial fixes (≤ 1 line) where overhead exceeds value.
- User-global edits (files under `~/.claude/`) — there is no project
  worktree to create. The jnd / bmi precedent: commit user-global
  changes from the project root or wherever convenient; only the bead
  state changes appear in the project repo.

If you skip A2, note the reason in the closing decision drawer.

## VARIABLE MIDDLE — return to the activity recipe

Hand control back to the activity recipe that pointed you here. The
recipe specifies the steps and stages between phase A and phase B.
When the recipe finishes its middle, return here for phase B.

## Phase B — VERIFICATION

Set stage `verify` at the start of B1.

### B1. Verification before completion

Invoke `superpowers:verification-before-completion`. Re-run the
activity's verification harness from a clean shell, confirm exact
counts (test pass/fail counts, lint output, manual smoke results),
and check `git diff --stat` matches intended scope. State results
with evidence in user-facing output BEFORE moving to phase C.

If verification fails, do not advance the stage — return to the
variable middle and address the failure. The shell will not paper
over a red verification.

## Phase C — INTEGRATION

### C1. (Per task) Code review

If the activity middle contained multiple discrete tasks, invoke
`superpowers:requesting-code-review` after each task — not at
end-of-implementation. For single-task work, run code review once
here.

### C2. Commit on the branch

Set stage `commit` before the commit lands.

Descriptive subject + body that names symptom (or feature scope),
root cause (or design choice), fix (or implementation summary), test
counts, family lineage if applicable. Co-author trailer per project
convention.

### C3. Finish the branch

Invoke `superpowers:finishing-a-development-branch`. Presents the
four options (merge locally / push & PR / keep branch / discard) and
handles cleanup correctly per option.

For batched multi-bead sessions: merge sequentially in dependency
order, run verification once after all merges, fix any cross-branch
collateral in a single follow-up commit.

## Phase D — CLOSEOUT

### D1. bd preflight

```bash
bd preflight
```

PR-readiness checks (lint, stale, orphans). Address any output before
closing.

### D2. Close + push

```bash
bd close <id1> <id2> ... --reason="<one-line summary>"
bd dolt push
git push
git status   # MUST show "up to date with origin"
```

The `bd-close-capture` hook will block the close if recent capture
work is missing — bypass with `--force` or `BD_CLOSE_FORCE=1` only
for trivial fixes that genuinely don't warrant a drawer. The hook
writes `stage=close`.

### D3. Capture the decision in MemPalace

Set stage `wrap-up` before D3.

For each closed bead, file:

1. **Decision drawer** in the project's `decisions` room with:
   symptom (or feature goal), root cause (or design choice),
   options-considered + which-chosen + why, family lineage,
   verification at decision time. The `drawer-author` subagent
   (`~/.claude/agents/drawer-author.md`) drafts these well.

2. **KG triples** for convention or design-family work
   (`subject → predicate → object`) so future sessions see the
   family on the next phase A1 search. The
   `kg-relationship-extractor` subagent handles this.

3. **Diary entry** via `mempalace_diary_write` in AAAK — what got
   shipped, what was surprising, what to remember.

4. **Optional** `bd remember "<one-line insight>"` for project tribal
   knowledge that should auto-inject at `bd prime` time. Boundary
   (per 2026-05-02 decision): one-line tribal facts → `bd remember`;
   multi-paragraph decisions → MemPalace drawer.

The `/wrap-up` slash command bundles these three captures.

## How activity recipes reference the shell

Recipes use **inline pointer text**, not auto-loading. A recipe body
contains literal references to lifecycle phases:

> Follow `bead-lifecycle-shell` phase A (MemPalace search + claim +
> optional worktree). Then run the variable middle below. Return to
> the shell for phase B (verification), phase C (commit + finish-
> branch), and phase D (close + capture).

Recipes never duplicate phase bodies; they cite phases by letter and
trust this skill to remain the source of truth. If a phase body
changes here, every recipe inherits the change automatically.

When a recipe needs to extend a phase (e.g., a feature recipe wants
extra integration verification beyond B1), the recipe says so
explicitly: `extends phase B with: <recipe-specific check>`. The
shell phase still runs first; the extension follows.

## Decision: parallel vs sequential

Use `superpowers:dispatching-parallel-agents` when 2+ beads have
independent root causes (different files, no shared state). Trigger:
`bd ready` shows multiple unblocked beads that touch disjoint files.
Stay sequential when beads share files, when one fix depends on
another, or when interactive judgment is needed per step.

The shell is per-bead; parallel agents each run their own copy of the
shell + their own variable middle.

## Failure modes (concrete)

- **Skip phase A1 (MemPalace search):** design lands without seeing
  prior art; rework when reviewer spots the family. Caught
  2026-05-02 by Frank's "are you using MemPalace fully?" question.
  The 0qw fix design pivoted from defensive coercion to convention
  alignment after the search surfaced huu.15.2.
- **Skip stage writes:** status line goes stale; future cold-start
  sessions can't reconstruct where work stopped. The shell mandates
  these writes precisely because the v1 best-effort approach drifted.
- **Skip phase B1 (verification):** "it works in my head" failures
  reach commit. Verification-before-completion is the gate; the
  shell does not advance to phase C without evidence.
- **Skip phase D3 (capture):** the next session repeats the
  research from scratch; the family lineage stays implicit. Caught
  repeatedly across bug families before the workflow infrastructure
  was built.
- **Inline phase bodies in recipes:** drift between recipes within
  three sessions. Always cite by letter; never duplicate.

## Related infrastructure

This shell is the v2 successor to the v1 `working-a-bead` skill
(which is bug-shaped). Full design + decisions live in the MemPalace
drawer "RECIPE SHAPES — ACTIVITY MATRIX" (hundred_acre_woods/decisions
room, 2026-05-02). Build queue tracked under beads epic
`hundred-acre-woods-bng`.

Companion skills (each one fills the variable middle for one
activity shape):

- `bugfix-a-bead` (renames v1 `working-a-bead`) — bead `ipj`
- `feature-a-bead` — bead `305`
- `refactor-a-bead` — bead `2q2`
- `research-a-bead` — bead `3ck`
- `cleanup-a-bead` (deferred) — bead `94t`
- `docs-a-bead` (deferred) — bead `ott`

Slash commands and subagents that integrate with the shell:

- `/working-a-bead <id>` — router that picks the right activity
  recipe (bead `8t4`).
- `/wrap-up` — bundles phase D3 captures.
- `bug-family-researcher` — phase A1 helper.
- `drawer-author` — phase D3 helper.
- `kg-relationship-extractor` — phase D3 helper.
