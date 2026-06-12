---
name: loom-mine-history
description: Mine a brownfield repo's git/PR history for decisions stated in-flight but never captured, then file the salient survivors as `provenance:mined` decision drawers in the project's own MemPalace wing. Drives the `~/.claude/scripts/loom-mine-history` wrapper through a locked two-pass cost gate — zero-spend dry-run preview, explicit user go-ahead, then the paid LLM salience pass — and does the MCP filing the bash engine cannot. Invoked by `/loom-mine-history`.
---

# Mine-History — Decision Archaeology for a Brownfield Repo

Recovers the design rationale a repo accumulated before loom's capture
discipline existed. The bash engine (`lib/loom-mine-history.sh`) harvests
PRs + commits + tags, gates them, runs an LLM salience+draft pass, and
writes a manifest to disk — but it cannot file into MemPalace, because MCP
tools are not callable from bash. This skill is the other half: it drives
the wrapper through the cost gate, then files the manifest via MCP.

The seam is firm: **the wrapper owns repo+wing resolution and engine
invocation; this skill's prose owns the cost-gate orchestration and the
MCP filing loop.** Do not duplicate resolution logic here — read what the
wrapper resolved (it writes the wing to `<out>/wing`).

Design source: `drawer_loom_decisions_e43e3693c8ee82e3bc6e34c6`
(loom/decisions wing). Engine close: `drawer_loom_decisions_490284f114c5a773ee3456cf`.

## When to use

The user runs `/loom-mine-history` (optionally `--root`, `--wing`,
`--since`, `--since-release`, `--since-sha`, `--max-units`, `--resume`,
`--synthesize`) against a repo whose history predates its MemPalace
wing — a freshly-adopted project, a legacy service, loom itself before
bn7. Manual-only; never auto-fired. `--synthesize` adds the tier-2 pass:
the engine clusters salient units and narrates one "narrative arc"
drawer per cluster, emitting `<out>/arcs.jsonl` for the skill to file
alongside the per-unit drawers (step 4b).

Re-running the mine is **incremental by watermark**: this skill reads
the repo's `history_mined_through` KG fact before the dry-run (step 0)
and passes `--since-sha=<that SHA>` so only post-watermark history is
harvested, then re-files an updated `history_mined_through` fact after
the filing loop (step 4d) pointing at the new HEAD. The `--resume` flag
is orthogonal — it recovers a single interrupted run from its
`<out>/.processed` checkpoint without re-spending the LLM pass; the
watermark spans runs, `--resume` spans an interruption within one run.

## The locked contract (do not redesign)

1. **Two-pass cost gate.** Run the wrapper `--dry-run` FIRST (zero spend).
   Surface the preview. Await an explicit go-ahead. ONLY THEN run the real
   pass. Never spend without the confirm beat.
2. **Seam.** Wrapper resolves + invokes; this skill files via MCP.
3. **Project's own wing, shared room, `provenance:mined` tag.** Mined
   drawers land in `<resolved-wing>/decisions` — the SAME room as native
   captures — distinguished by the `provenance:mined` tag, not a separate
   room. The wing defaults to the sanitized repo basename; `--wing`
   overrides. Read it from `<out>/wing` — never re-derive it.

## Procedure

### 0 — Read the watermark (before any wrapper call, zero spend)

A repo that has been mined before carries a `history_mined_through` KG
fact naming the HEAD the last mine examined through. Read it BEFORE the
dry-run so this run can be incremental — mining only the slice of history
added since the last watermark instead of re-harvesting (and risking
re-spending on) everything.

The repo entity is the resolved **wing** — the repo's stable palace
identity, the same string the wrapper writes to `<out>/wing` and the
`mined_from` object the engine's triples carry. Resolve it the way the
wrapper does (the repo-root basename verbatim, or the user's `--wing`)
so the query keys on the same entity the write in step 4d will use.

1. **Query** — `mempalace_kg_query(entity=<repo-entity>)` and look for an
   outgoing `history_mined_through` predicate. (Use the same repo-entity
   string step 4d files under — see that step.)
2. **No fact present** — this is a first mine. Skip `--since-sha`; the
   engine harvests full history. Proceed to step 1.
3. **A fact present** — let `WATERMARK` be its object (the prior HEAD
   SHA). Pass `--since-sha=<WATERMARK>` to BOTH wrapper passes (dry-run
   in step 1 and the real pass in step 3) so the engine harvests only
   `WATERMARK..HEAD`. Hold onto `WATERMARK` — you also need it to
   invalidate the stale fact in step 4d, and to compute the
   "resuming from watermark" line in step 2.

If the repo's HEAD has not advanced since the watermark (`--since-sha`
selects an empty range), the dry-run preview will show `0 harvested` —
nothing new to mine. Report that and stop; there is no second fact to
file (the watermark already points at HEAD).

### 1 — Resolve target (dry-run, zero spend)

Run the wrapper with `--dry-run`, forwarding the user's flags (including
`--since-sha=<WATERMARK>` when step 0 found a prior fact). Pick a tmp
dir now so the real pass can reuse it:

```bash
out=$(mktemp -d)
~/.claude/scripts/loom-mine-history --dry-run [--root <dir>] [--wing <name>] \
  [--since=DATE] [--since-release=TAG] [--since-sha=WATERMARK] \
  [--max-units=N] [--synthesize]
```

Pass `--since-sha=<WATERMARK>` here whenever step 0 found a prior
`history_mined_through` fact — it scopes the harvest to `WATERMARK..HEAD`
and takes precedence over `--since-release`. Omit it on a first mine.

Forward `--synthesize` through both passes when the user asked for it —
the dry-run preview reflects only the tier-1 cost (the tier-2 arc cost is
computed in the real pass), but the flag must reach the real pass below
so `<out>/arcs.jsonl` is emitted.

The dry-run emits the engine's cost preview line
(`cost-preview: N harvested -> M gated -> ~M LLM reads, est <= M model
calls`), the gated candidate list, and the resolved wing
(`(wing for filing: <wing>)`). No `--out` on the dry-run — it writes no
manifest and calls no model.

### 2 — Surface the preview, await go-ahead

Present to the user, in one beat:

- **the watermark line, when step 0 found a prior fact**:
  `resuming from watermark <short-sha> (N new units since last mine)` —
  where `<short-sha>` is the prior `WATERMARK` abbreviated and N is the
  dry-run's harvested count (the units in `WATERMARK..HEAD`). On a first
  mine (no prior fact) omit this line; the run covers full history;
- the cost preview: **N harvested → M gated → ~M LLM reads, est cost**;
- the resolved **wing** the drawers will land in;
- the gated candidates (so they can sanity-check what survived).

Then STOP and ask for explicit confirmation. Do not proceed to the paid
pass on implicit assent — wait for a clear go-ahead. If the user wants a
tighter run, re-run step 1 with `--max-units`/`--since` and re-preview.

### 3 — Real pass (paid; only after go-ahead)

```bash
~/.claude/scripts/loom-mine-history --out "$out" \
  [same --root/--wing/--since/--since-sha/... flags] [--synthesize] [--resume]
```

Pass the SAME `--since-sha=<WATERMARK>` you passed to the dry-run, so the
paid pass mines the same `WATERMARK..HEAD` slice you previewed. Reuse the
same `$out` across the dry-run and real pass — `--resume` (below) reads
the `<out>/.processed` checkpoint that the real pass writes there.

The wrapper invokes the engine with `--yes --out "$out"`, which runs the
LLM salience+draft pass and writes the manifest. With `--synthesize` it
also runs the tier-2 clustering+narration pass and emits
`<out>/arcs.jsonl`. Then read:

- `<out>/wing` — the resolved wing (single line). Use this verbatim.
- `<out>/watermark` — the HEAD SHA the engine mined through this run
  (single line). The real pass always writes it, even with zero salient
  drafts (the engine DID examine through HEAD). Step 4d files it as the
  new `history_mined_through` fact AFTER the filing loop completes.
- `<out>/drafts.jsonl` — one JSON/line:
  `{source_id, source_type, anchor{id,url,date,author}, verbatim,
  synthesis, drawer_body, room, tags}`.
- `<out>/kg-triples.jsonl` — one JSON/line:
  `{subject, predicate, object}`.
- `<out>/arcs.jsonl` — **only present when `--synthesize` was passed**
  (tier-2). One JSON/line:
  `{arc_title, theme, narrative, constituents[], drawer_body, room,
  tags}`. Each entry in `constituents` is a **`source_id`** matching a
  draft line in `drafts.jsonl`. The arc's `drawer_body` references its
  constituents by source ANCHOR (PR#/SHA), because the engine has no
  drawer_ids — step 4b rewrites those to the real drawer_ids it filed.
  Absent without `--synthesize`; skip the arc-filing step (4b) when the
  file is missing or empty.

If `drafts.jsonl` is empty, nothing was salient — report that and stop
(no filing, no error).

### 4 — Filing loop (MCP; this is the skill's job, not the wrapper's)

**Two-phase, ordered: per-unit drafts FIRST, arcs SECOND.** The arc
drawers (step 4b) cross-reference the per-unit drawers, so the per-unit
drawers must exist — and their `drawer_id`s be known — before any arc
is filed. Do not interleave.

#### 4a — Per-unit drafts

Let `WING` be the contents of `<out>/wing`. Keep a running map
`source_id → drawer_id` (`ID_MAP`) — you will need it in step 4b to
rewrite arc constituents. For each draft line in `<out>/drafts.jsonl`:

1. **Dedup check** — `mempalace_check_duplicate(content=<drawer_body>)`.
   If it reports a match, SKIP this draft (count it skipped-dup); do not
   file a near-duplicate of an existing drawer. If the match exposes the
   existing drawer's id, still record `source_id → <existing drawer_id>`
   in `ID_MAP` so an arc can link to it; otherwise leave it unmapped.
2. **File the drawer** —
   `mempalace_add_drawer(wing=WING, room="decisions",
   content=<drawer_body>, source_file=<anchor.url or anchor.id>)`.
   Capture the returned `drawer_id`.
3. **Tag provenance** —
   `mempalace_tag_drawer(drawer_id=<id>, tag_key="provenance",
   tag_value="mined")`. (The `provenance:mined` tag from the manifest's
   `tags` array, expressed as the tool's key/value pair.)
4. **Record the mapping** — add `source_id → drawer_id` to `ID_MAP`,
   keyed by this draft's `source_id`. This is the lookup table step 4b
   consumes.

#### 4b — Arc drawers (only when `<out>/arcs.jsonl` exists; tier-2)

Skip this entire step if `--synthesize` was not passed (no `arcs.jsonl`)
or the file is empty. Otherwise — **only after every per-unit draft in
4a is filed and `ID_MAP` is complete** — for each arc line in
`<out>/arcs.jsonl`:

1. **Resolve constituents → drawer_ids.** Walk the arc's
   `constituents[]` (each is a `source_id`); look each up in `ID_MAP` to
   get the real `drawer_id` filed in 4a. A `source_id` absent from
   `ID_MAP` (skipped-dup with no exposed id, or never filed) has no
   drawer to link — drop it from the linked set and note it.
2. **Rewrite the body anchors → drawer_ids.** The engine's
   `drawer_body` lists constituents by source anchor (PR#/SHA) in its
   "Constituent decisions:" block, since it had no drawer_ids. Rewrite
   each constituent reference from the anchor to the resolved
   `drawer_id` (or its `mp://<drawer_id>` URI), so the filed arc drawer
   cross-references the real filed drawers rather than bare anchors.
   Keep the anchor as a parenthetical only if useful; the `drawer_id`
   is the primary link.
3. **Dedup check** — `mempalace_check_duplicate(content=<rewritten
   drawer_body>)`. If matched, SKIP (count it skipped-dup).
4. **File the arc drawer** —
   `mempalace_add_drawer(wing=WING, room="decisions",
   content=<rewritten drawer_body>)`. Capture the returned `drawer_id`.
5. **Tag** — `mempalace_tag_drawer(drawer_id=<id>,
   tag_key="provenance", tag_value="mined")` AND
   `mempalace_tag_drawer(drawer_id=<id>, tag_key="synthesis",
   tag_value="arc")`. (Both tags come from the arc line's `tags`
   array: `provenance:mined` + `synthesis:arc`.)

#### 4c — KG triples

For each triple line in `<out>/kg-triples.jsonl`:

- `mempalace_kg_add(subject=<subject>, predicate=<predicate>,
  object=<object>)`. The engine emits `decided`, `mined_from`, and
  `authored_by` triples per salient unit; file each as-is.

#### 4d — Advance the watermark (LAST; after the whole filing loop)

**Do this only after 4a + 4b + 4c are all complete** — the watermark
records that everything through `<out>/watermark` has been FILED, so it
must not advance until the drawers and per-unit triples are actually in
the palace. (If the filing loop aborted partway, leave the old fact
standing — re-running re-mines the unfiled tail; advancing early would
skip it.)

The repo entity is the same string step 0 queried — the resolved
**wing** (`WING`, the contents of `<out>/wing`). Keying the write and the
step-0 read on the same entity is what makes the round-trip close.

1. **Read the new HEAD** — let `NEW_SHA` be the single line in
   `<out>/watermark` (the HEAD the engine mined through this run).
2. **Invalidate the stale fact, then add the new one (replace
   semantics).** If step 0 found a prior `history_mined_through` fact,
   it must be RETIRED before the new one is added — otherwise the graph
   carries two `history_mined_through` objects and step 0 of the next
   run cannot tell which is current. Do it in order:
   - `mempalace_kg_invalidate(...)` the old
     `(<WING>, history_mined_through, <WATERMARK>)` fact (the prior SHA
     from step 0);
   - THEN `mempalace_kg_add(subject=WING,
     predicate="history_mined_through", object=NEW_SHA)`.
   On a **first** mine (step 0 found no prior fact) there is nothing to
   invalidate — just `mempalace_kg_add` the new fact.
3. **Idempotence guard.** If `NEW_SHA == WATERMARK` (HEAD did not advance
   — the step-0 empty-range case should have stopped you already, but
   guard anyway), the fact already points at HEAD: skip both the
   invalidate and the add, leaving the existing fact untouched.

This is the write half of the round-trip whose read half is step 0: next
run's step 0 queries `<WING> → history_mined_through → NEW_SHA` and mines
only `NEW_SHA..HEAD`.

Process drafts (4a) before arcs (4b) before triples (4c) before the
watermark (4d) — the drawers must exist when arcs link them and when the
graph references their sources, and the watermark must not advance until
all of that is filed.

### 5 — Adoption summary

Report terse counts the user can scan:

- **filed**: per-unit drawers added to `WING/decisions`;
- **arcs-filed**: when `--synthesize` ran, surface
  `filed K arc drawer(s) linking N per-unit drawers` — K = arc drawers
  filed in 4b, N = the distinct per-unit `drawer_id`s those arcs link
  (resolved via `ID_MAP`). Omit this line when no arcs were emitted;
- **skipped-dup**: drafts/arcs that matched an existing drawer;
- **triples-added**: KG facts filed;
- **watermark**: `advanced <old-short-sha> → <new-short-sha>` when step
  4d replaced a prior fact, or `set <new-short-sha> (first mine)` when it
  filed the initial fact. This is the user's signal that the next mine
  will be incremental from here.

Name the wing explicitly so the user knows where to search next
(`mempalace_search` filtered to `WING/decisions`, or by the
`provenance:mined` tag — `synthesis:arc` narrows to the arc drawers).

## Interrupted runs (`--resume`)

The LLM salience pass is the expensive beat; an interrupted real pass
(crash, cancel, network drop) leaves the units it already processed in
`<out>/.processed`. To recover WITHOUT re-spending on those units, re-run
the real pass against the SAME `$out` with `--resume`:

```bash
~/.claude/scripts/loom-mine-history --out "$out" --resume \
  [same flags as the interrupted run, including --since-sha]
```

The engine skips every survivor recorded in `<out>/.processed` and
spends only on the remainder, appending to the existing `drafts.jsonl` /
`kg-triples.jsonl`. After the resumed pass completes, run the filing loop
(step 4) as normal — `mempalace_check_duplicate` (4a/4b) makes re-filing
any drawers that WERE filed before the interruption idempotent, so it is
safe to file the whole manifest, not just the resumed tail.

`--resume` and the watermark are distinct layers and compose:

- **`--resume`** recovers ONE interrupted run from its on-disk
  `.processed` checkpoint — same `$out`, same `WATERMARK..HEAD` slice. It
  does NOT advance the `history_mined_through` fact; that only happens in
  step 4d once the filing loop completes successfully.
- **The watermark** spans runs: it is the across-invocation incremental
  cursor, advanced once per fully-filed run (step 4d). A fresh run with
  no `$out` to resume still benefits from it via the step-0 `--since-sha`
  read.

So an interrupted run is resumed with `--resume` (cheap, same dir); a
later clean run is scoped with `--since-sha` from the watermark (step 0).
Only the latter advances the fact.

## Anti-scope

- Do NOT re-implement repo/wing resolution — the wrapper owns it; read
  `<out>/wing`.
- Do NOT skip the dry-run or the go-ahead beat — spending without the
  confirm beat violates the locked contract.
- Do NOT file mined drawers into loom's wing (unless loom is the repo
  being mined) — they belong to the project they came from.
- Do NOT invent a separate `mined` room — same `decisions` room, the tag
  carries provenance.
- Do NOT file arcs before the per-unit drafts (4a) are all filed — the
  arc-constituent rewrite reads `ID_MAP`, which is only complete once
  every draft has a `drawer_id`. Filing an arc early links bare anchors
  instead of real drawers.
- Do NOT re-cluster or re-narrate arcs here — the engine's
  `--synthesize` pass owns clustering + narration and emits
  `arcs.jsonl`. The skill only files them and rewrites anchors →
  drawer_ids; it does not redraw the arc set.
- Do NOT advance the watermark (4d) before the filing loop (4a–4c)
  completes — the fact asserts everything through that SHA is FILED. An
  early advance on a partial/aborted run silently skips the unfiled tail
  on the next mine.
- Do NOT `kg_add` a new `history_mined_through` without first
  `kg_invalidate`-ing the prior one — two live facts make step 0
  ambiguous about which SHA is current. Replace, never accumulate.
- Do NOT compute the watermark SHA yourself (`git rev-parse HEAD`, etc.)
  — read `<out>/watermark`, the HEAD the engine actually mined through.
  Deriving it independently risks recording a HEAD the engine did not
  examine (e.g. if it advanced mid-run).
- Do NOT conflate `--resume` with the watermark — `--resume` recovers an
  interrupted single run from `<out>/.processed`; it never advances the
  `history_mined_through` fact. Only a fully-filed run advances it (4d).

## Related

- Command (user door): `commands/loom-mine-history.md`.
- Wrapper (executable seam): `~/.claude/scripts/loom-mine-history`.
- Engine (harvest → gate → LLM → manifest, `--synthesize` tier-2 arcs):
  `lib/loom-mine-history.sh`.
- Closes: loom-bn7.4 (per-unit filing), loom-68r (arc filing +
  anchor→drawer_id rewrite), loom-zcv (skill-side watermark round-trip:
  step-0 `--since-sha` read + step-4d `history_mined_through` write).
  Lib half of `--synthesize`: loom-bn7.2; lib half of the watermark
  (`--since-sha` + `<out>/watermark` emit + `--resume`): loom-bn7.3.
