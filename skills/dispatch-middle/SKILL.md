---
name: dispatch-middle
description: Orchestrate a bead's variable middle as a test-author → implementer (→ optional verify) pipeline of INDEPENDENT subagents, each in its OWN isolation worktree, so central invokes once and writes nothing. The friction-inversion lever — makes dispatch cheaper than inline. Central briefs each agent with ONLY its slice of context (the locked CONTRACT for the test-author; the verbatim RED-test content for the implementer, relayed over the content-bridge), receives GREEN counts, then hands back for verify + merge + close + capture. Triggers on "/dispatch-middle <bead>", or when an activity recipe reaches its RED→GREEN middle and the bead is non-trivial.
---

# Dispatch-Middle — Test-Author → Implementer Pipeline

This skill owns the **variable middle** of a bead's lifecycle when
that middle is a RED→GREEN cycle. It runs the middle as a pipeline of
**independent subagents**, so the central session **invokes once and
writes nothing** — no test, no line of code, no accumulated junk
context.

Each agent runs in its **OWN `isolation: "worktree"`** — there is NO
single shared worktree. The RED test crosses the test-author →
implementer boundary as a verbatim **artifact relayed by central**
(the **content-bridge**, loom-fx9m), not via a file both agents read
off one shared disk. (See "Why each agent gets its own worktree"
below — this is the v2 correction to the original shared-worktree
design.)

It is the *pull* half of loom's dispatch posture. The `dispatch-nudge`
hook (loom-yb5) is the *push* — it pressures central toward dispatch.
The push alone wasn't enough because dispatching used to mean
write-a-brief + wait + verify + merge (high friction), so central
kept defaulting to inline. `/dispatch-middle` inverts that: one
invocation runs the whole middle. Make the right thing the easy thing
and the behavior flips on its own.

## Why this exists (the 3 failure modes it kills)

Central doing the middle in-thread causes three problems (locked in
`drawer_loom_decisions_fe831554f7a62b9c6ea4bf18`, dispatch-v2
brainstorm, 2026-06-07):

1. **Central eats planning context.** The RED/GREEN churn fills the
   context window central needs for conversation + executive function
   with the user. → Fix: central is orchestration-only; the churn
   lives in subagents.
2. **Test-author == code-author (the anti-pattern).** When the same
   agent writes the test and the implementation, the test is a
   tautology shaped by the implementation — no independent
   verification. → Fix: the test-author and the implementer are
   DIFFERENT agents, and the implementer **never sees the
   test-author's reasoning**. It inherits the test as an ARTIFACT
   (the verbatim test text), not a shared mind. Issue #2 solved by
   construction.
3. **Central accumulates unrelated context.** Whole-file reads,
   debugging detours, half-formed approaches pile up in central's
   thread. → Fix: central extracts the **minimal slice** per brief;
   no session-history dump.

## Why each agent gets its own worktree (the content-bridge)

The original design ran both agents in ONE shared worktree
`frank/<bead>` and let the implementer read the test-author's
committed RED test off disk. **That mechanism is broken** (loom-fx9m):
the `Agent` tool's `isolation: "worktree"` **auto-names** the worktree
it creates and gives the caller no way to target a named branch or to
reuse another agent's worktree. Two `Agent` calls therefore land in
two DIFFERENT trees — there is no single shared worktree to point both
at. Forcing one would require central to create + manage the worktree
by hand, re-importing the friction the skill exists to remove.

The fix is the **content-bridge**: the test text itself crosses the
boundary as a verbatim ARTIFACT that central RELAYS between the two
isolated agents.

- **Each agent runs in its OWN `isolation: "worktree"`** — separate,
  auto-named, fully isolated. No single shared worktree is required.
- The **test-author RETURNS the verbatim RED-test file content** (the
  test text itself, not merely a path).
- Central **relays that verbatim test content** into the implementer's
  brief.
- The **implementer RECREATES the test file exactly** from the relayed
  content, confirms it is RED, implements to GREEN, and **must not
  modify or weaken it**.

This **preserves the independence invariant** while keeping BOTH
agents fully isolated → no main-leak. The implementer inherits the
test as an ARTIFACT (verbatim text), never the author's mind: it never
sees the test-author's reasoning, conversation, or worktree. The two
roles cannot collapse back into one. The content-bridge is just a
different *transport* for the same artifact the shared-worktree design
moved over disk — independence is identical; isolation is strictly
better. This resolves loom-fx9m.

**Tradeoff.** Central **relays** the test text through its own
context, so a LARGE test costs context proportional to its size, and
central must re-run the test + check the assertion count post-merge to
confirm the implementer recreated it faithfully (the on-disk shared
file gave that for free). For a large test, use the **path-capture
fallback** below.

### Path-capture fallback (for a LARGE test)

When the RED test is large enough that relaying its full text is too
expensive, capture the test-author's returned worktree path (from its
completion / return payload) and point the implementer's `cd` at that
**same worktree**, so it reads the committed test off disk instead of
recreating it from relayed content. This is the one place "same
worktree" legitimately survives — both agents end up operating on the
same on-disk tree. It trades the relay context-cost for the need to
hand the implementer a concrete path, and it leans on the harness
actually exposing the test-author's worktree path. Prefer the
content-bridge by default; reach for path-capture only when the test
is too large to relay comfortably.

## When to use

- A bead's middle is a RED→GREEN cycle (most feature/bugfix beads).
- The change is non-trivial (the inline exception — ≤ ~15 lines, one
  non-test file, no new test — still applies; see the "Dispatch
  discipline" section of `bead-lifecycle-shell`).
- A locked CONTRACT exists: the bead's `RED:` line, an M1 spec, or an
  acceptance criterion. The test-author needs this; without it, go
  back to design/brainstorm first.

## Skip when

- The change is genuinely trivial (waved through inline).
- There is no contract yet — lock it first (design phase / M1
  dialogue). `/dispatch-middle` consumes contracts; it does not
  produce them.

## Composition — within-bead vs across-bead

- **`/dispatch-middle` owns the WITHIN-bead split** — one bead's
  test/code division of labor (test-author then implementer).
- **The loom-yb5 fan-out detector owns ACROSS-bead parallelism** —
  multiple independent ready beads, each worked via its own
  `/dispatch-middle`. (`scripts/loom-fanout-detect`, surfaced at
  selection by session-startup step 6a + the `/working-a-bead`
  router.)

The two compose orthogonally: the fan-out detector proposes a wave of
N file-disjoint beads; each bead in the wave runs its middle through
`/dispatch-middle`. The `dispatch-nudge` hook (push) now points at
`/dispatch-middle` (pull) — push + pull compose.

## Interlock with loom-tdua (design phase)

The test-author's **contract slot IS the bead's `RED:` line**. The
loom-tdua design-phase epic emits contracts (its T4 writes a `RED:`
line per bead); `/dispatch-middle` consumes them. Design produces the
spec; dispatch turns each spec into an independent test→code pipeline.
If the bead has no `RED:` line, fall back to the M1 spec or the
acceptance criterion as the contract.

## Model-tier policy — test-author ≥ implementer (loom-0ahj.4, D5)

Dispatch is per-role, so the model TIER is a per-dispatch choice — and
the two roles do not deserve the same tier. The test-author writes the
SPEC: the RED test is the *ceiling* on correctness the implementer is
gated against (F9, the imperfect-test ceiling, arXiv 2411.17501 — a
weak test caps how good the implementation can be, because passing a
weak test is all the implementer is asked to do). The implementer's
job is narrower: make that fixed artifact go GREEN with the minimal
change. So:

- **Dispatch the test-author with `model:<strong>`** (Step 2) — the
  spec-setting / ceiling role gets the stronger model.
- **Dispatch the implementer with `model:<cheaper>`** (Step 3) — the
  gated / mechanical role can run on a cheaper model, since the
  test-author's ceiling already bounds the outcome.

**The INVARIANT:** the test-author's model tier is **≥** the
implementer's — the role that sets the ceiling is **never cheaper**
than the role gated beneath it. This is the *inverted* model-tier rule
(strong where generation/ceiling-setting lives, cheap where the work is
gated and mechanical), the within-bead instance of the epic's per-stage
budgeting.

This is a **default NUDGE, not a hard gate** (loom-yb5,
nudge-not-block) — pick concrete tiers to fit the bead (a subtle
contract may want both roles strong; a rote one may run both cheap),
but keep author ≥ implementer when you split them. The rule's payoff is
**validated later via Move-3a telemetry** (`scripts/loom-stage-spend`,
loom-0ahj.3, the measure-first per-stage spend reader) — there is **no
separate A/B**; the per-stage spend data tells us whether the split
pays.

**Tier is chosen PER-DISPATCH, not per-agent-type.** The agent
DEFINITION files stay `model:inherit` — the test-author and implementer
are not distinct agent *types* with baked-in tiers; they are the same
generic dispatched-worker role briefed differently, and central picks
the tier on each `Agent` call. Do not encode a tier into any agent
definition.

---

## Dispatch mode — `run_in_background: true` is the DEFAULT (loom-li8h)

Dispatch every agent in this pipeline with **`run_in_background: true`
by DEFAULT**. The test-author (Step 2), the implementer (Step 3), and
the optional verifier (Step 4) are all background dispatches unless the
exception below applies.

**Rationale — dispatch-v2 lean-central.** A foreground dispatch holds
central's turn idle until the agent returns; central sits and waits,
doing nothing, which directly contradicts the lean-central goal this
skill exists to serve. With `run_in_background: true`, central
**yields the turn** the moment it dispatches and **resumes on the
agent's completion event** — free meanwhile to converse with the user,
explain in-flight decisions, pre-stage the next bead, or revise the
in-flight contract (exactly the "Allowed while the pipeline runs" list
in `bead-lifecycle-shell`). Backgrounding is what makes
"central writes nothing in the middle" also mean "central is not
*blocked* during the middle."

**Foreground is the explicit EXCEPTION**, reserved for the narrow case
where **the next step is immediate integration with nothing else
interleavable** — e.g. a single short dispatch whose return is the only
thing central is waiting on and which it will merge + close the instant
it lands, with no conversation, planning, or staging to fill the gap.
If anything else could usefully happen while the agent runs, background
it.

### Concurrency caution — never two full-suite loops in one repo at once

Backgrounding makes it *easy* to have multiple agents in flight; that
is the point. But there is one hard concurrency rule: **never run two
full-suite loops in the same repo at the same time.** Two suite runs
racing in one working tree contend on shared git/bd state and produce
nonsense results.

This is not hypothetical. During the loom-fx9m close detour
(2026-06-08), a foreground-wait combined with the harness
auto-backgrounding a long-running loop produced **two suite runs racing
in one repo**. When the duplicate suite task was `TaskStop`'d, it left
**orphan `bd-post-rewrite` child processes** behind — `TaskStop` reaps
the task it targets but **may not reap that task's grandchildren**, so
the orphaned children kept racing on git/bd state and yielded a **false
`63/2` suite result**. The lesson: one suite loop per repo at a time,
and after a `TaskStop` confirm no orphan `bd-post-rewrite` (or other
grandchild) processes survived before trusting any suite number.

---

## Central's sequence

Central runs these steps. Central **writes nothing** between step 1
and step 5 — every test/code edit happens inside a subagent (and, per
the Dispatch-mode section above, dispatches each with
`run_in_background: true` by default so the turn is never held idle).

### Step 1 — No shared worktree to set up

Unlike the original design, central does NOT pre-create one shared
worktree. Each dispatched agent gets its OWN auto-named
`isolation: "worktree"` from the `Agent` tool. Central's only job
between dispatches is to **relay the verbatim RED-test content** the
test-author returns into the implementer's brief — the content-bridge.

### Step 2 — Dispatch the TEST-AUTHOR

`Agent` with `isolation: "worktree"` and **`model:<strong>`** — the
test-author sets the ceiling, so it gets the stronger model (see the
"Model-tier policy" section above; tier is per-dispatch, the agent
definition stays `model:inherit`). Its OWN fresh, auto-named worktree.
Build the brief from ONLY:

- the locked **CONTRACT** (the bead's `RED:` line / M1 spec /
  acceptance criterion) — verbatim, nothing more;
- the **interface under test** (the function/CLI/hook signature it
  will exercise — names + shapes, not the implementation body);
- the **pre-flight smoke battery** (`.claude/rules/dispatched-agents.md`)
  as the first bash call;
- the instruction: **write the RED test that pins the contract,
  commit it, and RETURN THE VERBATIM TEST FILE CONTENT (the test text
  itself, not just a path) plus the failure output; do NOT implement.**

Do NOT paste session history, your own reasoning, or unrelated files.
Minimal slice only.

The test-author returns: the **verbatim RED-test file content** + the
verbatim failure output + the commit SHA (+ its worktree path, for the
path-capture fallback).

### Step 3 — Dispatch the IMPLEMENTER (its OWN fresh worktree)

`Agent` with `isolation: "worktree"` and **`model:<cheaper>`** — the
implementer is gated against the test-author's fixed ceiling, so it can
run on a cheaper model (keep author tier ≥ implementer tier; see the
"Model-tier policy" section above; tier is per-dispatch, the agent
definition stays `model:inherit`). A separate, fresh, auto-named
worktree of its own. Central relays the test-author's **verbatim test
content** into this brief over the content-bridge. Build the brief
from ONLY:

- the **verbatim RED-test content** to recreate (the implementer reads
  the test as an ARTIFACT — it does NOT receive the test-author's
  reasoning, mind, or conversation);
- the **code area** (the file/module to change);
- the **pre-flight smoke battery** as the first bash call;
- the instruction: **recreate the test file exactly from the relayed
  content, confirm it is RED, then make the RED test pass with the
  minimal change; do NOT modify or weaken the test; if the test looks
  wrong, STOP and report to central** (do not "fix" the test
  yourself).

This is the independence rule made mechanical: the implementer
never sees the test-author's reasoning, so the implementation can't be
shaped to match a private intent — only to satisfy the public
artifact. That is how the test-author == code-author anti-pattern is
solved by construction, now with both agents fully isolated.

The implementer returns: GREEN pass/fail counts + the commit SHA.

*(LARGE test? Use the path-capture fallback — point the implementer's
`cd` at the test-author's returned worktree path so it reads the
committed test off the same worktree on disk instead of recreating it
from relayed content.)*

### Step 4 — OPTIONAL verifier

If the change warrants review, dispatch the existing
`requesting-code-review` / `code-reviewer` agent against the worktree
diff. Optional in v1; skip for small middles.

### Step 5 — Hand back to central for integration

The pipeline hands a SUMMARY back to central (RED output, GREEN
counts, commit SHAs, any stop-and-report flags). Central — and ONLY
central, because integration is cwd-sensitive and bd-authoritative —
then does **verify + merge + close + capture** (see
`bead-lifecycle-shell` phases C/D). As part of verify, central
**re-runs the test and checks the assertion count** to confirm the
implementer recreated it faithfully over the content-bridge (the cheap
guard the on-disk shared file used to give for free). Central does not
re-do the middle; it integrates what the pipeline produced.

If the implementer hit a stop-and-report (the test looked wrong),
central resolves the contract dispute — re-brief the test-author or
re-lock the contract — rather than letting the implementer weaken the
test.

---

## Context-scoping discipline

The whole point is that each agent gets ONLY its slice:

- **Test-author** gets the contract + interface. NOT the
  implementation, NOT central's reasoning, NOT session history.
- **Implementer** gets the verbatim RED-test content + the code area.
  NOT the test-author's reasoning, NOT the contract dialogue.
- **Central** keeps the minimal slice it needs to brief + relay +
  integrate — it does NOT dump its session history into any brief.

Minimal slice per brief is what kills failure mode #3 (junk context)
and reinforces #2 (independence): an implementer that never sees the
author's mind cannot collapse the two roles back into one.

---

## Brief template — TEST-AUTHOR

Fill the `<…>` slots with the minimal slice. Paste nothing else.
**Dispatch this agent with `model:<strong>`** — the test-author sets
the ceiling (per the Model-tier policy section; keep author tier ≥
implementer tier).

```
You are the TEST-AUTHOR for bead <bead-id>. You run in your OWN
isolation worktree (auto-named by the Agent tool — there is no shared
worktree). Write the RED test only. Do NOT implement.

STEP 0 — Run the pre-flight smoke battery from
.claude/rules/dispatched-agents.md as your FIRST bash call. Abort and
report if any check FAILs. Use relative paths for all Edit/Write.

CONTRACT (the bead's RED: line / M1 spec / acceptance — pin EXACTLY
this, nothing more):
<contract — verbatim RED: line goes here>

INTERFACE UNDER TEST (names + shapes only):
<function / CLI / hook signature here>

YOUR TASK:
1. Write the test that pins the contract above. It must FAIL now
   (the implementation does not exist / is wrong yet).
2. Run it; confirm RED. Capture the failure output verbatim.
3. Commit ONLY the test file:
   git add <test-path> && git commit -m "<bead-id>: RED <contract> test"
   (do NOT git add .beads/issues.jsonl)
4. Do NOT write any implementation. If the contract is unclear or
   self-contradictory, STOP and report to central — do not guess.

RETURN: the VERBATIM TEST FILE CONTENT (the full test text, so central
can relay it to the implementer over the content-bridge) + the
verbatim failure output + the commit SHA + this worktree's path (for
the path-capture fallback if the test is large).
```

## Brief template — IMPLEMENTER

**Dispatch this agent with `model:<cheaper>`** — the implementer is
gated against the test-author's fixed ceiling (per the Model-tier
policy section; keep author tier ≥ implementer tier).

```
You are the IMPLEMENTER for bead <bead-id>. You run in your OWN fresh
isolation worktree (auto-named by the Agent tool). The test-author's
RED test is handed to you below as VERBATIM CONTENT — recreate it
exactly; you have NOT seen how or why it was written. Make it pass
with the minimal change.

STEP 0 — Run the pre-flight smoke battery from
.claude/rules/dispatched-agents.md as your FIRST bash call. Abort and
report if any check FAILs. Use relative paths for all Edit/Write.

RED TEST (your only spec — treat it as an ARTIFACT; recreate the file
EXACTLY from this verbatim content, character-for-character):
<red-test — the verbatim test content to recreate goes here>

(For a LARGE test, central instead points your cd at the test-author's
worktree so you read the committed test off the SAME worktree on disk —
path-capture fallback. Default is to recreate from the content above.)

CODE AREA (the file/module to change):
<implementation file/module here>

YOUR TASK:
1. Recreate the RED test file exactly from the verbatim content above
   (or read it off disk via the path-capture fallback). Run it;
   confirm it is RED.
2. Make the MINIMAL change to the code area that turns it GREEN.
3. Do NOT modify, weaken, delete, or skip the test. If the test looks
   WRONG (over-specified, testing the wrong thing, contradicts the
   interface), STOP and report to central — do NOT "fix" the test
   yourself. Resolving a bad contract is central's job, not yours.
4. Run the test; confirm GREEN. Run the surrounding suite to confirm
   no regressions.
5. Commit ONLY the test file + the implementation:
   git add <test-path> <code-path> && git commit -m "<bead-id>: GREEN <contract>"
   (do NOT git add .beads/issues.jsonl)

RETURN: the GREEN pass/fail counts + the commit SHA + any
stop-and-report. If you processed only a SAMPLE/subset of a larger
set (you handled N-of-M items rather than all M), say so explicitly
with a `Processed: X of Y` line — NEVER silently sample.
```

---

## DO / DON'T

- **DO** keep central orchestration-only through the middle — central
  writes nothing.
- **DO** dispatch each agent with **`run_in_background: true` by
  default** (lean-central: central yields the turn and resumes on the
  completion event); reserve foreground for the narrow
  immediate-integration exception (see the Dispatch-mode section).
- **DO** give each agent its OWN `isolation: "worktree"`; relay the
  test-author's verbatim content to the implementer over the
  content-bridge (or use the path-capture fallback for a large test).
- **DO** dispatch the test-author with `model:<strong>` and the
  implementer with `model:<cheaper>` — keep author tier ≥ implementer
  tier (the inverted rule; a default nudge, not a gate).
- **DO** give each brief only its slice.
- **DO** re-run the test + check the assertion count at central's
  verify step, to confirm the implementer recreated the test
  faithfully over the content-bridge.
- **DO** surface sampling transparently in any worker's return: a
  worker that processed only a SAMPLE/subset of a larger set MUST
  report `Processed: X of Y` (the sampled_of_total) — never silently
  sample (loom-z3m.16). When the input set is large, brief the
  `sampled_of_total` field requirement in. See the "Worker-report
  sampling transparency" section of `.claude/rules/dispatched-agents.md`.
- **DON'T** try to force both agents into one shared worktree — the
  Agent tool auto-names isolated worktrees and gives no handle to
  reuse another agent's tree (loom-fx9m).
- **DON'T** let central write the test or the code "just this once" —
  that re-collapses test-author and implementer into one mind.
- **DON'T** let the implementer modify the test. A failing implementer
  reports; it does not weaken the spec.
- **DON'T** dispatch the implementer on a STRONGER model than the
  test-author — that inverts the ceiling rule. And **don't** bake a
  tier into any agent definition; tier is per-dispatch, definitions
  stay `model:inherit`.
- **DON'T** run two full-suite loops in the same repo at once — they
  race on git/bd state. After a `TaskStop`, confirm no orphan
  `bd-post-rewrite` grandchild processes survived before trusting any
  suite number (the loom-fx9m false `63/2` result).
- **DON'T** dump session history into a brief.
