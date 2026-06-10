#!/usr/bin/env bash
# pytest-tempdir-prune.sh — SessionStart housekeeping hook (loom-skxj).
#
# WHAT IT DOES
#   On session start, removes STALE pytest temp dirs that accumulate
#   under a project's `./tmp/` and eat drive space. pytest writes its
#   per-run temp trees to `<basetemp>/pytest-of-<user>/...`; projects
#   that point pytest's basetemp at `./tmp/` (or that just run pytest
#   from a cwd whose `./tmp/` collects them) end up with a growing
#   `./tmp/pytest-of-<user>/` that nothing ever reaps. Origin: a project
#   with `./tmp/pytest-of-frank` grown huge.
#
# SCOPE — STRICTLY ./tmp/pytest-of-* (PROJECT-RELATIVE), DIRECT CHILDREN
#   The prune is deliberately project-scoped, NOT machine-global. It
#   touches ONLY direct children of the cwd-relative `./tmp/` directory
#   whose name matches `pytest-of-*` AND that are directories older than
#   24h. It does NOT touch:
#     - /tmp/pytest-of-$USER or anything under the system /tmp,
#     - ./pytest-of-* sitting directly in the project root (outside ./tmp/),
#     - ./tmp/<anything-not-matching-pytest-of-*> (e.g. ./tmp/keepme/),
#     - ./tmp/sub/pytest-of-* nested below a direct child (maxdepth 1).
#   The `find ./tmp -maxdepth 1` base + `-name 'pytest-of-*'` + `-type d`
#   make it structurally impossible to escape `./tmp/`'s direct children.
#
# RETENTION
#   Only entries older than 24h are removed (`-mtime +1`). A pytest run
#   from the current session (fresh temp dir) is kept, so the hook never
#   races a just-started test run.
#
# PREVENT (the durable root-cause fix — documented, not enforced here)
#   The non-destructive root fix is pytest's own retention config.
#   Downstream pytest projects SHOULD set, in `pyproject.toml`:
#
#       [tool.pytest.ini_options]
#       tmp_path_retention_count = 1
#       tmp_path_retention_policy = "failed"
#
#   That keeps only the most recent failed-run temp tree, so the dirs
#   never accumulate in the first place. This hook is the complementary
#   sweep for projects that have not (yet) adopted that config, or for
#   temps that predate it. See docs/reference/pytest-tempdir-prune.md.
#
# POSTURE — NON-BLOCKING, ALWAYS EXIT 0
#   This is a loom housekeeping hook. It NEVER blocks session start and
#   NEVER emits blocking JSON. Every path exits 0: absent ./tmp, no
#   matches, opt-out, or a successful prune. A find/rm error is
#   swallowed (fail-open) so a permissions hiccup can never wedge a
#   session.
#
# OPT-OUT
#   LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1  (literal "1", per loom-b1l) → no-op.

set -uo pipefail

# Lib resolution: an explicitly-set LOOM_TEST_LIB_DIR wins (so a
# worktree's modified libs are what the fixture tests exercise, not
# main's installed copy). Otherwise prefer the installed copy, then the
# repo-relative copy. Provides loom_env_enabled (the literal-"1" gate).
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

# Opt-out gate (literal "1"). Helper may be unavailable in a degraded
# environment — fall back to an inline literal check so the gate always
# works.
if declare -F loom_env_enabled >/dev/null 2>&1; then
  loom_env_enabled LOOM_PYTEST_TEMPDIR_PRUNE_SKIP && exit 0
else
  [ "${LOOM_PYTEST_TEMPDIR_PRUNE_SKIP:-}" = "1" ] && exit 0
fi

# Drain stdin (the SessionStart payload). The prune keys off the cwd's
# `./tmp/`, not any payload field; draining keeps the hook well-behaved
# as a pipe consumer.
cat >/dev/null 2>&1 || true

# No ./tmp/ → nothing to prune. Exit 0 no-op.
[ -d "./tmp" ] || exit 0

# Prune STALE (>24h) direct-child pytest-of-* dirs under ./tmp/ ONLY.
#   -maxdepth 1  → direct children of ./tmp/ only (no recursion below).
#   -name        → matches the pytest-of-* basename only.
#   -type d      → directories only (a ./tmp/notpytest file is ignored
#                  anyway by -name, but -type d is belt-and-suspenders).
#   -mtime +1    → older than 24h (a fresh same-session run is kept).
# The relative `./tmp` base + maxdepth 1 make it structurally
# impossible to reach /tmp/, ./pytest-of-*, or nested ./tmp/sub/... .
# Fail-open: any find/rm error is swallowed so the hook still exits 0.
find ./tmp -maxdepth 1 -name 'pytest-of-*' -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true

exit 0
