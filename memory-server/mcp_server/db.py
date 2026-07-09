"""mcp_server/db.py — Dolt sql-server connection helpers.

Connection details are read from the environment at CALL time (not
cached at import time), so tests can point the MCP tools at an
ephemeral dolt sql-server the same way scripts/start-server.sh's own
test bring-up does (see that script's docstring for the full env-var
list). A new connection is opened per call rather than pooled — tool
invocations from a local MCP stdio server are low-frequency, and a
fresh connection avoids any cross-call transaction-state leakage
(important for tools/drawers.py's update_drawer, which needs
autocommit OFF + SERIALIZABLE isolation only for its own call).

Env vars (all optional):
  LOOM_MEMORY_HOST      default: 127.0.0.1  (matches start-server.sh)
  LOOM_MEMORY_PORT      default: 3307       (matches start-server.sh)
  LOOM_MEMORY_DATABASE  default: doltdb     (matches start-server.sh's
                        data-dir-derived default database name)
  LOOM_MEMORY_USER      default: root
  LOOM_MEMORY_PASSWORD  default: "" (empty — start-server.sh does not
                        configure auth on the dolt sql-server)
"""
from __future__ import annotations

import os

import pymysql
import pymysql.cursors


def connection_config() -> dict:
    return {
        "host": os.environ.get("LOOM_MEMORY_HOST", "127.0.0.1"),
        "port": int(os.environ.get("LOOM_MEMORY_PORT", "3307")),
        "database": os.environ.get("LOOM_MEMORY_DATABASE", "doltdb"),
        "user": os.environ.get("LOOM_MEMORY_USER", "root"),
        "password": os.environ.get("LOOM_MEMORY_PASSWORD", ""),
    }


def connect(*, autocommit: bool = True) -> pymysql.connections.Connection:
    """Open a fresh connection to the memory server's dolt sql-server,
    using a DictCursor by default so tool code gets column-keyed rows.
    """
    cfg = connection_config()
    return pymysql.connect(
        autocommit=autocommit,
        connect_timeout=5,
        cursorclass=pymysql.cursors.DictCursor,
        **cfg,
    )
