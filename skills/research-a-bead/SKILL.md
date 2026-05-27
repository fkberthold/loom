---
name: research-a-bead
description: Activity recipe for working a research-shaped beads issue. Owns the research-specific variable middle — define the question → search prior art (palace + KG + bd memories + diary) → fetch authoritative external docs → synthesize → file findings as decision drawer + KG triples + optional follow-up beads. Defers to the bead-lifecycle-shell skill for claim/verify/close/capture. No code, no worktree (usually). Triggers on phrases like "research <topic>", "what do we know about <X>", "investigate <Y>", or right after the session-startup or /working-a-bead router picks a research bead.
---

# Research-a-Bead — Variable Middle for Research-Shaped Beads

This skill owns ONLY the research-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim, optional
worktree, verification, commit, finish-branch, close + capture — lives
in the `bead-lifecycle-shell` skill. This recipe cites those phases by
letter and supplies the variable middle that runs between phase A
(pre-middle) and phase B (verification).

It codifies the research discipline that was implicit in the
2026-05-02 deploy-day MemPalace search habit: search the palace
BEFORE answering, fetch authoritative docs only after the local
search is exhausted, and treat the closing decision drawer + KG
triples as the primary output — not a write-up afterthought.

For a research bead the closeout *is* the deliverable. Skipping
phase D3 is equivalent to not doing the work.

Invocation: explicit only — either directly (`/research-a-bead <bead-id>`)
or via the `/working-a-bead` router that selects an activity recipe by
bead shape. The Skill tool may surface this recipe via auto-discovery
when a message strongly matches the trigger phrases above; if that
happens at the wrong moment (e.g., the bead isn't research-shaped),
decline and switch to the right recipe.

## When to use

Right after `session-startup` (or the `/working-a-bead` router)
picks a research-shaped bead, OR whenever the user asks a question
whose answer should outlive the conversation (architecture options,
library evaluation, prior-art lineage, design-space exploration).

A bead is research-shaped when the deliverable is *understanding* or
*decision input* rather than running code. The output usually lives
in MemPalace + maybe `docs/` — not in src/.

## Skip when

- The bead is bug/feature/refactor/cleanup/docs-shaped — use the
  matching activity recipe instead.
- The question is a quick lookup answerable by a single tool call
  (one `Grep`, one `bd show`, one MCP call). Don't spin up the full
  recipe for what's effectively a `mempalace_search` away. The
  recipe earns its keep when synthesis across multiple sources is
  needed.
- Pure brainstorming with no concrete question yet — use
  `superpowers:brainstorming` (or `beadpowers:brainstorming`) until
  the exploration yields a focused question, then re-engage this
  recipe to answer it durably.
- Mid-task interruption. This recipe is for new research starts,
  not for context recovery within an in-flight bead.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written.
  Local-palace search before external fetch, full synthesis, drawer
  + KG triples mandatory.
- **light** — local-palace search before external fetch is still
  recommended (the search habit is the whole point), but the
  closing artifacts may compress. Drawer-capture remains
  recommended; KG triples become optional unless the research
  surfaces a convention or design-family relationship.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds research-specific intermediate stages between phase A
and phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (define the question) | `defining` |
| Entering step M1.5 (decompose scope) | `scoping` |
| Entering step M2 (search prior art) | `searching` |
| Entering step M3 (fetch authoritative docs) | `fetching` |
| Entering step M4 (synthesize) | `synthesizing` |
| Entering step M5 (file findings) | `filing` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>`
at the moment the step starts. The status line surfaces these so
future cold-start sessions can see exactly where the research
paused — research beads often span multiple sessions because the
bottleneck is human review, not tool execution.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:
- **A1.** MemPalace search for the research family (sets stage
  `research`). For research the query patterns are
  `mempalace_search "<topic> <area>"` plus
  `mempalace_kg_query("<entity-name>")` for any named concept in the
  bead, plus `bd memories <keyword>` for tribal one-liners. The
  goal at A1 is to detect *whether the question has already been
  answered* — if a recent decision drawer already nails it, the
  recipe converges fast: M1 → M4-via-citation → M5.
- **A2.** `bd update <id> --claim`. **Skip the worktree** by default
  — research beads typically don't change project source. Create a
  worktree only if the synthesis will land as a `docs/` file or
  tracked artifact in the project repo.

If the search at A1 surfaces a sibling research drawer with the
same question, restate the bead in terms of "extends X" or "narrows
X" before continuing. Do not redo prior work; cite it and add only
what's new.

### Variable middle — M1 → M5 (brief a worker)

Per `bead-lifecycle-shell § Dispatch discipline — central agent
briefs a worker (loom-7p6)`, phase B is worker territory: brief a
single worker in one dispatch covering the full variable middle,
then review on return and re-dispatch only on surprises. The steps
below are **scope items for the worker brief**, not central's own
to-do list. Central does not run `mempalace_search`,
`context7-plugin:docs`, or `WebFetch` itself during phase B; the
worker drafts, central reviews and files the resulting MemPalace
artifacts at phase D.

**Dispatch shape for research beads.** Research is no-code by
default (drawer + KG triples + maybe a `docs/` page), so the worker
brief should default to **background dispatch without
`isolation: "worktree"`** — there is no source change to isolate
and a worktree adds ceremony without benefit. Add `isolation:
"worktree"` only when the bead writes a tracked `docs/` artifact or
other repo file that should branch + merge rather than land on main
directly. The phase-ownership table in the shell still applies; the
worktree clause is the research-specific exception.

The worker brief packs M1 → M5 into the **Scope** section of the
inline template at `bead-lifecycle-shell § Worker-brief template`.
Phrase each step as one sentence pointing at this recipe; the
worker reads the recipe for the details, the brief just names the
discipline to enforce.

#### M1. Have the worker define the question

Worker sets stage `defining` and writes the *exact* question the
bead is asking, in one or two sentences, in their own words. This
is not the bead title — it's the operational question whose answer
will become the drawer body. Common failure: the bead title is
broad ("evaluate vector DBs"); the operational question is narrow
("does Chroma 1.5.7 still hit the multi-process Rust bug under our
deep-sleep concurrency pattern?"). The worker finds the narrow form
before searching, or the search returns mush.

If the question can't be stated in one or two sentences, it's two
questions — worker stops and surfaces the split decision to central
before continuing.

The worker returns the question to central before moving to M1.5.
A misframed question is the most expensive failure mode of this
recipe; central confirms framing before the worker burns context on
M2 searches.

#### M1.5. Have the worker decompose the question across research axes

Worker sets stage `scoping`. For each axis pair below, the worker
asks *does my question apply to both sides?* If yes, the worker
flags it so M2 searches both — don't let the question's surface
wording skew the first wave to one side.

- **static-config vs dynamic-trace** — declarations vs runtime.
- **observable-from-logs vs observable-from-settings** — emitted
  vs configured.
- **snapshot vs time-series** — point-in-time vs evolution.
- **per-call vs per-session** — one invocation vs accumulated run.
- **scope-of-N vs scope-of-1** — fleet vs single instance.

Worked example (loom-nsb): "what does context cost?" needs
*both* static-config (prompt+schema bytes) AND dynamic-trace
(per-call tokens accumulating per-session). The user redirected
mid-bead because M2 only covered static. The brief should name
decomposition explicitly so the worker decomposes first, searches
once.

#### M2. Have the worker search prior art (local palace + tribal facts + diary)

Worker sets stage `searching`. The shell's A1 search was a quick
scan; M2 is the worker's deep dive across all four internal
sources. The brief should name the source ordering:

1. `mempalace_search` — worker tries multiple query rephrasings;
   semantic search is sensitive to wording. Search both the
   project's wing and any sibling wings where the topic might have
   surfaced before (cross-project lineage is common — the LOOM
   PROVENANCE drawer is the canonical example).
2. `mempalace_kg_query` — worker queries every named concept in
   the question. The KG surfaces convention/design-family
   relationships that semantic search can miss.
3. `mempalace_traverse` and `mempalace_follow_tunnels` — when
   M2.1 surfaces a hub drawer; worker follows tunnels one or two
   hops to discover lineage.
4. `bd memories <keyword>` — tribal one-liners that auto-inject
   at `bd prime` time.
5. `mempalace_diary_read("<agent>", N)` — diary entries often
   capture design pivots that decision drawers don't, especially
   for partially-formed designs.
6. `Grep` / `Glob` against the project — code is also prior art.

Worker captures findings in a working buffer (scratch notes in
the worker's session, or a draft drawer). Keep verbatim quotes
and source file/drawer paths so the M4 synthesis can cite cleanly
when central files the drawer at phase D.

If M2 already produces a confident answer, worker jumps to M4 —
don't fetch external docs that aren't needed.

#### M3. Have the worker fetch authoritative external docs (only if needed)

Worker sets stage `fetching`. Two routes, in order of preference:

1. **Library / framework / API docs** — worker invokes the
   `context7-plugin:docs` skill (or calls the
   `mcp__plugin_context7-plugin_context7__query-docs` tool
   directly). Context7 is the canonical route for library
   documentation; prefer it over web search when the question is
   "what does library X do" / "how do I configure Y."
2. **Web search / fetch** — `WebSearch` or `WebFetch` for
   everything else: vendor announcements, blog posts, RFC threads,
   GitHub issue discussions. Worker always includes a year filter
   (current year per environment date) to avoid stale answers.

Worker skips M3 entirely if M2 already answered the question.
Research beads with a strong palace ground often need zero
external fetch.

When the worker does fetch, capture the source URL + date next to
each quote so the M4 synthesis stays auditable for central's
review.

#### M4. Have the worker synthesize findings

Worker sets stage `synthesizing` and composes the answer in the
shape of a decision drawer body, even if the project also wants a
docs/ file. The worker's synthesis should include:

- The question, restated.
- The answer, stated up front (not buried at the end).
- Options considered + which-chosen + why — the
  `WHY NOT THE OTHER OPTIONS` section is load-bearing for future
  sessions; it's what prevents the same research from being redone.
- Family lineage (sibling drawers, cross-wing tunnels, prior beads).
- Verification at decision time — what evidence backs the answer
  (palace cites, doc URLs, code refs).
- OPEN — followups that became visible during the research.

If the synthesis surfaces multiple distinct findings, the worker
drafts them as separate drawer bodies — one drawer = one decision
is the canonical shape (per the `drawer-author` agent's discipline).

#### M5. Have the worker surface findings for central to file

Worker sets stage `filing` and returns the drafted artifacts in
the worker summary so central can file them at phase D. The brief
should name four output classes:

1. **Decision drawer body** — drafted in the worker's summary, ready
   for central to file via `mempalace_add_drawer` into the project's
   `decisions` room. The worker can invoke the `drawer-author`
   subagent within its session to draft the drawer body well, but
   the actual `mempalace_add_drawer` call belongs to central at
   phase D.
2. **KG triple proposals** — for convention or design-family
   relationships surfaced by the research. The worker can invoke the
   `kg-relationship-extractor` subagent to draft 3-5 triples; central
   reviews and files via `mempalace_kg_add`. Skip in light mode
   unless the research *is* a convention/family question — in which
   case the triples are the deliverable, not optional.
3. **Optional follow-up beads** — if the research uncovered work
   that should happen but is out of scope for this bead, the worker
   names the candidate beads (title + one-line scope + parent epic)
   in the summary; central files them via `bd create` at phase D.
   Don't expand scope inside the worker session; surface and let
   central decide.
4. **Optional `bd remember "<one-line>"`** — worker proposes the
   one-liner in the summary for tribal facts that future sessions
   need at `bd prime` time (the project-keyword auto-inject); central
   runs `bd remember` at phase D. Multi-paragraph findings → drawer.

Cross-reference: if the closing drawer relates to a sibling drawer
in another wing (e.g., loom research that extends an HAW finding),
the worker names the sibling drawer ID in the summary so central
can add a tunnel via `mempalace_create_tunnel` at phase D and the
lineage stays discoverable.

### Phase B — verification (delegate to shell, with research extension)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Research has no test suite, so phase B verification asks instead:

- Did M5 actually file the drawer? (`mempalace_get_drawer` round-
  trip the just-filed slug.)
- Do the KG triples round-trip via `mempalace_kg_query`?
- If a `docs/` artifact was written, does it render / lint?
- Does the drawer answer the question stated at M1, or did the
  scope drift?

State results with evidence in user-facing output BEFORE moving to
phase C. **extends phase B with: round-trip the filed artifacts.**

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:
- **C1.** Code review applies only if a `docs/` artifact landed in
  the repo. Pure-MemPalace research skips C1.
- **C2.** Commit on the branch (sets stage `commit`). For
  research beads with no source change, the commit is just the
  closed bead in `.beads/issues.jsonl`. The body should name the
  question, the answer, and the slug of the filed drawer.
- **C3.** `superpowers:finishing-a-development-branch` — for
  no-code research the only sensible options are merge-to-main
  (single closed bead) or skip-branch (commit on main if no
  worktree was created).

### Phase D — closeout (delegate to shell)

Follow `bead-lifecycle-shell` phase D:
- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push` →
  `git push` (sets stage `close`).
- **D3.** Drawer + KG + diary capture (sets stage `wrap-up`). For
  research beads, the drawer was already filed at M5 — D3 is the
  diary entry + any final cross-wing tunnels + a drawer-update if
  the post-merge state diverged from the M5 draft.

## Choosing brainstorming variant (rare, but explicit when needed)

A research bead occasionally surfaces that the question was wrong
or that the answer demands new design work. When that happens,
pause this recipe at M2 or M4 and invoke:

- **`beadpowers:brainstorming`** — when the design will land as
  new beads (epics + tasks).
- **`superpowers:brainstorming`** — when the design will land as a
  spec or plan in `docs/`.

Resume research-a-bead at M4 once the design lands, or split the
bead: file the original research finding via M5, then create a new
feature/refactor bead for the design work and pick its recipe.

## Failure modes (concrete)

- **Skip M1 (define the question):** M2 returns mush because the
  query terms are vague. The drawer ends up answering "everything
  about X" instead of the specific question. Future sessions can't
  cite the drawer as a decision because there's no decision in it.
- **Skip M1.5 (axis decomposition):** the first search wave skews
  to one axis (typically static-config / scope-of-1 / snapshot —
  whichever the question's surface wording suggests). User
  re-steers mid-bead and M2 reruns against the missing axis. The
  loom-nsb static-vs-dynamic redirect is the canonical example.
- **Skip M2 (local search), jump to web fetch:** the answer often
  already lives in the palace as a sibling drawer. Skipping M2
  produces redundant drawers that fragment the family lineage.
  This was the failure mode the 2026-05-02 deploy-day cleanup
  exposed when the huu.15.2 lineage hadn't been searched before
  the 0qw fix design.
- **Skip M5 (file findings):** the research lives only in this
  conversation's context window and vanishes at `/clear`. All the
  M1→M4 work is wasted because the next session redoes it from
  scratch.
- **Skip M5.2 (KG triples) for convention questions:** the family
  doesn't surface on the next phase A1 search. The huu.7.1 →
  huu.15.2 → huu.19.3 → 0qw chain is the canonical example of
  what happens without KG triples — four bugs of the same shape
  before the convention was articulated.
- **Conflate research with implementation:** the recipe ends with
  code changes and the drawer never gets filed. Research beads
  should be no-code by default; if implementation falls out of the
  research, file a sibling implementation bead and let *that* bead
  carry the code change.
- **Over-fetch external docs at M3:** burning context on doc
  pages that the local search already covered. Fetch only when
  M2 left a specific gap.

## Related infrastructure

This recipe is the research-shaped peer to `bugfix-a-bead`. The
cross-activity lifecycle scaffolding lives in `bead-lifecycle-shell`.
Sibling activity recipes:

- `bugfix-a-bead` (loom-lzi) — bug-shaped middle (debug → RED →
  GREEN → bug-class → enshrined-sweep)
- `feature-a-bead` (loom-5rf) — feature-shaped middle
- `refactor-a-bead` (loom-uca) — characterization tests + restructure
- `cleanup-a-bead` (loom-62x) — scope → remove → verify
- `docs-a-bead` (loom-s0n) — gap → draft → review

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + description heuristics.

Subagents that integrate with this recipe:
- `bug-family-researcher` — phase A1 helper; useful even for
  non-bug research because the prior-art surfacing pattern is
  general.
- `drawer-author` — M5 helper; drafts the closing decision drawer.
- `kg-relationship-extractor` — M5 helper; proposes KG triples.

Full design + locked decisions live in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02). Build queue tracked under loom epic `loom-0y6`.
