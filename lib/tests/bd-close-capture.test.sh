#!/usr/bin/env bash
# Fixture tests for hooks/bd-close-capture.sh.
#
# Covers loom-8vb (Bug A: regex captures --reason content; Bug B: hook
# performs no real verification at all), loom-b20, loom-2t7, loom-8sd3,
# loom-oq0s, loom-lwg4, and — this pass — loom-b76s / loom-efrx /
# loom-84nx.
#
# Locked design: drawer_loom_decisions_2fbf2d5f4c0f5e50ab84e628.
#
# STORE FIXTURE (loom-b76s). Every earlier version of this file built a
# ChromaDB sqlite under MEMPALACE_HOME. The MemPalace MCP stopped writing
# ChromaDB at the Dolt migration, so those 753 lines validated a store
# shape that no longer exists — a green suite over a dead gate. The
# fixture is now an EPHEMERAL DATABASE on the live Dolt sql-server,
# created and dropped per run, with its tables copied from the live
# database via `CREATE TABLE ... LIKE` so the test exercises the real
# engine, the real column types, and the real (case-sensitive,
# utf8mb4_0900_bin) collation.
#
# When no server is reachable the store-dependent sections SKIP LOUDLY
# rather than passing quietly. Set LOOM_TEST_REQUIRE_MEMORY_SERVER=1 to
# turn those skips into failures (for a CI runner that always has one).
#
# Injection points used by the tests:
#   LOOM_MEMORY_HOST/PORT/DATABASE/USER/PASSWORD — the store the hook reads
#   LOOM_MEMORY_PYTHON — interpreter carrying pymysql
#   BD_BIN             — bd binary (default: bd)
#
# Run:  bash lib/tests/bd-close-capture.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-close-capture.sh"

# Lib ladder (loom-8ztk): make the hook under test load THIS checkout's
# lib/, not the installed symlinks into MAIN. Without it a worktree run
# silently verifies MAIN's helpers.
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

passed=0
failed=0
skipped=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }
skip() { echo "  SKIP: $1"; skipped=$((skipped + 1)); }

# ---------------------------------------------------------------------------
# Interpreter discovery
# ---------------------------------------------------------------------------
#
# The hook talks to Dolt through pymysql, which lives in the memory
# server's venv rather than in system python3. Inside a linked worktree
# that venv is absent — it is untracked build state that exists only in
# the main checkout — and in production the installed hook symlink
# resolves into the main checkout anyway. So look there too, rather than
# skipping every store test whenever the suite runs from a worktree.
find_memory_python() {
  local common main c
  common=$(git -C "$LOOM_ROOT" rev-parse --git-common-dir 2>/dev/null || true)
  main=""
  [ -n "$common" ] && main=$(cd "$common/.." 2>/dev/null && pwd || true)
  for c in \
    "${LOOM_MEMORY_PYTHON:-}" \
    "$LOOM_ROOT/memory-server/.venv/bin/python3" \
    "${main:+$main/memory-server/.venv/bin/python3}" \
    python3
  do
    [ -n "$c" ] || continue
    [ -x "$c" ] || command -v "$c" >/dev/null 2>&1 || continue
    if "$c" -c 'import pymysql' >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

MEMPY=$(find_memory_python || true)

# ---------------------------------------------------------------------------
# Store discovery
# ---------------------------------------------------------------------------
#
# Mirrors the hook's own resolution order (env, then the `env` block the
# mempalace MCP server is configured with, then db.py's defaults) so the
# fixture lands on the same server the hook will read.
settings_memory_env() {
  [ -n "$MEMPY" ] || return 1
  "$MEMPY" -c '
import json, os, sys
cands = []
proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
cands.append(os.path.join(proj, ".claude", "settings.local.json"))
cands.append(os.path.join(proj, ".claude", "settings.json"))
cands.append(os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or
                          os.path.expanduser("~/.claude"), "settings.json"))
cands.append(os.path.expanduser("~/.claude.json"))
for p in cands:
    try:
        with open(p) as fh:
            d = json.load(fh)
    except Exception:
        continue
    for srv in (d.get("mcpServers") or {}).values():
        env = (srv or {}).get("env") or {}
        hits = {k: v for k, v in env.items() if k.startswith("LOOM_MEMORY_")}
        if hits:
            for k, v in sorted(hits.items()):
                print(f"{k}={v}")
            sys.exit(0)
' 2>/dev/null
}

store_ping() {  # host port user password database
  [ -n "$MEMPY" ] || return 1
  PING_HOST="$1" PING_PORT="$2" PING_USER="$3" PING_PASS="$4" PING_DB="$5" \
  "$MEMPY" -c '
import os, sys, pymysql
try:
    con = pymysql.connect(host=os.environ["PING_HOST"], port=int(os.environ["PING_PORT"]),
                          user=os.environ["PING_USER"], password=os.environ["PING_PASS"],
                          database=os.environ["PING_DB"] or None, connect_timeout=3)
    con.close()
except Exception as e:
    print(e, file=sys.stderr); sys.exit(1)
' >/dev/null 2>&1
}

STORE_HOST="${LOOM_MEMORY_HOST:-}"
STORE_PORT="${LOOM_MEMORY_PORT:-}"
STORE_USER="${LOOM_MEMORY_USER:-}"
STORE_PASS="${LOOM_MEMORY_PASSWORD:-}"
STORE_LIVE_DB="${LOOM_MEMORY_DATABASE:-}"

while IFS='=' read -r k v; do
  case "$k" in
    LOOM_MEMORY_HOST)     [ -n "$STORE_HOST" ]    || STORE_HOST="$v" ;;
    LOOM_MEMORY_PORT)     [ -n "$STORE_PORT" ]    || STORE_PORT="$v" ;;
    LOOM_MEMORY_USER)     [ -n "$STORE_USER" ]    || STORE_USER="$v" ;;
    LOOM_MEMORY_PASSWORD) [ -n "$STORE_PASS" ]    || STORE_PASS="$v" ;;
    LOOM_MEMORY_DATABASE) [ -n "$STORE_LIVE_DB" ] || STORE_LIVE_DB="$v" ;;
  esac
done < <(settings_memory_env || true)

STORE_HOST="${STORE_HOST:-127.0.0.1}"
STORE_PORT="${STORE_PORT:-3307}"
STORE_USER="${STORE_USER:-root}"
STORE_LIVE_DB="${STORE_LIVE_DB:-doltdb}"

STORE_OK=0
EPH_DB=""
if [ -n "$MEMPY" ] && store_ping "$STORE_HOST" "$STORE_PORT" "$STORE_USER" "$STORE_PASS" "$STORE_LIVE_DB"; then
  STORE_OK=1
fi

# One statement per argv entry, against $1 (empty = no database selected).
store_sql() {
  local db="$1"; shift
  SQL_HOST="$STORE_HOST" SQL_PORT="$STORE_PORT" SQL_USER="$STORE_USER" \
  SQL_PASS="$STORE_PASS" SQL_DB="$db" \
  "$MEMPY" -c '
import os, sys, pymysql
con = pymysql.connect(host=os.environ["SQL_HOST"], port=int(os.environ["SQL_PORT"]),
                      user=os.environ["SQL_USER"], password=os.environ["SQL_PASS"],
                      database=os.environ["SQL_DB"] or None,
                      autocommit=True, connect_timeout=5)
cur = con.cursor()
for stmt in sys.argv[1:]:
    cur.execute(stmt)
con.close()
' "$@"
}

# The VECTOR(384) column is NOT NULL and takes no bare literal, so every
# seeded drawer carries a throwaway constant vector built with
# string_to_vector(CONCAT(...)) inside store_add_drawer below. Nothing in
# the hook reads the embedding; it exists only to satisfy the real schema.

store_reset() {
  store_sql "$EPH_DB" "DELETE FROM drawers" "DELETE FROM kg_triples"
}

store_add_drawer() {  # id wing room title text
  SQL_HOST="$STORE_HOST" SQL_PORT="$STORE_PORT" SQL_USER="$STORE_USER" \
  SQL_PASS="$STORE_PASS" SQL_DB="$EPH_DB" \
  "$MEMPY" -c '
import os, sys, pymysql
con = pymysql.connect(host=os.environ["SQL_HOST"], port=int(os.environ["SQL_PORT"]),
                      user=os.environ["SQL_USER"], password=os.environ["SQL_PASS"],
                      database=os.environ["SQL_DB"], autocommit=True, connect_timeout=5)
con.cursor().execute(
    "INSERT INTO drawers (id, wing, room, title, text, embedding, filed_at) "
    "VALUES (%s, %s, %s, %s, %s, "
    "string_to_vector(CONCAT('"'"'['"'"', REPEAT('"'"'0.1,'"'"', 383), '"'"'0.1]'"'"')), NOW())",
    (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]))
con.close()
' "$1" "$2" "$3" "$4" "$5"
}

store_add_triple() {  # id subject predicate object
  SQL_HOST="$STORE_HOST" SQL_PORT="$STORE_PORT" SQL_USER="$STORE_USER" \
  SQL_PASS="$STORE_PASS" SQL_DB="$EPH_DB" \
  "$MEMPY" -c '
import os, sys, pymysql
con = pymysql.connect(host=os.environ["SQL_HOST"], port=int(os.environ["SQL_PORT"]),
                      user=os.environ["SQL_USER"], password=os.environ["SQL_PASS"],
                      database=os.environ["SQL_DB"], autocommit=True, connect_timeout=5)
con.cursor().execute(
    "INSERT INTO kg_triples (id, subject, predicate, object, created_at) "
    "VALUES (%s, %s, %s, %s, NOW())",
    (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]))
con.close()
' "$1" "$2" "$3" "$4"
}

if [ "$STORE_OK" = "1" ]; then
  EPH_DB="loom_bdclose_test_$$_$(date +%s)"
  if store_sql "" "CREATE DATABASE $EPH_DB" >/dev/null 2>&1 && \
     store_sql "$EPH_DB" \
       "CREATE TABLE drawers LIKE ${STORE_LIVE_DB}.drawers" \
       "CREATE TABLE kg_triples LIKE ${STORE_LIVE_DB}.kg_triples" >/dev/null 2>&1; then
    :
  else
    STORE_OK=0
    EPH_DB=""
  fi
fi

drop_eph_db() {
  [ -n "$EPH_DB" ] || return 0
  store_sql "" "DROP DATABASE $EPH_DB" >/dev/null 2>&1 || true
  EPH_DB=""
}

# A port nothing listens on. Used to exercise the UNREACHABLE path, which
# by design needs no server at all — so those tests always run.
DEAD_PORT=1

# ---------------------------------------------------------------------------
# Non-store fixtures
# ---------------------------------------------------------------------------

mk_proj_full() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.claude"
  echo '{"v":1,"mode":"full"}' > "$dir/.claude/workflow.json"
  echo "$dir"
}

# Make a project dir with a CONTROLLED directory basename (loom-lwg4).
# The repo-directory name is the second rung of the wing-candidate chain,
# so a fixture that exercises it needs to own its own basename — which
# `mktemp -d` does not give. `git init` makes the repo-root resolution
# deterministic rather than depending on whether /tmp happens to sit
# inside someone's checkout.
mk_proj_named() {
  local name="$1"
  local base; base=$(mktemp -d)
  local dir="$base/$name"
  mkdir -p "$dir/.claude"
  echo '{"v":1,"mode":"full"}' > "$dir/.claude/workflow.json"
  git -C "$dir" init -q >/dev/null 2>&1 || true
  echo "$dir"
}

# Fixture bd binary that emits canned `bd memories` output.
mk_bd_stub() {
  local memories_text="$1"
  local f; f=$(mktemp)
  cat > "$f" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "memories" ]; then
  printf '%s\n' "$memories_text"
  exit 0
fi
exit 0
EOF
  chmod +x "$f"
  echo "$f"
}

NULL_BD=$(mk_bd_stub "No memories matching")
PROJ=$(mk_proj_full)

trap 'drop_eph_db; rm -rf "$PROJ" "$NULL_BD"' EXIT

# ---------------------------------------------------------------------------
# Hook drivers
# ---------------------------------------------------------------------------

_payload() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# Run against the ephemeral store (reachable). Only meaningful when
# STORE_OK=1.
run_hook() {
  local proj="$1" cmd="$2"
  local bdb="${3:-$NULL_BD}"
  local force="${4:-}"
  local payload; payload=$(_payload "$cmd")
  if [ -n "$force" ]; then
    (cd "$proj" && BD_CLOSE_FORCE="$force" BD_BIN="$bdb" \
      LOOM_MEMORY_PYTHON="$MEMPY" LOOM_MEMORY_HOST="$STORE_HOST" \
      LOOM_MEMORY_PORT="$STORE_PORT" LOOM_MEMORY_USER="$STORE_USER" \
      LOOM_MEMORY_PASSWORD="$STORE_PASS" LOOM_MEMORY_DATABASE="$EPH_DB" \
      bash "$HOOK" <<<"$payload" 2>&1)
  else
    (cd "$proj" && BD_BIN="$bdb" \
      LOOM_MEMORY_PYTHON="$MEMPY" LOOM_MEMORY_HOST="$STORE_HOST" \
      LOOM_MEMORY_PORT="$STORE_PORT" LOOM_MEMORY_USER="$STORE_USER" \
      LOOM_MEMORY_PASSWORD="$STORE_PASS" LOOM_MEMORY_DATABASE="$EPH_DB" \
      bash "$HOOK" <<<"$payload" 2>&1)
  fi
}

# Run against a port nothing listens on — the UNREACHABLE path. Needs no
# server, so every caller runs unconditionally.
run_hook_dead() {
  local proj="$1" cmd="$2"
  local bdb="${3:-$NULL_BD}"
  local force="${4:-}"
  local payload; payload=$(_payload "$cmd")
  if [ -n "$force" ]; then
    (cd "$proj" && BD_CLOSE_FORCE="$force" BD_BIN="$bdb" \
      LOOM_MEMORY_PYTHON="${MEMPY:-python3}" LOOM_MEMORY_HOST="127.0.0.1" \
      LOOM_MEMORY_PORT="$DEAD_PORT" LOOM_MEMORY_USER="root" \
      LOOM_MEMORY_PASSWORD="" LOOM_MEMORY_DATABASE="doltdb" \
      bash "$HOOK" <<<"$payload" 2>&1)
  else
    (cd "$proj" && BD_BIN="$bdb" \
      LOOM_MEMORY_PYTHON="${MEMPY:-python3}" LOOM_MEMORY_HOST="127.0.0.1" \
      LOOM_MEMORY_PORT="$DEAD_PORT" LOOM_MEMORY_USER="root" \
      LOOM_MEMORY_PASSWORD="" LOOM_MEMORY_DATABASE="doltdb" \
      bash "$HOOK" <<<"$payload" 2>&1)
  fi
}

# ===========================================================================
# STORE-INDEPENDENT SECTIONS
# ===========================================================================
#
# The bead-ID parser, the bypass paths and the trigger guard all sit
# UPSTREAM of the store, so they are exercised through the unreachable
# path — no server needed, and therefore no skip. The unreachable report
# names each bead it could not verify, which is the observation channel
# these sections grep.

# ---------------------------------------------------------------------------
# 1. Bug A — regex parses ONLY `bd close <ids...>`, ignores --reason
# ---------------------------------------------------------------------------

echo "==> 1. Bead-ID regex scope (Bug A fix)"

out=$(run_hook_dead "$PROJ" 'bd close liza_base-dab --reason "Wave 1: re-dispatch and rule-based follow-up landed"')
if echo "$out" | grep -qE 'liza_base-dab' && \
   ! echo "$out" | grep -qE 're-dispatch' && \
   ! echo "$out" | grep -qE 'rule-based' && \
   ! echo "$out" | grep -qE 'follow-up'; then
  pass "regex extracts only liza_base-dab; --reason content ignored"
else
  fail "regex still leaks --reason words" "$out"
fi

if echo "$out" | grep -qE 'liza_base-dab' && ! echo "$out" | grep -qE '\bbase-dab\b'; then
  pass "underscore-prefix bead ID preserved (liza_base-dab, not base-dab)"
else
  fail "underscore prefix dropped" "$out"
fi

out=$(run_hook_dead "$PROJ" 'bd close loom-8vb loom-2xh --reason "...real-issue and side-quest..."')
if echo "$out" | grep -qE 'loom-8vb' && echo "$out" | grep -qE 'loom-2xh' && \
   ! echo "$out" | grep -qE '\breal-issue\b' && ! echo "$out" | grep -qE '\bside-quest\b'; then
  pass "multi-bead close: both args extracted, --reason content ignored"
else
  fail "multi-bead extraction broken" "$out"
fi

out=$(run_hook_dead "$PROJ" 'bd close loom-8vb.4 --reason "..."')
if echo "$out" | grep -qE 'loom-8vb\.4'; then
  pass "sub-suffix bead ID (loom-8vb.4) extracted intact"
else
  fail "sub-suffix bead ID lost" "$out"
fi

out=$(run_hook_dead "$PROJ" 'bd close liza_base-abcd --reason "..."')
if echo "$out" | grep -qE 'liza_base-abcd'; then
  pass "4-char hash suffix (liza_base-abcd) extracted (loom-gcb)"
else
  fail "4-char hash suffix dropped — regex still {3} not {3,}" "$out"
fi

out=$(run_hook_dead "$PROJ" 'bd close hundred-acre-woods-bng --reason "..."')
if echo "$out" | grep -qE 'hundred-acre-woods-bng'; then
  pass "multi-hyphen prefix (hundred-acre-woods-bng) extracted (loom-2t7)"
else
  fail "multi-hyphen prefix dropped — regex still rejects hyphens" "$out"
fi

# ---------------------------------------------------------------------------
# 2. Bypass paths preserved (regression)
# ---------------------------------------------------------------------------

echo "==> 2. Bypass paths"

out=$(run_hook_dead "$PROJ" 'bd close loom-8vb --force'); rc=$?
if [ "$rc" -eq 0 ]; then pass "--force bypasses verification"; else fail "--force did not bypass (exit=$rc)" "$out"; fi

out=$(run_hook_dead "$PROJ" 'bd close loom-8vb' "$NULL_BD" "1"); rc=$?
if [ "$rc" -eq 0 ]; then pass "BD_CLOSE_FORCE=1 in the ENVIRONMENT bypasses"; else fail "BD_CLOSE_FORCE=1 did not bypass (exit=$rc)" "$out"; fi

LIGHT=$(mktemp -d); mkdir -p "$LIGHT/.claude"; echo '{"v":1,"mode":"light"}' > "$LIGHT/.claude/workflow.json"
out=$(run_hook_dead "$LIGHT" 'bd close loom-8vb'); rc=$?
if [ "$rc" -eq 0 ]; then pass "mode=light bypasses verification"; else fail "mode=light did not bypass (exit=$rc)" "$out"; fi
rm -rf "$LIGHT"

out=$(echo '{"tool_name":"Edit","tool_input":{"command":"bd close loom-8vb"}}' | bash "$HOOK" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then pass "non-Bash tools ignored"; else fail "non-Bash tool blocked (exit=$rc)" "$out"; fi

# ---------------------------------------------------------------------------
# 9. Edge cases — bare `bd close`, --suggest-next flag
# ---------------------------------------------------------------------------

echo "==> 9. Edge cases"

# bd-close with no positional ID → distinct error, exit 2.
# IMPORTANT: keep backticks out of test-name strings. An earlier draft
# used `pass "bare \`bd close\` ..."` which bash command-substituted,
# inadvertently firing `bd close` against the live workspace and closing
# the most-recently-touched bead. Caught live during loom-8vb self-test.
out=$(run_hook_dead "$PROJ" 'bd close --reason "no positional"'); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Could not parse bead ID'; then
  pass 'bd-close with no positional id -> distinct parse-error block'
else
  fail 'bd-close no-positional did not give parse-error' "$out"
fi

out=$(run_hook_dead "$PROJ" 'bd close loom-8vb --suggest-next --reason "..."'); rc=$?
if echo "$out" | grep -q 'loom-8vb' && ! echo "$out" | grep -qE '\bsuggest-next\b'; then
  pass "trailing flags (--suggest-next) excluded from bead-ID list"
else
  fail "trailing flags leaked into bead-ID list" "$out"
fi

# ---------------------------------------------------------------------------
# 10. Trigger-guard command-shape (loom-oq0s, sibling of loom-9ng)
# ---------------------------------------------------------------------------
#
# Bug: the trigger guard matched the two-word close-phrase as a substring /
# line-anchored pattern of the whole command string, so a `bd create`
# whose --description (or -m / any quoted string arg) CONTAINED the phrase
# fired the hook. The hook then found no parsable bead ID and ABORTED the
# legitimate create with 'Could not parse bead ID'. HIT LIVE 2026-06-08
# filing loom-n1sk. Fix: anchor detection to the command actually INVOKING
# the close subcommand (argv: token `bd` adjacent to token `close`), not a
# textual match anywhere in the string — including inside a quoted value.

echo "==> 10. Trigger-guard command-shape (loom-oq0s)"

out=$(run_hook_dead "$PROJ" 'bd create --type bug --description "Hook fires when bd close phrase appears in a description" -t title'); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "bd create with close-phrase in --description (single line) → not intercepted"
else
  fail "bd create with close-phrase in --description wrongly intercepted (exit=$rc)" "$out"
fi

ML_DESC=$'Hook false-positives.\nExample of the buggy invocation:\nbd close foo aborts the legitimate command.'
out=$(run_hook_dead "$PROJ" "$(printf 'bd create --type bug --description %q -t title' "$ML_DESC")"); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "bd create with multi-line --description (line begins 'bd close') → not intercepted"
else
  fail "bd create with multi-line close-phrase description wrongly intercepted (exit=$rc)" "$out"
fi

out=$(run_hook_dead "$PROJ" 'git commit -m "note: bd close was blocked earlier"'); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "git commit -m with close-phrase in message → not intercepted"
else
  fail "git commit -m with close-phrase wrongly intercepted (exit=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 11. Unresolved shell-variable in bead-ID position (loom-8sd3)
# ---------------------------------------------------------------------------
#
# Bug: the shlex-based parser correctly isolates the positional token in
# bead-ID position, but when that token is an UNRESOLVED shell-variable
# reference ($name / ${name} shape) rather than a literal bead-ID-shaped
# string, the token fails the bead-ID regex, BEAD_IDS ends up empty, and
# the hook falls into the "Could not parse bead ID" hard-block (exit 2) --
# aborting a multi-line script whose `bd close` line may never even
# execute at runtime (e.g. an untaken `case` branch). Fix: detect the
# $var / ${var} shape in bead-ID position and FAIL OPEN (exit 0, silent
# no-op).

echo "==> 11. Unresolved shell-variable bead-ID position (loom-8sd3)"

CASE_CMD='case "$state" in
  MERGED) bd close "$id" --reason="Auto-merged, closing bead" ;;
  *) echo "not merged" ;;
esac'
out=$(run_hook_dead "$PROJ" "$CASE_CMD"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass 'case-branch bd close "$id" (MERGED branch untaken) -> fails open silently'
else
  fail 'case-branch bd close "$id" wrongly hard-blocked' "$out ... (exit=$rc)"
fi

out=$(run_hook_dead "$PROJ" 'id=xyz-123; bd close "$id"'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass 'one-liner id=xyz-123; bd close "$id" -> fails open silently'
else
  fail 'one-liner bd close "$id" wrongly hard-blocked' "$out ... (exit=$rc)"
fi

out=$(run_hook_dead "$PROJ" 'id=xyz-123; bd close "${id}"'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass 'brace-expansion id=xyz-123; bd close "${id}" -> fails open silently'
else
  fail 'brace-expansion bd close "${id}" wrongly hard-blocked' "$out ... (exit=$rc)"
fi

# ---------------------------------------------------------------------------
# 13. UNREACHABLE store is UNKNOWN, not absent (loom-b76s)
# ---------------------------------------------------------------------------
#
# THE DEFECT. open_ro() returned None for a missing store and every
# matcher then returned False, so "the gate cannot see the store" was
# indistinguishable from "you did not capture". The block message said
# "No capture evidence found", which reads as a content problem, so the
# author rewrites the reason — four times, in the live case — and that
# never helps.
#
# THE CONTRACT. An unreachable store makes checks 1-3 UNKNOWN. The hook
# reports that distinctly, names the DSN it could not reach, and does NOT
# block: it cannot prove capture is absent when it cannot read the store.
# Same fail-open-when-you-cannot-prove-a-violation posture the other loom
# hooks take. Needs no server, so it always runs.

echo "==> 13. Unreachable store → UNKNOWN, not absent (loom-b76s)"

out=$(run_hook_dead "$PROJ" 'bd close loom-8vb'); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "unreachable store does NOT block (exit 0)"
else
  fail "unreachable store blocked the close (exit=$rc)" "$out"
fi

if echo "$out" | grep -qF 'UNVERIFIABLE'; then
  pass "unreachable store reports UNVERIFIABLE"
else
  fail "unreachable store did not report UNVERIFIABLE" "$out"
fi

if ! echo "$out" | grep -qF 'No capture evidence found'; then
  pass "unreachable diagnostic is DISTINCT from the no-evidence block message"
else
  fail "unreachable store reused the 'No capture evidence found' wording" "$out"
fi

if echo "$out" | grep -qE "127\.0\.0\.1:$DEAD_PORT"; then
  pass "unreachable diagnostic names the DSN that failed"
else
  fail "unreachable diagnostic does not name the failed DSN" "$out"
fi

# Anchored on the matrix ROW, not on a bare question mark — the
# explanatory prose below the matrix also contains one, so a loose grep
# would pass even if every row had rendered as ✗.
if echo "$out" | grep -qE '^  \? Drawer in ' \
   && echo "$out" | grep -qE '^  \? KG triple referencing ' \
   && echo "$out" | grep -qE '^  \? Diary entry mentioning '; then
  pass "unreachable store marks store-backed checks with a distinct marker (not ✗)"
else
  fail "unreachable store used ✗ for checks it could not evaluate" "$out"
fi

# The two matchers that need no store must still report a real verdict.
if echo "$out" | grep -qE '^  ✗ bd memory tagged with ' \
   && echo "$out" | grep -qE '^  ✗ Substantive close --reason'; then
  pass "store-independent checks 4 and 5 still report ✓/✗, never ?"
else
  fail "checks 4 and 5 went UNKNOWN on an unreachable store" "$out"
fi

if echo "$out" | grep -qF 'loom-8vb'; then
  pass "unreachable diagnostic names the bead"
else
  fail "unreachable diagnostic does not name the bead" "$out"
fi

# A reason that DOES satisfy check 5 must pass quietly through the
# unreachable path — check 5 is an independent signal that needs no store.
UNREACH_OK_REASON="Landed the Dolt-backed matcher kernel and reworked the fixture onto an ephemeral database, so the gate now reads the store the MCP writes. Lineage in commit a1b2c3d plus drawer drawer_loom_decisions_2fbf2d5f4c0f5e50ab84e628. Suite green."
out=$(run_hook_dead "$PROJ" "bd close loom-8vb --reason \"$UNREACH_OK_REASON\""); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -qF 'UNVERIFIABLE'; then
  pass "substantive --reason still passes independently of the store"
else
  fail "check 5 did not stand alone under an unreachable store (exit=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# 14. loom-84nx — the advertised bypass must be reachable mid-turn
# ---------------------------------------------------------------------------
#
# INVARIANT: the escape route the block message names is one an agent can
# actually take mid-turn.
#
# The hook is PreToolUse. It fires BEFORE any shell runs, so a
# command-prefix assignment (`BD_CLOSE_FORCE=1 bd close <id>`) is still
# just text at hook time and never reaches loom_env_enabled. The --force
# flag DOES reach the hook, because it is in the command text the hook
# reads. This static check needs no store.

echo "==> 14. Advertised bypass is reachable mid-turn (loom-84nx)"

if ! grep -qF 'BD_CLOSE_FORCE=1 bd close' "$HOOK"; then
  pass "hook no longer advertises the unreachable command-prefix form"
else
  fail "hook still advertises 'BD_CLOSE_FORCE=1 bd close' as a bypass" \
    "$(grep -nF 'BD_CLOSE_FORCE=1 bd close' "$HOOK")"
fi

# ===========================================================================
# STORE-DEPENDENT SECTIONS
# ===========================================================================

store_sections() {
  local out rc

  # -------------------------------------------------------------------------
  # 3. Full mode + zero artifacts → blocks
  # -------------------------------------------------------------------------
  echo "==> 3. Full mode + zero capture evidence → blocks with explicit message"

  store_reset
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 2 ]; then pass "blocks (exit 2) when no evidence"; else fail "expected exit 2, got $rc" "$out"; fi

  for needle in \
    "No capture evidence found for" \
    "Drawer in loom" \
    "KG triple referencing loom-8vb" \
    "Diary entry" \
    "bd memory" \
    "Substantive close --reason" \
    "/wrap-up"
  do
    if echo "$out" | grep -qF "$needle"; then
      pass "block message contains: $needle"
    else
      fail "block message missing: $needle" "$out"
    fi
  done

  # loom-84nx: the block message must name a route an agent can take
  # mid-turn. --force is in the command text, so the hook reads it.
  if echo "$out" | grep -qF -- "--force"; then
    pass "block message advertises the --force flag (reachable mid-turn)"
  else
    fail "block message does not advertise the --force flag" "$out"
  fi

  if ! echo "$out" | grep -qF 'BD_CLOSE_FORCE=1 bd close'; then
    pass "block message does NOT advertise the unreachable command-prefix form"
  else
    fail "block message still advertises 'BD_CLOSE_FORCE=1 bd close'" "$out"
  fi

  # And the prefix form really does NOT bypass — pin the behavior the
  # message used to mis-describe.
  out=$(run_hook "$PROJ" 'BD_CLOSE_FORCE=1 bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "command-prefix BD_CLOSE_FORCE=1 does NOT bypass (loom-84nx)"
  else
    fail "command-prefix BD_CLOSE_FORCE=1 unexpectedly bypassed (exit=$rc)" "$out"
  fi

  # The --force flag DOES reach the hook.
  out=$(run_hook "$PROJ" 'bd close loom-8vb --force'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "--force flag reaches the hook and bypasses (loom-84nx)"
  else
    fail "--force flag did not bypass against a reachable store (exit=$rc)" "$out"
  fi

  # -------------------------------------------------------------------------
  # 4. Matcher 1 — drawer in any room of the project's wing → allows
  # -------------------------------------------------------------------------
  echo "==> 4. Drawer matcher (any room of wing)"

  store_reset
  store_add_drawer "drawer_loom_decisions_1111111111111111aaaa1111" loom decisions \
    "loom-8vb verification" "loom-8vb shipped real artifact verification on 2026-05-06."
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 0 ]; then pass "drawer in decisions room → allows"; else fail "drawer-room match did not allow (exit=$rc)" "$out"; fi

  store_reset
  store_add_drawer "drawer_loom_findings_2222222222222222bbbb2222" loom findings \
    "regex finding" "Diagnostic finding: loom-8vb regex confused parser."
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 0 ]; then pass "drawer in non-decisions room (findings) → allows"; else fail "non-decisions room did not allow (exit=$rc)" "$out"; fi

  store_reset
  store_add_drawer "drawer_liza_base_decisions_3333333333333333cccc3333" liza_base decisions \
    "wrong wing" "loom-8vb mentioned but in wrong wing"
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 2 ]; then pass "drawer in OTHER wing → blocks (wing scoping works)"; else fail "wrong-wing drawer leaked (exit=$rc)" "$out"; fi

  # THE loom-b76s REGRESSION. A drawer filed through the MemPalace MCP
  # for bead X satisfies check 1 for X — including from a HYPHENATED wing,
  # which is the naming loom-audit-resolve produces by default because
  # repository directories are conventionally hyphenated (loom-efrx).
  store_reset
  store_add_drawer "drawer_reddit-archiver_decisions_08b2f2d538e5a1cf0da15836" \
    reddit-archiver decisions "Spaces bucket created" \
    "Closes reddit-archiver-5co. Spaces bucket created, public-read objects."
  out=$(run_hook "$PROJ" 'bd close reddit-archiver-5co'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "MCP-shaped drawer in a hyphenated wing satisfies check 1 (loom-b76s)"
  else
    fail "MCP-shaped drawer did not satisfy check 1 (exit=$rc)" "$out"
  fi

  # Chunk rows sit alongside the parent. Matching either proves capture;
  # the matcher is a boolean, so a parent plus four chunks is still one
  # passing check, never five.
  store_reset
  store_add_drawer "drawer_reddit-archiver_decisions_08b2f2d538e5a1cf0da15836_chunk_000000" \
    reddit-archiver decisions "Spaces bucket created" \
    "Closes reddit-archiver-5co. Spaces bucket created, public-read objects."
  out=$(run_hook "$PROJ" 'bd close reddit-archiver-5co'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "a chunk row alone satisfies check 1 (loom-b76s)"
  else
    fail "chunk row did not satisfy check 1 (exit=$rc)" "$out"
  fi

  # Short-form drawer body (loom-b20 sub-issue 2).
  store_reset
  store_add_drawer "drawer_liza_base_decisions_4444444444444444dddd4444" liza_base decisions \
    "b33-architecture" "B33 ARCHITECTURE LOCKED. The b33 design names three tracks."
  out=$(run_hook "$PROJ" 'bd close liza_base-b33'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "short-form drawer body (b33 within liza_base wing) → allows (loom-b20)"
  else
    fail "short-form drawer match did not allow (exit=$rc)" "$out"
  fi

  # Bug-class: body uses ONLY the uppercase short form. The live schema's
  # collation is utf8mb4_0900_bin — CASE SENSITIVE — so a bare LIKE would
  # miss this. Verified directly against the server before the fix.
  store_reset
  store_add_drawer "drawer_liza_base_decisions_5555555555555555eeee5555" liza_base decisions \
    "B33-arch" "B33 ARCHITECTURE LOCKED. Three tracks committed."
  out=$(run_hook "$PROJ" 'bd close liza_base-b33'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "uppercase-only short-form drawer (B33) → allows (loom-b20 verbatim)"
  else
    fail "uppercase short-form drawer did not allow (exit=$rc)" "$out"
  fi

  store_reset
  store_add_drawer "drawer_loom_decisions_6666666666666666ffff6666" loom decisions \
    "b33-note" "Note: b33 mentioned but this drawer is in the loom wing."
  out=$(run_hook "$PROJ" 'bd close liza_base-b33'); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "short-form match is wing-scoped (b33 in loom wing rejected for liza_base-b33) (loom-b20)"
  else
    fail "short-form leaked across wings (exit=$rc)" "$out"
  fi

  # Short-form must be ≥3 chars. The bead-ID regex requires {3,}, so
  # `liza_base-ab` does not even parse as a bead ID.
  store_reset
  store_add_drawer "drawer_liza_base_decisions_7777777777777777aaaa7777" liza_base decisions \
    "ab-trivial" "Unrelated drawer mentioning 'ab' twice: ab and ab."
  out=$(run_hook "$PROJ" 'bd close liza_base-ab'); rc=$?
  if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Could not parse bead ID'; then
    pass "2-char suffix not accepted as bead ID (regex {3,} guard) (loom-b20)"
  else
    fail "2-char suffix passed bead-ID regex (suffix length guard regressed)" "$out"
  fi

  # -------------------------------------------------------------------------
  # 5. Matcher 2 — KG triple referencing the bead → allows
  # -------------------------------------------------------------------------
  echo "==> 5. KG triple matcher"

  store_reset
  store_add_triple "triple_1111111111111111" "loom-8vb" "ships" "real-verification"
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 0 ]; then pass "KG triple subject=loom-8vb → allows"; else fail "KG subject match did not allow (exit=$rc)" "$out"; fi

  store_reset
  store_add_triple "triple_2222222222222222" "real-verification" "implements" "loom-8vb"
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 0 ]; then pass "KG triple object=loom-8vb → allows"; else fail "KG object match did not allow (exit=$rc)" "$out"; fi

  # The live shape from the loom-efrx symptom history: triple_fd3b29be…
  # has subject reddit-archiver-5co and the hook still crossed check 2,
  # because it was reading ChromaDB's sibling knowledge_graph.sqlite3.
  store_reset
  store_add_triple "triple_fd3b29beb0358255" "reddit-archiver-5co" "provisioned" \
    "Spaces bucket reddit-folklore-archive in nyc3"
  out=$(run_hook "$PROJ" 'bd close reddit-archiver-5co'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "MCP-filed KG triple satisfies check 2 (loom-b76s)"
  else
    fail "MCP-filed KG triple did not satisfy check 2 (exit=$rc)" "$out"
  fi

  # -------------------------------------------------------------------------
  # 6. Matcher 3 — diary entry referencing the bead → allows
  # -------------------------------------------------------------------------
  echo "==> 6. Diary matcher"

  store_reset
  store_add_drawer "drawer_wing_claude-opus_diary_8888888888888888bbbb8888" \
    wing_claude-opus diary "session" "SESSION:2026-05-06|loom-8vb shipped|stage:wrap-up"
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 0 ]; then pass "diary entry mentioning bead → allows"; else fail "diary match did not allow (exit=$rc)" "$out"; fi

  store_reset
  store_add_drawer "drawer_wing_claude-opus_diary_9999999999999999cccc9999" \
    wing_claude-opus diary "b33-session" \
    "SESSION:2026-05-08|liza_base: b33 architecture locked|stage:wrap-up"
  out=$(run_hook "$PROJ" 'bd close liza_base-b33'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "short-form diary body with wing-name nearby → allows (loom-b20)"
  else
    fail "short-form diary did not allow (exit=$rc)" "$out"
  fi

  store_reset
  store_add_drawer "drawer_wing_claude-opus_diary_aaaaaaaaaaaaaaaadddda111" \
    wing_claude-opus diary "b33-only" "SESSION:2026-05-08|b33 mentioned in passing|stage:debug"
  out=$(run_hook "$PROJ" 'bd close liza_base-b33'); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "short-form diary WITHOUT wing-name → blocks (loom-b20 wing guard)"
  else
    fail "short-form diary leaked without wing-name (exit=$rc)" "$out"
  fi

  # A drawer in the diary room must NOT satisfy the DRAWER matcher — that
  # matcher deliberately excludes the diary room so the two checks stay
  # independent signals.
  store_reset
  store_add_drawer "drawer_loom_diary_bbbbbbbbbbbbbbbbeeee2222" loom diary \
    "loom-8vb note" "loom-8vb touched today"
  out=$(run_hook "$PROJ" 'bd close loom-8vb'); rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qE '✗✗✓|✗✗✓✗✗'; then
    pass "diary-room drawer satisfies check 3 only, not check 1"
  elif [ "$rc" -eq 0 ]; then
    pass "diary-room drawer allows (matrix: $(echo "$out" | grep -o '(.....)' | head -1))"
  else
    fail "diary-room drawer did not allow (exit=$rc)" "$out"
  fi

  # -------------------------------------------------------------------------
  # 7. Matcher 4 — bd memory referencing the bead → allows
  # -------------------------------------------------------------------------
  echo "==> 7. bd memory matcher"

  store_reset
  BD_WITH_MEM=$(mk_bd_stub "loom-8vb-shipped-real-verification — captured 2026-05-06")
  out=$(run_hook "$PROJ" 'bd close loom-8vb' "$BD_WITH_MEM"); rc=$?
  if [ "$rc" -eq 0 ]; then pass "bd memory mentioning bead → allows"; else fail "bd memory match did not allow (exit=$rc)" "$out"; fi
  rm -f "$BD_WITH_MEM"

  # -------------------------------------------------------------------------
  # 8. Matcher 5 — substantive --reason → allows
  # -------------------------------------------------------------------------
  echo "==> 8. Substantive --reason matcher"

  store_reset
  LONG_REASON_OK="Wave 1 voice pass: filter haiku→sonnet, drives saturation 1.0→0.8 across the bank pool. Lineage in commit abc1234 plus sibling drawer drawer_liza_base_decisions_aabbccdd11223344. Audit clean, 1101/1101 pass."
  out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$LONG_REASON_OK\""); rc=$?
  if [ "$rc" -eq 0 ]; then pass "≥200 char --reason with commit SHA + drawer ID → allows"; else fail "substantive --reason did not allow (exit=$rc)" "$out"; fi

  LONG_REASON_NOREF=$(printf 'placeholder %.0s' {1..50})
  out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$LONG_REASON_NOREF\""); rc=$?
  if [ "$rc" -eq 2 ]; then pass "long --reason without commit/drawer ID → blocks"; else fail "no-ref long --reason allowed (exit=$rc)" "$out"; fi

  SHORT_REASON_REF="Fixed in abc1234"
  out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$SHORT_REASON_REF\""); rc=$?
  if [ "$rc" -eq 2 ]; then pass "short --reason with SHA but <200 chars → blocks"; else fail "short --reason allowed (exit=$rc)" "$out"; fi

  out=$(run_hook "$PROJ" "bd close loom-8vb --reason=\"$LONG_REASON_OK\""); rc=$?
  if [ "$rc" -eq 0 ]; then pass "--reason=\"…\" form (= sign) accepted"; else fail "--reason=\"…\" form not parsed (exit=$rc)" "$out"; fi

  # loom-efrx: DRAWER_RE must accept a hyphenated wing segment. Measured
  # 2026-08-20 against the shipped regex: reddit-archiver False,
  # golden-path False, loom True, tla_puzzles True. This reason carries a
  # real hyphenated drawer id and NO SHA, so it passes only if DRAWER_RE
  # was widened.
  HYPHEN_DRAWER_REASON="Bucket provisioning finished and the public-read refinement is captured end to end. The decision, the alternatives weighed, and the verification are all in drawer drawer_reddit-archiver_decisions_08b2f2d538e5a1cf0da15836 which names this bead in its opening line."
  out=$(run_hook "$PROJ" "bd close reddit-archiver-5co --reason \"$HYPHEN_DRAWER_REASON\""); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "DRAWER_RE accepts a hyphenated wing segment (loom-efrx)"
  else
    fail "DRAWER_RE still rejects hyphenated wing names (exit=$rc)" "$out"
  fi

  # Regression: a non-hyphenated drawer id must keep matching.
  PLAIN_DRAWER_REASON="Landed the matcher kernel rework and reworked the fixture onto an ephemeral database, so the gate reads the store the MCP actually writes. The decision, alternatives and verification are in drawer drawer_loom_decisions_2fbf2d5f4c0f5e50ab84e628 which names this bead."
  out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$PLAIN_DRAWER_REASON\""); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "DRAWER_RE still accepts a plain wing segment (regression)"
  else
    fail "DRAWER_RE regressed on plain wing names (exit=$rc)" "$out"
  fi

  # loom-efrx: SHA_RE must not accept a decimal resource ID. The live
  # false pass was reddit-archiver-0el closing on 593934797, a
  # DigitalOcean droplet ID that is nine characters of [0-9a-f].
  DROPLET_REASON="Droplet provisioning finished and the archiver now runs on its own host. The droplet is 593934797 in nyc3, sized s-1vcpu-1gb, and the systemd unit is enabled. Nothing else in this reason points at a commit or a drawer, so the gate should not treat the resource ID as capture evidence."
  out=$(run_hook "$PROJ" "bd close reddit-archiver-0el --reason \"$DROPLET_REASON\""); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "SHA_RE rejects an all-digit resource ID (loom-efrx)"
  else
    fail "all-digit resource ID still proves capture (exit=$rc)" "$out"
  fi

  # Regression: a real short SHA must keep passing.
  REAL_SHA_REASON="Reworked the matcher kernel onto the Dolt store the MemPalace MCP writes, so the four artifact checks can pass again for anything filed through the MCP. The change landed in commit a1b2c3d and the fixture now builds an ephemeral database per run rather than a retired ChromaDB sqlite."
  out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$REAL_SHA_REASON\""); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "SHA_RE still accepts a real short SHA (regression)"
  else
    fail "SHA_RE rejected a legitimate short SHA (exit=$rc)" "$out"
  fi

  # -------------------------------------------------------------------------
  # 12. Wing derivation for HYPHENATED project prefixes (loom-lwg4)
  # -------------------------------------------------------------------------
  #
  # INVARIANT: for a bead id whose project prefix contains hyphens
  # (`e2e-api-tests-e70`) the derived MemPalace wing is the FULL prefix
  # (`e2e-api-tests`), not the first hyphen-delimited token; underscore
  # prefixes (`liza_base-6r49` -> `liza_base`) keep working.
  echo "==> 12. Hyphenated-prefix wing derivation (loom-lwg4)"

  store_reset
  store_add_drawer "drawer_e2e-api-tests_decisions_cccccccccccccccc1111e222" \
    e2e-api-tests decisions "smoke suite" "e2e-api-tests-e70 landed the first API smoke suite."
  out=$(run_hook "$PROJ" 'bd close e2e-api-tests-e70'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "hyphenated prefix: drawer in e2e-api-tests wing → allows"
  else
    fail "hyphenated prefix: full-prefix wing not derived (exit=$rc)" "$out"
  fi

  store_reset
  out=$(run_hook "$PROJ" 'bd close e2e-api-tests-e70'); rc=$?
  if [ "$rc" -eq 2 ] && echo "$out" | grep -qF 'Drawer in e2e-api-tests/*' \
     && ! echo "$out" | grep -qF 'Drawer in e2e/*'; then
    pass "block message names the FULL wing (e2e-api-tests, not e2e)"
  else
    fail "block message names a truncated wing" "$out"
  fi

  store_reset
  store_add_drawer "drawer_liza_base_decisions_dddddddddddddddd2222f333" liza_base decisions \
    "complaint notebook" "liza_base-6r49 locked the complaint-notebook shape."
  out=$(run_hook "$PROJ" 'bd close liza_base-6r49'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "underscore prefix (liza_base-6r49 → liza_base) still allows"
  else
    fail "underscore prefix regressed (exit=$rc)" "$out"
  fi

  store_reset
  store_add_drawer "drawer_golden-path_decisions_eeeeeeeeeeeeeeee3333a444" golden-path decisions \
    "abc1-note" "ABC1 shipped the Hugo pipeline rewrite."
  out=$(run_hook "$PROJ" 'bd close golden-path-abc1'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "hyphenated prefix: short-form drawer (abc1 in golden-path) → allows"
  else
    fail "hyphenated prefix: short suffix mis-split (exit=$rc)" "$out"
  fi

  store_reset
  store_add_drawer "drawer_wing_claude-opus_diary_ffffffffffffffff4444b555" \
    wing_claude-opus diary "abc1-session" \
    "SESSION:2026-07-25|golden-path: abc1 docs rebuild landed|stage:wrap-up"
  out=$(run_hook "$PROJ" 'bd close golden-path-abc1'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "hyphenated prefix: short-form diary naming golden-path → allows"
  else
    fail "hyphenated prefix: diary wing-scope guard mis-split (exit=$rc)" "$out"
  fi

  store_reset
  store_add_drawer "drawer_some-other-project_decisions_11111111111111115555c666" \
    some-other-project decisions "abc1-note" \
    "Note: abc1 mentioned but this drawer belongs to another project."
  out=$(run_hook "$PROJ" 'bd close golden-path-abc1'); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "hyphenated prefix: short-form in a foreign wing still blocks"
  else
    fail "wing scoping leaked after widening (exit=$rc)" "$out"
  fi

  # prefix != wing. dreamer-engine's bd prefix is `dream` while its
  # MemPalace wing is `dreamer-engine`, so no literal split of the bead ID
  # yields the wing. Second rung of the candidate chain: the repo dir name.
  DREAM_PROJ=$(mk_proj_named dreamer-engine)
  store_reset
  store_add_drawer "drawer_dreamer-engine_decisions_222222222222222266667777" \
    dreamer-engine decisions "narrative loop" "dream-xyz1 locked the narrative-loop contract."
  out=$(run_hook "$DREAM_PROJ" 'bd close dream-xyz1'); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "prefix != wing: repo-dir fallback (dream-* → dreamer-engine) → allows"
  else
    fail "prefix != wing: repo-dir fallback missing (exit=$rc)" "$out"
  fi

  store_reset
  store_add_drawer "drawer_some-other-project_decisions_3333333333333333777788" \
    some-other-project decisions "unrelated" \
    "dream-xyz1 mentioned in an unrelated project's wing."
  out=$(run_hook "$DREAM_PROJ" 'bd close dream-xyz1'); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "repo-dir fallback stays wing-scoped (foreign wing still blocks)"
  else
    fail "repo-dir fallback became a blanket pass (exit=$rc)" "$out"
  fi
  rm -rf "$(dirname "$DREAM_PROJ")"

  store_reset
}

if [ "$STORE_OK" = "1" ]; then
  echo "==> store fixture: ephemeral database ${EPH_DB} on ${STORE_USER}@${STORE_HOST}:${STORE_PORT}"
  store_sections
else
  echo
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!! SKIPPING every store-dependent section."
  echo "!!! No Dolt memory server reachable at ${STORE_USER}@${STORE_HOST}:${STORE_PORT}/${STORE_LIVE_DB}"
  if [ -z "$MEMPY" ]; then
    echo "!!! (no interpreter carrying pymysql; set LOOM_MEMORY_PYTHON)"
  fi
  echo "!!! Start it with memory-server/scripts/start-server.sh, or point the"
  echo "!!! suite at one with LOOM_MEMORY_HOST / LOOM_MEMORY_PORT."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo
  skip "sections 3-8 and 12 (matcher kernel against a real store)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if [ "$skipped" -gt 0 ]; then
  echo "Tests: $passed passed, $failed failed, $skipped SKIPPED (memory server unreachable)"
  if [ "${LOOM_TEST_REQUIRE_MEMORY_SERVER:-}" = "1" ]; then
    echo "LOOM_TEST_REQUIRE_MEMORY_SERVER=1 — treating skips as failures."
    exit 1
  fi
else
  echo "Tests: $passed passed, $failed failed"
fi
[ "$failed" -eq 0 ]
