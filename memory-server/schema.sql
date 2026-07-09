-- memory-server/schema.sql — Production schema for loom's shared,
-- concurrent, Dolt-backed memory server (epic loom-40ec, this bead
-- loom-40ec.3).
--
-- Locked design: MemPalace drawer
--   drawer_loom_decisions_521e654693797b4f169b4cbd
--
--   D5 (locked) — substrate = Dolt `sql-server`, validated via
--   SPIKE-1 (Recall@10=0.81, MRR=0.52, p95 query latency=3.94ms, no
--   reader lockout under concurrent writes). Schema shape:
--   drawers(id, wing, room, title, text, embedding VECTOR(384) NOT
--   NULL) with CREATE VECTOR INDEX + VEC_DISTANCE() queries.
--
--   D6 (locked) — no branch-per-session / no custom CAS. A single
--   shared branch relying on Dolt's native SQL transaction semantics
--   (OCC catches same-row write conflicts at commit time). Not this
--   schema's concern directly; noted here so a reader doesn't go
--   looking for branch/merge machinery that was deliberately NOT
--   built.
--
--   D7 (locked) — kg_triples migrates as a curated relational table,
--   reproduced below EXACTLY as specified in the drawer.
--
-- Idempotent by construction: every statement is safe to re-run
-- against an already-provisioned database (IF NOT EXISTS throughout).
-- Verified against dolt 2.1.10 (self-contained install, see
-- scripts/install-dolt.sh) via both the embedded `dolt sql` engine and
-- a live `dolt sql-server` connection.
--
-- NOTE on inserting into the `embedding` VECTOR(384) column: a bare
-- string/JSON-array literal does NOT implicitly convert to `vector`
-- (verified — raises "value of type string cannot be converted to
-- 'vector' type"). Use the `string_to_vector('[0.1,0.2,...]')`
-- function, e.g.:
--   INSERT INTO drawers (id, wing, room, title, text, embedding, ...)
--   VALUES ('d1', 'loom', 'decisions', 'title', 'text',
--           string_to_vector('[0.1,0.2,...]'), ...);
-- Querying is symmetric: VEC_DISTANCE(embedding, string_to_vector('[...]')).

-- NOTE on database naming: this schema deliberately does NOT issue a
-- `CREATE DATABASE` / `USE` — Dolt names the default database after
-- the directory a `dolt init` was run in (verified: `CREATE DATABASE
-- x` from inside an already-init'd repo creates x as a NESTED
-- sub-repo/sub-directory, which is confusing plumbing this schema
-- doesn't need). scripts/start-server.sh inits the persistent data
-- directory at `data/doltdb/`, so the default (and only) database
-- these tables land in is named `doltdb` — matching the SPIKE-1
-- prototype's proven connection convention (`database="doltdb"`).

-- D5: drawers — semantic-search-backed memory unit. The five columns
-- in the drawer's locked shape (id, wing, room, title, text,
-- embedding) plus metadata columns mirroring MemPalace's existing
-- drawer shape (filed_at, source_file, chunk_index, parent_drawer_id,
-- added_by).
CREATE TABLE IF NOT EXISTS drawers (
    id                VARCHAR(128)  NOT NULL,
    wing              VARCHAR(128)  NOT NULL,
    room              VARCHAR(128)  NOT NULL,
    title             VARCHAR(512)  NOT NULL,
    text              LONGTEXT      NOT NULL,
    embedding         VECTOR(384)   NOT NULL,
    filed_at          DATETIME      NULL,
    source_file       VARCHAR(512)  NULL,
    chunk_index       INT           NULL,
    parent_drawer_id  VARCHAR(128)  NULL,
    added_by          VARCHAR(128)  NULL,
    PRIMARY KEY (id)
);

-- Vector index enabling `ORDER BY VEC_DISTANCE(embedding, :q) LIMIT k`
-- to run as an index-assisted nearest-neighbor search rather than a
-- full table scan. `CREATE VECTOR INDEX` (unlike plain `CREATE INDEX`)
-- does support `IF NOT EXISTS` on dolt 2.1.10 — verified directly.
CREATE VECTOR INDEX IF NOT EXISTS drawers_embedding_idx ON drawers(embedding);

-- D7: KG triples migrate as a curated relational table (reproduced
-- verbatim from the locked decision — column set, types, and
-- constraints are NOT to be changed without a new decision).
CREATE TABLE IF NOT EXISTS kg_triples (
    id             VARCHAR(64)   NOT NULL,
    subject        VARCHAR(256)  NOT NULL,
    predicate      VARCHAR(128)  NOT NULL,
    object         VARCHAR(256)  NOT NULL,
    confidence     FLOAT         DEFAULT 1.0,
    valid_from     DATETIME      NULL,
    valid_to       DATETIME      NULL,
    source_closet  VARCHAR(256)  NULL,
    `current`      BOOLEAN       DEFAULT TRUE,
    created_at     DATETIME      NOT NULL,
    PRIMARY KEY (id)
);

-- D7's three named indices: (subject), (object), (subject, predicate).
-- Plain `CREATE INDEX ... IF NOT EXISTS` is idempotent on dolt 2.1.10
-- — verified directly (a second run against an existing index is a
-- silent no-op, exit 0).
CREATE INDEX IF NOT EXISTS kg_triples_subject_idx ON kg_triples(subject);
CREATE INDEX IF NOT EXISTS kg_triples_object_idx ON kg_triples(object);
CREATE INDEX IF NOT EXISTS kg_triples_subject_predicate_idx ON kg_triples(subject, predicate);
