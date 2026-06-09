#!/usr/bin/env bash
# PreToolUse hook for `bd close`.
#
# Per locked workflow-infrastructure decision (2026-05-02 #2): block
# until drawer + KG + diary are captured. Bypass via --force flag or
# BD_CLOSE_FORCE=1 env var.
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
# Test injection points:
#   MEMPALACE_HOME — palace dir (default: ~/.mempalace)
#   BD_BIN          — bd binary (default: bd)
#
# Block strategy: exit 2 with stderr message. Claude Code surfaces
# stderr and blocks the tool call.

set -uo pipefail

INPUT=$(cat)
MEMPALACE_HOME="${MEMPALACE_HOME:-$HOME/.mempalace}"
BD_BIN="${BD_BIN:-bd}"

# --- Tool dispatch ---------------------------------------------------------

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
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
            j += 1
        break
    i += 1
if not found:
    print("__NO_BD_CLOSE__")
else:
    print(" ".join(ids))
')

# Gate: no real `bd close` invocation → hook is a silent no-op.
[ "$PARSE_OUT" = "__NO_BD_CLOSE__" ] && exit 0
BEAD_IDS="$PARSE_OUT"

# --- Mode resolution -------------------------------------------------------

# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"
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

# Run the matcher kernel.
MATRIX=$(BEAD_IDS="$BEAD_IDS" \
         MEMPALACE_HOME="$MEMPALACE_HOME" \
         BD_MEM_DUMP="$BD_MEM_DUMP" \
         REASON_TEXT="$REASON_TEXT" \
         python3 - <<'PY'
import os, re, sqlite3

bead_ids = os.environ.get("BEAD_IDS", "").split()
palace_home = os.environ["MEMPALACE_HOME"]
mem_dump = os.environ.get("BD_MEM_DUMP", "")
reason = os.environ.get("REASON_TEXT", "")

chroma_db = os.path.join(palace_home, "palace", "chroma.sqlite3")
kg_db = os.path.join(palace_home, "palace", "knowledge_graph.sqlite3")

def open_ro(path):
    if not os.path.exists(path):
        return None
    try:
        return sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.OperationalError:
        return None

chroma = open_ro(chroma_db)
kg = open_ro(kg_db)

def palace_match(needle, wing_filter=None, exclude_room=None,
                 only_room=None, require_needle_in_doc=False,
                 require_wing_in_doc=None):
    if chroma is None:
        return False
    cur = chroma.cursor()
    try:
        rows = cur.execute(
            "SELECT rowid FROM embedding_fulltext_search "
            "WHERE string_value MATCH ?",
            (f'"{needle}"',)
        ).fetchall()
    except sqlite3.OperationalError:
        return False
    if not rows:
        return False
    rowids = [r[0] for r in rows]
    placeholders = ",".join("?" * len(rowids))
    md_rows = cur.execute(
        f"SELECT id, key, string_value FROM embedding_metadata "
        f"WHERE id IN ({placeholders}) AND string_value IS NOT NULL",
        rowids
    ).fetchall()
    by_id = {}
    for rid, k, v in md_rows:
        by_id.setdefault(rid, {})[k] = v
    for rid, meta in by_id.items():
        w = meta.get("wing", "")
        r = meta.get("room", "")
        doc = meta.get("chroma:document", "") or ""
        if wing_filter is not None and w != wing_filter:
            continue
        if exclude_room and r == exclude_room:
            continue
        if only_room and r != only_room:
            continue
        if require_needle_in_doc and needle.lower() not in doc.lower():
            continue
        # Cross-wing scope guard for short-form lookups: when the diary
        # (or any only_room match) accepts a short-form needle, require
        # the bead's wing name to also appear in the doc body. Prevents
        # `b33` in wing_claude-opus/diary from satisfying any project's
        # `<wing>-b33` close (loom-b20 sub-issue 2).
        if require_wing_in_doc is not None and \
                require_wing_in_doc.lower() not in doc.lower():
            continue
        return True
    return False

# Drawer matcher: try the full bead ID first; fall back to the short
# suffix scoped to the bead's wing. Wing-scoping makes the short form
# unambiguous within a single project's drawers (loom-b20 sub-issue 2).
def has_drawer(bead, wing):
    if palace_match(bead, wing_filter=wing, exclude_room="diary"):
        return True
    short = bead.split("-", 1)[1] if "-" in bead else ""
    if len(short) >= 3 and palace_match(
            short, wing_filter=wing, exclude_room="diary",
            require_needle_in_doc=True):
        return True
    return False

# Diary matcher: try the full bead ID first; fall back to the short
# suffix when the diary doc body ALSO names the bead's wing (the diary
# room is global across wings, so a `b33` mention in a different
# project's diary entry must not satisfy `liza_base-b33`).
def has_diary(bead):
    if palace_match(bead, wing_filter=None, only_room="diary",
                    require_needle_in_doc=True):
        return True
    if "-" not in bead:
        return False
    wing, short = bead.split("-", 1)
    if len(short) < 3:
        return False
    return palace_match(short, wing_filter=None, only_room="diary",
                        require_needle_in_doc=True,
                        require_wing_in_doc=wing)

def has_kg(bead):
    if kg is None:
        return False
    try:
        row = kg.execute(
            "SELECT 1 FROM triples WHERE subject LIKE ? OR object LIKE ? LIMIT 1",
            (f"%{bead}%", f"%{bead}%")
        ).fetchone()
    except sqlite3.OperationalError:
        return False
    return row is not None

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

SHA_RE = re.compile(r"\b[0-9a-f]{7,40}\b")
DRAWER_RE = re.compile(r"drawer_[a-z0-9_]+_[a-f0-9]{16,}")

def has_substantive_reason():
    if len(reason) < 200:
        return False
    return bool(SHA_RE.search(reason) or DRAWER_RE.search(reason))

reason_ok = has_substantive_reason()

for bead in bead_ids:
    wing = bead.split("-", 1)[0]
    m1 = "Y" if has_drawer(bead, wing) else "N"
    m2 = "Y" if has_kg(bead) else "N"
    m3 = "Y" if has_diary(bead) else "N"
    m4 = "Y" if has_bd_memory(bead) else "N"
    m5 = "Y" if reason_ok else "N"
    print(f"{bead}|{wing}|{m1}|{m2}|{m3}|{m4}|{m5}")
PY
)

# --- Decide + report ------------------------------------------------------

ALL_PASS=1
BLOCK_REPORT=""
WARN_REPORT=""

while IFS='|' read -r bead wing m1 m2 m3 m4 m5; do
  [ -n "$bead" ] || continue
  evidence_count=0
  for v in "$m1" "$m2" "$m3" "$m4" "$m5"; do
    [ "$v" = "Y" ] && evidence_count=$((evidence_count + 1))
  done

  s1="✗"; [ "$m1" = "Y" ] && s1="✓"
  s2="✗"; [ "$m2" = "Y" ] && s2="✓"
  s3="✗"; [ "$m3" = "Y" ] && s3="✓"
  s4="✗"; [ "$m4" = "Y" ] && s4="✓"
  s5="✗"; [ "$m5" = "Y" ] && s5="✓"

  if [ "$evidence_count" -eq 0 ]; then
    ALL_PASS=0
    BLOCK_REPORT+=$'\n'"[bd-close-capture hook] No capture evidence found for ${bead}."$'\n\n'
    BLOCK_REPORT+="Looked for (need ANY ONE):"$'\n'
    BLOCK_REPORT+="  ${s1} Drawer in ${wing}/* mentioning ${bead}"$'\n'
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
    BLOCK_REPORT+="Bypass (use sparingly):"$'\n'
    BLOCK_REPORT+="  BD_CLOSE_FORCE=1 bd close ${bead}   # auditable; recorded in workflow state"$'\n'
  else
    WARN_REPORT+=$'\n'"[bd-close-capture hook] ${bead}: ${evidence_count}/5 matchers (${s1}${s2}${s3}${s4}${s5}) — allowing."
  fi
done <<<"$MATRIX"

if [ "$ALL_PASS" = "1" ]; then
  [ -n "$WARN_REPORT" ] && printf '%s\n' "$WARN_REPORT" >&2
  workflow_state_set --start-dir="$PWD" activity=idle bead= stage=close \
    >/dev/null 2>&1 || true
  exit 0
fi

printf '%s\n' "$BLOCK_REPORT" >&2
exit 2
