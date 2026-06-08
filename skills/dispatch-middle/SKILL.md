---
name: dispatch-middle
description: Orchestrate a bead's variable middle as a test-author → implementer (→ optional verify) pipeline of INDEPENDENT subagents in one shared worktree, so central invokes once and writes nothing. The friction-inversion lever — makes dispatch cheaper than inline. Central briefs each agent with ONLY its slice of context (the locked CONTRACT for the test-author; the RED-test-as-file for the implementer), receives GREEN counts, then hands back for verify + merge + close + capture. Triggers on "/dispatch-middle <bead>", or when an activity recipe reaches its RED→GREEN middle and the bead is non-trivial.
---

# Dispatch-Middle — Test-Author → Implementer Pipeline

This skill owns the **variable middle** of a bead's lifecycle when
that middle is a RED→GREEN cycle. It runs the middle as a pipeline of
**independent subagents** in ONE shared worktree, so the central
session **invokes once and writes nothing** — no test, no line of
code, no accumulated junk context.

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
   (a file), not a shared mind. Issue #2 solved by construction.
3. **Central accumulates unrelated context.** Whole-file reads,
   debugging detours, half-formed approaches pile up in central's
   thread. → Fix: central extracts the **minimal slice** per brief;
   no session-history dump.

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

---

## Central's sequence

Central runs these steps. Central **writes nothing** between step 1
and step 5 — every test/code edit happens inside a subagent.

### Step 1 — Ensure a worktree `frank/<bead>`

One shared worktree for the whole pipeline. If it doesn't exist,
create it (see `bead-lifecycle-shell` phase A2 / `using-git-worktrees`).
Both the test-author and the implementer run in THIS worktree, so the
implementer sees the test-author's committed RED test on disk.

### Step 2 — Dispatch the TEST-AUTHOR

`Agent` with `isolation: "worktree"`, pointed at `frank/<bead>`. Build
the brief from ONLY:

- the locked **CONTRACT** (the bead's `RED:` line / M1 spec /
  acceptance criterion) — verbatim, nothing more;
- the **interface under test** (the function/CLI/hook signature it
  will exercise — names + shapes, not the implementation body);
- the **pre-flight smoke battery** (`.claude/rules/dispatched-agents.md`)
  as the first bash call;
- the instruction: **write the RED test that pins the contract,
  commit it, return the failure output verbatim; do NOT implement.**

Do NOT paste session history, your own reasoning, or unrelated files.
Minimal slice only.

The test-author returns: the RED test file path + the verbatim
failure output.

### Step 3 — Dispatch the IMPLEMENTER (SAME worktree)

`Agent`, pointed at the **same worktree** so the committed RED test is
on disk. Build the brief from ONLY:

- the **RED test file path** (the implementer reads the test as an
  ARTIFACT — it does NOT receive the test-author's reasoning, mind, or
  conversation);
- the **code area** (the file/module to change);
- the **pre-flight smoke battery** as the first bash call;
- the instruction: **make the RED test pass with the minimal change;
  do NOT modify or weaken the test; if the test looks wrong, STOP and
  report to central** (do not "fix" the test yourself).

This is the independence rule made mechanical: the implementer never sees the test-author's reasoning, so the implementation can't be shaped to match a private intent — only to satisfy the public artifact. That is how the test-author == code-author anti-pattern is solved by construction.

The implementer returns: GREEN pass/fail counts + the commit SHA.

### Step 4 — OPTIONAL verifier

If the change warrants review, dispatch the existing
`requesting-code-review` / `code-reviewer` agent against the worktree
diff. Optional in v1; skip for small middles.

### Step 5 — Hand back to central for integration

The pipeline hands a SUMMARY back to central (RED output, GREEN
counts, commit SHAs, any stop-and-report flags). Central — and ONLY
central, because integration is cwd-sensitive and bd-authoritative —
then does **verify + merge + close + capture** (see
`bead-lifecycle-shell` phases C/D). Central does not re-do the middle;
it integrates what the pipeline produced.

If the implementer hit a stop-and-report (the test looked wrong),
central resolves the contract dispute — re-brief the test-author or
re-lock the contract — rather than letting the implementer weaken the
test.

---

## Context-scoping discipline

The whole point is that each agent gets ONLY its slice:

- **Test-author** gets the contract + interface. NOT the
  implementation, NOT central's reasoning, NOT session history.
- **Implementer** gets the RED-test-as-file + the code area. NOT the
  test-author's reasoning, NOT the contract dialogue.
- **Central** keeps the minimal slice it needs to brief + integrate —
  it does NOT dump its session history into any brief.

Minimal slice per brief is what kills failure mode #3 (junk context)
and reinforces #2 (independence): an implementer that never sees the
author's mind cannot collapse the two roles back into one.

---

## Brief template — TEST-AUTHOR

Fill the `<…>` slots with the minimal slice. Paste nothing else.

```
You are the TEST-AUTHOR for bead <bead-id>, working in the shared
worktree frank/<bead-id>. Write the RED test only. Do NOT implement.

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

RETURN: the RED test file path + the verbatim failure output + the
commit SHA.
```

## Brief template — IMPLEMENTER

```
You are the IMPLEMENTER for bead <bead-id>, working in the SAME shared
worktree frank/<bead-id>. A RED test already exists on disk. Make it
pass with the minimal change.

STEP 0 — Run the pre-flight smoke battery from
.claude/rules/dispatched-agents.md as your FIRST bash call. Abort and
report if any check FAILs. Use relative paths for all Edit/Write.

RED TEST (your only spec — treat it as an ARTIFACT; you have NOT seen
how or why it was written):
<red-test file path here>

CODE AREA (the file/module to change):
<implementation file/module here>

YOUR TASK:
1. Read the RED test. Run it; confirm it is RED.
2. Make the MINIMAL change to the code area that turns it GREEN.
3. Do NOT modify, weaken, delete, or skip the test. If the test looks
   WRONG (over-specified, testing the wrong thing, contradicts the
   interface), STOP and report to central — do NOT "fix" the test
   yourself. Resolving a bad contract is central's job, not yours.
4. Run the test; confirm GREEN. Run the surrounding suite to confirm
   no regressions.
5. Commit ONLY the implementation:
   git add <code-path> && git commit -m "<bead-id>: GREEN <contract>"
   (do NOT git add .beads/issues.jsonl)

RETURN: the GREEN pass/fail counts + the commit SHA + any
stop-and-report.
```

---

## DO / DON'T

- **DO** keep central orchestration-only through the middle — central
  writes nothing.
- **DO** run both agents in the SAME worktree so the implementer reads
  the test-author's committed file.
- **DO** give each brief only its slice.
- **DON'T** let central write the test or the code "just this once" —
  that re-collapses test-author and implementer into one mind.
- **DON'T** let the implementer modify the test. A failing implementer
  reports; it does not weaken the spec.
- **DON'T** dump session history into a brief.
