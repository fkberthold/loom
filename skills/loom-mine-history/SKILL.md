---
name: loom-mine-history
description: Mine a brownfield repo's git/PR history for decisions stated in-flight but never captured, then file the salient survivors as `provenance:mined` decision drawers in the project's own MemPalace wing. Drives the `scripts/loom-mine-history` wrapper through a locked two-pass cost gate — zero-spend dry-run preview, explicit user go-ahead, then the paid LLM salience pass — and does the MCP filing the bash engine cannot. Invoked by `/loom-mine-history`.
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
`--since`, `--since-release`, `--max-units`, `--synthesize`) against a
repo whose history predates its MemPalace wing — a freshly-adopted
project, a legacy service, loom itself before bn7. Manual-only; never
auto-fired. `--synthesize` adds the tier-2 pass: the engine clusters
salient units and narrates one "narrative arc" drawer per cluster,
emitting `<out>/arcs.jsonl` for the skill to file alongside the per-unit
drawers (step 4b).

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

### 1 — Resolve target (dry-run, zero spend)

Run the wrapper with `--dry-run`, forwarding the user's flags. Pick a tmp
dir now so the real pass can reuse it:

```bash
out=$(mktemp -d)
scripts/loom-mine-history --dry-run [--root <dir>] [--wing <name>] \
  [--since=DATE] [--since-release=TAG] [--max-units=N] [--synthesize]
```

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

- the cost preview: **N harvested → M gated → ~M LLM reads, est cost**;
- the resolved **wing** the drawers will land in;
- the gated candidates (so they can sanity-check what survived).

Then STOP and ask for explicit confirmation. Do not proceed to the paid
pass on implicit assent — wait for a clear go-ahead. If the user wants a
tighter run, re-run step 1 with `--max-units`/`--since` and re-preview.

### 3 — Real pass (paid; only after go-ahead)

```bash
scripts/loom-mine-history --out "$out" [same --root/--wing/--since/... flags] [--synthesize]
```

The wrapper invokes the engine with `--yes --out "$out"`, which runs the
LLM salience+draft pass and writes the manifest. With `--synthesize` it
also runs the tier-2 clustering+narration pass and emits
`<out>/arcs.jsonl`. Then read:

- `<out>/wing` — the resolved wing (single line). Use this verbatim.
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

Process drafts (4a) before arcs (4b) before triples (4c) so the drawers
exist when arcs link them and when the graph references their sources.

### 5 — Adoption summary

Report terse counts the user can scan:

- **filed**: per-unit drawers added to `WING/decisions`;
- **arcs-filed**: when `--synthesize` ran, surface
  `filed K arc drawer(s) linking N per-unit drawers` — K = arc drawers
  filed in 4b, N = the distinct per-unit `drawer_id`s those arcs link
  (resolved via `ID_MAP`). Omit this line when no arcs were emitted;
- **skipped-dup**: drafts/arcs that matched an existing drawer;
- **triples-added**: KG facts filed.

Name the wing explicitly so the user knows where to search next
(`mempalace_search` filtered to `WING/decisions`, or by the
`provenance:mined` tag — `synthesis:arc` narrows to the arc drawers).

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

## Related

- Command (user door): `commands/loom-mine-history.md`.
- Wrapper (executable seam): `scripts/loom-mine-history`.
- Engine (harvest → gate → LLM → manifest, `--synthesize` tier-2 arcs):
  `lib/loom-mine-history.sh`.
- Closes: loom-bn7.4 (per-unit filing), loom-68r (arc filing +
  anchor→drawer_id rewrite). Lib half of `--synthesize`: loom-bn7.2.
