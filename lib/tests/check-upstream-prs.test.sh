#!/usr/bin/env bash
# Fixture tests for commands/check-upstream-prs.md.
#
# Closes loom-k2g.3: /check-upstream-prs slash command sweeps open
# upstream:watch beads, queries `gh pr view <url> --json
# state,mergedAt` for each, auto-closes MERGED, surfaces CLOSED
# (rejected) for user, no-ops on OPEN. Schedulable via the existing
# wake-up scheduler (no scheduling config tested here).
#
# Design source: drawer_loom_decisions_a6e64f9cfb21a9d16fc47604
# (loom/decisions wing).
#
# The slash command body is markdown — its load-bearing content is
# the bash blocks. We test the COMMAND body by extracting the bash
# pipeline and running it against PATH-shadowed `bd` and `gh` stubs.
# This mirrors the bd-stub pattern in bd-post-rewrite.test.sh.
#
# Run:  bash lib/tests/check-upstream-prs.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CMD="$LOOM_ROOT/commands/check-upstream-prs.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- Stub helpers ----------------------------------------------------
#
# Both stubs are scripts that read $1 (subcommand) and emit canned
# output. Driven by side-channel files (.bd-list, .gh-map, .bd-closes)
# so each test case can prepare fixtures without rewriting the stubs.

mk_stubs_dir() {
  local d
  d=$(mktemp -d)
  cat > "$d/bd" <<'EOF'
#!/usr/bin/env bash
# Stub bd. Supports:
#   bd list --label=upstream:watch --status=open --json  → cat $BD_LIST_FILE
#   bd close <id> --reason="..."                         → append to $BD_CLOSES_FILE
case "$1" in
  list)
    cat "$BD_LIST_FILE"
    ;;
  close)
    shift
    # Capture the close as "<id>\t<reason>" on one line.
    id="$1"; shift
    reason=""
    for a in "$@"; do
      case "$a" in
        --reason=*) reason="${a#--reason=}" ;;
      esac
    done
    printf '%s\t%s\n' "$id" "$reason" >> "$BD_CLOSES_FILE"
    ;;
  *)
    exit 1
    ;;
esac
EOF
  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
# Stub gh. Supports:
#   gh pr view <url> --json state,mergedAt
# Looks up <url> in $GH_MAP_FILE (one "url<TAB>json" line per URL).
# If URL not found, exits non-zero (malformed/unreachable simulation).
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  url="$3"
  line=$(grep -F "$url	" "$GH_MAP_FILE" 2>/dev/null | head -1)
  if [ -z "$line" ]; then
    echo "no such PR: $url" >&2
    exit 1
  fi
  # Print everything after the first tab.
  printf '%s\n' "${line#*	}"
  exit 0
fi
exit 1
EOF
  chmod +x "$d/bd" "$d/gh"
  echo "$d"
}

# Extract the bash sweep block from the command markdown. The command
# body wraps the sweep in a single ```bash ... ``` fence labeled with
# the sentinel comment "# SWEEP" on its first line. Tests run that
# block under set -uo pipefail with the stubs PATH-prepended.
extract_sweep() {
  awk '
    /^```bash$/ { in_fence=1; buf=""; next }
    /^```$/ && in_fence { in_fence=0; if (buf ~ /# SWEEP/) print buf; buf="" }
    in_fence { buf = buf $0 "\n" }
  ' "$CMD"
}

run_sweep() {
  # $1=bd_list_json $2=gh_map_lines
  local bd_list="$1"; local gh_map="$2"
  local stubs work
  stubs=$(mk_stubs_dir)
  work=$(mktemp -d)
  printf '%s' "$bd_list" > "$work/bd-list.json"
  printf '%s' "$gh_map"  > "$work/gh-map.tsv"
  : > "$work/closes.tsv"
  local sweep
  sweep=$(extract_sweep)
  if [ -z "$sweep" ]; then
    echo "SWEEP_EXTRACT_EMPTY" >&2
    rm -rf "$stubs" "$work"
    return 99
  fi
  local out rc
  out=$(
    PATH="$stubs:$PATH" \
    BD_LIST_FILE="$work/bd-list.json" \
    GH_MAP_FILE="$work/gh-map.tsv" \
    BD_CLOSES_FILE="$work/closes.tsv" \
    bash -c "set -uo pipefail; $sweep" 2>&1
  )
  rc=$?
  # Echo the closes file as a trailer for callers to grep.
  printf '%s\n---CLOSES---\n' "$out"
  cat "$work/closes.tsv"
  rm -rf "$stubs" "$work"
  return $rc
}

# -------------------------------------------------------------------
# 0. Command file exists and contains the SWEEP-tagged bash fence.
# -------------------------------------------------------------------

echo "==> 0. Command file shape"

if [ -f "$CMD" ]; then
  pass "commands/check-upstream-prs.md exists"
else
  fail "commands/check-upstream-prs.md missing"
fi

if [ -n "$(extract_sweep)" ]; then
  pass "extractable '# SWEEP'-tagged bash fence present"
else
  fail "no '# SWEEP'-tagged bash fence in command body (tests cannot run)"
fi

# -------------------------------------------------------------------
# 1. MERGED auto-close. A watch-bead whose PR URL resolves to
#    state=MERGED is closed via `bd close <id> --reason=...` that
#    references the PR URL. No close for OPEN beads in the same sweep.
# -------------------------------------------------------------------

echo "==> 1. MERGED → auto-close"

BD_LIST='[
  {"id":"loom-watch-1","description":"watch upstream foo/bar#42: https://github.com/foo/bar/pull/42"},
  {"id":"loom-watch-2","description":"watch upstream baz/qux#7: https://github.com/baz/qux/pull/7"}
]'
GH_MAP="https://github.com/foo/bar/pull/42	{\"state\":\"MERGED\",\"mergedAt\":\"2026-05-27T12:00:00Z\"}
https://github.com/baz/qux/pull/7	{\"state\":\"OPEN\",\"mergedAt\":null}"

result=$(run_sweep "$BD_LIST" "$GH_MAP"); rc=$?
closes=$(printf '%s' "$result" | awk '/^---CLOSES---$/{flag=1;next}flag')
report=$(printf '%s' "$result" | awk '/^---CLOSES---$/{exit}{print}')

if [ "$rc" -eq 0 ]; then pass "sweep exits 0"; else fail "sweep rc=$rc" "$result"; fi

if echo "$closes" | grep -q "^loom-watch-1	"; then
  pass "MERGED bead closed"
else
  fail "MERGED bead NOT closed" "$closes"
fi

if echo "$closes" | grep "^loom-watch-1	" | grep -q "https://github.com/foo/bar/pull/42"; then
  pass "close reason references PR URL"
else
  fail "close reason missing PR URL" "$closes"
fi

if echo "$closes" | grep -q "^loom-watch-2	"; then
  fail "OPEN bead was closed (should be no-op)" "$closes"
else
  pass "OPEN bead NOT closed in same sweep"
fi

# -------------------------------------------------------------------
# 2. CLOSED (rejected) → surface for user, do NOT auto-close.
#    Sweep output names the bead + PR URL + the CLOSED state so the
#    user can read the report and decide whether to manually close.
# -------------------------------------------------------------------

echo "==> 2. CLOSED → surface to user, no auto-close"

BD_LIST='[
  {"id":"loom-watch-3","description":"watch upstream foo/bar#99: https://github.com/foo/bar/pull/99"}
]'
GH_MAP="https://github.com/foo/bar/pull/99	{\"state\":\"CLOSED\",\"mergedAt\":null}"

result=$(run_sweep "$BD_LIST" "$GH_MAP"); rc=$?
closes=$(printf '%s' "$result" | awk '/^---CLOSES---$/{flag=1;next}flag')
report=$(printf '%s' "$result" | awk '/^---CLOSES---$/{exit}{print}')

if [ "$rc" -eq 0 ]; then pass "sweep exits 0 with CLOSED present"; else fail "sweep rc=$rc" "$result"; fi

if [ -z "$closes" ]; then
  pass "CLOSED bead NOT auto-closed (waits for user)"
else
  fail "CLOSED bead was auto-closed (should surface only)" "$closes"
fi

if echo "$report" | grep -q "loom-watch-3" && \
   echo "$report" | grep -q "https://github.com/foo/bar/pull/99" && \
   echo "$report" | grep -qi "closed\|rejected"; then
  pass "report surfaces CLOSED bead with PR URL + state"
else
  fail "report missing CLOSED surfacing" "$report"
fi

# -------------------------------------------------------------------
# 3. OPEN → no-op. The bead stays open, no close written, the report
#    may either be silent or list the bead as 'still open'.
# -------------------------------------------------------------------

echo "==> 3. OPEN → no-op"

BD_LIST='[
  {"id":"loom-watch-4","description":"watch upstream foo/bar#5: https://github.com/foo/bar/pull/5"}
]'
GH_MAP="https://github.com/foo/bar/pull/5	{\"state\":\"OPEN\",\"mergedAt\":null}"

result=$(run_sweep "$BD_LIST" "$GH_MAP"); rc=$?
closes=$(printf '%s' "$result" | awk '/^---CLOSES---$/{flag=1;next}flag')

if [ "$rc" -eq 0 ]; then pass "sweep exits 0 on all-OPEN list"; else fail "sweep rc=$rc" "$result"; fi

if [ -z "$closes" ]; then
  pass "OPEN bead: no close written"
else
  fail "OPEN bead was closed (should be no-op)" "$closes"
fi

# -------------------------------------------------------------------
# 4. Malformed URL / unreachable PR → graceful skip, sweep continues
#    on remaining beads. Failure to query one PR must NOT abort the
#    whole sweep (each bead is independent).
# -------------------------------------------------------------------

echo "==> 4. Malformed/unreachable URL → graceful skip"

BD_LIST='[
  {"id":"loom-watch-5","description":"watch upstream noop/no#x: https://github.com/noop/no/pull/x"},
  {"id":"loom-watch-6","description":"watch upstream foo/bar#10: https://github.com/foo/bar/pull/10"}
]'
# Only watch-6 has a gh-map entry. watch-5's URL will return non-zero
# from the gh stub.
GH_MAP="https://github.com/foo/bar/pull/10	{\"state\":\"MERGED\",\"mergedAt\":\"2026-05-27T13:00:00Z\"}"

result=$(run_sweep "$BD_LIST" "$GH_MAP"); rc=$?
closes=$(printf '%s' "$result" | awk '/^---CLOSES---$/{flag=1;next}flag')
report=$(printf '%s' "$result" | awk '/^---CLOSES---$/{exit}{print}')

if [ "$rc" -eq 0 ]; then
  pass "sweep exits 0 despite one unreachable URL (graceful)"
else
  fail "sweep aborted on unreachable URL (rc=$rc)" "$result"
fi

if echo "$closes" | grep -q "^loom-watch-6	"; then
  pass "sweep continued past unreachable URL and closed valid MERGED bead"
else
  fail "sweep did NOT continue past unreachable URL" "$closes"
fi

if echo "$report" | grep -q "loom-watch-5"; then
  pass "skipped bead surfaced in report (visibility for user)"
else
  fail "skipped bead not surfaced (silent skip — should be visible)" "$report"
fi

# -------------------------------------------------------------------
# 5. Empty watch list → no-op, exit 0, no closes written.
# -------------------------------------------------------------------

echo "==> 5. Empty watch list → no-op"

result=$(run_sweep '[]' ''); rc=$?
closes=$(printf '%s' "$result" | awk '/^---CLOSES---$/{flag=1;next}flag')

if [ "$rc" -eq 0 ]; then pass "empty list: sweep exits 0"; else fail "empty list rc=$rc" "$result"; fi
if [ -z "$closes" ]; then pass "empty list: no closes"; else fail "empty list: spurious close" "$closes"; fi

# -------------------------------------------------------------------
# 6. Bead description without a parseable PR URL → graceful skip,
#    surface to user. Watch-beads should always carry the PR URL per
#    upstream-a-bead M7 convention, but a malformed/legacy bead must
#    not crash the sweep.
# -------------------------------------------------------------------

echo "==> 6. Bead without PR URL → graceful skip"

BD_LIST='[
  {"id":"loom-watch-7","description":"watch upstream foo/bar: (PR URL missing — legacy bead)"}
]'
result=$(run_sweep "$BD_LIST" ''); rc=$?
closes=$(printf '%s' "$result" | awk '/^---CLOSES---$/{flag=1;next}flag')
report=$(printf '%s' "$result" | awk '/^---CLOSES---$/{exit}{print}')

if [ "$rc" -eq 0 ]; then pass "no-URL bead: sweep exits 0"; else fail "no-URL bead rc=$rc" "$result"; fi
if [ -z "$closes" ]; then pass "no-URL bead: not closed"; else fail "no-URL bead: spurious close" "$closes"; fi
if echo "$report" | grep -q "loom-watch-7"; then
  pass "no-URL bead surfaced in report"
else
  fail "no-URL bead silently skipped (should surface)" "$report"
fi

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
