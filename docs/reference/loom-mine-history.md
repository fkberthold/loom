# loom-mine-history — reference

> Decision-archaeology for a brownfield repo. `/loom-mine-history`
> mines a repo's git/PR history for design rationale that was stated
> in-flight but never captured, then files the salient survivors as
> `provenance:mined` decision drawers in the project's **own**
> MemPalace wing. It is the P4 phase of [`/loom-adopt`](loom-adopt.md)
> and also stands alone as a primitive you run directly.

A greenfield loom project accretes its decision record as it grows —
every locked decision lands in a drawer at the moment it's made. A
brownfield repo is the opposite: an empty palace sitting on top of a
rich decision record that already exists in git — PR descriptions,
commit messages, release-tag annotations — none of it captured the
loom way. `/loom-mine-history` recovers that rationale.

The work is split across a **firm seam**:

- **The bash engine** (`lib/loom-mine-history.sh`, driven by the
  `scripts/loom-mine-history` wrapper) harvests PRs + commits + tags,
  gates them down to plausible decision candidates, runs an LLM
  salience+draft pass, and writes a manifest to disk. It owns
  repo+wing resolution and engine invocation. It **cannot** file into
  MemPalace — MCP tools are not callable from bash.
- **The skill** (`skills/loom-mine-history/SKILL.md`) drives the
  wrapper through the cost gate and does the MCP filing the engine
  cannot. It owns the cost-gate orchestration and the filing loop.

Read what the wrapper resolved (it writes the resolved wing to
`<out>/wing`); the skill never re-derives resolution logic.

## The two-pass cost gate

The single most important thing to know as a user: **the mine never
spends without showing you a preview first.** The gate is locked and
runs in two passes:

1. **Dry-run (zero spend).** The wrapper runs `--dry-run` first. It
   harvests and gates candidates and emits a **cost-preview line** —
   `N harvested → M gated → ~M LLM reads, est ≤ M model calls` — plus
   the gated candidate list and the resolved wing. It calls no model
   and writes no manifest.
2. **Real pass (paid; only after your explicit go-ahead).** The skill
   surfaces the preview, then **stops and waits** for a clear
   confirmation. Only then does the paid LLM salience+draft pass run.

Implicit assent is not enough — the skill waits for an explicit
go-ahead. If the preview looks too expensive, you can re-run the
dry-run with `--max-units` or `--since` to tighten the scope and
re-preview before committing any spend.

## Where mined drawers land — `provenance:mined`

Mined drawers land in **the project's own wing**, in the **same
`decisions` room** as native captures — distinguished by the
`provenance:mined` tag, **not** a separate room. This is deliberate:

- The wing defaults to the sanitized repo basename; `--wing`
  overrides it. The skill reads it from `<out>/wing` and never
  re-derives it.
- Keeping mined drawers in the `decisions` room (rather than a
  dedicated `mined` room) means **bug-family search reaches them** the
  same way it reaches native decisions. The tag is what carries
  provenance, so you can still filter to mined-only when you want to.
- Mined drawers are **never** filed into loom's own wing — they belong
  to the project they came from. (The exception is when loom itself is
  the repo being mined.)

To find mined drawers afterward, search filtered to `<wing>/decisions`
or filter by the `provenance:mined` tag. With `--synthesize` (below),
`synthesis:arc` narrows further to the narrative-arc drawers.

## Incremental re-mining — the watermark

Re-running the mine is **incremental by watermark**. The repo carries
a `history_mined_through` KG fact naming the HEAD the last mine
examined through:

- **Before the dry-run**, the skill reads that fact and passes
  `--since-sha=<watermark>` so only post-watermark history is
  harvested — a re-mine never re-harvests (and never risks re-spending
  on) history it already covered.
- **After the filing loop completes**, the skill advances the fact to
  the new HEAD (invalidate-then-add: replace semantics, never two live
  facts). On a first mine there is no prior fact — it just files the
  initial one.

If HEAD hasn't advanced since the watermark, the dry-run shows
`0 harvested` and the run stops — there's nothing new to mine.

The watermark is keyed on the **resolved wing** (the repo's stable
palace identity), so the read half (before the dry-run) and the write
half (after filing) close the round-trip on the same entity.

## Interrupted runs — `--resume`

`--resume` and the watermark are **distinct layers** that compose:

- **`--resume`** recovers ONE interrupted real pass from its on-disk
  `<out>/.processed` checkpoint — same `$out`, same slice. It spends
  only on the units the interrupted run had not yet processed. It does
  **not** advance the `history_mined_through` fact.
- **The watermark** spans runs: it's the across-invocation incremental
  cursor, advanced once per fully-filed run. A fresh run with no
  `$out` to resume still benefits from it via the dry-run's
  `--since-sha` read.

So an interrupted run is resumed with `--resume` (cheap, same dir); a
later clean run is scoped with `--since-sha` from the watermark. Only
the latter advances the fact.

## Narrative arcs — `--synthesize` (tier-2)

`--synthesize` adds a second LLM pass: the engine clusters the salient
units and narrates one **narrative-arc** drawer per cluster, emitting
`<out>/arcs.jsonl`. The skill files those arc drawers **after** the
per-unit drawers (the arcs cross-reference the per-unit drawers, so
those must exist first), rewriting each arc's constituent references
from the source anchor (PR#/SHA) to the real filed `drawer_id`. Arc
drawers carry both `provenance:mined` and `synthesis:arc` tags. Without
`--synthesize`, no `arcs.jsonl` is emitted and that step is skipped.

## Flags

| Flag | Effect |
|---|---|
| `--root <dir>` | Repo root to mine (default: cwd's git root). |
| `--wing <name>` | MemPalace wing for the mined drawers (default: sanitized repo basename, read from `<out>/wing`). |
| `--since <DATE>` | Harvest only history after `DATE`. |
| `--since-release <TAG>` | Harvest only history after release tag `TAG`. |
| `--since-sha <SHA>` | Harvest only `SHA..HEAD`. Set automatically from the watermark on a re-mine; takes precedence over `--since-release`. |
| `--max-units <N>` | Cap the number of harvested units (use to tighten a too-expensive preview). |
| `--synthesize` | Add the tier-2 narrative-arc clustering+narration pass. |
| `--resume` | Recover an interrupted real pass from `<out>/.processed` without re-spending on already-processed units. |

## Adoption summary

After the filing loop, the skill reports terse counts you can scan:
**filed** (per-unit drawers), **arcs-filed** (when `--synthesize` ran),
**skipped-dup** (drafts that matched an existing drawer),
**triples-added** (KG facts), and **watermark**
(`advanced <old> → <new>` or `set <new> (first mine)`). The summary
names the wing explicitly so you know where to search next.

## Related

| Item | Page |
|---|---|
| The orchestrator that runs this as its P4 phase | [loom-adopt](loom-adopt.md) |
| Walking a brownfield adoption end-to-end (audit → scaffold → mine) | [Adopt a brownfield project](../how-to/adopt-a-brownfield-project.md) |
| Why mined drawers carry `provenance:mined` and share the `decisions` room | [Provenance](../explanation/provenance.md) |
| The MCP filing surface the skill drives | [MemPalace MCP](mempalace-mcp.md) |
| Command (user door) | `commands/loom-mine-history.md` |
| Wrapper + engine (executable seam) | `scripts/loom-mine-history`, `lib/loom-mine-history.sh` |

## Skill source

The full procedure — watermark read, two-pass cost gate, the two-phase
filing loop (per-unit drafts → arcs → KG triples → watermark advance),
and the `--resume`/anti-scope details — is included verbatim below from
`skills/loom-mine-history/SKILL.md`. Edits go to the primitive, not
this page.

{%
  include-markdown "../../skills/loom-mine-history/SKILL.md"
  heading-offset=1
%}
