---
name: feature-a-bead
description: Activity recipe for working a feature-shaped beads issue. Owns the feature-specific variable middle — brainstorm the design → optionally split into a plan + child beads → RED test that pins the desired contract → minimal GREEN implementation → negative-cases + integration coverage. Defers to the bead-lifecycle-shell skill for claim/isolate/verify/close/capture. Triggers on phrases like "let's work on <feature-bead-id>", "build <bead-id>", "implement <bead-id>", or right after the session-startup or /working-a-bead router picks a feature bead.
---

# Feature-a-Bead — Variable Middle for Feature-Shaped Beads

This skill owns ONLY the feature-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim + worktree,
verification, commit, finish-branch, close + capture — lives in the
`bead-lifecycle-shell` skill. This recipe cites those phases by letter
and supplies the variable middle that runs between phase A (pre-middle)
and phase B (verification).

The conceptual shift from `bugfix-a-bead` is small but load-bearing:
a bug has a symptom, so the RED test reproduces that symptom verbatim
and GREEN makes the symptom go away. A feature has no symptom — it
has a *desired contract*. The RED test pins that contract (the
feature's API, output shape, observable behavior) and is initially
red because the feature doesn't exist yet. GREEN is the first
implementation that satisfies the contract. Get this shift wrong and
you write tests that pin implementation details instead of contract,
which is the most common way feature TDD turns into theater.

Negative cases play the role that bug-class coverage plays in
bugfix-a-bead: every new contract introduces new failure modes
(invalid input, edge cases, partial-failure paths). Cover them at
landing time so the next regression surfaces fast — don't wait for a
production bug to teach you what your validation surface looks like.

Invocation: explicit only — either directly (`/feature-a-bead <bead-id>`)
or via the `/working-a-bead` router that selects an activity recipe by
bead shape. The Skill tool may surface this recipe via auto-discovery
when a message strongly matches the trigger phrases above; if that
happens at the wrong moment (e.g., the bead isn't feature-shaped),
decline and switch to the right recipe.

## When to use

Right after `session-startup` (or the `/working-a-bead` router) picks a
feature-shaped bead, OR whenever you start implementation on a claimed
feature bead. A bead is feature-shaped when the deliverable is *new
behavior* — a new API surface, a new command, a new module, a new
output — not a fix to existing behavior and not a structural rework
that preserves behavior.

## Skip when

- The bead is bug/refactor/research/cleanup/docs-shaped — use the
  matching activity recipe instead. Particularly common confusion:
  "feature that fixes a missing capability" is often actually
  bug-shaped (the missing capability has a symptom and a regression
  test target); "feature that restructures existing behavior" is
  often refactor-shaped.
- Pure spike with no committed contract yet — use
  `superpowers:brainstorming` (or `beadpowers:brainstorming`) until
  the design lands as a contract, then re-engage this recipe.
- Mid-task interruption. This recipe is for new feature starts, not
  for context recovery within an in-flight bead.
- Multi-task feature work where M2 (planning) splits the bead into
  child beads — once the plan lands, each child bead re-enters this
  recipe (or a different shape's recipe) on its own claim.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written.
  Brainstorm before testing, RED before GREEN, negative-cases +
  integration test mandatory.
- **light** — brainstorm at M1 still recommended (skipping it usually
  costs more than it saves), but the formal `superpowers:writing-plans`
  step at M2 becomes optional, and the integration test at M5 may
  collapse to "the unit test exercises the integration boundary."
  Negative-cases coverage stays recommended.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds activity-specific intermediate stages between phase A
and phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (brainstorm the design) | `designing` |
| Entering step M2 (plan if multi-task) | `planning` |
| Entering step M3 (RED — pin the contract) | `red` |
| Entering step M4 (GREEN — minimal implementation) | `green` |
| Entering step M5 (negative cases + integration) | `integration` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>` at
the moment the step starts. The status line surfaces these so future
cold-start sessions can see exactly where work paused. Feature beads
often span multiple sessions — the brainstorm at M1 and the contract
test at M3 are natural pause points and deserve accurate stage
markers.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:
- **A1.** MemPalace search for the feature family (sets stage
  `research`). For features the search has TWO targets:
  1. **Pattern hunt** — `mempalace_search "<area> <feature-shape>"`
     plus `mempalace_kg_query("<entity>")` to find sibling features
     in the same area. Existing conventions (file layout, test
     scaffolding, naming) should be honored unless the bead
     explicitly diverges.
  2. **Prior-art hunt** — search for prior decisions about the
     contract being designed. If the contract overlaps with an
     existing API surface, the prior decision drawer is the
     authoritative source on what the surface should look like;
     you're extending, not inventing.
- **A2.** `bd update <id> --claim`, then worktree on `frank/<bead>`
  from `main`. Features almost always touch project source, so the
  worktree is rarely skipped — only for ≤1-line config-style features
  with no real implementation surface.

If the search surfaces a sibling feature in the same family (same
service, same module, same output shape), restate the design at M1 in
terms of that lineage BEFORE the brainstorm goes deep. Diverging from
established convention without naming the divergence is the most
common way features cause cleanup work three months later.

### Variable middle — M1 → M5 (recipe owns)

#### M1. Brainstorm the design

Set stage `designing`. The design must be explicit BEFORE any test is
written — features without an upfront contract produce tests that pin
implementation accidents instead of intent.

Choose the brainstorming variant by where the design will land:
- **`beadpowers:brainstorming`** — when the design will land as new
  beads (epics + child tasks). This is the right choice when the
  feature is non-trivial and will be implemented across multiple
  beads — the brainstorm output IS the bead structure.
- **`superpowers:brainstorming`** — when the design will land as a
  spec or plan in `docs/` (single-bead implementation, but design
  needs to be captured for review before code).

The brainstorm should produce, at minimum: the contract (input shape,
output shape, observable behavior), the failure modes the contract
introduces, and the boundary with adjacent components. State the
contract to the user before moving to M2 — a misstated contract is
the most expensive failure mode of this recipe, because every test
written downstream pins the wrong thing.

If the brainstorm reveals the bead is actually bug-shaped or
refactor-shaped (the contract already exists; you're fixing or
restructuring it), pause here and switch recipes. Mis-typed beads
waste the rest of the middle.

#### M2. Plan if multi-task

Set stage `planning`. Decide whether the work is single-task or
multi-task. Single-task means one branch, one verification pass, one
commit family. Multi-task means the contract from M1 decomposes into
discrete pieces with their own verification surfaces.

For multi-task work, invoke `superpowers:writing-plans`:
- Draft the plan in `docs/plans/<bead-id>-<slug>.md` (or the project's
  conventional plan location).
- File child beads under this bead (or under the same epic, blocked
  on this bead) for each task in the plan.
- This bead becomes the *coordinator* — its closing drawer documents
  the contract; the child beads carry the implementation.

For single-task work, skip `superpowers:writing-plans` and continue
to M3 in this same bead. Don't invent ceremony for a one-step
implementation.

The judgment call: if you'd write more than ~3 commits to land the
feature, or the feature crosses more than ~2 service boundaries,
plan it. Otherwise inline.

#### M3. RED — pin the desired contract

Set stage `red`. Invoke `superpowers:test-driven-development`. Write
the failing test that pins the contract from M1.

This is the conceptual hinge of the recipe. The test is initially red
not because of a bug but because the feature doesn't exist yet. The
test should describe the *contract*, not the implementation:
- For an API: pin the request/response shape and the observable
  state change, not the internal call sequence.
- For a CLI: pin the command surface, exit code, and stdout/stderr
  shape, not the helper functions that produce them.
- For a module: pin the public function signatures and their
  behavior under representative inputs, not private helpers.

Run the test, watch it fail with the *expected* failure (typically
"undefined symbol" or "function returns nil" before any
implementation exists), and paste the failure to user-facing output
BEFORE moving to M4. If the test fails for a different reason (test
setup is broken, the contract assumes something that isn't true),
fix that BEFORE writing implementation — a mis-RED test produces
a deceptive GREEN.

#### M4. GREEN — minimal implementation

Set stage `green`. Smallest implementation that satisfies the
contract test. Resist the urge to build out the full feature surface
in this step — keep the diff focused on what the M3 test actually
exercises so the contract→implementation lineage stays legible in
git history.

Re-run the M3 test to confirm GREEN. If you wrote multiple contract
tests at M3 (a feature with several observable behaviors), make them
all GREEN before advancing — but don't add behaviors the tests don't
exercise.

The git log after M4 should show: one commit-shaped diff that adds
the failing test, then one commit-shaped diff that makes it pass.
This is auditable evidence that the contract drove the
implementation, not the other way around. Use the
`git commit --fixup`/squash dance later if your project's convention
prefers a single commit, but the RED→GREEN order should be visible
during the bead.

#### M5. Negative cases + integration test

Set stage `integration`. New contracts introduce new failure modes;
this step covers them.

**Negative cases** — for each input dimension the contract names,
write a test for the failure path:
- For input validation: the malformed-input case, the empty-input
  case, the boundary cases on either side of any limit.
- For partial failures: the case where a downstream dependency
  errors mid-call, the case where the operation needs to be
  rolled back.
- For state preconditions: the case where the precondition is
  violated.

This is the bug-class equivalent for features. Without it, the first
production failure becomes a bug bead in the same family three weeks
later — and that's a self-inflicted wound: the failure modes were
visible at design time. Frank's durable rule from HAW 13p.3.11
generalizes: *"write a test for the contract AND for the contract's
failure surface."*

**Integration test** — exercise the feature end-to-end against real
systems where applicable:
- For an API endpoint: a test that hits the real router with the
  real request payload and asserts the real response.
- For a CLI: a test that shells out to the real binary with the
  real arguments.
- For a service-to-service feature: a test that exercises the
  cross-service call path against a real (or testcontainer-real)
  dependency.

If the feature has no meaningful integration surface (a pure
function with no I/O), skip the integration test and document that
in the closing drawer. Don't fake an integration test by mocking
everything — that's just a unit test wearing a costume.

### Phase B — verification (delegate to shell, with feature extension)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Re-run the full suite from a clean shell, confirm exact pass/fail
counts, check `git diff --stat` matches intended scope. State results
with evidence in user-facing output BEFORE moving to phase C.

**extends phase B with:** the contract test from M3, the
negative-case tests from M5, and the integration test from M5 must
all pass. The RED→GREEN history from M3→M4 should be auditable
via `git log --oneline` (the failing-test commit precedes the
making-it-pass commit, even if they later get squashed). If the
project squashes feature commits, capture the RED→GREEN evidence in
the closing drawer instead.

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:
- **C1.** Code review (per task if M2 split the work).
- **C2.** Commit on the branch (sets stage `commit`). Subject + body
  should name the contract that landed (one-line summary of the
  feature's observable behavior), the design source (drawer slug or
  plan path), test counts, family lineage if applicable. Co-author
  trailer.
- **C3.** `superpowers:finishing-a-development-branch` — pick from
  the four options (merge / push & PR / keep / discard).

### Phase D — closeout (delegate to shell, with feature extension)

Follow `bead-lifecycle-shell` phase D:
- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push` →
  `git push` (sets stage `close`).
- **D3.** Drawer + KG triples + diary capture (sets stage `wrap-up`).

**extends phase D3 with:** the closing decision drawer must name the
contract that landed (verbatim, in a "WHAT LANDED" section), the
negative-cases coverage achieved (which failure surfaces are now
test-pinned), and any failure surfaces deliberately left uncovered
(with rationale). For features that establish a new convention or
extend an existing one, KG triples are load-bearing — they're what
future phase A1 pattern hunts will surface for sibling features.

## Choosing brainstorming variant

(Already covered at M1, but stated here for parity with sibling
recipes that surface this section explicitly.)

- **`beadpowers:brainstorming`** — design lands as new beads (epics
  + child tasks). Use this when the feature is multi-bead and the
  brainstorm output IS the bead structure.
- **`superpowers:brainstorming`** — design lands as a spec or plan
  in `docs/`. Use this when a single bead carries the implementation
  but the design needs durable capture for review or for future
  feature extensions.

If both are tempting, pick `beadpowers:brainstorming` — beads are
easier to convert to a `docs/` plan than the reverse, and the bead
structure forces explicit decomposition that a free-form spec can
elide.

## Failure modes (concrete)

- **Skip M1 (brainstorm):** the contract is implicit at M3, so the
  RED test pins whatever behavior felt natural to type. Three weeks
  later a sibling feature wants a different contract and there's no
  drawer to cite the original choice — the contract has to be
  reverse-engineered from the test, which is the hard direction.
- **Skip M3 RED (jump straight to implementation):** the test
  written after GREEN tends to pin implementation details (call
  sequences, internal state shapes) rather than contract. When the
  implementation gets refactored, the test breaks for reasons that
  have nothing to do with whether the contract still holds. The
  feature becomes brittle in a way that's hard to diagnose because
  the test pretends to be a contract test.
- **Skip M5 negative cases:** the first production failure becomes a
  bug bead in the same family within weeks. The validation surface
  was visible at M1; not pinning it then is a self-inflicted wound.
  The huu.7.1 / huu.15.2 / huu.19.3 / 0qw chain is the bug-side
  example; features have the same pattern but the original feature
  bead is the canonical owner of the negative-cases coverage.
- **Conflate feature with refactor:** the bead is filed as "add X"
  but the contract from M1 turns out to already exist — what's
  actually needed is a structural rework. Pushing through with the
  feature recipe produces tests that pin behavior the existing code
  already exhibits (so they pass without any change), and the
  "feature" lands as a no-op. Switch to `refactor-a-bead` when M1
  reveals the contract already exists.
- **Over-design before testing:** the brainstorm at M1 expands into
  a multi-week design exercise covering speculative future
  extensions. Plan only what the bead's contract requires; file
  follow-up beads for everything else. The 80% of design that
  speculates about features that don't exist yet is the 80% that
  gets thrown away.
- **Pin implementation in the contract test:** the M3 test asserts
  on internal call counts, mock invocation order, or private state.
  The test passes with any implementation that happens to make those
  internal calls in that order, even if the contract changes
  meaning. Symptom: refactoring breaks the test even when the
  observable behavior is unchanged. Fix: rewrite the test to assert
  on the public observable.
- **Skip the integration test by mocking the integration boundary:**
  the M5 "integration test" mocks the very dependency it was
  supposed to exercise. The test passes locally and silently fails
  the first time the real dependency does anything mocks didn't
  anticipate.

## Related infrastructure

This recipe is the feature-shaped peer to `bugfix-a-bead`. The
cross-activity lifecycle scaffolding lives in `bead-lifecycle-shell`.
Sibling activity recipes:

- `bugfix-a-bead` (loom-lzi) — bug-shaped middle (debug → RED →
  GREEN → bug-class → enshrined-sweep)
- `refactor-a-bead` (loom-uca) — characterization tests + restructure
- `research-a-bead` (loom-0q0) — define → search → synthesize → file
- `cleanup-a-bead` (loom-62x) — scope → remove → verify
- `docs-a-bead` (loom-s0n) — gap → draft → review

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + description heuristics.

Subagents that integrate with this recipe:
- `bug-family-researcher` — phase A1 helper; useful for the
  pattern-hunt and prior-art-hunt searches even though "bug" is in
  the name (the prior-art-surfacing pattern is general).
- `drawer-author` — phase D3 helper; drafts the closing decision
  drawer with the WHAT LANDED + negative-cases-coverage sections.
- `kg-relationship-extractor` — phase D3 helper; proposes KG
  triples for convention-establishing features.

Full design + locked decisions live in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02). Build queue tracked under loom epic `loom-0y6`.
