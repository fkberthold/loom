#!/usr/bin/env bash
# Fixture tests for the per-bead dispatch field + session drift counters.
#
# Closes loom-0zr (T1 of epic loom-yb5): add a `dispatch` field to
# workflow-state recording how the current bead was worked
# (`worker` = dispatched to a parallel worker, `inline:<reason>` =
# worked inline in the central session with a stated reason), plus
# two session-scoped counters that tally drift away from the
# dispatch-preferred default:
#   - `dispatched`: count of `dispatch=worker` sets this session
#   - `inline`:     count of `dispatch=inline:...` sets this session
# Both counters INCREMENT on each matching `set` (they are running
# tallies, not last-write-wins overrides like `dispatch` itself).
#
# Statusline surfaces the dispatch chip + "inline:N/dispatched:M"
# when either counter is non-zero.
#
# Mirrors the parallel_candidates precedent (loom-z3m.5) for the
# state-file shape, integer-field handling, and statusline-surfacing
# conventions.
#
# Run:  bash lib/tests/dispatch-state.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WS="$LOOM_ROOT/scripts/workflow-state"
SL="$LOOM_ROOT/scripts/statusline.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# Minimal beads workspace with workflow.json + workflow-state.
mk_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"claim","updated":"2026-06-06T00:00:00Z"}\n' \
    > "$d/.claude/workflow-state.json"
  printf '%s' "$d"
}

# -------------------------------------------------------------------
# 1. Unset is a valid initial state
# -------------------------------------------------------------------

echo "==> 1. dispatch unset initially"
proj=$(mk_project)
val=$(bash "$WS" get dispatch "$proj")
if [ -z "$val" ]; then
  pass "dispatch reads empty when unset"
else
  fail "dispatch expected empty initially, got '$val'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 2. set dispatch=worker round-trips
# -------------------------------------------------------------------

echo "==> 2. dispatch=worker round-trip"
proj=$(mk_project)
bash "$WS" set "--start-dir=$proj" dispatch=worker >/dev/null 2>&1
val=$(bash "$WS" get dispatch "$proj")
if [ "$val" = "worker" ]; then
  pass "dispatch=worker round-trips via get"
else
  fail "dispatch=worker expected 'worker', got '$val'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 3. set dispatch=inline:<reason> round-trips (reason preserved)
# -------------------------------------------------------------------

echo "==> 3. dispatch=inline:<reason> round-trip"
proj=$(mk_project)
bash "$WS" set "--start-dir=$proj" "dispatch=inline:single-file-tweak" >/dev/null 2>&1
val=$(bash "$WS" get dispatch "$proj")
if [ "$val" = "inline:single-file-tweak" ]; then
  pass "dispatch=inline:<reason> round-trips with reason intact"
else
  fail "dispatch=inline expected 'inline:single-file-tweak', got '$val'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 4. dispatch=worker increments `dispatched` counter
# -------------------------------------------------------------------

echo "==> 4. dispatch=worker increments dispatched counter"
proj=$(mk_project)
bash "$WS" set "--start-dir=$proj" dispatch=worker >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" dispatch=worker >/dev/null 2>&1
d=$(bash "$WS" get dispatched "$proj")
i=$(bash "$WS" get inline "$proj")
if [ "$d" = "2" ]; then
  pass "two dispatch=worker sets → dispatched=2"
else
  fail "dispatched expected 2, got '$d'"
fi
if [ "$i" = "0" ] || [ -z "$i" ]; then
  pass "inline counter untouched by worker sets (=0/empty)"
else
  fail "inline expected 0/empty, got '$i'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 5. dispatch=inline:... increments `inline` counter
# -------------------------------------------------------------------

echo "==> 5. dispatch=inline increments inline counter"
proj=$(mk_project)
bash "$WS" set "--start-dir=$proj" "dispatch=inline:reason-a" >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" "dispatch=inline:reason-b" >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" "dispatch=inline:reason-c" >/dev/null 2>&1
i=$(bash "$WS" get inline "$proj")
d=$(bash "$WS" get dispatched "$proj")
if [ "$i" = "3" ]; then
  pass "three dispatch=inline sets → inline=3"
else
  fail "inline expected 3, got '$i'"
fi
if [ "$d" = "0" ] || [ -z "$d" ]; then
  pass "dispatched counter untouched by inline sets (=0/empty)"
else
  fail "dispatched expected 0/empty, got '$d'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 6. Mixed: counters accumulate independently; dispatch=latest
# -------------------------------------------------------------------

echo "==> 6. mixed sets — counters independent, dispatch latest-wins"
proj=$(mk_project)
bash "$WS" set "--start-dir=$proj" dispatch=worker >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" "dispatch=inline:why" >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" dispatch=worker >/dev/null 2>&1
d=$(bash "$WS" get dispatched "$proj")
i=$(bash "$WS" get inline "$proj")
cur=$(bash "$WS" get dispatch "$proj")
if [ "$d" = "2" ] && [ "$i" = "1" ]; then
  pass "mixed: dispatched=2 inline=1"
else
  fail "mixed: expected dispatched=2 inline=1, got dispatched=$d inline=$i"
fi
if [ "$cur" = "worker" ]; then
  pass "mixed: dispatch reflects latest set (worker)"
else
  fail "mixed: dispatch expected 'worker', got '$cur'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 7. dispatch_counts compound getter → inline:N/dispatched:M
# -------------------------------------------------------------------

echo "==> 7. get dispatch_counts → inline:N/dispatched:M"
proj=$(mk_project)
bash "$WS" set "--start-dir=$proj" dispatch=worker >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" "dispatch=inline:x" >/dev/null 2>&1
bash "$WS" set "--start-dir=$proj" "dispatch=inline:y" >/dev/null 2>&1
counts=$(bash "$WS" get dispatch_counts "$proj")
if [ "$counts" = "inline:2/dispatched:1" ]; then
  pass "dispatch_counts → 'inline:2/dispatched:1'"
else
  fail "dispatch_counts expected 'inline:2/dispatched:1', got '$counts'"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 8. Statusline surfaces dispatch value + counts when set
# -------------------------------------------------------------------

echo "==> 8. statusline shows dispatch + inline:N/dispatched:M"
proj=$(mk_project)
cat > "$proj/.claude/workflow-state.json" <<'EOF'
{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"claim","dispatch":"worker","dispatched":3,"inline":1,"updated":"2026-06-06T00:00:00Z"}
EOF
out=$(printf '{"cwd":"%s"}' "$proj" | bash "$SL" 2>&1)
if echo "$out" | grep -q "worker"; then
  pass "statusline: dispatch value 'worker' shown"
else
  fail "statusline: dispatch value missing" "$out"
fi
if echo "$out" | grep -q "inline:1/dispatched:3"; then
  pass "statusline: 'inline:1/dispatched:3' shown"
else
  fail "statusline: counts missing" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 9. Statusline omits dispatch chip when unset and counters zero/missing
# -------------------------------------------------------------------

echo "==> 9. statusline omits dispatch when unset + counters 0"
proj=$(mk_project)
cat > "$proj/.claude/workflow-state.json" <<'EOF'
{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"claim","updated":"2026-06-06T00:00:00Z"}
EOF
out=$(printf '{"cwd":"%s"}' "$proj" | bash "$SL" 2>&1)
if ! echo "$out" | grep -qE "dispatched:|inline:"; then
  pass "statusline: no dispatch counts when field missing"
else
  fail "statusline: dispatch counts leaked when unset" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
