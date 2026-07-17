# DEPLOY RUNBOOK — cut the live memory-server over to the loom-rpsf recall pipeline

**Status:** attended, operator-run cutover. Epic `loom-rpsf` (design D1–D9,
drawer `drawer_loom_decisions_04b915d08eac99c49cef0f1f`) is merged to
`main @ a1f8cca`. This runbook cuts the **live production** memory store over
to the new retrieval pipeline (chunking, search rollup, hybrid BM25+RRF,
neighbour-stitch, content-hash IDs).

**Acceptance (D8, gate-don't-advise / loom-wj26.1):** the new pipeline must
measure **Recall@10 strictly > the pre-chunking baseline (~0.50)** and
**MRR ≥ baseline** on the same held-out set — or you do **not** cut over.

> ⚠️ **Two prerequisites block execution — see §10.** (1) build `scripts/eval-live.py`
> (loom-rpsf.7); (2) expand the held-out ground-truth set (loom-rpsf.8).

---

## 0. Environment facts (verified)

| Thing | Value |
|---|---|
| memory-server root | `/home/frank/repos/loom/memory-server` |
| Python | `.venv/bin/python` |
| Dolt binary | `bin/dolt` (v2.1.10, pinned) |
| **Production port** | **3308** (`db.py` defaults to 3307 = test — always override) |
| Prod data dir | `~/.loom-memory-server/data/doltdb` |
| Service | `systemctl --user {status,start,stop,restart} loom-memory-server` |
| Logs | `journalctl --user -u loom-memory-server -f` |
| SQL client | `mysql --protocol=tcp -h 127.0.0.1 -P 3308 -u root doltdb` (no auth) |
| MCP spawn | Claude Code spawns `.venv/bin/python3 -m mcp_server.server` (stdio) per session, `LOOM_MEMORY_PORT=3308` |

Every prod-targeting script needs `LOOM_MEMORY_PORT=3308` in its environment.

---

## 1. Architecture — DATA layer vs LOGIC layer

- **DATA layer** — the always-on Dolt `sql-server` (port 3308, systemd user
  service), holding the `drawers`/`kg_triples` rows. Shared by every session,
  MCP, and script. **A write here (re-chunk, dedup) is visible to all connected
  processes immediately.**
- **LOGIC layer** — the `mcp_server.server` stdio subprocess Claude Code spawns
  per session from the on-disk code. **It does NOT hot-reload** — a running
  session keeps the code it was spawned with; new code goes live on the **next
  MCP spawn** (next session, or a mid-session MCP restart).

The standalone scripts (`eval-live.py`, `rechunk-migrate.py`, `dedup-sweep.py`)
import `mcp_server.*` from the on-disk `main` checkout, so they always run the
**new** code regardless of any MCP subprocess.

---

## 2. The ordering hazard (READ BEFORE TOUCHING DATA)

Re-chunking lands parent + child chunk rows in the shared DATA layer. An **old
(pre-rpsf) MCP** runs single-stage `VEC_DISTANCE` with **no rollup**, so the
instant chunk rows exist it returns raw `*_chunk_NNNNNN` **fragments** instead
of canonical drawers (the D4 failure). The **new** `search()` rolls up and is
correct over both un-chunked and chunked corpora (rollup is a no-op with no
children; the BM25 lane is pure gain).

**Rule: `new code can read an old corpus safely; old code cannot read a new
corpus safely — cut LOGIC over first, DATA second.`**

- The code is already on `main`, so any **fresh** Claude Code session spawns the
  new, rollup-capable MCP. Do the cutover from such a session (or restart the
  running MCP), then re-chunk.
- Accepted, bounded cost: the operator's own current (pre-`a1f8cca`) session
  gets fragment `mempalace_search` from when the re-chunk lands until its MCP
  respawns. The eval + rechunk scripts are unaffected (they don't go via the MCP).

---

## 3. Pre-flight

```bash
cd /home/frank/repos/loom/memory-server
export LOOM_MEMORY_PORT=3308
PY=.venv/bin/python
```

**3a — service up + on new code**
```bash
systemctl --user status loom-memory-server         # active (running)
git -C /home/frank/repos/loom log --oneline -1      # a1f8cca or later
$PY scripts/verify-production.py                     # read-only smoke, 6/6
```

**3b — capture current state** (record `logical`; `chunk_rows` must be 0)
```bash
mysql --protocol=tcp -h 127.0.0.1 -P 3308 -u root doltdb -e "
  SELECT COUNT(*) total,
         SUM(parent_drawer_id IS NULL) logical,
         SUM(parent_drawer_id IS NOT NULL) chunk_rows FROM drawers;"
```

**3c — DOLT commit BACKUP (the rollback anchor)** — issue over the live SQL
connection (NOT the `bin/dolt` CLI: the server holds the data-dir lock):
```bash
mysql --protocol=tcp -h 127.0.0.1 -P 3308 -u root doltdb -e "
  CALL DOLT_ADD('-A');
  CALL DOLT_COMMIT('-m','pre-rechunk backup');
  SELECT commit_hash,message,date FROM dolt_log ORDER BY date DESC LIMIT 3;"
```
**Record the top `commit_hash` as `PRE_RECHUNK_SHA`** — the data rollback target.

**3d — confirm the held-out ground-truth set** (see §10; set `GT=<path>`) and
verify every relevant id resolves in prod (they must — re-chunk preserves parent
ids, D7). A missing target can only ever count as a recall miss and poisons the gate.

---

## 4. Ordered steps

Let `GT` be the held-out `bug_family` ground-truth file.

**A — BASELINE ("before"), while the corpus is still un-chunked:**
```bash
LOOM_MEMORY_PORT=3308 $PY scripts/eval-live.py --mode before \
    --ground-truth "$GT" -k 10 --kinds bug_family --strict-wild \
    | tee /tmp/eval-before.json
```
Record `BASELINE_RECALL@10` + `BASELINE_MRR` (expect ~0.50). `--strict-wild`
hard-fails on any known-item leak (loom-buqk guard).

**B — DRY-RUN re-chunk (writes nothing):**
```bash
LOOM_MEMORY_PORT=3308 $PY scripts/rechunk-migrate.py --dry-run \
    --out /tmp/rechunked-corpus.jsonl
```
Inspect: `sources ≈ logical`; `emitted > sources`; parents keep id + full text;
children are `{parent}_chunk_000000…`, ≤800-char slices.

**C — REAL re-chunk (the DATA write).** Ordering gate: confirm §2 (tools already
on new code; you accept the current session's degradation window).
```bash
LOOM_MEMORY_PORT=3308 $PY scripts/rechunk-migrate.py \
    --out /tmp/rechunked-corpus.jsonl --checkpoint-file /tmp/rechunk.checkpoint
```
Idempotent (`INSERT … ON DUPLICATE KEY UPDATE` keyed on id); re-running is a safe
no-op. Post-write check: `logical` unchanged, `chunk_rows > 0`.

**D — AFTER measurement (new pipeline):**
```bash
LOOM_MEMORY_PORT=3308 $PY scripts/eval-live.py --mode after \
    --ground-truth "$GT" -k 10 --kinds bug_family --strict-wild \
    | tee /tmp/eval-after.json
```
Record `AFTER_RECALL@10` + `AFTER_MRR`. Drives the full new pipeline (rollup +
hybrid BM25/RRF + stitch + recency) over the re-chunked live corpus.

---

## 5. D8 acceptance gate

**PASS iff `AFTER_RECALL@10 > BASELINE_RECALL@10` (strictly) AND
`AFTER_MRR ≥ BASELINE_MRR`** on the same held-out set.

**If it does NOT improve: STOP, do not cut over.** Roll the DATA layer back
(§6 Step C), then investigate: is the BM25 index populated? do the GT ids resolve
post-rechunk? is the GT set too thin (8 queries → one flip swings ~0.12)? a
rollup/tokenizer regression (re-read D4/D5)? A non-improvement is a real failure
signal, not a rounding artifact to wave through (gate-don't-advise).

---

## 6. Rollback per step

| Step | Undo |
|---|---|
| **C — re-chunk (DATA)** | `CALL DOLT_RESET('--hard','PRE_RECHUNK_SHA');` over 3308, then `systemctl --user restart loom-memory-server`; verify `chunk_rows = 0` |
| **B — dry-run** | delete `/tmp/rechunked-corpus.jsonl` |
| **A / D — eval** | read-only, nothing to undo |
| **Code (git)** | `git -C /home/frank/repos/loom revert -m 1 a1f8cca` — **⚠️ must be paired with a DATA `DOLT_RESET` to `PRE_RECHUNK_SHA`** (old code + old corpus is the only consistent pairing), then respawn MCPs (§7) |

---

## 7. MCP live cutover

The `mempalace_*` tools go live on new code at the **next MCP spawn**:
- **Preferred:** end the current session, start a **fresh** session in this repo.
- **Mid-session:** restart the running MCP subprocess (cuts the tools over in the
  active session).
- **No DATA action** — the re-chunk was visible to all connections instantly.

**Ideal sequence** (per §2): respawn MCP on new code → *then* re-chunk (Step C).
If you re-chunked first, respawn promptly to close the fragment window.

Verify (from the fresh session): `mempalace_search("loom-40ec.7")` returns
canonical drawer ids, never `*_chunk_*` fragments.

---

## 8. Optional dedup sweep (D6 / loom-rpsf.6)

Removes residual pre-content-hash near-dup logical drawers. Own backup first:
```bash
mysql … -e "CALL DOLT_ADD('-A'); CALL DOLT_COMMIT('-m','pre-dedup backup');
            SELECT commit_hash,message,date FROM dolt_log ORDER BY date DESC LIMIT 2;"
# record PRE_DEDUP_SHA
LOOM_MEMORY_PORT=3308 $PY scripts/dedup-sweep.py            # dry-run (default)
LOOM_MEMORY_PORT=3308 $PY scripts/dedup-sweep.py --apply    # attended, after eyeballing
```
Re-run the D8 gate (§4D/§5) after applying. Rollback:
`CALL DOLT_RESET('--hard','PRE_DEDUP_SHA');` + service restart.

---

## 9. Post-cutover live verification (from a fresh session on the new MCP)

1. **BM25 exact-token win** — `mempalace_search("loom-40ec.7")` surfaces the
   drawer containing it verbatim, despite semantic unrelatedness (D5).
2. **No fragments** — every result id is a canonical `drawer_*` id (§2 negative test).
3. **Stitch** — a long drawer's `snippet` is a multi-chunk stitched window, not one slice.
4. **In-the-wild recall** — describe a known prior lesson by *symptom* (not id);
   the relevant decision drawer surfaces. This is the felt-loss the epic reverses.
5. **Content-hash idempotency (D6)** — add identical `(wing,room,content)` twice →
   one row (do it in a throwaway wing).

---

## 10. Prerequisites / gaps (must be settled before deploy)

1. **`scripts/eval-live.py` does not exist yet → loom-rpsf.7.** `eval-recall.py`'s
   `run_eval(ground_truth, search_fn, k)` is an injectable seam, but its `main()`
   only wires the raw-VEC baseline. The `--mode before/after` driver (inject
   `make_dolt_search_fn` vs `mcp_server.tools.search.search`, both against live
   3308) is required for Step D. Draft:

   ```python
   #!/usr/bin/env python3
   """scripts/eval-live.py — D8 gate against the live prod server (3308).
   --mode before: raw VEC_DISTANCE (old pipeline). --mode after: new hybrid search()."""
   import argparse, importlib.util, json, os, sys
   from pathlib import Path
   ROOT = Path(__file__).resolve().parent.parent
   sys.path.insert(0, str(ROOT)); os.environ.setdefault("LOOM_MEMORY_PORT","3308")
   spec = importlib.util.spec_from_file_location("eval_recall", ROOT/"scripts"/"eval-recall.py")
   er = importlib.util.module_from_spec(spec); spec.loader.exec_module(er)
   from mcp_server.db import connect
   def main():
       ap = argparse.ArgumentParser()
       ap.add_argument("--mode", choices=["before","after"], required=True)
       ap.add_argument("--ground-truth", type=Path, required=True)
       ap.add_argument("-k","--k", type=int, default=10)
       ap.add_argument("--kinds", default="bug_family")
       ap.add_argument("--strict-wild", action="store_true")
       a = ap.parse_args()
       kinds = None if a.kinds.strip().lower()=="all" else [s.strip() for s in a.kinds.split(",") if s.strip()]
       gt = er.load_ground_truth(a.ground_truth, kinds=kinds)
       if a.strict_wild:
           conn=connect()
           with conn.cursor() as c:
               c.execute("SELECT id,title FROM drawers WHERE parent_drawer_id IS NULL")
               cbyid={r["id"]:r for r in c.fetchall()}
           conn.close()
           _, known = er.partition_in_the_wild(gt, cbyid)
           if known: raise SystemExit(f"STRICT-WILD FAIL: {len(known)} known-item leak(s)")
       if a.mode=="before":
           from sentence_transformers import SentenceTransformer
           conn=connect(); fn = er.make_dolt_search_fn(conn, SentenceTransformer(er.MODEL_NAME), k=a.k)
           res = er.run_eval(gt, fn, k=a.k); conn.close()
       else:
           from mcp_server.tools.search import search
           res = er.run_eval(gt, lambda q: [r["id"] for r in search(q, limit=a.k)], k=a.k)
       res["mode"]=a.mode; print(json.dumps(res, indent=2, default=str))
   if __name__ == "__main__": main()
   ```

2. **The held-out `bug_family` ground-truth set is thin → loom-rpsf.8.** Only ~8
   hand-curated in-the-wild queries exist in `~/loom-spike1-benchmark/ground_truth.jsonl`
   (the rest are the lineage-narrow kind loom-buqk flagged, dropped by `--kinds
   bug_family` / `--strict-wild`). 8 queries → one flip swings Recall@10 ~0.12.
   Expand to dozens of realistic symptom-phrased query→drawer pairs (loom-buqk
   methodology; relevant ids must be **parent** ids that resolve in prod) before
   the gate is trustworthy. Absorbs loom-buqk's methodology angle.

3. **Port discipline** — always `LOOM_MEMORY_PORT=3308` (baked into every command above).

4. **Backup/rollback route** — DOLT stored procedures over the live 3308 SQL
   connection (NOT the CLI, which fights the server's data-dir lock).

5. **Concurrency** — don't run re-chunk/dedup while other sessions are actively
   writing drawers; one re-chunk at a time.
