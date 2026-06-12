---
description: "Mine a brownfield repo's git/PR history for decisions that were stated in-flight but never captured in MemPalace, then file the survivors as `provenance:mined` decision drawers in the project's own wing. Runs behind a two-pass cost gate — a zero-spend dry-run preview first, your explicit go-ahead, then the paid LLM salience pass."
disable-model-invocation: true
---

Decision-archaeology for a repo that predates loom's capture
discipline. Harvests merged PRs + merge/squash commits + release
tags, heuristically gates them down to decision-shaped survivors,
runs an LLM salience+draft pass behind a mandatory cost gate, and
files the salient ones as MemPalace decision drawers tagged
`provenance:mined` — landing them in the PROJECT'S OWN wing so a
brownfield repo's design rationale becomes searchable alongside
new, natively-captured decisions.

The engine (`lib/loom-mine-history.sh`, loom-bn7.1) does the
deterministic harvest → gate → LLM → manifest pipeline; it cannot
file into MemPalace from bash. The `~/.claude/scripts/loom-mine-history`
wrapper resolves the repo + wing and invokes the engine; the
`skills/loom-mine-history` skill drives the two-pass cost gate and
does the MCP filing. This command is the user-facing door onto that
skill.

Design source:
[`drawer_loom_decisions_e43e3693c8ee82e3bc6e34c6`](mempalace://drawer_loom_decisions_e43e3693c8ee82e3bc6e34c6)
(loom/decisions wing).

## What it does

1. **Resolve target.** Repo = `--root <dir>` if given, else the cwd's
   git toplevel. Wing = `--wing <name>` if given, else the sanitized
   basename of the repo root (`-`→`_`, e.g. `liza-base` → `liza_base`).
   Mined drawers land in `<wing>/decisions`, distinguished from
   natively-captured decisions by the `provenance:mined` tag (not a
   separate room).
2. **Read the watermark (zero spend).** Before the dry-run, the skill
   queries the repo's `history_mined_through` KG fact. If one exists, it
   passes `--since-sha=<that SHA>` so only history added since the last
   mine is harvested, and the preview opens with
   `resuming from watermark <short-sha> (N new units since last mine)`.
   On a first mine (no fact) it mines full history.
4. **Dry-run preview (zero spend).** Run the wrapper with `--dry-run`
   and surface the cost preview — `N harvested → M gated → ~M LLM
   reads, est cost`. No model is called, no manifest is written.
5. **Await your go-ahead.** The skill never spends without an explicit
   confirm. You see the preview and the resolved wing, then decide.
6. **Real pass.** On go-ahead, run the wrapper with `--out <tmp>`. The
   engine runs the LLM salience+draft pass and emits a manifest
   (`drafts.jsonl` + `kg-triples.jsonl`, plus `arcs.jsonl` when
   `--synthesize` was passed, and `watermark` — the HEAD mined through);
   the wrapper records the resolved wing alongside it.
7. **File the manifest.** Per-unit drafts FIRST: dedup-check, then add
   the drawer to `<wing>/decisions` and tag it `provenance:mined`,
   recording each `source_id → drawer_id`. THEN, when `--synthesize`
   ran, file the arcs: rewrite each arc's constituents from source
   anchor → the per-unit `drawer_id` just filed, then add the arc drawer
   tagged `provenance:mined` + `synthesis:arc`. Per KG triple: add it to
   the graph.
8. **Advance the watermark.** After the filing loop completes, the skill
   reads `<out>/watermark` (the new HEAD) and files the repo's
   `history_mined_through` KG fact — invalidating the prior fact first
   when one existed (replace, not accumulate) — so the next mine resumes
   from here. Finish with an adoption summary (filed / arcs-filed /
   skipped-dup / triples-added / watermark advanced).

## Flags

- `--root <dir>` — repo to mine. Default: the cwd's git toplevel.
- `--wing <name>` — MemPalace wing for the mined drawers. Default: the
  sanitized basename of the repo root.
- `--since=DATE` — only mine commits/PRs since DATE (git `--since`
  syntax, e.g. `--since=2025-01-01`).
- `--since-release=TAG` — only mine history after release TAG.
- `--since-sha=SHA` — only mine history after SHA (harvests `SHA..HEAD`);
  the *consume* side of the watermark. Takes precedence over
  `--since-release`. You rarely pass this by hand: on a re-mine the skill
  reads the repo's `history_mined_through` KG fact and supplies it
  automatically (see "Incremental re-mining" below). Pass it explicitly
  only to override the recorded watermark.
- `--max-units=N` — cap the survivors fed to the (paid) LLM pass.
  Useful to bound spend on a large repo's first mine.
- `--resume` — recover an interrupted real pass without re-spending on
  the units it already processed. Re-run against the SAME output dir; the
  engine skips everything recorded in `<out>/.processed` and spends only
  on the remainder. Scoped to one run's recovery — distinct from the
  cross-run watermark.
- `--synthesize` — tier-2 pass. After the per-unit salience pass, the
  engine clusters salient units by shared decision-area and spends one
  extra LLM call per cluster (≥2 units) to narrate a "narrative arc",
  emitting `arcs.jsonl`. The skill files those as `synthesis:arc`
  drawers that cross-reference the per-unit drawers they summarize.
  Opt-in; adds per-cluster cost on top of the tier-1 pass.
- `--dry-run` — preview only. The skill always runs this first; pass it
  yourself to see the gate without committing to a run.

## Contract

- **Two-pass cost gate, always.** The dry-run preview is free and
  mandatory; the paid pass runs only after your explicit go-ahead.
  Nothing spends silently.
- **Project's own wing.** Mined decisions belong to the repo they came
  from — never loom's wing (unless loom is the repo being mined).
- **`provenance:mined` tag, shared room.** Mined drawers live in the
  same `decisions` room as native captures, tagged so provenance stays
  legible and a future sweep can find them.
- **Dedup before file.** Each draft is checked against existing drawers
  before it's added, so re-running the mine is close to idempotent.
- **Arcs link real drawers, not anchors (`--synthesize`).** Per-unit
  drawers are filed first; arcs are filed second, with each constituent
  rewritten from its source anchor (PR#/SHA) to the per-unit
  `drawer_id` just filed — so an arc drawer cross-references filed
  drawers rather than bare anchors.
- **Incremental re-mining (watermark).** Each completed run records a
  `history_mined_through` KG fact pointing at the HEAD it mined through.
  The next run reads that fact and harvests only `<that SHA>..HEAD`, so
  re-mining a repo costs only the new history — never a full re-scan. The
  fact is REPLACED each run (old invalidated, new added), so exactly one
  watermark is current. The advance happens only after the filing loop
  succeeds; an aborted run leaves the old watermark standing and re-mines
  the unfiled tail next time.
- **`--resume` ≠ watermark.** `--resume` recovers a single interrupted
  run from its on-disk `<out>/.processed` checkpoint (same dir, same
  range, no re-spend on done units); it does NOT touch the watermark. The
  watermark is the across-run cursor, advanced once per fully-filed run.

## Related

- Engine: `lib/loom-mine-history.sh` (loom-bn7.1; `--synthesize` tier-2
  arcs: loom-bn7.2; `--since-sha`/`--resume`/watermark emit: loom-bn7.3).
- Wrapper: `~/.claude/scripts/loom-mine-history` (this command's executable seam).
- Skill (cost gate + MCP filing): `skills/loom-mine-history/SKILL.md`.
- Closes: loom-bn7.4 (per-unit filing), loom-68r (arc filing through
  the skill), loom-zcv (skill-side watermark round-trip +
  `--since-sha`/`--resume` flag pass-through).
