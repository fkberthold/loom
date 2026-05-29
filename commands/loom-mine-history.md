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
file into MemPalace from bash. The `scripts/loom-mine-history`
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
2. **Dry-run preview (zero spend).** Run the wrapper with `--dry-run`
   and surface the cost preview — `N harvested → M gated → ~M LLM
   reads, est cost`. No model is called, no manifest is written.
3. **Await your go-ahead.** The skill never spends without an explicit
   confirm. You see the preview and the resolved wing, then decide.
4. **Real pass.** On go-ahead, run the wrapper with `--out <tmp>`. The
   engine runs the LLM salience+draft pass and emits a manifest
   (`drafts.jsonl` + `kg-triples.jsonl`); the wrapper records the
   resolved wing alongside it.
5. **File the manifest.** Per draft: dedup-check, then add the drawer
   to `<wing>/decisions` and tag it `provenance:mined`. Per KG triple:
   add it to the graph. Finish with an adoption summary (filed /
   skipped-dup / triples-added).

## Flags

- `--root <dir>` — repo to mine. Default: the cwd's git toplevel.
- `--wing <name>` — MemPalace wing for the mined drawers. Default: the
  sanitized basename of the repo root.
- `--since=DATE` — only mine commits/PRs since DATE (git `--since`
  syntax, e.g. `--since=2025-01-01`).
- `--since-release=TAG` — only mine history after release TAG.
- `--max-units=N` — cap the survivors fed to the (paid) LLM pass.
  Useful to bound spend on a large repo's first mine.
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

## Related

- Engine: `lib/loom-mine-history.sh` (loom-bn7.1).
- Wrapper: `scripts/loom-mine-history` (this command's executable seam).
- Skill (cost gate + MCP filing): `skills/loom-mine-history/SKILL.md`.
- Closes: loom-bn7.4.
