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
`--since`, `--since-release`, `--max-units`) against a repo whose history
predates its MemPalace wing — a freshly-adopted project, a legacy service,
loom itself before bn7. Manual-only; never auto-fired.

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
  [--since=DATE] [--since-release=TAG] [--max-units=N]
```

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
scripts/loom-mine-history --out "$out" [same --root/--wing/--since/... flags]
```

The wrapper invokes the engine with `--yes --out "$out"`, which runs the
LLM salience+draft pass and writes the manifest. Then read:

- `<out>/wing` — the resolved wing (single line). Use this verbatim.
- `<out>/drafts.jsonl` — one JSON/line:
  `{source_id, source_type, anchor{id,url,date,author}, verbatim,
  synthesis, drawer_body, room, tags}`.
- `<out>/kg-triples.jsonl` — one JSON/line:
  `{subject, predicate, object}`.

If `drafts.jsonl` is empty, nothing was salient — report that and stop
(no filing, no error).

### 4 — Filing loop (MCP; this is the skill's job, not the wrapper's)

Let `WING` be the contents of `<out>/wing`. For each draft line in
`<out>/drafts.jsonl`:

1. **Dedup check** — `mempalace_check_duplicate(content=<drawer_body>)`.
   If it reports a match, SKIP this draft (count it skipped-dup); do not
   file a near-duplicate of an existing drawer.
2. **File the drawer** —
   `mempalace_add_drawer(wing=WING, room="decisions",
   content=<drawer_body>, source_file=<anchor.url or anchor.id>)`.
   Capture the returned `drawer_id`.
3. **Tag provenance** —
   `mempalace_tag_drawer(drawer_id=<id>, tag_key="provenance",
   tag_value="mined")`. (The `provenance:mined` tag from the manifest's
   `tags` array, expressed as the tool's key/value pair.)

For each triple line in `<out>/kg-triples.jsonl`:

- `mempalace_kg_add(subject=<subject>, predicate=<predicate>,
  object=<object>)`. The engine emits `decided`, `mined_from`, and
  `authored_by` triples per salient unit; file each as-is.

Process drafts before triples so the drawers exist when the graph
references their sources.

### 5 — Adoption summary

Report terse counts the user can scan:

- **filed**: drawers added to `WING/decisions`;
- **skipped-dup**: drafts that matched an existing drawer;
- **triples-added**: KG facts filed.

Name the wing explicitly so the user knows where to search next
(`mempalace_search` filtered to `WING/decisions`, or by the
`provenance:mined` tag).

## Anti-scope

- Do NOT re-implement repo/wing resolution — the wrapper owns it; read
  `<out>/wing`.
- Do NOT skip the dry-run or the go-ahead beat — spending without the
  confirm beat violates the locked contract.
- Do NOT file mined drawers into loom's wing (unless loom is the repo
  being mined) — they belong to the project they came from.
- Do NOT invent a separate `mined` room — same `decisions` room, the tag
  carries provenance.

## Related

- Command (user door): `commands/loom-mine-history.md`.
- Wrapper (executable seam): `scripts/loom-mine-history`.
- Engine (harvest → gate → LLM → manifest): `lib/loom-mine-history.sh`.
- Closes: loom-bn7.4.
