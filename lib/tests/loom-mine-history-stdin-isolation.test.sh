#!/usr/bin/env bash
# Fixture test for lib/loom-mine-history.sh — the SALIENCE-CALL STDIN-LEAK
# bug (rnxp re-mine investigation, 2026-06-09 night).
#
# BUG (root cause, diagnosed empirically):
#   The salience loop iterates survivors with
#     while IFS=$'\t' read -r ... ; do
#       reply=$(claude -p "$prompt" --model "$model" --output-format text 2>err)
#       ...
#     done < "$survivors"
#   Every command inside the loop inherits the loop's stdin — the
#   "$survivors" file descriptor, positioned AFTER the current line.
#   `claude -p` in print mode READS that stdin: with a large survivors
#   stream it slurps the remaining units and folds them into its reply
#   (observed: a reply that explicitly discussed "filler0002-filler0400").
#   The per-unit reply is derailed (no clean {"salient":...} for THIS
#   unit) AND the loop's own read position is corrupted. On a real
#   large-repo mine this produced 0/787, 0/353, and a 4/4 abort — the
#   deeper blocker that survived loom-b10 (body truncation), loom-bzl
#   (fence strip), and loom-ug4p (abort-loud). A capped 10-unit run
#   masked it: 9 tiny remaining lines don't derail the reply.
#
# THE FIX this test pins:
#   The salience claude call must redirect stdin from /dev/null so it
#   NEVER reads the survivors stream:
#     reply=$(claude -p "$prompt" ... </dev/null 2>err)
#
# Test strategy (mirrors loom-mine-history-claude-failure.test.sh):
#   - PATH-prepended `claude` + `gh` stubs.
#   - The `claude` stub here is a STDIN-WITNESS: it reads its stdin and,
#     if ANY bytes arrive, records a leak marker to CLAUDE_STDIN_LEAK_FILE.
#     With the fix (</dev/null) stdin is empty → no marker. Without it,
#     the survivors fd leaks in → marker present.
#   - A REAL temp git repo with several substantial decision commits, so
#     the salience pass runs over >= 2 survivors (a non-empty remaining
#     stream after line 1).
#
# Run:  bash lib/tests/loom-mine-history-stdin-isolation.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-mine-history.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- Stub directory --------------------------------------------------
#
# `gh` degrades to git-only (auth fails). `claude` is a STDIN-WITNESS:
#   - reads ALL of stdin (non-blocking against a regular file / /dev/null),
#   - if stdin carried ANY bytes, append a "LEAK" line to
#     CLAUDE_STDIN_LEAK_FILE (the survivors stream leaked in),
#   - always emits a valid salient reply + exits 0 (we are testing stdin
#     isolation, not the failure path).
mk_stubs_dir() {
  local d
  d=$(mktemp -d)

  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) exit 1 ;;
  pr)   echo "[]" ;;
  api)  : ;;
  *)    exit 1 ;;
esac
EOF

  cat > "$d/claude" <<'EOF'
#!/usr/bin/env bash
# STDIN-WITNESS stub. Reads stdin; records a leak if non-empty.
stdin_data=$(cat 2>/dev/null)
if [ -n "$stdin_data" ] && [ -n "${CLAUDE_STDIN_LEAK_FILE:-}" ]; then
  printf 'LEAK %d bytes\n' "${#stdin_data}" >> "$CLAUDE_STDIN_LEAK_FILE"
fi
# Always a valid, successful, SALIENT reply.
echo '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}'
EOF

  chmod +x "$d/gh" "$d/claude"
  echo "$d"
}

# --- git fixture repo: several survivors ------------------------------
mk_fixture_repo_many() {
  local work repo
  work=$(mktemp -d)
  repo="$work/repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email miner@test
    git config user.name "Decision Miner"

    echo "base" > README.md
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "initial"

    local i
    for i in 1 2 3 4 5 6; do
      cat > "schema_$i.sql" <<SQL
CREATE TABLE t$i (id INT PRIMARY KEY, body TEXT);
SQL
      git add -A
      git -c core.hooksPath=/dev/null commit -q -m "Add schema variant $i

We chose design variant $i over the alternative because query latency
on the hot read path dominates; the trade-off is heavier migrations but
faster reads. Decision recorded for downstream consumers."
    done
  ) || { echo "FIXTURE_BUILD_FAILED" >&2; return 1; }
  echo "$repo"
}

run_mine() {
  local repo="$1"; shift
  (
    PATH="$STUBS:$PATH" bash -c '
      set -uo pipefail
      source "$1"; shift
      loom_mine_history "$@"
    ' _ "$LIB" "$repo" "$@"
  ) 2>&1
}

# =====================================================================
# 1. STDIN ISOLATION — the salience claude call must NOT receive the
#    survivors stream on stdin. With the fix (</dev/null) the witness
#    stub sees empty stdin; without it, the survivors fd leaks in.
# =====================================================================
echo "==> 1. Salience claude call gets EMPTY stdin (no survivors-stream leak)"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo_many)
OUT=$(mktemp -d)
LEAK=$(mktemp)
: > "$LEAK"

export GH_AUTH_OK=0
export CLAUDE_STDIN_LEAK_FILE="$LEAK"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

# 1a. No leak marker → claude received empty stdin on every call.
if [ ! -s "$LEAK" ]; then
  pass "salience claude call received empty stdin (no survivors leak)"
else
  fail "survivors stream LEAKED into claude stdin (missing </dev/null)" "$(cat "$LEAK")"
fi

# 1b. Sanity: the salience pass actually ran (the engine reached claude).
if [ -s "$OUT/drafts.jsonl" ]; then
  pass "salience pass ran (drafts emitted)"
else
  fail "salience pass did not run — no drafts emitted" "$out"
fi

# 1c. Sanity: with isolated stdin the loop processes ALL survivors, not
#     just the first (a leaked read corrupts the loop's own iteration).
#     >= 2 processed proves the loop wasn't truncated by a stdin drain.
processed=0
[ -f "$OUT/.processed" ] && processed=$(grep -c . "$OUT/.processed" 2>/dev/null)
processed=${processed:-0}
if [ "$processed" -ge 2 ]; then
  pass "loop processed all survivors (.processed=$processed, not stdin-truncated)"
else
  fail "loop processed only $processed unit(s) — stdin drain truncated iteration" "$out"
fi

# =====================================================================
# 2. STRUCTURAL pin — the salience claude call redirects stdin from
#    /dev/null. Defense-in-depth alongside the behavioral witness above:
#    documents the exact fix mechanism so a future refactor that drops
#    the redirect is caught at the source, not only at runtime.
# =====================================================================
echo "==> 2. Salience claude call source carries </dev/null"

if grep -E 'claude -p "\$prompt".*</dev/null' "$LIB" >/dev/null 2>&1; then
  pass "salience claude -p call redirects stdin from /dev/null"
else
  fail "salience claude -p call is missing </dev/null (source pin)" \
       "$(grep -n 'claude -p "\$prompt"' "$LIB")"
fi

# =====================================================================
# Summary
# =====================================================================
echo
echo "loom-mine-history-stdin-isolation: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
