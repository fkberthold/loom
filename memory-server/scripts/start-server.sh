#!/usr/bin/env bash
# memory-server/scripts/start-server.sh — production bring-up for
# loom's shared, concurrent, Dolt-backed memory server (loom-40ec.3).
#
# What it does, in order:
#   1. Ensures a self-contained `dolt` binary exists (bin/dolt),
#      installing it via install-dolt.sh if missing.
#   2. Ensures dolt's global user.name/user.email are set (required
#      for dolt's internal commits) — sets placeholder values ONLY if
#      unset, never clobbers an existing config.
#   3. Inits a persistent dolt data directory (default
#      data/doltdb/ — gitignored; this holds a REAL database, never
#      committed) if not already a dolt repo.
#   4. Applies schema.sql (idempotent — every statement is
#      IF NOT EXISTS, safe to re-run against an already-provisioned
#      database) via the embedded `dolt sql` engine, BEFORE the server
#      starts.
#   5. Starts `dolt sql-server` in the foreground with sane production
#      flags: a tuned --max-connections (NOT the scratch/default value
#      an ad-hoc benchmark script would use), a non-default port to
#      avoid colliding with any system MySQL on 3306, and an explicit
#      per-instance socket path so multiple loom services on one
#      machine don't collide on /tmp/mysql.sock.
#
# All settings are overridable via environment variables so the SAME
# script serves both production bring-up (defaults) and test bring-up
# (a test points LOOM_MEMORY_DATA_DIR at an ephemeral temp directory
# and LOOM_MEMORY_PORT at a free port for isolation):
#
#   LOOM_MEMORY_DATA_DIR    default: <memory-server>/data/doltdb
#   LOOM_MEMORY_HOST        default: 127.0.0.1
#   LOOM_MEMORY_PORT        default: 3307
#   LOOM_MEMORY_MAX_CONNS   default: 150
#   LOOM_MEMORY_SOCKET      default: <memory-server>/data/loom-memory.sock
#   LOOM_MEMORY_LOG_LEVEL   default: info
#
# Usage: scripts/start-server.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMSERVER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_DIR="${LOOM_MEMORY_DATA_DIR:-$MEMSERVER_ROOT/data/doltdb}"
HOST="${LOOM_MEMORY_HOST:-127.0.0.1}"
PORT="${LOOM_MEMORY_PORT:-3307}"
# Tuned, not scratch: SPIKE-1's throwaway benchmark server ran with no
# explicit --max-connections (dolt's bare default of 1000, sized for
# an arbitrary heavy client load, not this deployment's actual expected
# concurrency of a handful of local loom agents + hooks). 150 is a
# deliberate, documented bound rather than an unexamined default.
MAX_CONNS="${LOOM_MEMORY_MAX_CONNS:-150}"
SOCKET="${LOOM_MEMORY_SOCKET:-$MEMSERVER_ROOT/data/loom-memory.sock}"
LOG_LEVEL="${LOOM_MEMORY_LOG_LEVEL:-info}"

DOLT_BIN="$MEMSERVER_ROOT/bin/dolt"

# --- 1. Ensure a working dolt binary -----------------------------------
if [ ! -x "$DOLT_BIN" ]; then
  echo "start-server: no dolt binary at $DOLT_BIN — installing." >&2
  "$SCRIPT_DIR/install-dolt.sh"
fi

# --- 2. Ensure dolt global user config (required for internal commits) -
if ! "$DOLT_BIN" config --global --get user.email >/dev/null 2>&1; then
  echo "start-server: no global dolt user.email configured — setting placeholder." >&2
  "$DOLT_BIN" config --global --add user.email "loom-memory-server@localhost"
fi
if ! "$DOLT_BIN" config --global --get user.name >/dev/null 2>&1; then
  echo "start-server: no global dolt user.name configured — setting placeholder." >&2
  "$DOLT_BIN" config --global --add user.name "loom-memory-server"
fi

# --- 3. Init the persistent data directory if needed --------------------
mkdir -p "$DATA_DIR"
if [ ! -d "$DATA_DIR/.dolt" ]; then
  echo "start-server: initializing dolt repository at $DATA_DIR" >&2
  ( cd "$DATA_DIR" && "$DOLT_BIN" init )
fi

# --- 4. Apply schema.sql (idempotent) -----------------------------------
echo "start-server: applying schema.sql to $DATA_DIR" >&2
( cd "$DATA_DIR" && "$DOLT_BIN" sql < "$MEMSERVER_ROOT/schema.sql" )

# --- 5. Start dolt sql-server in the foreground -------------------------
echo "start-server: starting dolt sql-server on $HOST:$PORT (max-connections=$MAX_CONNS, data-dir=$DATA_DIR)" >&2
exec "$DOLT_BIN" sql-server \
  --host "$HOST" \
  --port "$PORT" \
  --data-dir "$DATA_DIR" \
  --max-connections "$MAX_CONNS" \
  --socket "$SOCKET" \
  --loglevel "$LOG_LEVEL"
