#!/usr/bin/env bash
# Fixture tests for hooks/bd-close-capture.sh.
#
# Covers loom-8vb (Bug A: regex captures --reason content; Bug B: hook
# performs no real verification at all).
#
# Locked design: drawer_loom_decisions_2fbf2d5f4c0f5e50ab84e628.
#
# Fixtures rely on env-var injection points (added by the loom-8vb fix):
#   MEMPALACE_HOME — point at a fixture palace tmpdir
#   BD_BIN          — point at a fixture/stubbed bd binary
#
# Run:  bash lib/tests/bd-close-capture.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-close-capture.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook in a controlled env: PWD is a project dir with workflow.json,
# MEMPALACE_HOME points at a fixture palace, BD_BIN points at a fixture bd.
# Returns combined stdout+stderr; exit code captured separately via $?.
run_hook() {
  local proj="$1" cmd="$2"
  local mp="${3:-$NULL_PALACE}"
  local bdb="${4:-$NULL_BD}"
  local force="${5:-}"
  local payload
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  if [ -n "$force" ]; then
    (cd "$proj" && BD_CLOSE_FORCE="$force" MEMPALACE_HOME="$mp" BD_BIN="$bdb" \
      bash "$HOOK" <<<"$payload" 2>&1)
  else
    (cd "$proj" && MEMPALACE_HOME="$mp" BD_BIN="$bdb" \
      bash "$HOOK" <<<"$payload" 2>&1)
  fi
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Minimal Chroma sqlite with one drawer-style row mentioning a bead.
# Uses the embedding_metadata layout we observed (key/string_value rows
# joined by `id` column referencing a synthetic rowid).
mk_palace_with_drawer() {
  local dir="$1" wing="$2" room="$3" bead="$4" body="$5"
  mkdir -p "$dir/palace"
  python3 - "$dir/palace/chroma.sqlite3" "$wing" "$room" "$body" <<'PY'
import sqlite3, sys
db, wing, room, body = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
con = sqlite3.connect(db)
cur = con.cursor()
cur.execute("CREATE VIRTUAL TABLE embedding_fulltext_search USING fts5(string_value)")
cur.execute("CREATE TABLE embedding_metadata (id INTEGER, key TEXT, string_value TEXT, int_value INTEGER, float_value REAL, bool_value INTEGER)")
rid = 1
cur.execute("INSERT INTO embedding_fulltext_search(rowid, string_value) VALUES (?, ?)", (rid, body))
for k, v in (("wing", wing), ("room", room), ("chroma:document", body)):
    cur.execute("INSERT INTO embedding_metadata(id, key, string_value) VALUES (?, ?, ?)", (rid, k, v))
con.commit()
PY
  # KG sqlite (empty triples table — exists so KG-matcher path doesn't crash).
  # Lives next to chroma.sqlite3 in <palace_home>/palace/ — caught live on
  # the loom-8vb self-test: the hook's earlier kg_db path was at the palace
  # root, but the real palace puts both DBs under palace/.
  python3 - "$dir/palace/knowledge_graph.sqlite3" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT, properties TEXT, created_at TEXT)")
con.execute("CREATE TABLE triples (id INTEGER PRIMARY KEY, subject TEXT, predicate TEXT, object TEXT, valid_from TEXT, valid_to TEXT, confidence REAL, source_closet TEXT, source_file TEXT, extracted_at TEXT)")
con.commit()
PY
}

# Empty Chroma + empty KG.
mk_empty_palace() {
  local dir="$1"
  mkdir -p "$dir/palace"
  python3 - "$dir/palace/chroma.sqlite3" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE VIRTUAL TABLE embedding_fulltext_search USING fts5(string_value)")
con.execute("CREATE TABLE embedding_metadata (id INTEGER, key TEXT, string_value TEXT, int_value INTEGER, float_value REAL, bool_value INTEGER)")
con.commit()
PY
  python3 - "$dir/palace/knowledge_graph.sqlite3" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT, properties TEXT, created_at TEXT)")
con.execute("CREATE TABLE triples (id INTEGER PRIMARY KEY, subject TEXT, predicate TEXT, object TEXT, valid_from TEXT, valid_to TEXT, confidence REAL, source_closet TEXT, source_file TEXT, extracted_at TEXT)")
con.commit()
PY
}

# Add a KG triple to an existing palace.
add_kg_triple() {
  local dir="$1" subj="$2" pred="$3" obj="$4"
  python3 - "$dir/palace/knowledge_graph.sqlite3" "$subj" "$pred" "$obj" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("INSERT INTO triples(subject, predicate, object, valid_from, confidence) VALUES (?, ?, ?, '2026-05-06', 1.0)",
            (sys.argv[2], sys.argv[3], sys.argv[4]))
con.commit()
PY
}

# Make a project dir with workflow.json mode=full.
mk_proj_full() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.claude"
  echo '{"v":1,"mode":"full"}' > "$dir/.claude/workflow.json"
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

# Empty bd stub (no memories).
NULL_BD=$(mk_bd_stub "No memories matching")

# Empty palace (no drawers, no KG triples).
NULL_PALACE=$(mktemp -d)
mk_empty_palace "$NULL_PALACE"

# Loom project fixture with workflow.json mode=full.
PROJ=$(mk_proj_full)

trap 'rm -rf "$PROJ" "$NULL_PALACE" "$NULL_BD"' EXIT

# ---------------------------------------------------------------------------
# 1. Bug A — regex parses ONLY `bd close <ids...>`, ignores --reason
# ---------------------------------------------------------------------------

echo "==> 1. Bead-ID regex scope (Bug A fix)"

# Unique-block: extracted bead IDs are visible in the block-message header.
# We force a block (full mode + null palace + no bypass) and grep the
# 'No capture evidence found for' line for the ID.
out=$(run_hook "$PROJ" 'bd close liza_base-dab --reason "Wave 1: re-dispatch and rule-based follow-up landed"' "$NULL_PALACE" "$NULL_BD")
if echo "$out" | grep -qE 'liza_base-dab' && \
   ! echo "$out" | grep -qE 're-dispatch' && \
   ! echo "$out" | grep -qE 'rule-based' && \
   ! echo "$out" | grep -qE 'follow-up'; then
  pass "regex extracts only liza_base-dab; --reason content ignored"
else
  fail "regex still leaks --reason words" "$out"
fi

# Underscore-prefix preservation (the prior regex stripped the liza_ part).
if echo "$out" | grep -qE 'liza_base-dab' && ! echo "$out" | grep -qE '\bbase-dab\b'; then
  pass "underscore-prefix bead ID preserved (liza_base-dab, not base-dab)"
else
  fail "underscore prefix dropped" "$out"
fi

# Multi-bead args: both extracted, neither garbage from --reason.
out=$(run_hook "$PROJ" 'bd close loom-8vb loom-2xh --reason "...real-issue and side-quest..."' "$NULL_PALACE" "$NULL_BD")
if echo "$out" | grep -qE 'loom-8vb' && echo "$out" | grep -qE 'loom-2xh' && \
   ! echo "$out" | grep -qE '\breal-issue\b' && ! echo "$out" | grep -qE '\bside-quest\b'; then
  pass "multi-bead close: both args extracted, --reason content ignored"
else
  fail "multi-bead extraction broken" "$out"
fi

# Sub-suffix bead IDs (e.g. loom-8vb.4 from epic structure).
out=$(run_hook "$PROJ" 'bd close loom-8vb.4 --reason "..."' "$NULL_PALACE" "$NULL_BD")
if echo "$out" | grep -qE 'loom-8vb\.4'; then
  pass "sub-suffix bead ID (loom-8vb.4) extracted intact"
else
  fail "sub-suffix bead ID lost" "$out"
fi

# 4+char hash suffix bead IDs (sibling projects like liza_base can mint
# longer hashes; loom-gcb widened the regex from {3} to {3,}).
out=$(run_hook "$PROJ" 'bd close liza_base-abcd --reason "..."' "$NULL_PALACE" "$NULL_BD")
if echo "$out" | grep -qE 'liza_base-abcd'; then
  pass "4-char hash suffix (liza_base-abcd) extracted (loom-gcb)"
else
  fail "4-char hash suffix dropped — regex still {3} not {3,}" "$out"
fi

# Multi-hyphen prefix bead IDs (e.g. HAW's 'hundred-acre-woods-bng').
# loom-2t7 widened the prefix class from [a-z0-9_]* to [a-z0-9_-]*.
out=$(run_hook "$PROJ" 'bd close hundred-acre-woods-bng --reason "..."' "$NULL_PALACE" "$NULL_BD")
if echo "$out" | grep -qE 'hundred-acre-woods-bng'; then
  pass "multi-hyphen prefix (hundred-acre-woods-bng) extracted (loom-2t7)"
else
  fail "multi-hyphen prefix dropped — regex still rejects hyphens" "$out"
fi

# ---------------------------------------------------------------------------
# 2. Bypass paths preserved (regression)
# ---------------------------------------------------------------------------

echo "==> 2. Bypass paths"

# --force flag bypasses.
out=$(run_hook "$PROJ" 'bd close loom-8vb --force' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "--force bypasses verification"; else fail "--force did not bypass (exit=$rc)" "$out"; fi

# BD_CLOSE_FORCE=1 bypasses.
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$NULL_PALACE" "$NULL_BD" "1"); rc=$?
if [ "$rc" -eq 0 ]; then pass "BD_CLOSE_FORCE=1 bypasses verification"; else fail "BD_CLOSE_FORCE=1 did not bypass (exit=$rc)" "$out"; fi

# mode != full (light mode) bypasses.
LIGHT=$(mktemp -d); mkdir -p "$LIGHT/.claude"; echo '{"v":1,"mode":"light"}' > "$LIGHT/.claude/workflow.json"
out=$(run_hook "$LIGHT" 'bd close loom-8vb' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "mode=light bypasses verification"; else fail "mode=light did not bypass (exit=$rc)" "$out"; fi
rm -rf "$LIGHT"

# Non-Bash tools ignored.
out=$(echo '{"tool_name":"Edit","tool_input":{"command":"bd close loom-8vb"}}' | bash "$HOOK" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then pass "non-Bash tools ignored"; else fail "non-Bash tool blocked (exit=$rc)" "$out"; fi

# ---------------------------------------------------------------------------
# 3. Full mode + zero artifacts → blocks (Bug B fix: real verification)
# ---------------------------------------------------------------------------

echo "==> 3. Full mode + zero capture evidence → blocks with explicit message"

out=$(run_hook "$PROJ" 'bd close loom-8vb' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ]; then pass "blocks (exit 2) when no evidence"; else fail "expected exit 2, got $rc" "$out"; fi

# Error message lists the 5 matchers with ✗.
for needle in \
  "No capture evidence found for" \
  "Drawer in loom" \
  "KG triple referencing loom-8vb" \
  "Diary entry" \
  "bd memory" \
  "Substantive close --reason" \
  "/wrap-up" \
  "BD_CLOSE_FORCE=1"
do
  if echo "$out" | grep -qF "$needle"; then
    pass "block message contains: $needle"
  else
    fail "block message missing: $needle" "$out"
  fi
done

# ---------------------------------------------------------------------------
# 4. Matcher 1 — drawer in any room of the project's wing → allows
# ---------------------------------------------------------------------------

echo "==> 4. Drawer matcher (any room of wing)"

# Drawer in `decisions` room of wing `loom` mentioning loom-8vb.
DRAWER_PALACE=$(mktemp -d)
mk_palace_with_drawer "$DRAWER_PALACE" loom decisions loom-8vb \
  "loom-8vb shipped real artifact verification on 2026-05-06."
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$DRAWER_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "drawer in decisions room → allows"; else fail "drawer-room match did not allow (exit=$rc)" "$out"; fi
rm -rf "$DRAWER_PALACE"

# Drawer in `findings` room of wing `loom` (non-decisions room).
FIND_PALACE=$(mktemp -d)
mk_palace_with_drawer "$FIND_PALACE" loom findings loom-8vb \
  "Diagnostic finding: loom-8vb regex confused parser."
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$FIND_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "drawer in non-decisions room (findings) → allows"; else fail "non-decisions room did not allow (exit=$rc)" "$out"; fi
rm -rf "$FIND_PALACE"

# Drawer in WRONG wing → still blocks.
WRONG_WING=$(mktemp -d)
mk_palace_with_drawer "$WRONG_WING" liza_base decisions loom-8vb \
  "loom-8vb mentioned but in wrong wing"
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$WRONG_WING" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ]; then pass "drawer in OTHER wing → blocks (wing scoping works)"; else fail "wrong-wing drawer leaked (exit=$rc)" "$out"; fi
rm -rf "$WRONG_WING"

# Short-form drawer body (loom-b20 sub-issue 2): the drawer mentions the
# bead via its short suffix (`b33`) instead of the full `liza_base-b33`.
# Wing-scoped matching makes this unambiguous — the suffix only matches
# within the bead's own wing. Lowercase form.
SHORT_PALACE=$(mktemp -d)
mk_palace_with_drawer "$SHORT_PALACE" liza_base decisions "b33-architecture" \
  "B33 ARCHITECTURE LOCKED. The b33 design names three tracks."
out=$(run_hook "$PROJ" 'bd close liza_base-b33' "$SHORT_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "short-form drawer body (b33 within liza_base wing) → allows (loom-b20)"
else
  fail "short-form drawer match did not allow (exit=$rc)" "$out"
fi
rm -rf "$SHORT_PALACE"

# Bug-class: drawer body uses ONLY uppercase short form (verbatim
# loom-b20 sub-issue 2 scenario — "B33 ARCHITECTURE LOCKED"). Match
# must be case-insensitive so the original failure case is fixed.
UPPER_PALACE=$(mktemp -d)
mk_palace_with_drawer "$UPPER_PALACE" liza_base decisions "B33-arch" \
  "B33 ARCHITECTURE LOCKED. Three tracks committed."
out=$(run_hook "$PROJ" 'bd close liza_base-b33' "$UPPER_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "uppercase-only short-form drawer (B33) → allows (loom-b20 verbatim)"
else
  fail "uppercase short-form drawer did not allow (exit=$rc)" "$out"
fi
rm -rf "$UPPER_PALACE"

# Short-form match must remain wing-scoped: a drawer in wing `loom` whose
# body mentions only `b33` must NOT satisfy capture for `liza_base-b33`.
# Wing scoping prevents cross-project ambiguity.
CROSS_WING=$(mktemp -d)
mk_palace_with_drawer "$CROSS_WING" loom decisions "b33-note" \
  "Note: b33 mentioned but this drawer is in the loom wing."
out=$(run_hook "$PROJ" 'bd close liza_base-b33' "$CROSS_WING" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "short-form match is wing-scoped (b33 in loom wing rejected for liza_base-b33) (loom-b20)"
else
  fail "short-form leaked across wings (exit=$rc)" "$out"
fi
rm -rf "$CROSS_WING"

# Short-form must be ≥3 chars to avoid trivial-substring false positives.
# Bead suffix regex is already {3,}; this guards regression if the matcher
# ever takes a shorter substring.
TINY_PALACE=$(mktemp -d)
mk_palace_with_drawer "$TINY_PALACE" liza_base decisions "ab-trivial" \
  "Unrelated drawer mentioning 'ab' twice: ab and ab."
out=$(run_hook "$PROJ" 'bd close liza_base-ab' "$TINY_PALACE" "$NULL_BD"); rc=$?
# The bead-ID regex requires {3,} for the suffix; `liza_base-ab` won't
# even parse as a bead ID, so the hook should treat the command as
# "no parsable bead ID" — exit 2 with the parse error.
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "2-char suffix not accepted as bead ID (regex {3,} guard) (loom-b20)"
else
  fail "2-char suffix passed bead-ID regex (suffix length guard regressed)" "$out"
fi
rm -rf "$TINY_PALACE"

# ---------------------------------------------------------------------------
# 5. Matcher 2 — KG triple referencing the bead → allows
# ---------------------------------------------------------------------------

echo "==> 5. KG triple matcher"

KG_PALACE=$(mktemp -d)
mk_empty_palace "$KG_PALACE"
add_kg_triple "$KG_PALACE" "loom-8vb" "ships" "real-verification"
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$KG_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "KG triple subject=loom-8vb → allows"; else fail "KG subject match did not allow (exit=$rc)" "$out"; fi

# Object also matches.
KG_PALACE2=$(mktemp -d)
mk_empty_palace "$KG_PALACE2"
add_kg_triple "$KG_PALACE2" "real-verification" "implements" "loom-8vb"
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$KG_PALACE2" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "KG triple object=loom-8vb → allows"; else fail "KG object match did not allow (exit=$rc)" "$out"; fi
rm -rf "$KG_PALACE" "$KG_PALACE2"

# ---------------------------------------------------------------------------
# 6. Matcher 3 — diary entry referencing the bead → allows
# ---------------------------------------------------------------------------

echo "==> 6. Diary matcher"

DIARY_PALACE=$(mktemp -d)
mk_palace_with_drawer "$DIARY_PALACE" wing_claude-opus diary loom-8vb \
  "SESSION:2026-05-06|loom-8vb shipped|stage:wrap-up"
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$DIARY_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "diary entry mentioning bead → allows"; else fail "diary match did not allow (exit=$rc)" "$out"; fi
rm -rf "$DIARY_PALACE"

# Short-form diary entry (loom-b20 sub-issue 2). Diary is global across
# wings — the bead body must still appear literally, so the short form
# needs an extra wing-scope check inside the diary path.
SHORT_DIARY=$(mktemp -d)
mk_palace_with_drawer "$SHORT_DIARY" wing_claude-opus diary "b33-session" \
  "SESSION:2026-05-08|liza_base: b33 architecture locked|stage:wrap-up"
out=$(run_hook "$PROJ" 'bd close liza_base-b33' "$SHORT_DIARY" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "short-form diary body with wing-name nearby → allows (loom-b20)"
else
  fail "short-form diary did not allow (exit=$rc)" "$out"
fi
rm -rf "$SHORT_DIARY"

# Bug-class: short-form diary entry that does NOT name the wing must
# NOT satisfy capture (prevents `b33` mentioned in some unrelated diary
# from satisfying liza_base-b33). loom-b20 sub-issue 2 wing-scope guard.
SHORT_DIARY_NOWING=$(mktemp -d)
mk_palace_with_drawer "$SHORT_DIARY_NOWING" wing_claude-opus diary "b33-only" \
  "SESSION:2026-05-08|b33 mentioned in passing|stage:debug"
out=$(run_hook "$PROJ" 'bd close liza_base-b33' "$SHORT_DIARY_NOWING" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "short-form diary WITHOUT wing-name → blocks (loom-b20 wing guard)"
else
  fail "short-form diary leaked without wing-name (exit=$rc)" "$out"
fi
rm -rf "$SHORT_DIARY_NOWING"

# ---------------------------------------------------------------------------
# 7. Matcher 4 — bd memory referencing the bead → allows
# ---------------------------------------------------------------------------

echo "==> 7. bd memory matcher"

BD_WITH_MEM=$(mk_bd_stub "loom-8vb-shipped-real-verification — captured 2026-05-06")
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$NULL_PALACE" "$BD_WITH_MEM"); rc=$?
if [ "$rc" -eq 0 ]; then pass "bd memory mentioning bead → allows"; else fail "bd memory match did not allow (exit=$rc)" "$out"; fi
rm -f "$BD_WITH_MEM"

# ---------------------------------------------------------------------------
# 8. Matcher 5 — substantive --reason (≥200 chars + commit/drawer ID) → allows
# ---------------------------------------------------------------------------

echo "==> 8. Substantive --reason matcher"

LONG_REASON_OK="Wave 1 voice pass: filter haiku→sonnet, drives saturation 1.0→0.8 across the bank pool. Lineage in commit abc1234 plus sibling drawer drawer_liza_base_decisions_aabbccdd1122. Audit clean, 1101/1101 pass."
out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$LONG_REASON_OK\"" "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "≥200 char --reason with commit SHA + drawer ID → allows"; else fail "substantive --reason did not allow (exit=$rc)" "$out"; fi

# Long but no commit/drawer ID → still blocks.
LONG_REASON_NOREF=$(printf 'placeholder %.0s' {1..50})  # ~600 chars of placeholder
out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$LONG_REASON_NOREF\"" "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ]; then pass "long --reason without commit/drawer ID → blocks"; else fail "no-ref long --reason allowed (exit=$rc)" "$out"; fi

# Short --reason with SHA → still blocks (must be ≥200 chars).
SHORT_REASON_REF="Fixed in abc1234"
out=$(run_hook "$PROJ" "bd close loom-8vb --reason \"$SHORT_REASON_REF\"" "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ]; then pass "short --reason with SHA but <200 chars → blocks"; else fail "short --reason allowed (exit=$rc)" "$out"; fi

# --reason="..." form (= instead of space) parsed identically.
out=$(run_hook "$PROJ" "bd close loom-8vb --reason=\"$LONG_REASON_OK\"" "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ]; then pass "--reason=\"…\" form (= sign) accepted"; else fail "--reason=\"…\" form not parsed (exit=$rc)" "$out"; fi

# ---------------------------------------------------------------------------
# 9. Edge cases — bare `bd close`, --suggest-next flag
# ---------------------------------------------------------------------------

echo "==> 9. Edge cases"

# bd-close with no positional ID → distinct error, exit 2.
# IMPORTANT: keep backticks out of test-name strings. An earlier draft
# used `pass "bare \`bd close\` ..."` which bash command-substituted,
# inadvertently firing `bd close` against the live workspace and closing
# the most-recently-touched bead. Caught live during loom-8vb self-test.
out=$(run_hook "$PROJ" 'bd close --reason "no positional"' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Could not parse bead ID'; then
  pass 'bd-close with no positional id -> distinct parse-error block'
else
  fail 'bd-close no-positional did not give parse-error' "$out"
fi

# Mixed non-bead-token args ignored (wouldn't match the regex).
out=$(run_hook "$PROJ" 'bd close loom-8vb --suggest-next --reason "..."' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'loom-8vb' && \
   ! echo "$out" | grep -qE '\bsuggest-next\b'; then
  pass "trailing flags (--suggest-next) excluded from bead-ID list"
else
  fail "trailing flags leaked into bead-ID list" "$out"
fi

# ---------------------------------------------------------------------------
# 10. Trigger-guard command-shape — close-phrase inside a --description of a
#     DIFFERENT command must NOT fire the hook (loom-oq0s, sibling of loom-9ng)
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

# 10a. Single-line bd create whose --description contains the close-phrase
#      mid-string. Must NOT be intercepted (exit 0, hook is a no-op).
out=$(run_hook "$PROJ" 'bd create --type bug --description "Hook fires when bd close phrase appears in a description" -t title' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "bd create with close-phrase in --description (single line) → not intercepted"
else
  fail "bd create with close-phrase in --description wrongly intercepted (exit=$rc)" "$out"
fi

# 10b. MULTI-LINE bd create whose --description has a line BEGINNING with
#      the close-phrase (the live loom-n1sk failure shape — the `\n`-anchored
#      alternative in the old regex matched the embedded line). Must NOT fire.
ML_DESC=$'Hook false-positives.\nExample of the buggy invocation:\nbd close foo aborts the legitimate command.'
out=$(run_hook "$PROJ" "$(printf 'bd create --type bug --description %q -t title' "$ML_DESC")" "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "bd create with multi-line --description (line begins 'bd close') → not intercepted"
else
  fail "bd create with multi-line close-phrase description wrongly intercepted (exit=$rc)" "$out"
fi

# 10c. close-phrase inside -m message of a non-close command → not intercepted.
out=$(run_hook "$PROJ" 'git commit -m "note: bd close was blocked earlier"' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "git commit -m with close-phrase in message → not intercepted"
else
  fail "git commit -m with close-phrase wrongly intercepted (exit=$rc)" "$out"
fi

# 10d. REGRESSION: a genuine `bd close <id>` invocation MUST still be parsed
#      (blocks here because PROJ is full-mode + null palace → no evidence).
out=$(run_hook "$PROJ" 'bd close loom-8vb' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'loom-8vb'; then
  pass "genuine bd close <id> still parsed + verified (regression)"
else
  fail "genuine bd close no longer detected (exit=$rc)" "$out"
fi

# 10e. REGRESSION: a genuine close in a command CHAIN (after &&) still fires.
out=$(run_hook "$PROJ" 'git add -A && bd close loom-8vb' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'loom-8vb'; then
  pass "chained 'git add && bd close <id>' still fires (regression)"
else
  fail "chained bd close no longer detected (exit=$rc)" "$out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
