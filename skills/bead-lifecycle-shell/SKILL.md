---
name: bead-lifecycle-shell
description: Cross-activity lifecycle scaffolding for working a beads issue from claim to merged. Owns MemPalace bug-family search, claim, optional worktree, verification, commit, finishing-a-development-branch, preflight + close + push, and decision drawer + KG triples + diary capture. Each activity recipe (bugfix-a-bead, feature-a-bead, refactor-a-bead, research-a-bead, etc.) references the lettered phases below and supplies its own VARIABLE MIDDLE between phase B and phase C. Internal building block — invoked indirectly via an activity recipe, not directly by the user.
---

# Bead Lifecycle Shell — Cross-Activity Scaffolding

The lifecycle steps that surround any bead work — search, claim,
isolate, verify, commit, close, capture — are the same regardless of
what activity sits in the middle. This skill owns those steps. Each
activity recipe (bugfix / feature / refactor / research / cleanup /
docs) references the phases here and only specifies its own VARIABLE
MIDDLE between phase B and phase C.

The shell is an internal building block — activity recipes call into
it by reference; the user (and the router) never invoke it directly.
Triggering: an activity recipe (or the `/working-a-bead` router that
picks one) cites this skill in its body and instructs you to follow
specific phases. If the Skill tool ever surfaces the shell directly
(via auto-discovery against the description), decline — start at an
activity recipe instead and let it cite the shell phases by letter.

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

### A2.5 Seam scan — parallelizable siblings? (loom-z3m.5)

After the claim resolves (and after the optional worktree is set
up), run the seam scan as a one-line sanity check:

```bash
~/.claude/scripts/loom-seam-scan <claimed-bead-id>
```

The script reads `bd ready --json`, finds sibling beads (same parent
epic) whose extracted file-paths are disjoint from the claimed bead
and from each other, writes the count to `workflow-state.json`
under `parallel_candidates`, and emits one of:

```
Parallelizable: none.
Parallelizable: N candidates (loom-foo, loom-bar).
```

The statusline picks the count up and shows `PAR:N` when `N > 0`.
**When N > 0, mandatorily invoke `superpowers:dispatching-parallel-
agents` before the variable middle begins** — the recipe's middle
then runs once per dispatched bead in parallel. When N = 0, proceed
sequentially through the variable middle as usual.

The heuristic is conservative — it extracts path-shaped tokens
(`*.md`, `*.sh`, `*.py`, etc.) from each bead's design + description
+ notes text because `bd show` exposes no structured file list. A
bead that mentions only directories will look "disjoint" against
everything; trust your judgment when reading the candidate list,
the value of the scan is the ritualized prompt, not a hard gate.

Skip the scan when phase A2 was skipped entirely (the trivial-fix
and user-global precedents above). Document the skip in the closing
drawer if it shaped the integration plan.

## VARIABLE MIDDLE — return to the activity recipe

Hand control back to the activity recipe that pointed you here. The
recipe specifies the steps and stages between phase A and phase B.
When the recipe finishes its middle, return here for phase B.

### Dispatch discipline — central orchestrates a pipeline (loom-6bv1)

Dispatch discipline (uniform across all recipes): the variable middle
is dispatched, never typed in the central thread. **The DEFAULT is
`/dispatch-middle`** — it runs the middle as a pipeline of INDEPENDENT
subagents, **each in its OWN `isolation: "worktree"`** (the `Agent`
tool auto-names them; there is no single shared worktree): the
**test-author THEN implementer (DIFFERENT agents)**, with an optional
verifier. The test-author writes the RED test and commits it; the
implementer inherits that test as an ARTIFACT relayed over the
content-bridge — the verbatim test content, never the author's
reasoning, mind, or conversation — and makes it GREEN. Because the
two roles are different agents, the test-author == code-author
anti-pattern is solved by construction. **Central writes NOTHING in
the middle** — no test, no
line of code: it invokes `/dispatch-middle <bead>` once and hands back
for integration. (This supersedes the old loom-yb5 model where one
worker covered the full RED→GREEN in a single dispatch; the split into
two independent agents is the v2 change.) Do NOT use
Edit/Write/MultiEdit yourself between bead-claim and bead-close. While
the pipeline runs: answer user questions, pre-stage the next bead, or
revise the contract — but do NOT start parallel code-work in the
central session. The pipeline returns; you integrate; you re-dispatch
only on surprises.

**The sharpened central/worker line.** Central does ONLY three things:
**conversation** (executive function + dialogue with the user),
**contract-lock** (M1 = the genuine user dialogue that pins the bead's
`RED:` line / spec / acceptance), and **integration** (verify + merge
+ close + capture — the cwd-sensitive, bd-authoritative steps only
central can do safely). Everything in between — the **RED-test +
GREEN-code + research + review** — is worker work, each agent briefed
with ONLY its MINIMAL scoped slice of context (the locked contract for
the test-author; the RED-test-as-file for the implementer). Central
never writes a test or a line of code. See `dispatch-middle` for the
pipeline mechanics, the two brief templates, and the context-scoping
discipline.

**Friction-inversion — why the default flipped (loom-5m94).**
loom-yb5 was a *push* (a nudge pressuring toward dispatch); central
still defaulted to inline because dispatching used to mean
write-a-brief + wait + verify + merge — high friction. `/dispatch-
middle` is the *pull*: dispatch is now a **single cheap command** that
runs the whole middle. With friction inverted, **inline's only
remaining justification is the mechanical threshold** — and even when
that threshold is met, **`/dispatch-middle` is still preferred**;
inline is the deliberate exception you reach for, not the comfortable
default.

**Inline is the explicit, justified EXCEPTION.** Working the variable
middle inline (central edits directly, no dispatch) is allowed
**without** justification ONLY when ALL of these hold:

- the change is ≤ ~15 lines, AND
- it touches a single non-test file, AND
- it adds no new test.

Pure docs/config/prose edits qualify. **Anything with a RED→GREEN
cycle defaults to `/dispatch-middle`** — no exception waved through on
"feels trivial" or "contained," and even a change that clears the
threshold above still prefers `/dispatch-middle` over inline. Going
inline on a bead that fails any clause above is a deliberate override:
record the reason (below) and own it.

**Recording the choice.** Central records the decision in
`workflow-state`'s `dispatch` field (bead loom-0zr): `dispatch=worker`
for the `/dispatch-middle` default, or `dispatch=inline:<reason>` for
a justified exception. The dispatch-nudge hook (bead loom-h5s; updated
in T3 to point at `/dispatch-middle`) reads this field and prompts when
a bead with a RED→GREEN-shaped variable middle is about to be worked
inline without a recorded `inline:<reason>`.

**Model-tier nudge — test-author ≥ implementer (loom-0ahj.4, D5).**
When the middle splits into the test-author → implementer pipeline,
the model TIER is a per-dispatch choice, and the two roles do not
deserve the same tier. The test-author writes the SPEC — the RED test
is the *ceiling* the implementer is gated against (F9, the
imperfect-test ceiling, arXiv 2411.17501) — so it gets the stronger
model; the implementer's narrower job (turn that fixed artifact GREEN
with the minimal change) can run on a cheaper one. **The INVARIANT:
the test-author's model tier is ≥ the implementer's** — the
ceiling-setting role is never cheaper than the role gated beneath it
(the *inverted* model-tier rule). This is a **default NUDGE, not a
gate** (loom-yb5, nudge-not-block); pick concrete tiers to fit the
bead, but keep author ≥ implementer when you split. Tier is chosen
**per-dispatch, not per-agent-type** — the agent DEFINITION files stay
`model:inherit`; central picks the tier on each `Agent` call. The
payoff is **validated via Move-3a telemetry** (`scripts/loom-stage-
spend`, loom-0ahj.3) — no separate A/B. `dispatch-middle` owns the
full rationale, the per-step `model:` slots (Steps 2/3), and the two
brief templates; the shell only states the nudge so recipes inherit
it.

**Dispatch mode — `run_in_background: true` is the DEFAULT (loom-li8h).**
Dispatch every pipeline agent with **`run_in_background: true` by
default**. A foreground dispatch holds central's turn idle until the
agent returns — central sits and waits, which defeats lean-central. With
background dispatch, central **yields the turn** on dispatch and
**resumes on the agent's completion event**, free meanwhile to do the
"Allowed while the pipeline runs" work below.
**Foreground is the explicit exception**, reserved for the narrow case
where the next step is **immediate integration with nothing else
interleavable** (a single short dispatch central will merge + close the
instant it lands, with no conversation/planning/staging to fill the
gap). `dispatch-middle` owns the full rationale; the shell states the
default so recipes inherit it.

**Allowed while the pipeline runs (central session):**
- Answer the user's questions; explain in-flight decisions.
- Pre-stage the next bead (read its description, surface prior art,
  draft the next contract — but do not claim it yet).
- Revise the in-flight contract if the user clarifies intent (capture
  in a follow-up note for the re-dispatch, do not edit code).
- Read-only investigation: `bd show`, `git log`, MemPalace search.

**Forbidden while the pipeline runs (central session):**
- Edit, Write, or MultiEdit on any file in the worktree.
- Parallel code-work on the same bead in the main repo.
- Closing the bead, merging the branch, or pushing.
- Starting a second pipeline on the same bead's variable middle.

**Concurrency caution — never two full-suite loops in one repo at once.**
Backgrounding makes multiple agents in flight cheap, but **never run two
full-suite loops in the same repo at the same time** — they race on
shared git/bd state. During the loom-fx9m close detour (2026-06-08) a
foreground-wait plus the harness auto-backgrounding a long loop produced
two suite runs racing in one repo; `TaskStop`'ing the duplicate left
**orphan `bd-post-rewrite` grandchild processes** (`TaskStop` reaps the
targeted task but may not reap its grandchildren), which kept racing and
returned a **false `63/2` suite result**. One suite loop per repo; after
a `TaskStop`, confirm no orphan `bd-post-rewrite` processes survived
before trusting any suite number.

#### Brief templates — delegated to `/dispatch-middle`

The middle's brief templates live in `dispatch-middle`, not here:
the **test-author brief** (locked contract + interface under test) and
the **implementer brief** (RED-test file path + code area). Both
carry the pre-flight smoke battery (`.claude/rules/dispatched-
agents.md`) as the first bash call, run in their OWN auto-named
`isolation: "worktree"` (one per agent — not a single shared tree),
and instruct each agent to **commit on its branch but not
merge, push, or close — central handles integration**. The shell does
not duplicate the templates; recipes and central reference
`/dispatch-middle` by name and let it own the template shape. Each
brief gets ONLY its slice of context — no session-history dump.

#### Re-dispatch decision rule

When the pipeline returns, central reviews the diff + the pipeline's
summary (RED output, GREEN counts, commit SHAs, any stop-and-report
flags), then chooses:

- **Clean** — verification GREEN, diff matches scope, no surprises.
  Advance to phase B (verification) and onward to C/D. No
  re-dispatch.
- **Minor polish (≤ 3 lines)** — typo, wording nit, missing
  citation. Central edits in place. Do not re-run the pipeline for
  ≤ 3 lines.
- **Substantive rework** — wrong design, missed scope, new failure
  mode surfaced. **Re-brief** a fresh test-author or implementer with
  the corrected contract. Do not chain edits onto a returned agent's
  session. If the implementer hit a stop-and-report (the test looked
  wrong), central resolves the contract dispute — re-lock the contract
  or re-brief the test-author — rather than letting the implementer
  weaken the test.

Central re-runs the activity's verification harness after the pipeline
returns regardless of which branch above fires — trust-but-verify
per `superpowers:verification-before-completion`. The pipeline's
RED→GREEN counts in the summary are evidence to spot-check, not to
take on faith.

#### Phase ownership (who runs what)

- **A1 (bug-family search):** SUBAGENT — `bug-family-researcher`,
  auto-dispatched by the `bd update --claim` PreToolUse hook.
- **A2 / A3 (claim + worktree):** CENTRAL — short ceremony, no
  dispatch needed.
- **B (variable middle):** PIPELINE — the test-author→implementer
  split run via `/dispatch-middle`, each agent in its OWN auto-named
  isolation worktree (the RED test crosses between them over the
  content-bridge, not a shared disk). Central does not Edit/Write
  here; it invokes once and writes nothing.
- **C (commit + finish-branch):** CENTRAL — the pipeline commits on
  the branch; central reviews, runs phase B verification, then
  drives `superpowers:finishing-a-development-branch` for
  integration.
- **D (file outputs):** CENTRAL files; drafting is SUBAGENT work —
  `drawer-author` drafts the decision drawer, `kg-relationship-
  extractor` drafts the KG triples, central reviews and files
  through MemPalace MCP tools.

### Mid-recipe branchpoint — NEW failure mode → TDD detour (loom-z3m.6)

While the activity recipe owns the variable middle, the shell
mandates one cross-cutting reflex inside it: **when a bash tool call
exits non-zero with a failure mode you have NOT yet seen in this
bead, suspend the recipe's current step and invoke
`superpowers:test-driven-development` BEFORE the next Edit / Write /
MultiEdit on a non-test file.**

"NEW" means: a test failure, build failure, lint failure, or
exception surface that wasn't already represented by an existing
failing test (or characterization test) in this bead. The first
sighting of a failure mode is the moment to pin it with a RED test;
each successive sighting then just re-runs the existing test. This
applies inside ALL six activity middles — bug, feature, refactor,
research, cleanup, docs — because the failure-then-quick-fix slip
isn't recipe-specific.

Concrete sequence at the branchpoint:

1. Note the new failure (symptom + reproducer).
2. Invoke `superpowers:test-driven-development`. Write the minimal
   test that captures the symptom and confirm it goes RED.
3. Resume the activity recipe's middle. The Edit that produces the
   fix or the design change goes GREEN against the just-written
   test.
4. If the failure was actually unrelated to the current bead's
   scope (e.g. a pre-existing flake the work surfaced incidentally),
   file a follow-up bead and bypass the guard for this edit. Do not
   let scope-creep absorb unrelated failures.

**Mechanical backstop.** The `hooks/edit-after-failure-guard.sh`
PreToolUse hook (loom-z3m.6) intercepts Edit/Write/MultiEdit when a
recent Bash tool_result contained test-failure markers AND no test
file has been touched since. It refuses with a TDD reminder; bypass
via `LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1` in the rare case where
the failure is unrelated. The hook is convention-aligned, not
convention-creating — the branchpoint above is the rule it
enforces. See
[`docs/reference/hooks/edit-after-failure-guard.md`](../../docs/reference/hooks/edit-after-failure-guard.md).

**Activity-recipe note.** Activity recipes do not need to restate
this branchpoint in their own bodies; the shell owns it. Recipes
MAY add activity-specific extensions (e.g. `bugfix-a-bead` already
has a "RED before GREEN" prescription in its variable middle —
that's compatible; the branchpoint just extends the same discipline
to mid-recipe surprises).

## Phase B — VERIFICATION

Set stage `verify` at the start of B1.

### B1. Verification before completion

Invoke `superpowers:verification-before-completion`. Re-run the
activity's verification harness from a clean shell, confirm exact
counts (test pass/fail counts, lint output, manual smoke results),
and check `git diff --stat` matches intended scope. State results
with evidence in user-facing output BEFORE moving to phase C.

**Doc-surface audit.** After the diff-scope check, walk the docs
site quickly using the diff itself as the worklist. The published
site under `docs/` (Diataxis-shaped, MkDocs Material) pulls primitive
bodies in via include globs, so most edits propagate automatically.
What remains manual is the chrome around those includes and the
prose pages that aren't auto-generated:

1. **Did the diff touch any primitive** (`skills/<name>/SKILL.md`,
   `commands/<name>.md`, `agents/<name>.md`, `hooks/<name>.sh`)? If
   yes: the docs site auto-picks up the body via include glob —
   inspect the *chrome* only. That's the intro paragraph above the
   include directive on the relevant `docs/reference/` page, any
   "shipped in bead X" / version label that should be bumped, and
   cross-links from Tutorials / How-to / Explanation pages that
   point at the primitive. Usually 2 lines of text touched, often
   zero. If nothing needs editing, say so explicitly so the audit
   leaves a footprint.
2. **New primitive added or removed?** Auto-handled by the include
   glob; nothing manual on the reference side. (Removals: see
   `cleanup-a-bead` M2 — the orphan-reference grep covers `docs/`
   so dead in-doc cross-links to the removed primitive don't
   linger.)
3. **Did the diff change user-visible behavior described in
   non-reference docs** (Tutorials / How-to / Explanation)? If yes,
   the prose on those pages doesn't update itself. Decide:
   in-scope to fix here, or follow-up bead? Default is
   **file-later** — open a `docs-a-bead`-shaped follow-up via
   `bd create` and keep this bead focused on the behavior change.
   In-scope-here is appropriate only when the doc edit is a
   one-or-two-line factual correction directly downstream of the
   code edit; otherwise the bead grows mid-flight.

State the audit result (which of 1/2/3 applied, what was edited or
deferred) before advancing to phase C. The audit is cheap when run
incrementally and expensive to retrofit — running it at every B1
keeps the docs site aligned without ever needing a "great
documentation sweep" bead.

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

**Worktree commits — bd hook bypass.** When committing from inside
a worktree (`.worktrees/<bead>/`), use:

```bash
git -c core.hooksPath=/dev/null commit -m '...'
```

The bd pre-commit hook misbehaves from worktrees (loom-22h /
loom-bm2): it exports `issues.jsonl` to the worktree root instead
of the canonical `.beads/issues.jsonl`, defeating `.gitignore` and
amend-based cleanup (the hook re-stages on every commit). Bypassing
the hook here is safe because the canonical `.beads/issues.jsonl`
is regenerated from bd's database on the next main-repo commit
(typically the post-merge `<bead>: bead closed (post-merge state)`
commit). Skip this bypass when committing from the main repo path
— the hook works correctly there and the canonical export is
desired.

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

**For docs-bearing projects (mkdocs.yml present):** the
`bd-preflight-docs-strict` PreToolUse hook (loom-cya) auto-fires on
both `bd preflight` and `bd close` and refuses (`exit 2` in full
mode) if the branch's diff vs `main` touches docs-relevant paths
(`docs/`, `mkdocs.yml`, `requirements.txt`, `skills/`, `commands/`,
`agents/`, `hooks/`) AND `mkdocs build --strict` fails. Mode-aware:
full blocks, light warns, off silent. Bypass for emergencies via
`LOOM_BD_PRECLOSE_STRICT_SKIP=1`. Companion to sibling loom-kbo
(pre-push hook) — close-time + push-time + CI = defense-in-depth.

### D1b. Docs SERVING check (full-Diataxis projects)

`mkdocs build --strict` (D1, above) verifies the docs BUILD; it does
NOT verify that the published site ACTUALLY SERVES. Those are
different failures: on 2026-06-08 every Deploy-docs run was green AND
gh-pages was a valid site, yet `https://fkberthold.github.io/loom/`
404'd for an unknown period because GitHub Pages had been DISABLED —
a *silent-green* outage that neither the strict build nor
session-startup step 1c (which only flags RED Deploy-docs runs)
caught. The serving check closes that gap.

```bash
scripts/loom-docs-serving-check          # derive site_url from mkdocs.yml
scripts/loom-docs-serving-check <url>    # or pass an explicit site URL
```

The helper (loom-7q1g) gates on **full-Diataxis** (`docs/` +
`mkdocs.yml` present AND no `docs/.no-diataxis` marker; otherwise it
skips cleanly) and reports three layers: **Layer 1** `mkdocs build
--strict` build integrity; **Layer 2** the latest Deploy-docs GitHub
Actions run conclusion (via `gh run list`); **Layer 3 (the new part)**
the site ACTUALLY SERVES — `curl -sIL <site_url>` → HTTP 200, falling
back to the GitHub Pages API (`gh api repos/{owner}/{repo}/pages` →
`status=built` / not 404) when curl is absent or inconclusive. It is
**INFO/nudge — always `exit 0`, never hard-blocks** (nudge-not-block,
loom-yb5): the findings print to stdout (`WARN —` prefix on a problem
layer) and you decide. It degrades gracefully — any layer whose tool
(mkdocs / gh / curl) or network is unavailable is skipped with a note
rather than failing the wrap-up. Composes with session-startup step 1c
(red-run detection) and the `bd-preflight-docs-strict` hook (D1):
build-time + close-time-serving + CI = defense-in-depth.

### D2. Close + push

```bash
bd close <id1> <id2> ... --reason="<one-line summary>"
# Guard: skip bd dolt push for solo workspaces (no remote configured) — loom-hsb.
if bd dolt remote list --json 2>/dev/null | grep -q '"name"'; then
  bd dolt push
else
  echo "(solo bd workspace; no Dolt remote — skipping bd dolt push)"
fi
git push
git status   # MUST show "up to date with origin"
```

The `bd-close-capture` hook will block the close if recent capture
work is missing — bypass with `--force` or `BD_CLOSE_FORCE=1` only
for trivial fixes that genuinely don't warrant a drawer. The hook
writes `stage=close`.

**Flag gotcha (loom-b20, sub-issue 1):** `bd close` accepts `--reason
"..."`, NOT `--notes`. The `--notes` flag exists on `bd update` and
is easy to pattern-match into a close command. When you pass an
unknown flag, bd's Cobra parser prints `Error: unknown flag: --notes`
followed by the full help text, **but exits 0** — the close was not
performed and the failure can look like a successful close-with-help
in a busy terminal scrollback. Always use `--reason` on close. If you
need richer post-close notes, run `bd update <id> --append-notes "..."`
*after* the close.

The `bd dolt push` guard exists because solo bd workspaces (no Dolt
remote configured) have `bd dolt push` exit 1 with a "remote 'origin'
not found" error that is benign — issues are still versioned locally
in `.beads/`. The guard checks `bd dolt remote list --json` and skips
the push when the result is empty (`[]`). See loom-hsb.

### D3. Capture the decision in MemPalace

Set stage `wrap-up` before D3.

**The capture fan-out is the DEFAULT capture path (loom-0ahj.5,
grounding design-doc 14f08e6d D6 + the exploration capture-tax
finding).** Capture is itself dispatched, not hand-written: central
fans the drafting out to the **`drawer-author` + `kg-relationship-
extractor` subagents in parallel** (the two-agent capture fan-out),
then **REVIEWS** their drafts and **FILES** them through the MemPalace
MCP tools. This mirrors the variable-middle posture — just as central
writes no test or line of code in the middle (it dispatches the
test-author → implementer pipeline), central **does NOT hand-write the
drawer, the KG triples, or the diary entry** here: the drafting is
SUBAGENT work, central is the reviewer-and-filer. The capture-tax
finding is the motivation — hand-authoring the closing drawer + KG +
diary was the friction that made phase D get skipped; defaulting to the
fan-out removes that tax. (Tiny ≤ 1-line fixes are the explicit
exception — see "What to skip" below.)

So the DEFAULT D3 sequence is: **dispatch the fan-out → review the two
drafts → file via MCP**. Central never types the drawer body or the
triples from scratch; it briefs each subagent with the bead-id + the
landing commit SHAs, reviews what comes back, edits at the margins, and
files. The `/wrap-up` slash command bundles exactly this default
fan-out (and the diary write + close + push) into one ritual.

For each closed bead, the fan-out drafts and central files:

1. **Decision drawer** in the project's `decisions` room with:
   symptom (or feature goal), root cause (or design choice),
   options-considered + which-chosen + why, family lineage,
   verification at decision time. The `drawer-author` subagent
   (`~/.claude/agents/drawer-author.md`) drafts these well — central
   reviews and files via `mempalace_add_drawer`, it does not
   hand-write the drawer.

2. **KG triples** for convention or design-family work
   (`subject → predicate → object`) so future sessions see the
   family on the next phase A1 search. The
   `kg-relationship-extractor` subagent drafts these; central reviews
   and files each via `mempalace_kg_add`.

3. **Diary entry** via `mempalace_diary_write` (params: `agent_name`,
   `entry`, optional `topic`) in AAAK — what got shipped, what was
   surprising, what to remember. Pass the AAAK summary in the `entry`
   field; the plugin's `-32000` error is opaque on param-name typos.

4. **Optional** `bd remember "<one-line insight>"` for project tribal
   knowledge that should auto-inject at `bd prime` time. Boundary
   (per 2026-05-02 decision): one-line tribal facts → `bd remember`;
   multi-paragraph decisions → MemPalace drawer.

The diary entry (item 3) and the optional `bd remember` (item 4)
stay central-side — they're a one-line AAAK write and a tribal-fact
write, not a drafting job. `/wrap-up` bundles the whole default
sequence: the drawer-author + kg-relationship-extractor fan-out (items
1–2, central reviews-and-files), the diary write, and the close +
push.

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

There are two distinct decision points — **across-bead** (which
beads to work on) and **within-bead** (how to execute one bead's
variable middle). Both call into `superpowers:dispatching-parallel-
agents`; the trigger and the cost-payoff threshold differ.

### Across-bead — when 2+ beads are unblocked

Use `superpowers:dispatching-parallel-agents` when 2+ beads have
independent root causes (different files, no shared state). Trigger:
`bd ready` shows multiple unblocked beads that touch disjoint files.
Stay sequential when beads share files, when one fix depends on
another, or when interactive judgment is needed per step.

The shell is per-bead; parallel agents each run their own copy of
the shell + their own variable middle.

### Within-bead — when M-steps are independent

Before starting an activity recipe's variable middle, scan the
M-steps and ask: are 2+ of them independent (different files, no
shared state, no sequential dependency)? If yes, dispatch them in
parallel via `superpowers:dispatching-parallel-agents` with
`isolation: "worktree"`. If no, stay sequential.

**Cost-payoff threshold.** Parallelism wins when each task is
non-trivial — more than a one-line edit per step. For tiny edits
(≤ ~5 lines per step), sequential is faster than dispatch overhead
(worker prompt, isolation worktree, review-on-return). Make the
call explicit: state "M-steps are independent but small; running
sequentially" or "M-steps are independent and non-trivial;
dispatching in parallel" so the choice is visible in the close
drawer.

**Worker leak hazard (loom-tag finding).** Parallel workers with
absolute paths (`/home/frank/repos/<project>/<file>`) write into
main, not the worktree — the harness creates the worktree but does
NOT sandbox absolute-path Edit/Write calls. When dispatching, give
workers **relative** paths in their prompts (`commands/foo.md`).
After workers return, verify with `git diff --stat` in BOTH the
worktree and main to detect leaks. See
`drawer_loom_decisions_df73c725b47dd67832935e3a` (loom-tag,
2026-05-04) for the full finding. This hazard is per-dispatch; it
does not multiply with the number of nudges that point at it.

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
room, 2026-05-02). Build queue tracked under loom epic `loom-0y6`
(continuation of HAW epic `hundred-acre-woods-bng`).

Companion skills (each one fills the variable middle for one
activity shape):

- `bugfix-a-bead` (renames v1 `working-a-bead`) — bead `loom-lzi`
- `feature-a-bead` — bead `loom-5rf`
- `refactor-a-bead` — bead `loom-uca`
- `research-a-bead` — bead `loom-0q0`
- `cleanup-a-bead` — bead `loom-62x`
- `docs-a-bead` — bead `loom-s0n`

Slash commands and subagents that integrate with the shell:

- `/working-a-bead <id>` — router that picks the right activity
  recipe (bead `loom-1ab`).
- `/wrap-up` — bundles phase D3 captures.
- `bug-family-researcher` — phase A1 helper.
- `drawer-author` — phase D3 helper.
- `kg-relationship-extractor` — phase D3 helper.
