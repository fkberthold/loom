# Migration wing-allowlist policy (loom-40ec.5)

Part 3 of loom-40ec.5's brief asked for a prune-vs-carry investigation
of the `sessions` wing's ~766,720 drawers before recommending what the
real production migration (a deliberate follow-up action, NOT this
bead) should carry forward. This document records that investigation's
findings and the resulting wing-allowlist policy — a decision, not a
silent assumption.

## Finding 1 — the `sessions` wing: PRUNE ENTIRELY, not just the big 3 rooms

An earlier pass at this investigation got stuck attempting deep-offset
pagination into the wing's three largest rooms (`architecture`=284,264,
`technical`=392,176, `problems`=83,109 — together 759,750 rows, 99.1%
of the wing's 766,720 total) and hit a real performance cliff:
`mempalace_list_drawers` calls against these rooms took **8–16 minutes
each**, regardless of whether the offset was 0 or deep into the room.
The slowness scales with the QUERIED ROOM's total size, not with how
far into it you page — confirmed by contrast: a same-shaped call
against the much smaller `sessions/decisions` room (1,437 rows)
returned **near-instantly**, at both offset=0 and offset=1400.

Given that, this investigation deliberately did NOT re-attempt paging
into the three giant rooms. Instead, it exploited the room-size
disparity itself as evidence: `decisions` (1,437), `general` (2,928),
and `planning` (2,802) are two orders of magnitude smaller and cheap to
sample directly.

**Every row sampled across all three smaller rooms — offset=0 in
`decisions`, `general`, and `planning`, PLUS a second sample at
offset=1400 in `decisions` — carries the IDENTICAL auto-mine
fingerprint:**

```json
"metadata": {
  "added_by": "mempalace",
  "extract_mode": "exchange",
  "ingest_mode": "convos",
  "id_recipe": "v3",
  "source_file": "<raw .jsonl or .txt transcript file>",
  "hall": "<creative|emotions|family|memory|general|identity|technical>",
  "filed_at": "<timestamp in the 2026-07-06 .. 2026-07-08 window>"
}
```

This is NOT curated decision content — it is raw conversational-
exchange extraction (`ingest_mode: convos`, `extract_mode: exchange`),
auto-chunked from transcript files, tagged with emotional/narrative
`hall` categories. Content excerpts sampled include a literal prompt
fragment — *"You are a memory curator for a character named Liza. Your
task is to decide whether the following memory entry should be KEEP,
DROP, or FLAG"* — indicating this wing is capturing an entirely
DIFFERENT project's (Liza's) auto-mined character-memory pipeline, not
loom (or any project's) curated technical/architectural decisions,
despite room names (`architecture`, `technical`, `decisions`) that
suggest otherwise.

**Conclusion: there is no clean "pre-bug real data" subset hiding in
any `sessions` room.** The room-name suggestion of curated content
(`decisions`, `architecture`) is misleading — every sampled row, in
every room checked, at every offset checked, is auto-mine exchange
extraction. The original hypothesis (find a timestamp cutoff
separating real-pre-bug data from bug-inflated garbage) does not apply
here: it isn't that the DATA changed character after some cutoff, it's
that this wing's content was never the kind of data loom's new memory
server is meant to hold.

**Policy: exclude the `sessions` wing ENTIRELY from the production
migration** — all rooms, no cutoff, no partial carry. (The
`_registry` room, 4 rows, errored on this investigation's query
attempt — "room contains invalid characters" — but at 4 rows out of
766,720 it's immaterial to the policy either way.)

## Finding 2 — liza-family wing naming: only `liza_base` is canonical

Independent of the `sessions` investigation, a correction surfaced
during this bead's review: MemPalace carries MULTIPLE liza-named wings
— `liza`, `liza_current`, `liza_base`, `liza_live`, `liza-live`,
`wing_liza`, `wing_liza_base`, `wing_liza_base_session_assistant`,
`save_liza` — accumulated from that project's own naming evolution
over time. **Only `liza_base` is current/canonical data worth
migrating; the rest are stale naming variants from liza's history, not
data to carry forward.**

This generalizes Finding 1's lesson beyond `sessions`: a wing's mere
PRESENCE in MemPalace, or a plausible-sounding name, does not mean its
contents are all worth migrating. The production migration's
wing-allowlist needs an explicit per-wing (not just per-project)
review, not a blanket "migrate every wing that isn't named `sessions`."

## Policy for the real production migration (loom-40ec.6, not this bead)

When the actual full production migration runs (a deliberate,
separately-monitored follow-up, per this bead's framing):

1. **Exclude `sessions` entirely** (Finding 1) — all rooms.
2. **Of the liza-family wings, include ONLY `liza_base`** (Finding 2)
   — exclude `liza`, `liza_current`, `liza_live`, `liza-live`,
   `wing_liza`, `wing_liza_base`, `wing_liza_base_session_assistant`,
   `save_liza`.
3. **Every other wing gets the same scrutiny before inclusion** — this
   investigation only had time/budget to check `sessions` and the
   liza-family; a real migration should spot-check each remaining
   wing's content shape (not just its room/wing NAME) the same way
   Finding 1 did, before assuming "not sessions, not liza-duplicate"
   is a sufficient inclusion test.
4. **Query-performance note for whoever runs the real migration**:
   avoid `mempalace_list_drawers` calls against any room north of
   ~50,000-100,000 rows if a cheaper path exists (e.g. this wing's
   exclusion makes the point moot for `sessions`, but the same
   slowness would apply to any other oversized room encountered
   later). If a future policy check needs to sample a large room
   anyway, budget for 8-16+ minutes PER CALL, not per rows-fetched —
   the slowness tracks the room's total size, not the requested page.

## What this bead (loom-40ec.5) actually validated vs. what remains

This bead built and validated `scripts/migrate.py` against the
committed `scripts/at-scale-corpus.jsonl` fixture (5,772 real rows
across 18 non-`sessions` wings, gathered by loom-40ec.7) — that fixture
was NOT filtered for the liza-family correction above (it predates this
finding), so it still contains some non-`liza_base` liza-family rows.
That's fine for THIS bead's purpose (proving the loading pipeline is
correct, idempotent, and fast) — but the REAL production migration must
apply the wing-allowlist above, not reuse the fixture's wing set
as-is.
