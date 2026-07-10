# memory-server — production deployment

This document describes the PRODUCTION, persistent Dolt sql-server
instance for loom's memory server (epic `loom-40ec`, this bead
`loom-40ec.6.1`). It is distinct from the ephemeral instances the test
suite and `scripts/benchmark-at-scale.py` spin up in a temp directory
on a random port — those are throwaway and torn down every run; this
is the one durable instance meant to actually back loom's memory going
forward.

**Scope of this bead**: stand up the durable service. It does NOT
touch MemPalace, does NOT change any live Claude Code MCP
configuration, and does NOT migrate any real data — that is
`loom-40ec.6.2` (data migration) and `loom-40ec.6.4` (MCP cutover),
both explicitly deferred.

## Chosen configuration

| Setting | Value | Why |
|---|---|---|
| Data directory | `~/.loom-memory-server/data/doltdb` (i.e. `/home/frank/.loom-memory-server/data/doltdb`) | Outside the git repo — this is a real running database (drawers + kg_triples rows), not source. Mirrors the same "real data lives outside the repo, gitignored" pattern `memory-server/.gitignore` already uses for the repo-relative `data/` dir the *test* fixtures use, just rooted in the home directory instead so it survives independent of any repo checkout/worktree lifecycle. |
| Socket | `~/.loom-memory-server/data/loom-memory.sock` | Kept alongside the data dir rather than under the repo's `data/` default, so nothing about the production instance depends on `memory-server/`'s own `data/` directory (which stays reserved for local dev/test bring-up). |
| Host | `127.0.0.1` | Local-only; no need for network exposure on a single-machine deployment. |
| Port | `3308` | **Deliberately distinct** from the test-fixture default (`3307`, `LOOM_MEMORY_PORT` in `scripts/start-server.sh`). Tests and benchmarks already override the port to a random free port per run, so a *fixed* production port at `3308` (one above the documented test default) can never collide with a concurrent test run, and is easy to remember as "the test default, plus one, for production." |
| Max connections | `150` (unchanged default) | Same tuned value `start-server.sh` already documents as deliberate (not dolt's raw 1000 default) — a handful of local loom agents/hooks, not a heavy multi-tenant load. |
| Log level | `info` (unchanged default) | Matches dev/test; can be bumped to `debug` per-invocation via `LOOM_MEMORY_LOG_LEVEL` if troubleshooting. |

The service runs the SAME `scripts/start-server.sh` used by every
other bring-up path (tests, benchmarks) — no separate production
script was written. `start-server.sh` already does everything needed
(install dolt if missing, set dolt's global user config, init the data
dir, apply `schema.sql` idempotently, then exec `dolt sql-server`); the
only thing this bead adds is a systemd unit that supplies the
production-mode environment variables and gives the process a
lifecycle independent of any single terminal or Claude Code session.

## systemd user-service unit

Canonical source: `memory-server/deploy/loom-memory-server.service`
(committed to the repo). It is **not** auto-installed — install it
once per machine:

```bash
# 1. Link the repo's canonical unit file into the user's systemd
#    config dir (a symlink, not a copy — edits to the repo file take
#    effect on the next daemon-reload with no re-install step).
systemctl --user link /home/frank/repos/loom/memory-server/deploy/loom-memory-server.service
systemctl --user daemon-reload

# 2. Enable it (so it starts automatically under lingering — see
#    below) and start it now.
systemctl --user enable loom-memory-server
systemctl --user start loom-memory-server
```

The unit's `ExecStart`/`WorkingDirectory` are hardcoded to this
machine's actual clone path (`/home/frank/repos/loom/memory-server`)
rather than templated — this is a single-machine deployment, and
loom's own conventions call out not to over-engineer cross-platform
portability for one box. If the clone ever moves, update the unit
file's paths and re-run the link + daemon-reload step.

> **Note on verification-time installation**: this bead was
> implemented and verified inside an isolated worktree
> (`.claude/worktrees/agent-ae04297acc27b3783/`), which is where the
> unit file currently physically lives on disk pending merge to
> `main`. The `ExecStart`/`WorkingDirectory` paths already point at
> the real main-repo location (`/home/frank/repos/loom/memory-server`)
> since that script is unchanged and already merged, so the *running
> service* is using the real, permanent copy of `start-server.sh` and
> `schema.sql`. Only the `.service` file's symlink target is
> worktree-local for now. **After this branch merges to `main`**,
> re-run the `systemctl --user link` step above pointing at the
> merged-in `/home/frank/repos/loom/memory-server/deploy/loom-memory-server.service`
> — the content is byte-identical, so this is bookkeeping (repointing
> the symlink to the permanent file location), not a behavior change.

## Lingering decision

**Chosen: enable lingering** (`loginctl enable-linger frank`), rather
than leaving the service tied to an active login session.

Why: the whole point of this bead is a service that "outlives any
single Claude Code session" — Claude Code sessions can start and stop
independent of whether the human is at an interactive desktop session.
Without lingering, a plain `systemctl --user` service stops the moment
the user's last login session ends (verified before making any change:
`loginctl show-user frank --property=Linger` → `Linger=no`), which
would make the "production, durable" framing of this bead false in
practice on this machine's normal usage pattern. Lingering is a real,
if minor, system-level change (it keeps `user@1000.service`, the
per-user systemd instance, running independent of login state, and per
`systemd-logind` semantics, starts it at boot too) — documented here
rather than left implicit, per the bead's explicit ask.

**Applied**: `loginctl enable-linger frank` was run during this bead's
verification. Confirmed via `loginctl show-user frank --property=Linger`
→ `Linger=yes`, and `systemctl status user@1000.service` shows the
user manager active.

**To reverse** (stop lingering, revert to session-tied lifecycle):

```bash
loginctl disable-linger frank
```

This does not stop the service itself if it's currently running under
an active session — it only removes the "start at boot / persist past
logout" behavior going forward.

**Known verification gap**: this environment cannot simulate an actual
logout/login or reboot cycle, so the "survives a true session boundary"
claim rests on `systemd-logind`'s documented lingering semantics plus
the observed facts (lingering enabled, `user@1000.service` active,
independent of the specific login session shown in
`loginctl list-sessions`) rather than a directly observed logout/login
round-trip. What WAS directly verified (see "Bring-up verification"
below) is the weaker-but-related claim: the service survives an
explicit `systemctl --user stop` / `start` cycle with data intact,
proving the persistence layer (the dolt data directory) is durable
across process restarts. The stronger claim (survives an actual
logout) is a documented gap, not a false claim.

## Bring-up verification (performed 2026-07-09)

All of the following were directly run and observed, not assumed:

1. **Service starts.** `systemctl --user start loom-memory-server` →
   `systemctl --user status` showed `Active: active (running)`, with
   the `dolt sql-server` process listening on `127.0.0.1:3308`
   (confirmed via `ss -tlnp`).
2. **Schema applied correctly.** `SHOW TABLES` → `drawers`,
   `kg_triples`. `SHOW INDEX FROM drawers` confirmed both
   `drawers_embedding_idx` (the vector index) and
   `drawers_wing_room_idx` (the `(wing, room)` composite index).
   `SHOW INDEX FROM kg_triples` confirmed all three named indices:
   `kg_triples_subject_idx`, `kg_triples_object_idx`,
   `kg_triples_subject_predicate_idx`.
3. **Round-trip works.** Inserted a real row into `drawers` (with a
   proper 384-dim `string_to_vector(...)` embedding) and selected it
   back successfully against the production instance on port `3308`.
4. **Restart survival.** Inserted a marker row
   (`id='prod-restart-marker'`), then `systemctl --user stop
   loom-memory-server` (confirmed port `3308` no longer listening,
   confirmed a new connection attempt gets `ERROR 2002 Can't connect`),
   then `systemctl --user start loom-memory-server` again (new PID,
   confirming a genuinely fresh process) — the marker row, and the
   earlier round-trip row, were both still present and selectable.
   `schema.sql` re-applied idempotently on the restart (logged, no
   errors, table/index set unchanged).
5. **Test-suite isolation.** The full 47-test suite
   (`.venv/bin/pytest tests/ -v`) was run **while the production
   service was live** on port 3308 with real data in it, and passed
   47/47 — confirming the ephemeral test fixtures (random free ports,
   temp data dirs) never interact with the production instance.

**Post-verification cleanup**: the `prod-verify-1` and
`prod-restart-marker` rows used for steps 3–4 above were deleted after
verification (`DELETE FROM drawers WHERE id IN (...)`), so the
production instance is handed off **empty** — `SELECT COUNT(*) FROM
drawers` returns `0` — ready for `loom-40ec.6.2`'s real data migration
rather than carrying leftover verification rows.

## Operating the service

```bash
# Status
systemctl --user status loom-memory-server

# Start / stop / restart
systemctl --user start loom-memory-server
systemctl --user stop loom-memory-server
systemctl --user restart loom-memory-server

# Logs (follow live)
journalctl --user -u loom-memory-server -f

# Logs (recent history)
journalctl --user -u loom-memory-server -n 100 --no-pager

# Connect with a MySQL-protocol client (mysql CLI, pymysql, etc.)
mysql --protocol=tcp -h 127.0.0.1 -P 3308 -u root doltdb
```

There is no password configured (matches `start-server.sh`'s existing
behavior for every other bring-up path — no `--user`/`--password`
flags are set on `dolt sql-server`). This is acceptable for a
localhost-only, single-user dev machine; revisit if the bind host or
threat model ever changes.

## Troubleshooting

**Service won't start / immediately exits:**

- `journalctl --user -u loom-memory-server -n 50 --no-pager` — read
  the actual failure first.
- **Port already in use.** `ss -tlnp | grep 3308` — if something else
  (e.g. a leftover benchmark run, or a manual `start-server.sh`
  invocation using the production port by mistake) already holds
  `3308`, the `dolt sql-server` bind fails. Stop the other process, or
  confirm this IS the production service already running
  (`systemctl --user status loom-memory-server`) before assuming a
  conflict.
- **Dolt binary missing / stale.** `start-server.sh` auto-installs
  `bin/dolt` via `scripts/install-dolt.sh` on first run if
  `memory-server/bin/dolt` doesn't exist — this requires outbound
  network access to GitHub releases. If that fails (offline, GitHub
  unreachable), the service will fail to start; run
  `scripts/install-dolt.sh` manually and check its output.
- **Permissions.** The data directory
  (`~/.loom-memory-server/data/doltdb`) and socket path must be
  writable by the user the service runs as (this is a `systemctl
  --user` service, so it's always the invoking user — no separate
  service-account permission mismatch is possible here, unlike a
  system-level unit).
- **Lingering not enabled + service appears to "randomly" stop.** If
  `loginctl show-user <user> --property=Linger` shows `Linger=no`,
  the service will stop when the last login session for that user
  ends. Re-run `loginctl enable-linger <user>` (see above).
- **Schema/index mismatch after a manual data-dir change.** Since
  `schema.sql` is idempotent (`IF NOT EXISTS` throughout), simply
  restarting the service (or manually running
  `dolt sql < schema.sql` from inside the data dir) re-applies it
  safely — it will never drop or alter existing tables/indices,
  only create what's missing.

## Files

- `memory-server/deploy/loom-memory-server.service` — canonical
  systemd user-service unit (this bead).
- `memory-server/scripts/start-server.sh` — the actual bring-up logic
  (dolt install, schema apply, server start), shared with tests and
  benchmarks (loom-40ec.3, pre-existing, unchanged by this bead).
- `memory-server/schema.sql` — the production schema (pre-existing,
  unchanged by this bead).
