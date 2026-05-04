---
name: docs-a-bead
description: Activity recipe for working a docs-shaped beads issue. Owns the docs-specific variable middle — identify the gap → sample sibling-doc voice → draft → review against code for accuracy → optional decision-drawer capture. Defers to the bead-lifecycle-shell skill for claim/verify/close/capture. The doc itself is the deliverable; a tracked file in the repo, not a MemPalace drawer. Triggers on phrases like "document <X>", "fix the docs for <Y>", "write a guide for <Z>", "update the README", "the docs are stale", or right after the session-startup or /working-a-bead router picks a docs bead.
---

# Docs-a-Bead — Variable Middle for Docs-Shaped Beads

This skill owns ONLY the docs-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim, optional
worktree, verification, commit, finish-branch, close + capture —
lives in the `bead-lifecycle-shell` skill. This recipe cites those
phases by letter and supplies the variable middle that runs between
phase A (pre-middle) and phase B (verification).

For a docs bead the deliverable is a **tracked file in the repo** —
`README.md`, something under `docs/`, an inline `.md` next to the
code it describes. The audience is users and contributors, not
future-Claude. That distinguishes docs-a-bead from research-a-bead:
research output is a MemPalace drawer (internal memory), docs output
is a committed file (external surface). When the bead is "document
our decision about X" the deliverable is a drawer and you should be
running `research-a-bead`; when the bead is "explain how to use
feature X" the deliverable is a tracked file and you are in the
right place.

The discipline this recipe codifies: **review against code for
accuracy is non-negotiable.** A doc with a bash snippet that doesn't
run, or a cross-reference that points nowhere, is worse than no doc
— it costs every reader time AND erodes trust in the rest of the
docs. M4 (review against code) is the load-bearing step; everything
else exists to feed it.

Invocation: explicit only — either directly (`/docs-a-bead <bead-id>`)
or via the `/working-a-bead` router that selects an activity recipe by
bead shape. The Skill tool may surface this recipe via auto-discovery
when a message strongly matches the trigger phrases above; if that
happens at the wrong moment (e.g., the bead isn't docs-shaped), decline
and switch to the right recipe.

## When to use

Right after `session-startup` (or the `/working-a-bead` router)
picks a docs-shaped bead. The shape covers four common cases:

- **New doc** — bead asks for a guide, reference page, or section
  that doesn't exist yet.
- **Drift repair** — code moved on; the doc still describes the old
  shape. Fix what's wrong without rewriting what's still right.
- **Missing context** — the doc is technically accurate but assumes
  knowledge the audience doesn't have; bead asks to fill the gap.
- **Broken cross-references** — links rotted, file paths moved,
  bead ids changed; bead asks for a sweep.

A bead is docs-shaped when the deliverable is a tracked text file
that ships with the repo and the change is to that file's content,
not to the code it describes.

## Skip when

- The bead is bug/feature/refactor/research/cleanup-shaped — use
  the matching activity recipe instead.
- The bead is "document our decision about X" — that's
  research-a-bead. The drawer is the deliverable; a tracked file
  may also fall out, but the drawer is primary.
- The bead is "fix the typo on line 42" — too small for the recipe.
  Just fix it inline; the recipe earns its keep when the change is
  more than a single edit.
- The bead is really an API change disguised as a doc fix — if you
  end up changing code to match the doc, you're in feature- or
  refactor-shaped territory; re-pick the recipe.
- Mid-task interruption. This recipe is for new docs starts, not
  for context recovery within an in-flight bead.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written.
  Sample sibling voice, draft, review against code, optional
  decision-drawer if the doc encodes a decision.
- **light** — sampling sibling voice (M2) may compress to a single
  reference doc instead of two or three. Decision-drawer capture
  (M5) becomes optional unless the doc encodes a project decision.
  **M4 (review against code) is NOT optional even in light mode** —
  it's the step that prevents lying docs and skipping it defeats
  the recipe.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds docs-specific intermediate stages between phase A and
phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (identify the gap) | `gap-finding` |
| Entering step M2 (sample sibling voice) | `voice-sampling` |
| Entering step M3 (draft) | `drafting` |
| Entering step M4 (review against code) | `reviewing` |
| Entering step M5 (optional decision-drawer) | `polishing` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>`
at the moment the step starts. The status line surfaces these so a
cold-start session can see whether you paused mid-draft or
mid-review — the answer changes how to resume.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:

- **A1.** MemPalace search for prior docs-related decisions (sets
  stage `research`). Docs-shaped query patterns:
  - `mempalace_search "<topic> docs"` and `mempalace_search "<area>
    documentation"` — surfaces prior decisions about doc structure,
    audience, or voice.
  - `mempalace_search "<area> README"` — surfaces decisions about
    what does and doesn't belong in top-level docs.
  - `mempalace_kg_query("<doc-name>")` — surfaces convention
    relationships (e.g., "this README follows the X pattern").
  - `bd memories <topic>` — tribal one-liners about doc audience or
    voice that auto-inject at `bd prime` time.
  - Read the existing doc tree in the area (`Glob` for sibling
    `*.md` files; `Read` two or three of them). The existing tree
    is itself prior art — it tells you the project's tacit voice
    and structure before you sample explicitly at M2.
- **A2.** `bd update <id> --claim`. Worktree is usually justified
  for docs work — even small doc PRs benefit from review on a
  branch. Skip the worktree only for ≤ 1-line tweaks (typo fix,
  broken link to known-good target).

If A1 surfaces a prior decision about the doc's structure or
audience that conflicts with the bead's framing, restate the bead
in those terms BEFORE drafting. The doc-decision lineage matters
the same way the bug-family lineage matters.

### Variable middle — M1 → M5 (recipe owns)

#### M1. Identify the gap

Set stage `gap-finding`. State the gap operationally in a single
sentence: "the README's installation section assumes `bd` is
already on PATH, but the install.sh that the section recommends
doesn't put it there." Not "the docs are bad," not "this section
is unclear" — a specific, falsifiable gap.

If the gap is actually two or three gaps ("the install section is
wrong AND the quickstart links to the wrong file AND the API
reference is missing the new flag"), split the bead. Docs beads
with multiple gaps drift in scope and produce sprawling diffs that
nobody can review.

State the gap to the user before moving to M2. A misdiagnosed gap
produces a doc edit that doesn't actually help anyone.

#### M2. Sample sibling-doc voice

Set stage `voice-sampling`. Read 2–3 sibling docs in the same area
before drafting. For a `docs/` page, read its sibling pages. For a
README section, read the rest of the README and the README of any
closely-related project in the same repo. Note:

- **Tone** — terse vs narrative, formal vs gritty, you-the-reader
  vs we-the-team.
- **Structure** — heading depth, ordered lists vs prose,
  introduction-then-detail vs detail-only.
- **Density** — short sections with lots of headings, or long
  sections with few?
- **Code-example style** — bash blocks vs inline code, real
  commands vs placeholders, output included vs commands only.

Voice mismatch is the #2 docs failure mode (after lying docs).
Readers feel a tonal jolt before they can articulate it; the doc
reads as foreign and the surrounding docs lose authority by
association.

For drift-repair beads on an existing doc, the doc itself IS the
voice sample — match the rest of the file you're editing, not
your own preferred voice.

#### M3. Draft

Set stage `drafting`. Two modes:

- **New doc** — draft the structure first (headings + a one-line
  intent under each), get it right, then fill in prose. The
  structure is the load-bearing part; if the structure is wrong
  the prose can't fix it. For longer docs, post the heading
  outline to the user before filling prose so a structural problem
  gets caught early.
- **Drift repair** — minimal surgery. Edit the paragraph that's
  wrong; leave the surrounding paragraphs alone unless they're
  also wrong. Resist the urge to "while I'm in here" rewrite — it
  bloats the diff, mixes the bug-fix with editorial preference,
  and makes the change hard to review.

Examples in the doc must be runnable, not approximate. Use real
file paths, real bead ids, real commands — values that round-trip
when the reader pastes them. Placeholder text (`<your-id>`) is
fine when the value genuinely varies per reader; never paper over
"I didn't check what this should be" with a placeholder.

#### M4. Review against code for accuracy

Set stage `reviewing`. **This step is non-negotiable.** Re-read
the code, feature, or behavior the doc describes. For each claim
in the doc, verify:

- **Command examples** — actually run them. A bash block that
  pretends to demonstrate setup but errors on first invocation
  is the canonical lying-doc failure. Run the commands; capture
  the output if the doc shows output.
- **API signatures, flag names, config keys** — match against the
  current source, not your memory of it. Names drift quietly.
- **Cross-references** — every file path, drawer slug, bead id,
  URL, and inter-doc link must resolve. Link rot is the #1 docs
  failure mode in workflow-infrastructure projects; assume any
  link not verified this session is broken.
- **Order-of-operations** — if the doc says "first do X, then Y,"
  walk the steps. Sequencing bugs are the most common substantive
  error in setup docs.
- **Audience-knowledge assumptions** — re-read with the audience's
  context (user, contributor, on-call engineer). If a step
  silently assumes context the audience doesn't have, name the
  assumption or supply the context.

When a verification fails, the answer is to fix the doc — not to
loosen the claim into something vague. "Run `bd close <id>`"
becomes "Run `bd close <id1> <id2> ... --reason='<one-line>'`"
when verification shows the real shape; it does not become "Use
the bd close command."

If the verification surfaces that the underlying code is wrong
(not the doc), pause and surface to the user. Pivoting to a
bug-fix mid-docs-bead is fine; silently papering over a code bug
in the doc is not.

#### M5. Optional decision-drawer capture

Set stage `polishing`. Most docs beads finish at M4 — the doc is
the deliverable, full stop. File a decision drawer ONLY when the
doc encodes a project decision worth surfacing in palace search
beyond the doc's lifetime:

- An architecture choice the doc is the first articulation of
  (e.g., "we standardize on bash for hooks, not Python" — the doc
  documents the convention, the drawer records the decision).
- A convention adoption (e.g., "all skills get `disable-model-
  invocation: true` by default" — drawer the decision, doc the
  convention).
- A deprecation (e.g., "v1 working-a-bead is replaced by the
  recipe family" — drawer the migration plan, doc the new shape).

When you do file a drawer, link it from the doc and link the doc
from the drawer. The drawer remembers WHY; the doc remembers HOW.

If the doc doesn't encode a decision — it's a how-to-use guide, a
reference page, a quickstart — skip M5. Filing a drawer for every
docs bead bloats the palace with non-decisions and makes future
search noisier.

### Phase B — verification (delegate to shell, with docs extension)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Docs verification asks:

- Does the doc render cleanly? For a static-site target, run the
  site build (`hugo`, `mkdocs build`, etc.) and confirm no errors
  and no broken-link warnings.
- Do code examples in the doc actually run from a clean shell?
  Re-run them once more end-to-end — M4 verified them in
  isolation; B re-verifies them as a sequence.
- Do every cross-reference resolve? A simple check: grep the doc
  for `](`, `[loom-`, `[hundred_acre_woods/`, and known link
  patterns; verify each target exists.
- Does `git diff --stat` match the gap stated at M1? If the diff
  is much wider, scope crept and you should split or trim before
  commit.

State results with evidence in user-facing output BEFORE moving
to phase C. **extends phase B with: link-check + example
runnability + render check.**

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:

- **C1.** Code review applies the same way it does for code beads
  — the doc is reviewed as a unit. For multi-section docs, ask for
  review per section if the change is large.
- **C2.** Commit on the branch (sets stage `commit`). The commit
  body should name the gap (one sentence from M1), the change made,
  and the verification evidence (which examples were run, which
  links were checked). Co-author trailer per project convention.
- **C3.** `superpowers:finishing-a-development-branch` — pick from
  the four options. Docs PRs benefit from human review more often
  than tiny code fixes do; default to push & PR unless the change
  is genuinely trivial.

### Phase D — closeout (delegate to shell)

Follow `bead-lifecycle-shell` phase D:

- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push` →
  `git push` (sets stage `close`).
- **D3.** Drawer + KG triples + diary capture (sets stage
  `wrap-up`). For docs beads the closing drawer is OPTIONAL — file
  one only when the doc encodes a decision (per M5). The diary
  entry is still recommended; it captures what shipped and what
  was surprising about the writing process. KG triples are usually
  not needed unless M5 fired.

## Failure modes (concrete)

- **Skip M4 (review against code):** the doc lies. The bash
  snippet doesn't run, the flag name is from last quarter, the
  cross-reference points to a bead that was renamed. Every reader
  pays the cost; the next docs bead in the area inherits the
  reader's distrust. The single most expensive failure mode of
  this recipe — and the one most often skipped under time
  pressure. Don't.
- **Skip M2 (voice sampling):** the new section reads as foreign.
  Tone shifts mid-doc; the surrounding docs lose authority by
  association. Caught by readers but rarely articulated; shows up
  as "this section is weird" review feedback that reviewers can't
  pin down.
- **Scope creep beyond the gap:** M1 stated "fix the install
  section"; the diff also rewrites the architecture overview, the
  contributing guide, and a sibling doc. Reviewer can't tell what
  changed for the bead vs what changed for editorial preference,
  so the review either rubber-stamps everything or bounces the
  whole PR.
- **Broken cross-references from typos:** `[loom-s0n](...)` typed
  as `[loom-son](...)`, `hundred_acre_woods/decisions` typed as
  `hundred_acre_wood/decisions`, file path off by one directory.
  Caught only if M4 verifies every link by clicking-or-grepping;
  trusting your typing is the failure mode.
- **Code examples that don't run:** the bash block uses a flag
  that was deprecated, references a file that moved, or assumes
  a tool is on PATH that the install steps don't add. Caught only
  by actually running each example end-to-end at M4. The doc that
  says "run `./install.sh && bd ready`" must be verified by
  someone running exactly those two commands from a clean shell.
- **Filing a decision drawer for a how-to-use doc:** M5 fires
  when the doc encodes no decision. Future palace search returns
  noise; the drawer is unfindable when a real decision drawer in
  the same area is searched for. Skip M5 by default; opt in only
  when the doc captures a project-level choice.

## Related infrastructure

This recipe is the docs-shaped peer to `research-a-bead` (the two
both deliver text; research delivers internal memory, docs deliver
external surface). The cross-activity lifecycle scaffolding lives
in `bead-lifecycle-shell`. Sibling activity recipes:

- `bugfix-a-bead` (loom-lzi) — bug-shaped middle (debug → RED →
  GREEN → bug-class → enshrined-sweep)
- `feature-a-bead` (loom-5rf) — feature-shaped middle
- `refactor-a-bead` (loom-uca) — characterization tests +
  restructure
- `research-a-bead` (loom-0q0) — define → search → synthesize →
  file (drawer is the deliverable)
- `cleanup-a-bead` (loom-62x) — scope → remove → verify

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + description heuristics.

Subagents that integrate with this recipe:
- `drawer-author` — M5 helper when the optional decision-drawer
  fires; drafts the closing decision drawer.

Full design + locked decisions live in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02). Build queue tracked under loom epic `loom-0y6`.
