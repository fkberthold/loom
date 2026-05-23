#!/usr/bin/env bash
# Fixture tests for hooks/bd-close-capture.sh prefix-regex coverage.
#
# Bead: loom-z3m.8 (retroactive filing for loom-2t7 — widen prefix class
# from [a-z][a-z0-9_]*- to [a-z][a-z0-9_-]*- so HAW-style multi-hyphen
# prefixes like `hundred-acre-woods` no longer require --force bypass).
#
# This file is intentionally narrow: prefix-shape acceptance + rejection
# of malformed bead-ID shapes. The broader matcher / bypass coverage
# lives in lib/tests/bd-close-capture.test.sh.
#
# Run:  bash lib/tests/bd-close-capture-prefix.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-close-capture.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook with a controlled env. We deliberately point the hook at
# an empty palace and a no-memories bd stub so that ANY parseable bead
# ID falls through to a "no capture evidence" block (exit 2) whose
# stderr surfaces the parsed bead ID in the "No capture evidence found
# for <id>" header. That header is the observation channel we grep for
# acceptance; the distinct "Could not parse bead ID" header is what we
# grep for rejection.
run_hook() {
  local proj="$1" cmd="$2"
  local mp="${3:-$NULL_PALACE}"
  local bdb="${4:-$NULL_BD}"
  local payload
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  (cd "$proj" && MEMPALACE_HOME="$mp" BD_BIN="$bdb" \
    bash "$HOOK" <<<"$payload" 2>&1)
}

# ---------------------------------------------------------------------------
# Fixtures (minimal — empty palace + empty bd stub + full-mode project)
# ---------------------------------------------------------------------------

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

mk_proj_full() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.claude"
  echo '{"v":1,"mode":"full"}' > "$dir/.claude/workflow.json"
  echo "$dir"
}

NULL_BD=$(mk_bd_stub "No memories matching")
NULL_PALACE=$(mktemp -d)
mk_empty_palace "$NULL_PALACE"
PROJ=$(mk_proj_full)

trap 'rm -rf "$PROJ" "$NULL_PALACE" "$NULL_BD"' EXIT

# ---------------------------------------------------------------------------
# 1. Accept — prefix shapes the regex MUST tolerate
# ---------------------------------------------------------------------------
#
# "Accept" here means: the bead-ID regex parses the token, the hook
# falls through to the artifact-matcher kernel against an empty palace,
# and produces the "No capture evidence found for <id>" block message
# at exit 2. Grepping for the bead-ID in that block confirms the regex
# accepted it.

echo "==> 1. Accepted prefix shapes (regex MUST tolerate)"

# Underscore prefix — liza_base-style projects.
out=$(run_hook "$PROJ" 'bd close liza_base-xxx' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qE 'No capture evidence found for liza_base-xxx'; then
  pass "underscore prefix (liza_base-xxx) accepted by regex"
else
  fail "underscore prefix rejected" "$out"
fi

# Hyphen prefix — HAW-style projects (hundred-acre-woods). The regression
# loom-z3m.8 / loom-2t7 fixes: prior regex [a-z][a-z0-9_]*- rejected
# hyphens in the prefix class.
out=$(run_hook "$PROJ" 'bd close hundred-acre-woods-xxx' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qE 'No capture evidence found for hundred-acre-woods-xxx'; then
  pass "hyphen prefix (hundred-acre-woods-xxx) accepted by regex (loom-z3m.8)"
else
  fail "hyphen prefix still rejected — regex regression" "$out"
fi

# Single-letter prefix — minimal prefix the regex must still allow
# (`[a-z][a-z0-9_-]*-` permits the leading [a-z] alone).
out=$(run_hook "$PROJ" 'bd close a-xxx' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qE 'No capture evidence found for a-xxx'; then
  pass "single-letter prefix (a-xxx) accepted by regex"
else
  fail "single-letter prefix rejected" "$out"
fi

# ---------------------------------------------------------------------------
# 2. Reject — malformed bead-ID shapes the regex MUST refuse
# ---------------------------------------------------------------------------
#
# When no token matches the bead-ID regex, the hook hits the "bare
# `bd close`" branch and emits the "Could not parse bead ID" header.
# That header is the observation channel for rejection.

echo "==> 2. Rejected shapes (regex MUST refuse)"

# No suffix at all — `foo-` has no hash-suffix component.
out=$(run_hook "$PROJ" 'bd close foo-' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "no-suffix shape (foo-) rejected — distinct parse-error block"
else
  fail "no-suffix shape (foo-) leaked through" "$out"
fi

# Suffix too short — `foo-ab` has only 2 chars after the final hyphen
# but the regex requires {3,}.
out=$(run_hook "$PROJ" 'bd close foo-ab' "$NULL_PALACE" "$NULL_BD"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Could not parse bead ID'; then
  pass "suffix-too-short shape (foo-ab, 2 chars) rejected — {3,} guard"
else
  fail "2-char suffix passed regex (suffix-length guard regressed)" "$out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
