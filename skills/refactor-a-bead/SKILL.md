---
name: refactor-a-bead
description: Activity recipe for working a refactor-shaped beads issue. Owns the refactor-specific variable middle — identify scope → write characterization tests if missing → restructure → verify behavior preserved (tests stay GREEN throughout, never RED). Defers to the bead-lifecycle-shell skill for claim/isolate/verify/close/capture. Triggers on phrases like "refactor X", "extract Y", "rename Z", "consolidate ...", "restructure ...", or right after the session-startup or /working-a-bead router picks a refactor bead.
disable-model-invocation: true
---

# Refactor-a-Bead — Variable Middle for Refactor-Shaped Beads

This skill owns ONLY the refactor-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim + worktree,
verification, commit, finish-branch, close + capture — lives in the
`bead-lifecycle-shell` skill. This recipe cites those phases by letter
and supplies the variable middle that runs between phase A (pre-middle)
and phase B (verification).

**The central inversion.** Bugfix and feature recipes both write tests
that go RED→GREEN: the test articulates the new behavior, then the
code catches up. Refactor INVERTS this. Tests come BEFORE the
restructure and must KEEP passing throughout. There is no RED state —
characterization tests are GREEN at write time because they pin
*current* behavior. The restructure introduces no new behavior; the
test suite is the contract that the refactor must not break. If a
test went RED during the refactor, either the refactor changed
behavior (bug just introduced) or the test was pinning an
implementation detail that needs investigation. Test edits during a
refactor are a smell, full stop.

Keep this inversion in mind at every step. It is the difference
between a refactor that ships safely and a refactor that quietly
becomes a behavior change.

`disable-model-invocation: true` — this recipe runs only when explicitly
invoked, either directly (`/refactor-a-bead <bead-id>`) or via the
`/working-a-bead` router that selects an activity recipe by bead shape.

## When to use

Right after `session-startup` (or the `/working-a-bead` router) picks
a refactor-shaped bead, OR whenever you start implementation on a
claimed refactor. A bead is refactor-shaped when the deliverable is
*restructure with no observable behavior change*: extracting a
function, renaming a symbol consistently, consolidating duplicate
code paths, splitting a module, switching an internal data shape,
inlining a wrapper, etc. The external contract — what callers see,
what tests assert — stays exactly the same.

## Skip when

- The bead is bug/feature/research/cleanup/docs-shaped — use the
  matching activity recipe instead.
- **The change is also altering observable behavior.** Refactor +
  feature in one bead is the most common antipattern this recipe
  exists to prevent. Split it: do the behavior change as a
  feature-a-bead (or bugfix-a-bead) bead, then the restructure as
  a separate refactor-a-bead bead. The two halves merge cleanly in
  history and each gets the right discipline.
- The change is removal rather than restructure (deleting dead
  code, dropping a deprecated path, retiring a feature flag). Use
  `cleanup-a-bead` — it's removal-shaped, not refactor-shaped.
- Mid-task interruption. This recipe is for new refactor starts,
  not for context recovery within an in-flight bead.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written.
  Characterization tests written if missing, full suite run after
  every meaningful restructure step, test diff inspected at phase B.
- **light** — characterization-test discipline still strongly
  recommended; the warning is that skipping it removes the tripwire
  that makes the refactor safe. Without characterization tests you
  are restructuring blind, and a behavior change can land without
  any signal. The shell's mode warning covers ceremony reduction
  generally; the recipe-specific risk in light mode is silent
  behavior drift.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds activity-specific intermediate stages between phase A
and phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (identify scope) | `scoping` |
| Entering step M2 (characterization tests) | `characterizing` |
| Entering step M3 (restructure) | `restructuring` |
| Entering step M4 (verify behavior preserved) | `verifying-behavior` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>`
at the moment the step starts. The status line surfaces these so
future cold-start sessions can see exactly where work paused. For
refactors, `restructuring` is the stage that often spans many small
edits — the stale-stage timer is forgiving here, but the test suite
should be running between every meaningful edit regardless.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:
- **A1.** MemPalace search for the refactor family (sets stage
  `research`). For refactors the query patterns are:
  - `mempalace_search "<area> refactor"` and
    `mempalace_search "<pattern> extracted|renamed|consolidated"` —
    has someone already restructured this code in a prior pass? Has
    the *opposite* refactor been done before and reverted?
  - `mempalace_kg_query("<entity-name>")` for any entity in the
    bead, and follow `sibling-of` and `derived-from` triples — the
    sibling-of relation is gold for refactors because the family
    of code-with-the-same-shape is exactly what's being restructured.
  - `mempalace_search "<original design decision>"` — the original
    decision that introduced the shape being refactored. Preserving
    its *intent* matters even when changing its form.
  - `bd memories <keyword>` for tribal one-liners about this area.
- **A2.** `bd update <id> --claim`, then optional worktree on
  `frank/<bead>` from `main`. Refactors usually warrant a worktree
  even when the diff is mechanical, because mid-refactor states are
  often broken and you don't want them on `main`.

If the search at A1 surfaces the original design decision that
introduced the current shape, read it carefully BEFORE M1. The
refactor must preserve whatever invariant that decision was
protecting, even if the form changes. If the original invariant no
longer holds, the bead is actually a feature/bugfix masquerading as
a refactor — split it.

### Variable middle — M1 → M4 (recipe owns)

#### M1. Identify scope

Set stage `scoping`. State explicitly, in user-facing output:

- **What is in scope.** The exact files, modules, or symbols being
  restructured. Be specific — "the `X` class", not "the X area".
- **What is NOT changing.** The external contract: function
  signatures (or the explicit list of signature changes that are
  pure renames with no semantic shift), return types, error shapes,
  observable side effects, persisted formats, wire formats. List
  these affirmatively so future you can spot drift.
- **The target shape.** What the code should look like when done.
  One or two sentences, concrete. "Extract the validation logic
  from `parse()` into a `Validator` struct in the same package, no
  exported API change" is a good target shape; "clean up parsing"
  is not.
- **What tests already cover this.** Run the test files that touch
  the in-scope code (`go test -run <Pattern>`, `pytest path/`,
  whatever the project uses). Note coverage gaps — those are the
  M2 candidates.

If any of these four can't be stated cleanly, the bead is
underspecified — pause and refine, or split. A vague refactor scope
is the single most common cause of "while I'm here" sprawl.

#### M2. Write characterization tests if missing

Set stage `characterizing`. The job here is to install a tripwire
*before* touching the code. If any breakage during M3 trips the
tripwire, you find out immediately and can revert one step instead
of debugging an opaque downstream failure.

Two cases:

1. **The area is already well-tested.** Document the existing tests
   that play this role — name them by file/function in user-facing
   output ("M2 satisfied by `parser_test.go::TestParseAll/*` and
   `validator_test.go::TestRoundTrip/*` — 47 cases covering all
   in-scope code paths"). Then move to M3. Do not write redundant
   tests just to fill the step; the existing suite is the
   characterization.

2. **The area is under-tested for the refactor's purposes.** Write
   tests that pin *current* behavior. This is itself a small TDD
   cycle, but with an inverted assertion: each test must pass
   GREEN against current code on the first run. If a
   characterization test goes RED on first run, either you
   misunderstand current behavior or there's a latent bug — both
   need investigation before continuing.

   Characterization tests should be:
   - **Behavior-pinning, not implementation-pinning.** Test what
     callers observe (return values, side effects, errors), not
     internal helper calls or private state. Implementation-pinning
     tests will block valid refactors and force you to edit them
     during M3 — exactly what this recipe is trying to prevent.
   - **Comprehensive at the boundary being preserved.** Include the
     happy path, the error path, the boundary cases, and any
     known-quirky behavior. Quirky behavior is the most likely to
     be accidentally "fixed" by a refactor.
   - **Verbatim where it matters.** If error messages or log lines
     are part of the contract, assert them verbatim.

Run the new tests against unchanged code. They MUST all pass
GREEN. Only then proceed to M3. Commit the characterization tests
as a separate commit before the restructure if the project
convention allows — it makes the test diff at phase B trivially
inspectable (it should be empty).

#### M3. Refactor — restructure without changing behavior

Set stage `restructuring`. Make the change the bead describes,
moving in small steps. The discipline:

- **Run the test suite frequently — every meaningful step.** The
  whole point of M2 was to install a tripwire; a tripwire only
  works if you check it. After each rename / extraction / move /
  consolidation, run the affected tests. After a few of those, run
  the broader suite. The cost of finding a regression at the next
  step is much lower than at the end.
- **Commit small.** Each green checkpoint is a candidate
  micro-commit on the branch. If you discover at step 7 that step
  3 broke something subtle, you want to bisect, not unravel.
- **No "while I'm here" edits.** If you spot an unrelated
  improvement, file it as a follow-up bead. Adding it here breaks
  the "no behavior change" guarantee even if the improvement is
  itself behavior-preserving — because every extra change widens
  the surface that future readers must verify is safe.
- **No test edits.** If a test starts failing during M3, STOP.
  Investigate. Either:
  - The refactor changed behavior (most common; revert the last
    step and try a different approach), or
  - The test was implementation-pinning (less common; document
    what implementation detail it was pinning, then carefully
    relax it — but do this as a separate, named, justified change,
    not a quiet edit).

  Editing a test to keep it passing during a refactor without
  understanding why it failed is the canonical way refactors
  silently become bug-injection events.

#### M4. Verify behavior preserved

Set stage `verifying-behavior`. Two checks, in order:

1. **Full suite, characterization tests included, must pass
   UNCHANGED.** Not "still passing after I tweaked them" — passing
   on the same assertions they had at end of M2.

2. **Inspect the test diff.** Run `git diff main -- <test-paths>`
   (or the equivalent against the refactor's base commit). The
   diff should be empty or near-empty:
   - Empty diff: ideal. The refactor preserved behavior cleanly.
   - Renames only (e.g., import-path updates from a moved file):
     acceptable, but check each rename is mechanical.
   - Anything else: a smell. Each non-rename test edit must be
     justified in user-facing output before phase B. If you can't
     justify it, the refactor changed behavior and the bead should
     be split or restated as a feature/bugfix.

If the test diff is more than mechanical, do not advance to phase
B. Return to M3 (or re-scope at M1) and bring the test diff back
to near-empty before claiming the refactor is done.

### Phase B — verification (delegate to shell, with refactor extension)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Re-run the full suite from a clean shell, confirm exact pass/fail
counts, check `git diff --stat` matches intended scope.

**extends phase B with: full suite + characterization tests must
all pass UNCHANGED, and the diff for tests should be empty or
near-empty.** State the test diff explicitly in user-facing
output: file count, line count, whether all changes are mechanical
(rename / import-path / etc). Commits with large test diffs are a
refactor smell — surface this loudly to the user before phase C
rather than papering over it.

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:
- **C1.** Code review (per task if multiple). Reviewers should
  particularly scrutinize the test diff for non-mechanical changes
  — that's where regressions hide in refactor PRs.
- **C2.** Commit on the branch (sets stage `commit`). Subject +
  body should name what was restructured, what shape it took, what
  was explicitly preserved, and the test count + test-diff summary
  ("47 tests, test diff: 3 import-path renames only"). Co-author
  trailer.
- **C3.** `superpowers:finishing-a-development-branch` — pick from
  the four options (merge / push & PR / keep / discard).

### Phase D — closeout (delegate to shell, with refactor extension)

Follow `bead-lifecycle-shell` phase D:
- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push` →
  `git push` (sets stage `close`).
- **D3.** Drawer + KG triples + diary capture (sets stage
  `wrap-up`). The closing drawer for a refactor names: **what was
  restructured** (the before-shape), **what shape it took**
  (the after-shape), **what was preserved** (the explicit list
  from M1's "what is NOT changing"), and **the
  characterization-test fingerprint** (the test count and any
  named test files that play the contract role). The fingerprint
  matters because future refactors of the same area need to know
  which tests are load-bearing for behavior preservation.

  KG triples: `<after-shape>` `derived-from` `<before-shape>`,
  plus any `sibling-of` triples to other code that took the same
  shape (so future "consolidate the family" work surfaces
  naturally).

## When the refactor surfaces a real bug

Sometimes M3 surfaces existing buggy behavior — a code path that
was wrong all along, exposed because the restructure makes it
visible. Default response: file a sibling bugfix bead and decide
whether to fix in this bead's scope or in a follow-up.

- **Default: split.** File a bugfix-a-bead bead, link it to this
  refactor bead, finish the refactor preserving the buggy behavior
  as-is (the characterization test pins the bug; that's fine —
  the bug was already there). Then claim the bugfix bead and run
  bugfix-a-bead on it. Two clean commits, two clean lineages.
- **Rare: fix in scope.** Only when the refactor is genuinely
  impossible without the fix — e.g., the buggy behavior depends
  on the shape being removed. In that case: name the in-scope
  fix explicitly in M1's scope statement, update the
  characterization test to pin the corrected behavior (this is
  the one place test edits are legitimate during this recipe,
  and only because the scope statement now permits it), and call
  out the conflated change in the closing drawer.

If you find yourself in the rare case more than once or twice,
that's a sign the bead was misshapen at filing time — a flag for
the router (loom-1ab) and the recipe-shape heuristics.

## Failure modes (concrete)

- **Skip M2 (characterization tests):** the refactor has no
  tripwire. A behavior change lands silently because no test
  asserts the contract that just shifted. Discovery happens later
  in production or via a downstream consumer's failed test, and
  the lineage to this refactor is no longer obvious. Always
  install the tripwire before restructuring, even if writing the
  tests feels redundant — that feeling is exactly when they
  matter most.
- **Edit tests to keep them passing instead of investigating
  why they failed:** the canonical way a refactor becomes a
  silent bug-injection event. The test was the contract; you
  just rewrote the contract to match the new behavior and now
  the regression has no signal. STOP at the first RED test, do
  not edit the assertion, investigate.
- **Conflate refactor with feature ("while I'm restructuring,
  let me also add ..."):** the diff balloons, the test diff
  balloons with it, the "no behavior change" guarantee is gone,
  and the reviewer can't distinguish the restructure from the
  feature. Split into two beads at M1 — refactor first, feature
  second — and the two commits compose cleanly.
- **"While I'm here" scope creep:** adjacent code looks ugly,
  you tidy it up "for free." Each touch widens the verification
  surface and makes the closing drawer's "what was preserved"
  list a lie. File the tidiness as a follow-up bead and stay in
  the original scope.
- **Refactor surfaces a bug and the bug gets buried:** you
  notice the buggy code path during M3, fix it in the same
  commit because it feels small, and the fix is now invisible in
  history because the commit message is about the restructure.
  Two months later someone reviewing the refactor PR can't
  understand why a test changed. File the bug as a sibling bead
  even when fixing in scope; the drawer-level lineage is what
  saves the future reader.
- **Implementation-pinning characterization tests written at
  M2:** the tests assert internal helper calls or private state.
  M3 starts to fail immediately, you can't tell whether behavior
  changed or just internals shuffled, M2 has to be redone.
  Characterization tests must pin the boundary, not the
  internals — that's the whole point.

## Related infrastructure

This recipe is the refactor-shaped peer to `bugfix-a-bead`. The
cross-activity lifecycle scaffolding lives in `bead-lifecycle-shell`.
Sibling activity recipes:

- `bugfix-a-bead` (loom-lzi) — bug-shaped middle (debug → RED →
  GREEN → bug-class → enshrined-sweep)
- `feature-a-bead` (loom-5rf) — feature-shaped middle
- `research-a-bead` (loom-0q0) — define → search → synthesize → file
- `cleanup-a-bead` (loom-62x) — scope → remove → verify
- `docs-a-bead` (loom-s0n) — gap → draft → review

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + description heuristics.

Subagents that integrate with this recipe:
- `bug-family-researcher` — phase A1 helper; for refactors it
  surfaces prior restructures and the original design decisions
  that introduced the current shape.
- `drawer-author` — phase D3 helper; drafts the closing decision
  drawer including the characterization-test fingerprint.
- `kg-relationship-extractor` — phase D3 helper; proposes
  `derived-from` and `sibling-of` triples that make future
  family-aware refactors discoverable.

Full design + locked decisions live in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02). Build queue tracked under loom epic `loom-0y6`.
