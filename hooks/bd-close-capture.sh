#!/usr/bin/env bash
# PreToolUse hook for `bd close`.
#
# Per locked workflow-infrastructure decision (2026-05-02 #2): block
# until drawer + KG + diary are captured. Bypass with the --force flag,
# which is in the command text this hook reads; BD_CLOSE_FORCE=1 works
# only when it is already in the hook's own environment (loom-84nx).
#
# Real artifact verification (loom-8vb, design drawer
# drawer_loom_decisions_2fbf2d5f4c0f5e50ab84e628). For each bead being
# closed, the hook checks five matchers; ANY ONE passing allows the
# close. ZERO passing blocks with an explicit ✓/✗ matrix.
#
#   1. Drawer in any room of the bead's wing mentioning the bead ID
#   2. KG triple where subject or object references the bead ID
#   3. Diary entry mentioning the bead ID
#   4. bd memory containing the bead ID
#   5. Substantive close --reason (≥200 chars + commit SHA or drawer ID)
#
# Mode-aware (per workflow-infra v1.5):
#   full   → block unless ANY matcher passes; on bypass/allow, write state stage=close.
#   light  → never blocks (informational); writes state on close.
#   off    → silent; writes state on close.
#
# Wing derivation (loom-lwg4). The wing a bead's drawers live in is
# derived from the bead ID via `bd_id_prefix_of` (lib/bd-id-extract.sh,
# loom-6mf7) — the LITERAL full prefix, split at the LAST hyphen before
# the 3+-alnum suffix. The earlier `bead.split("-", 1)[0]` split at the
# FIRST hyphen, which truncated every hyphenated project prefix
# (`e2e-api-tests-e70` -> `e2e`, a wing that does not exist) and silently
# blocked legitimate closes in those projects. Because bd prefix and wing
# name are not the same thing in general (dreamer-engine's prefix is
# `dream`), the repo directory name is tried as a second CANDIDATE wing.
# Both are candidates, not overrides: a drawer in ANY candidate wing
# satisfies the matcher, and a drawer in no candidate wing still blocks.
#
# Memory store (loom-b76s). Checks 1 to 3 read the Dolt sql-server the
# MemPalace MCP writes to. They used to read the ChromaDB palace under
# ~/.mempalace, which the MCP stopped writing at the Dolt migration — so
# every drawer, triple and diary entry filed through the MCP was
# invisible to the gate, and check 5 was the only path that could pass.
# That is what made the gate look intermittent: it passed exactly when a
# close reason happened to contain a hex-shaped token.
#
# Each connection field resolves in three rungs:
#   1. LOOM_MEMORY_{HOST,PORT,DATABASE,USER,PASSWORD} in this hook's own
#      environment.
#   2. The `env` block of whichever configured MCP server declares
#      LOOM_MEMORY_* keys. This hook is PreToolUse, so it does NOT
#      inherit that block; reading it is the only way the hook can find
#      the store on a machine that pins the port there and nowhere else.
#   3. mcp_server/db.py's connection_config() defaults.
#
# An UNREACHABLE store is UNKNOWN, never absent. Checks 1 to 3 report
# `?`, the DSN that failed is named, and the close is ALLOWED — the gate
# cannot prove capture is absent when it cannot read the store, which is
# the same fail-open-when-you-cannot-prove-a-violation posture the other
# loom hooks take. Check 5 stays an independent signal either way.
#
# Test injection points:
#   LOOM_MEMORY_*      — the five connection fields above
#   LOOM_MEMORY_PYTHON — interpreter carrying pymysql (default: the
#                        memory server's venv beside this hook's repo)
#   BD_BIN             — bd binary (default: bd)
#
# Block strategy: exit 2 with stderr message. Claude Code surfaces
# stderr and blocks the tool call.

set -uo pipefail

INPUT=$(cat)
BD_BIN="${BD_BIN:-bd}"

# --- Tool dispatch ---------------------------------------------------------

# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR > installed copy > repo-
# relative fallback (readlink -f so it resolves through an installed
# .git/hooks symlink, loom-fxad). TESTLIB must win, or a worktree's tests
# silently load MAIN's lib/ — ~/.claude/lib/* are symlinks into the main
# checkout, the bash flavor of the loom-rsk Python-import shadow.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi
TOOL=$(json_get_py '.tool_name' 'd.get("tool_name","")' "$INPUT")
CMD=$(json_get_py '.tool_input.command' 'd.get("tool_input",{}).get("command","")' "$INPUT")

[ "$TOOL" = "Bash" ] || exit 0

# --- Trigger gate + bead-ID extraction (command-shape, not substring) -----
#
# Detection anchors to the command actually INVOKING the close subcommand:
# argv parsed with shlex, looking for the adjacent token pair `bd` `close`.
# A textual / line-anchored regex over the raw command string (the prior
# approach) false-positived when the two-word close-phrase appeared INSIDE a
# quoted value of a DIFFERENT command — e.g. a multi-line
# `bd create --description "...\nbd close foo..."` — firing the hook, finding
# no parsable bead ID, and aborting the legitimate command with
# 'Could not parse bead ID' (loom-oq0s, sibling of loom-9ng; hit live
# 2026-06-08 filing loom-n1sk). shlex keeps a quoted --description / -m value
# as a SINGLE token, so the phrase inside it never yields adjacent
# `bd`/`close` argv tokens and the gate stays closed.
#
# The parser prints one of:
#   __NO_BD_CLOSE__   no `bd`→`close` invocation in argv → hook is a no-op
#   "<id> <id> ..."   close invocation present; space-joined positional IDs
#                     (possibly empty → bare-`bd close` parse-error path below)
#
# Positional IDs are only those between `close` and the first `--flag`.
# shlex grouping means the body of --reason "..." can never leak into the
# bead-ID list. Allows underscore in prefixes (liza_base-dab) and dotted
# sub-suffixes (loom-8vb.4). On unbalanced quotes (shlex ValueError) we
# cannot prove a close invocation, so fail OPEN (treat as no-op) rather than
# abort a command we can't parse.

PARSE_OUT=$(printf '%s' "$CMD" | python3 -c '
import re, shlex, sys
cmd = sys.stdin.read()
try:
    toks = shlex.split(cmd, posix=True)
except ValueError:
    print("__NO_BD_CLOSE__"); sys.exit(0)
ids = []
unresolved_var = False
i = 0
n = len(toks)
found = False
while i < n:
    if toks[i] == "bd" and i + 1 < n and toks[i+1] == "close":
        found = True
        j = i + 2
        while j < n:
            t = toks[j]
            if t.startswith("-"):
                break
            if re.fullmatch(r"[a-z][a-z0-9_-]*-[0-9a-z]{3,}(\.[0-9a-z]+)*", t):
                ids.append(t)
            elif re.match(r"^\$", t):
                unresolved_var = True
            j += 1
        break
    i += 1
if not found:
    print("__NO_BD_CLOSE__")
elif ids:
    print(" ".join(ids))
elif unresolved_var:
    print("__UNRESOLVED_VAR__")
else:
    print("")
')

# Gate: no real `bd close` invocation → hook is a silent no-op.
[ "$PARSE_OUT" = "__NO_BD_CLOSE__" ] && exit 0

# Gate: unresolved shell variable in bead-ID position → fail open silently.
# Cannot prove a close invocation from an unexecuted command, so be a no-op.
# Mirrors the existing __NO_BD_CLOSE__ fail-open principle (loom-8sd3).
[ "$PARSE_OUT" = "__UNRESOLVED_VAR__" ] && exit 0

BEAD_IDS="$PARSE_OUT"

# --- Mode resolution -------------------------------------------------------

# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR wins so a worktree's tests
# load the WORKTREE's lib, not MAIN's. No repo-relative rung — that
# preserves this hook's original hard-fail-if-absent posture exactly.
# shellcheck source=../lib/workflow-state.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/workflow-state.sh"
else
  . "$HOME/.claude/lib/workflow-state.sh"
fi
MODE=$(workflow_resolve_mode "$PWD")

# --- Bypass paths ---------------------------------------------------------

BYPASS=0
if loom_env_enabled BD_CLOSE_FORCE; then
  BYPASS=1
elif echo "$CMD" | grep -qE '(^|[[:space:]])--force(\b|=|$)'; then
  BYPASS=1
elif [ "$MODE" != "full" ]; then
  BYPASS=1
fi

if [ "$BYPASS" = "1" ]; then
  workflow_state_set --start-dir="$PWD" activity=idle bead= stage=close \
    >/dev/null 2>&1 || true
  exit 0
fi

# --- Bare `bd close` (no parsable IDs) ------------------------------------

if [ -z "${BEAD_IDS// /}" ]; then
  cat >&2 <<'EOF'
[bd-close-capture hook] Could not parse bead ID from `bd close` command.

Re-run with explicit bead ID(s):
  bd close <id> [<id> ...] [--reason "..."]
EOF
  exit 2
fi

# --- Wing candidates per bead (loom-lwg4) ---------------------------------

# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR > installed copy > repo-relative.
# `bd-id-extract.sh` is dual-mode (loom-6mf7): sourcing defines
# bd_id_prefix_of / bd_id_detect_prefix / bd_id_pattern / bd_id_scan and
# runs nothing.
# shellcheck source=../lib/bd-id-extract.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/bd-id-extract.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/bd-id-extract.sh"
elif [ -f "$HOME/.claude/lib/bd-id-extract.sh" ]; then
  . "$HOME/.claude/lib/bd-id-extract.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/bd-id-extract.sh"
fi

# shellcheck source=../lib/worktree-detect.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/worktree-detect.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/worktree-detect.sh"
elif [ -f "$HOME/.claude/lib/worktree-detect.sh" ]; then
  . "$HOME/.claude/lib/worktree-detect.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/worktree-detect.sh"
fi

# Defensive shim: this hook BLOCKS, so a missing helper must not silently
# degrade the wing to something narrower than the truth. Mirrors
# bd_id_prefix_of's contract (strip a dotted sub-suffix, then take
# everything before the LAST hyphen).
if ! declare -F bd_id_prefix_of >/dev/null 2>&1; then
  bd_id_prefix_of() {
    local stripped="${1%%.*}"
    local suffix="${stripped##*-}" prefix="${stripped%-*}"
    if printf '%s' "$suffix" | grep -qE '^[a-z0-9]{3,}$' && [ -n "$prefix" ]; then
      printf '%s' "$prefix"; return 0
    fi
    return 1
  }
fi

# Second candidate: the repo directory name. bd prefix and MemPalace wing
# are not the same thing in general — dreamer-engine's bd prefix is
# `dream` while its wing is `dreamer-engine` — so no literal split of the
# bead ID, of any shape, reaches that wing. The repo dir name does, and it
# is what loom's other wing-deriving sites already use
# (scripts/loom-mine-history, scripts/loom-audit-resolve). Worktree-aware
# so a dispatched worker in .claude/worktrees/agent-<id>/ resolves the
# MAIN checkout's name rather than `agent-<id>`.
REPO_WING=""
if declare -F loom_worktree_main_dir >/dev/null 2>&1; then
  REPO_WING=$(loom_worktree_main_dir "$PWD" 2>/dev/null || true)
fi
[ -n "$REPO_WING" ] || REPO_WING="$PWD"
REPO_WING=$(basename "$REPO_WING")

# bead<TAB>prefix-wing, one per line. The python kernel appends REPO_WING
# as the second candidate.
BEAD_WING_MAP=""
for id in $BEAD_IDS; do
  BEAD_WING_MAP+="$(printf '%s\t%s' "$id" "$(bd_id_prefix_of "$id" 2>/dev/null || true)")"$'\n'
done

# --- 5-matcher verification (Bug B fix) -----------------------------------

# Pre-compute bd memories output once per bead (cheap; CLI call).
BD_MEM_DUMP=""
for id in $BEAD_IDS; do
  mem_out=$("$BD_BIN" memories "$id" 2>/dev/null || true)
  BD_MEM_DUMP+=$(printf '\n---BEGIN %s---\n%s\n---END %s---\n' "$id" "$mem_out" "$id")
done

# Extract --reason text once (handles --reason="..." and --reason "...").
REASON_TEXT=$(printf '%s' "$CMD" | python3 -c '
import shlex, sys
cmd = sys.stdin.read()
try:
    toks = shlex.split(cmd, posix=True)
except ValueError:
    print(""); sys.exit(0)
out = []
i = 0
while i < len(toks):
    t = toks[i]
    if t == "--reason" and i + 1 < len(toks):
        out.append(toks[i+1]); i += 2; continue
    if t.startswith("--reason="):
        out.append(t[len("--reason="):]); i += 1; continue
    i += 1
print("\n".join(out))
')

# --- Memory-store interpreter (loom-b76s) ---------------------------------
#
# The matcher kernel talks to the Dolt sql-server through pymysql, which
# system python3 does not carry. The memory server's venv does. Resolve
# it from this hook's OWN real path — the same `readlink -f` idiom the
# lib ladder above uses — so an installed ~/.claude/hooks symlink lands
# on the loom checkout it points into rather than on $HOME.
#
# The last rung is plain python3, which will usually lack pymysql. That
# is not a failure path: the kernel reports the missing client as an
# UNREACHABLE store, which is UNKNOWN rather than absent, so the hook
# degrades to check 4 + check 5 instead of blocking every close.
HOOK_REAL=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
HOOK_REPO_ROOT=$(dirname "$(dirname "$HOOK_REAL")")
MEMORY_PY="${LOOM_MEMORY_PYTHON:-}"
if [ -z "$MEMORY_PY" ] && [ -x "$HOOK_REPO_ROOT/memory-server/.venv/bin/python3" ]; then
  MEMORY_PY="$HOOK_REPO_ROOT/memory-server/.venv/bin/python3"
fi
[ -n "$MEMORY_PY" ] || MEMORY_PY="python3"

# Run the matcher kernel.
#
# It prints one `__STORE__|<state>|<dsn>|<detail>` line followed by one
# line per bead. Matcher cells are Y (passed), N (did not pass) or U
# (could not be evaluated — the store was unreachable).
MATRIX=$(BEAD_IDS="$BEAD_IDS" \
         BD_MEM_DUMP="$BD_MEM_DUMP" \
         REASON_TEXT="$REASON_TEXT" \
         BEAD_WING_MAP="$BEAD_WING_MAP" \
         REPO_WING="$REPO_WING" \
         "$MEMORY_PY" - <<'PY'
import json, os, re, sys

bead_ids = os.environ.get("BEAD_IDS", "").split()
mem_dump = os.environ.get("BD_MEM_DUMP", "")
reason = os.environ.get("REASON_TEXT", "")
repo_wing = os.environ.get("REPO_WING", "").strip()

# bead -> literal full prefix, computed bash-side by bd_id_prefix_of
# (lib/bd-id-extract.sh, loom-6mf7).
prefix_wing = {}
for line in os.environ.get("BEAD_WING_MAP", "").splitlines():
    if "\t" not in line:
        continue
    b, w = line.split("\t", 1)
    if b:
        prefix_wing[b] = w.strip()


def bead_short(bead):
    """The suffix after the LAST hyphen (`e2e-api-tests-e70` -> `e70`).

    Splitting at the FIRST hyphen was the loom-lwg4 bug: it yielded
    `api-tests-e70`, which no drawer body contains.
    """
    return bead.rsplit("-", 1)[1] if "-" in bead else ""


def wings_for(bead):
    """Ordered, deduped candidate wings for one bead.

    1. the literal full bd prefix (the wing in the overwhelming majority
       of projects), and
    2. the repo directory name, which is the only rung that reaches a
       wing whose name differs from the bd prefix (dreamer-engine's
       prefix is `dream`).

    A drawer in ANY candidate satisfies the matcher; a drawer in none
    still blocks, so this widens the search without weakening the gate.
    """
    out = []
    for cand in (prefix_wing.get(bead) or bead.rsplit("-", 1)[0], repo_wing):
        if cand and cand not in out:
            out.append(cand)
    return out


# --- Connection resolution -------------------------------------------------

def _mcp_declared_env():
    """LOOM_MEMORY_* keys from the `env` block of a configured MCP server.

    This hook is PreToolUse: it inherits the harness's environment, not
    the MCP server subprocess's `env` block. A machine that pins the port
    only inside mcpServers.<name>.env therefore leaves the hook pointing
    somewhere the MCP never writes — which is one half of how loom-b76s
    stayed invisible. Reading the declaration directly closes that gap.

    Any server whose env declares LOOM_MEMORY_* wins, so the lookup does
    not depend on the server keeping the name `mempalace`.
    """
    proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    for path in (os.path.join(proj, ".claude", "settings.local.json"),
                 os.path.join(proj, ".claude", "settings.json"),
                 os.path.join(cfg, "settings.json"),
                 os.path.expanduser("~/.claude.json")):
        try:
            with open(path) as fh:
                data = json.load(fh)
        except Exception:
            continue
        for srv in (data.get("mcpServers") or {}).values():
            env = (srv or {}).get("env") or {}
            hits = {k: v for k, v in env.items()
                    if k.startswith("LOOM_MEMORY_") and v not in (None, "")}
            if hits:
                return hits
    return {}


_declared = _mcp_declared_env()


def _cfg(key, default):
    val = os.environ.get(key)
    if val:
        return val
    val = _declared.get(key)
    if val:
        return val
    return default


# Defaults mirror mcp_server/db.py's connection_config().
MEM_HOST = _cfg("LOOM_MEMORY_HOST", "127.0.0.1")
MEM_PORT = _cfg("LOOM_MEMORY_PORT", "3307")
MEM_DB = _cfg("LOOM_MEMORY_DATABASE", "doltdb")
MEM_USER = _cfg("LOOM_MEMORY_USER", "root")
MEM_PASS = os.environ.get("LOOM_MEMORY_PASSWORD")
if MEM_PASS is None:
    MEM_PASS = _declared.get("LOOM_MEMORY_PASSWORD", "")

DSN = f"mysql://{MEM_USER}@{MEM_HOST}:{MEM_PORT}/{MEM_DB}"

store = None
store_err = None
try:
    import pymysql
except Exception as exc:  # any import failure is "no client"
    store_err = f"pymysql unavailable in {sys.executable}: {exc}"
else:
    try:
        store = pymysql.connect(
            host=MEM_HOST, port=int(MEM_PORT), user=MEM_USER,
            password=MEM_PASS, database=MEM_DB,
            connect_timeout=3, read_timeout=15, autocommit=True,
        )
    except Exception as exc:  # any connect failure is "unreachable"
        store_err = f"{type(exc).__name__}: {exc}"


def store_has_row(sql, params):
    """True/False against the store; None when it cannot be read.

    None is the whole point of loom-b76s. The retired implementation
    returned False for a store it could not open, which made "the gate
    cannot see where you captured" indistinguishable from "you did not
    capture" — and sent the author off to rewrite a close reason that was
    never the problem.
    """
    if store is None:
        return None
    try:
        with store.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone() is not None
    except Exception:  # a mid-query failure is still "cannot read"
        return None


# Drawer rows are matched WITHOUT a chunk_index filter. Chunk rows carry
# slices of their parent's body, so a parent plus four chunks is five
# rows holding the same needle — but this matcher is a boolean with LIMIT
# 1, so it can never double-count, and the de-dup argument for filtering
# to parents does not apply to this consumer. Filtering would only NARROW
# what proves capture: nothing in the schema forces a chunk to have a
# surviving parent (`parent_drawer_id` carries no foreign key and
# `chunk_index` is nullable), so a partial write that lands chunks alone
# would silently recreate exactly the false-negative class this bead
# exists to kill. For a blocking gate, widen rather than narrow.
#
# LOWER() on both sides is load-bearing, not decoration: the live tables
# collate utf8mb4_0900_bin, which is CASE SENSITIVE, so a bare LIKE
# misses the uppercase short-form drawer body loom-b20 was filed over.
DRAWER_FULL_SQL = (
    "SELECT 1 FROM drawers WHERE wing = %s AND room <> 'diary' "
    "AND (LOWER(text) LIKE %s OR LOWER(title) LIKE %s) LIMIT 1"
)
DRAWER_SHORT_SQL = (
    "SELECT 1 FROM drawers WHERE wing = %s AND room <> 'diary' "
    "AND LOWER(text) LIKE %s LIMIT 1"
)
DIARY_FULL_SQL = (
    "SELECT 1 FROM drawers WHERE room = 'diary' AND LOWER(text) LIKE %s LIMIT 1"
)
DIARY_SHORT_SQL = (
    "SELECT 1 FROM drawers WHERE room = 'diary' AND LOWER(text) LIKE %s "
    "AND LOWER(text) LIKE %s LIMIT 1"
)
# Check 2 does NOT require `current = 1`. Invalidating a triple retires
# the FACT, not the record that the work was captured, and narrowing a
# blocking gate on that basis is the wrong error direction: a superseded
# decision was still filed. Deletion, not invalidation, is what removes
# capture evidence.
KG_SQL = (
    "SELECT 1 FROM kg_triples WHERE LOWER(subject) LIKE %s "
    "OR LOWER(object) LIKE %s LIMIT 1"
)


def _like(needle):
    return f"%{needle.lower()}%"


def has_drawer(bead, wings):
    """Full bead ID first, then the short suffix scoped to a candidate wing.

    Wing-scoping keeps the short form unambiguous within one project's
    drawers (loom-b20 sub-issue 2). The full form also matches on title —
    a drawer titled for the bead is evidence — while the short form does
    not, because a 3-character needle in a 512-character title collides
    far too easily.
    """
    unknown = False
    for wing in wings:
        got = store_has_row(DRAWER_FULL_SQL, (wing, _like(bead), _like(bead)))
        if got:
            return True
        if got is None:
            unknown = True
    short = bead_short(bead)
    if len(short) >= 3:
        for wing in wings:
            got = store_has_row(DRAWER_SHORT_SQL, (wing, _like(short)))
            if got:
                return True
            if got is None:
                unknown = True
    return None if unknown else False


def has_diary(bead, wings):
    """Full bead ID first; the short suffix needs a candidate wing named too.

    The diary room spans every wing, so a bare `b33` mention in another
    project's entry must not satisfy `liza_base-b33` (loom-b20 sub-issue
    2).
    """
    unknown = False
    got = store_has_row(DIARY_FULL_SQL, (_like(bead),))
    if got:
        return True
    if got is None:
        unknown = True
    short = bead_short(bead)
    if len(short) >= 3:
        for wing in wings:
            got = store_has_row(DIARY_SHORT_SQL, (_like(short), _like(wing)))
            if got:
                return True
            if got is None:
                unknown = True
    return None if unknown else False


def has_kg(bead):
    return store_has_row(KG_SQL, (_like(bead), _like(bead)))


def has_bd_memory(bead):
    needle = f"---BEGIN {bead}---"
    end = f"---END {bead}---"
    s = mem_dump.find(needle)
    e = mem_dump.find(end, s) if s >= 0 else -1
    if s < 0 or e < 0:
        return False
    segment = mem_dump[s + len(needle):e]
    if "No memories" in segment:
        return False
    return bead in segment


# A bare hex token used to prove capture, which let `593934797` — a
# DigitalOcean droplet ID that happens to be nine characters of [0-9a-f]
# — close reddit-archiver-0el (loom-efrx). The negative lookahead rejects
# any all-decimal token, so a resource ID can no longer stand in for a
# commit. A genuinely all-digit short SHA loses this path and has to cite
# the drawer instead, which is the right trade for a gate whose job is
# telling capture from coincidence.
SHA_RE = re.compile(r"\b(?![0-9]+\b)[0-9a-f]{7,40}\b")

# The wing segment takes hyphens. Without them a drawer id from a
# hyphen-named wing — the DEFAULT naming, since loom-audit-resolve takes
# the wing from the repo directory basename and repository directories
# are conventionally hyphenated — never matched, so check 5 could not
# pass for those projects no matter how good the reason was (loom-efrx).
DRAWER_RE = re.compile(r"drawer_[a-z0-9_-]+_[a-f0-9]{16,}")


def has_substantive_reason():
    if len(reason) < 200:
        return False
    return bool(SHA_RE.search(reason) or DRAWER_RE.search(reason))


reason_ok = has_substantive_reason()


def cell(value):
    if value is None:
        return "U"
    return "Y" if value else "N"


def clean(text):
    return str(text).replace("|", "/").replace("\n", " ").strip()


state = "ok" if store is not None else "unreachable"
print(f"__STORE__|{state}|{clean(DSN)}|{clean(store_err or '')}")

for bead in bead_ids:
    wings = wings_for(bead)
    wing = wings[0]
    others = ", ".join(wings[1:])
    m1 = cell(has_drawer(bead, wings))
    m2 = cell(has_kg(bead))
    m3 = cell(has_diary(bead, wings))
    m4 = cell(has_bd_memory(bead))
    m5 = "Y" if reason_ok else "N"
    print(f"{bead}|{wing}|{others}|{m1}|{m2}|{m3}|{m4}|{m5}")
PY
)

# --- Decide + report ------------------------------------------------------

ALL_PASS=1
BLOCK_REPORT=""
WARN_REPORT=""
UNKNOWN_REPORT=""
STORE_STATE="ok"
STORE_DSN=""
STORE_DETAIL=""

while IFS='|' read -r bead wing others m1 m2 m3 m4 m5; do
  [ -n "$bead" ] || continue

  if [ "$bead" = "__STORE__" ]; then
    STORE_STATE="$wing"
    STORE_DSN="$others"
    STORE_DETAIL="$m1"
    continue
  fi

  evidence_count=0
  for v in "$m1" "$m2" "$m3" "$m4" "$m5"; do
    [ "$v" = "Y" ] && evidence_count=$((evidence_count + 1))
  done

  # `?` is not decoration. A matcher the hook could not evaluate must not
  # render as ✗, because ✗ reads as "you did not capture" and sends the
  # author to rewrite a close reason that was never the problem.
  s1="✗"; [ "$m1" = "Y" ] && s1="✓"; [ "$m1" = "U" ] && s1="?"
  s2="✗"; [ "$m2" = "Y" ] && s2="✓"; [ "$m2" = "U" ] && s2="?"
  s3="✗"; [ "$m3" = "Y" ] && s3="✓"; [ "$m3" = "U" ] && s3="?"
  s4="✗"; [ "$m4" = "Y" ] && s4="✓"; [ "$m4" = "U" ] && s4="?"
  s5="✗"; [ "$m5" = "Y" ] && s5="✓"; [ "$m5" = "U" ] && s5="?"

  if [ "$evidence_count" -gt 0 ]; then
    WARN_REPORT+=$'\n'"[bd-close-capture hook] ${bead}: ${evidence_count}/5 matchers (${s1}${s2}${s3}${s4}${s5}) — allowing."
  elif [ "$STORE_STATE" = "unreachable" ]; then
    UNKNOWN_REPORT+=$'\n'"[bd-close-capture hook] ${bead}: capture UNVERIFIABLE — the memory store is unreachable."$'\n\n'
    UNKNOWN_REPORT+="  ${s1} Drawer in ${wing}/* mentioning ${bead}"$'\n'
    [ -n "$others" ] && \
      UNKNOWN_REPORT+="       (also searched wing(s): ${others})"$'\n'
    UNKNOWN_REPORT+="  ${s2} KG triple referencing ${bead}"$'\n'
    UNKNOWN_REPORT+="  ${s3} Diary entry mentioning ${bead}"$'\n'
    UNKNOWN_REPORT+="  ${s4} bd memory tagged with ${bead}"$'\n'
    UNKNOWN_REPORT+="  ${s5} Substantive close --reason (≥200 chars + commit SHA or drawer ID)"$'\n\n'
    UNKNOWN_REPORT+="  store: ${STORE_DSN}"$'\n'
    UNKNOWN_REPORT+="  error: ${STORE_DETAIL}"$'\n\n'
    UNKNOWN_REPORT+="Not blocking: the gate cannot prove capture is absent when it cannot"$'\n'
    UNKNOWN_REPORT+="read the store. A ? is not a ✗ — nothing about your close reason is"$'\n'
    UNKNOWN_REPORT+="wrong, so rewriting it will not help."$'\n\n'
    UNKNOWN_REPORT+="To restore the gate, start the memory server"$'\n'
    UNKNOWN_REPORT+="(memory-server/scripts/start-server.sh) or point the hook at it with"$'\n'
    UNKNOWN_REPORT+="LOOM_MEMORY_HOST / LOOM_MEMORY_PORT / LOOM_MEMORY_DATABASE /"$'\n'
    UNKNOWN_REPORT+="LOOM_MEMORY_USER / LOOM_MEMORY_PASSWORD."$'\n'
  else
    ALL_PASS=0
    BLOCK_REPORT+=$'\n'"[bd-close-capture hook] No capture evidence found for ${bead}."$'\n\n'
    BLOCK_REPORT+="Looked for (need ANY ONE):"$'\n'
    BLOCK_REPORT+="  ${s1} Drawer in ${wing}/* mentioning ${bead}"$'\n'
    [ -n "$others" ] && \
      BLOCK_REPORT+="       (also searched wing(s): ${others})"$'\n'
    BLOCK_REPORT+="  ${s2} KG triple referencing ${bead}"$'\n'
    BLOCK_REPORT+="  ${s3} Diary entry mentioning ${bead}"$'\n'
    BLOCK_REPORT+="  ${s4} bd memory tagged with ${bead}"$'\n'
    BLOCK_REPORT+="  ${s5} Substantive close --reason (≥200 chars + commit SHA or drawer ID)"$'\n\n'
    BLOCK_REPORT+="Recommended:"$'\n'
    BLOCK_REPORT+="  /wrap-up                            — full ritual (drawer + KG + diary)"$'\n\n'
    BLOCK_REPORT+="Or, for wave-batch closes, add lineage to --reason:"$'\n'
    BLOCK_REPORT+="  bd close ${bead} --reason \"Wave 1 voice pass: filter haiku→sonnet,"$'\n'
    BLOCK_REPORT+="  drives saturation 1.0→0.8. Commit abc1234. Sibling drawer"$'\n'
    BLOCK_REPORT+="  drawer_${wing}_decisions_<id>.\""$'\n\n'
    BLOCK_REPORT+="Bypass (use sparingly; both are auditable and recorded in workflow state):"$'\n'
    BLOCK_REPORT+="  bd close ${bead} --force"$'\n'
    BLOCK_REPORT+="      Works right now. --force is in the command text, which is what"$'\n'
    BLOCK_REPORT+="      this PreToolUse hook reads. Long form only; -f is not matched."$'\n'
    BLOCK_REPORT+="  BD_CLOSE_FORCE (session-level)"$'\n'
    BLOCK_REPORT+="      Read from this hook's OWN environment. The hook runs before any"$'\n'
    BLOCK_REPORT+="      shell does, so writing it as a command prefix never reaches it."$'\n'
    BLOCK_REPORT+="      Export it in the shell that launches Claude Code, or add it to"$'\n'
    BLOCK_REPORT+="      the top-level \"env\" block of ~/.claude/settings.json, then"$'\n'
    BLOCK_REPORT+="      restart the session."$'\n'
  fi
done <<<"$MATRIX"

if [ "$ALL_PASS" = "1" ]; then
  [ -n "$WARN_REPORT" ] && printf '%s\n' "$WARN_REPORT" >&2
  [ -n "$UNKNOWN_REPORT" ] && printf '%s\n' "$UNKNOWN_REPORT" >&2
  workflow_state_set --start-dir="$PWD" activity=idle bead= stage=close \
    >/dev/null 2>&1 || true
  exit 0
fi

[ -n "$UNKNOWN_REPORT" ] && printf '%s\n' "$UNKNOWN_REPORT" >&2
printf '%s\n' "$BLOCK_REPORT" >&2
exit 2
