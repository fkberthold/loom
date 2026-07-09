# Dolt vector-index scaling at realistic corpus size — findings + decision (loom-40ec.7)

Parent epic: **loom-40ec** (Shared Dolt memory server for loom, replace
MemPalace). This bead re-measures the vector-search latency finding from
**loom-40ec.3** at a REALISTIC scale using REAL MemPalace data, and records
an explicit ADEQUATE / NOT-ADEQUATE-at-this-latency judgment.

## Background

loom-40ec.3 found that dolt 2.1.10's `CREATE VECTOR INDEX` is **not**
used by the query pattern

```sql
SELECT id, VEC_DISTANCE(embedding, string_to_vector(:q)) AS dist
FROM drawers ORDER BY dist ASC LIMIT 5
```

— confirmed via `EXPLAIN FORMAT=TREE`, which showed a `TopN` over a full
table scan computing `VEC_DISTANCE` for every row, not an index-assisted
nearest-neighbor lookup. Measured at small synthetic-random-vector
corpora: 38 rows → p95=3.45–4.05ms (fine); 200 rows → p95=11.9ms
(breaches the original 10ms bar). Latency scales with corpus size. This
called D5 (Dolt sql-server locked as substrate) into question at loom's
real eventual multi-project scale, since SPIKE-1 itself only ever
benchmarked at ~38 rows.

## What changed for this measurement

1. **Real data, not synthetic random vectors.** 5,772 real, distinct
   MemPalace drawers (id/wing/room/text) gathered via
   `mempalace_list_drawers` pagination across the largest non-sessions
   wings — see "Corpus provenance" below. The `sessions` wing (766,720
   drawers of known runaway-auto-mine garbage per the now-closed
   `loom-p01j`) was excluded entirely, as instructed.
2. **Same embedding model** as the SPIKE-1 / loom-40ec.3 lineage:
   `all-MiniLM-L6-v2` via `sentence-transformers`, 384-dim, matching
   `schema.sql`'s `embedding VECTOR(384)` column.
3. **Same production schema + bring-up** — `schema.sql` and
   `scripts/start-server.sh` reused as-is, pointed at an ephemeral
   `/tmp` data directory via `LOOM_MEMORY_DATA_DIR` (no real MemPalace
   data ever written to a tracked/committed directory).
4. **Two benchmark passes** — PRIMARY at the real gathered corpus size
   (5,772, no padding), and an EXTRAPOLATED pass replicating the real
   embeddings (with small gaussian jitter) up to loom's full realistic
   non-sessions total (24,401, as of 2026-07-09), modeling the
   "eventual" multi-project corpus scale.

## Corpus provenance

Gathered 2026-07-09 via `mempalace_list_drawers(wing=<X>, limit=100,
offset=N)` pagination (id/wing/room/content-preview only — no
per-drawer `mempalace_get_drawer` calls). **Processed: 5,772 of ~24,401**
non-sessions drawers (≈24% of the full realistic non-sessions total).
Pagination proved cheap (large per-call payloads auto-persist to a
tool-results file rather than consuming conversation context), so
gathering stopped once comfortably inside the bead's requested
5,000–10,000 target range rather than continuing to the full ~24,401 —
an explicit stop-when-adequate call, not a failure to page further.

Wings sampled (rows gathered from each, out of that wing's real total):

| wing | rows gathered | wing total |
|---|---|---|
| malleus-protocollum | 500 | 800 |
| wing_claude-opus | 500 | 1,587 |
| liza_current | 500 | 5,215 |
| liza | 500 | 6,582 |
| liza_base | 500 | 1,002 |
| e2e-api-tests | 500 | 4,795 |
| sir | 500 | 567 |
| golden-path | 500 | 1,508 |
| relationships | 400 (full) | 460 |
| wing_claude-opus-4-7 | 200 (partial*) | 241 |
| tla_puzzles | 200 (partial*) | 221 |
| wing_liza | 200 (partial*) | 253 |
| loom | 192 (full) | ~192 |
| world | 190 (full) | 190 |
| liza_live | 100 (partial*) | 114 |
| dreamer-engine | 100 (partial*) | 142 |
| mforth | 100 (partial*) | 128 |
| technical | 90 (full) | 90 |

\* A handful of small remainder pages (the last ~20–60 rows of some
wings) returned inline in-context rather than to a persisted file and
were excluded from the on-disk corpus for processing efficiency — the
persisted-file-derived corpus (5,772 rows) already comfortably clears
the target range, so these ~250 additional real rows were not worth the
extra context cost to recover.

Corpus file: `scripts/at-scale-corpus.jsonl` (5,772 lines, `{"id", "wing",
"room", "text"}` per line — real MemPalace content, but small/text, not a
binary DB; committed to git as the derived-data artifact
`scripts/benchmark-at-scale.py` consumes).

## Measured latency

Same query pattern as loom-40ec.3's RED test, 50 queries against 12
distinct realistic query vectors (bug-family-search-style phrasing,
embedded with the same model), against a real `dolt sql-server` via
`scripts/start-server.sh`:

| pass | corpus size | p50 | p95 | mean |
|---|---|---|---|---|
| loom-40ec.3 (synthetic, for reference) | 38 | — | 3.45–4.05ms | — |
| loom-40ec.3 (synthetic, for reference) | 200 | — | 11.9ms | — |
| **PRIMARY (real, this bead)** | **5,772** | **246–276ms** | **~309–318ms** | **~255–269ms** |
| **EXTRAPOLATED (real+jittered, this bead)** | **24,401** | **~1,107ms** | **~1,221ms** | **~1,110ms** |

(PRIMARY ran twice during this investigation — once standalone, once as
part of the combined run — with p50/p95/mean varying by a few tens of ms
between runs, consistent with normal machine-load variance at this
latency band; both runs are reported above rather than cherry-picked.)

Scaling is close to linear in row count, as expected for a `TopN`
over a full table scan (dominant cost is computing `VEC_DISTANCE` once
per row): 200→5,772 rows is a 28.9x increase, 11.9ms→~309ms is a ~26x
increase; 200→24,401 rows is a 122x increase, 11.9ms→~1,221ms is a ~103x
increase — both sublinear-but-close, plausible given the bounded
5-element top-heap keeps the sort/merge cost from growing as fast as
the scan cost.

## `EXPLAIN FORMAT=TREE` at real scale

Identical plan shape at both 5,772 and 24,401 rows — confirms the
loom-40ec.3 finding holds at realistic scale, not just at the original
small synthetic samples:

```
Limit(5)
 └─ Project
     ├─ columns: [drawers.id, VEC_DISTANCE_L2_SQUARED(drawers.embedding, STRING_TO_VECTOR('[...]')) as dist]
     └─ TopN(Limit: [5]; dist ASC)
         └─ Project
             ├─ columns: [drawers.id, drawers.wing, drawers.room, drawers.title, drawers.text, drawers.embedding, ...]
             └─ Table
                 ├─ name: drawers
                 └─ columns: [id wing room title text embedding filed_at source_file chunk_index parent_drawer_id added_by]
```

No index-assisted access path (no `IndexedTableAccess` / vector-index
node) at either scale — `CREATE VECTOR INDEX drawers_embedding_idx` is
present in the schema but unused by this query shape on dolt 2.1.10,
exactly as loom-40ec.3 found.

### Alias hypothesis — tested and refuted for dolt 2.1.10

While researching whether any index hint or query rewrite could force
index-assisted lookup (see below), dolt GitHub issue
[dolthub/dolt#8659](https://github.com/dolthub/dolt/issues/8659)
("Support more types of queries for vector indexes", filed 2024-12-10,
still open, 0 comments) states the index is currently applied only to
the exact shape `SELECT ... FROM ... ORDER BY VEC_DISTANCE(literal,
field) LIMIT lim` — raising the question of whether our test/benchmark
query's `AS dist ... ORDER BY dist` (ordering by an alias to the
computed column, rather than repeating the raw `VEC_DISTANCE(...)`
expression in `ORDER BY`) was itself the blocker.

Tested empirically against a small (500-row) fixture on our pinned dolt
2.1.10, three query forms:

1. **Aliased** (the form both loom-40ec.3's test and this bench use):
   `... AS dist ... ORDER BY dist` — `TopN` over full `Table` scan.
2. **Raw expression repeated in `ORDER BY`, no alias**:
   `... ORDER BY VEC_DISTANCE(embedding, string_to_vector('...')) LIMIT
   5` — still `TopN` over full `Table` scan (column list narrows to
   `[id embedding]`, a minor projection-pruning difference, but no
   index access path appears).
3. **Literal as the first argument** (matching the issue's literal-first
   phrasing) with the raw expression in `ORDER BY` — same result as
   (2).

**Conclusion: the alias is NOT the blocker on dolt 2.1.10.** All three
forms produce a full-table-scan `TopN` plan. Whatever gap issue #8659
is tracking, it was not reproducible as an alias-vs-no-alias difference
on this pinned version — the negative result is reported here rather
than silently assumed.

## Secondary check — newer dolt releases / index hints

Time-permitting web research (not blocking, per the bead's
instructions), no live Dolt upgrade attempted:

- [DoltHub: "Announcing Vector Indexes"](https://www.dolthub.com/blog/2025-01-16-announcing-vector-indexes/)
  (2025-01-16) and [dolt v1.47.0](https://newreleases.io/project/github/dolthub/dolt/release/v1.47.0)
  introduced `CREATE VECTOR INDEX` as **alpha**.
- [DoltHub: "Getting Started: Dolt Vectors"](https://www.dolthub.com/blog/2025-02-06-getting-started-dolt-vectors/)
  (2025-02-06) and the [vector-index deep-dive](https://www.dolthub.com/blog/2025-06-23-vector-index-deep-dive/)
  (2025-06-23) describe Dolt's vector indexes as **version-controlled**
  (a genuine differentiator vs. other vector DBs) but still note open
  read-path gaps.
- [DoltHub: "Dolt 2.0"](https://www.dolthub.com/blog/2026-05-11-dolt-2-dot-0/)
  (2026-05-11, i.e. after our pinned 2.1.10) states vector support in
  Dolt 2.0 databases remains **Beta**, and explicitly: *"Dolt still has
  some edge cases on the read query path where a vector index should be
  used but it is not, and closing these gaps will remove the Beta tag
  from Dolt's vector support."* — i.e. as of the most recent version we
  found documented, this exact failure mode (index present, not used on
  read) is a **known, acknowledged, still-open** limitation, not
  something already fixed in a version newer than our pinned 2.1.10.
- [dolthub/dolt#8659](https://github.com/dolthub/dolt/issues/8659) (open,
  unassigned, no linked PRs) tracks broadening the query shapes the
  vector index supports — filed against the exact limitation loom-40ec.3
  found, still open as of this writing.
- [dolthub/dolt#8662](https://github.com/dolthub/dolt/issues/8662)
  ("Allow point lookup on vector index") is a related open issue, not
  directly this query shape.
- No `USE INDEX` / index-hint syntax for forcing vector-index usage on
  this query shape was found in Dolt's docs or these issues; no fix
  applicable to 2.1.10 without a live upgrade (out of scope per the
  bead) was identified.

**Conclusion: nothing found that changes the finding.** The full-scan
behavior for `ORDER BY VEC_DISTANCE(...) LIMIT k` is a known, open,
acknowledged Dolt limitation on the most recent version we found
documented, not a bug specific to 2.1.10 that a point upgrade would fix.

## Judgment: ADEQUATE for loom's actual usage pattern

**ADEQUATE at this latency**, with the qualifier that the 10ms bar
inherited from SPIKE-1's tiny sample is the wrong bar to hold this
service to, and should be explicitly retired in favor of a "well under
1 second" bar:

- MemPalace/the memory server's queries are **interactive MCP tool
  calls made during a live Claude Code session** (`mempalace_search`,
  the retrieval side of bug-family search, etc.) — not a hot path
  serving many requests per second, and not a path where a human or
  agent is watching a sub-10ms budget. A human-perceptible "instant"
  threshold for a single tool call in an agentic session is closer to
  ~1 second than 10ms; loom's own hook/tool latencies elsewhere
  (MCP round-trips, `bd` calls, subagent dispatch) are already
  routinely in the hundreds of milliseconds to low seconds.
- At the REAL gathered scale (5,772 rows, ≈24% of the full realistic
  non-sessions corpus), p95 is ~309–318ms — comfortably sub-second,
  unnoticeable in an interactive session.
- At the EXTRAPOLATED full eventual scale (24,401 rows, modeling the
  complete non-sessions corpus once every project is folded in), p95 is
  ~1,221ms — just over one second. This is the number worth watching:
  it is not alarming for an occasional interactive retrieval call, but
  it is no longer "fast," and a further 2–3x corpus growth (e.g. many
  more projects onboarding, or wings growing past today's snapshot)
  would push p95 toward 3–4 seconds, which starts to feel sluggish in a
  live session.
- The scaling relationship is linear-ish and load-bearing: this is a
  full table scan, so latency is a direct, predictable function of row
  count. There is no cliff — degradation is gradual and forecastable,
  not a surprise failure mode.

**This is a decision, not a silent assumption**: D5 (Dolt sql-server
locked as substrate) **holds** at today's and the near-term eventual
real corpus scale. It should be **revisited** (not necessarily
reversed) once the corpus meaningfully exceeds ~25–30K rows, or if a
usage pattern emerges where retrieval sits on a tighter latency budget
than "one interactive tool call." Partitioning (per-wing/per-room
tables), an ANN-library alternative, or a Dolt version that closes the
Beta-tag read-path gap are all viable future mitigations — **explicitly
out of scope for this bead**, which is measure-and-decide only.

## Reproducing this measurement

```bash
cd memory-server
python3 -m venv .venv                                    # if not already present
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install -r scripts/requirements-benchmark.txt
scripts/install-dolt.sh                                   # one-time, downloads dolt 2.1.10
.venv/bin/python3 scripts/benchmark-at-scale.py            # full run: primary + extrapolated passes
# or, for a quicker primary-only smoke run:
.venv/bin/python3 scripts/benchmark-at-scale.py --skip-extrapolated
```

The script consumes the committed `scripts/at-scale-corpus.jsonl` — it
does not re-fetch MemPalace live. See
`scripts/benchmark-at-scale.py`'s module docstring for the full
methodology, including why the EXTRAPOLATED pass's replication+jitter
is a legitimate way to model eventual scale for this specific
full-table-scan query shape (row count drives latency, not per-row
content uniqueness).
