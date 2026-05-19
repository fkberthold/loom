#!/usr/bin/env bash
# Fixture tests for scripts/loom-seam-scan.
#
# Closes loom-z3m.5: claim-phase seam scan that emits a one-line
# "Parallelizable: N candidates (...)" summary and writes
# `parallel_candidates` to workflow-state. Statusline surfaces
# "PAR:N" when N>0.
#
# Heuristic (documented in script + commit message):
#   The bead JSON has no structured `files` field, so the scan
#   extracts path-shaped tokens (`[A-Za-z0-9_./-]+\.(md|sh|py|...)`)
#   from each ready bead's design + description + notes. Two beads
#   are "disjoint" if their extracted path-sets do not overlap.
#   Candidates = sibling beads (same `parent` as the claimed bead)
#   that are disjoint with the claimed bead AND with each other.
#
# Run:  bash lib/tests/loom-seam-scan.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-seam-scan"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# Build a synthetic bd-ready-json fixture file. Each bead is one JSON
# object. The script reads from $LOOM_SEAM_SCAN_READY_JSON when set —
# this gives tests a sidedoor that bypasses live `bd ready`.
#
# Args: out-file claimed-id parent-id then triples of (id paths_csv).
#   paths_csv is comma-separated list of path tokens that will be
#   stuffed into the bead's design field.
mk_ready_json() {
  local out="$1"; shift
  local claimed_id="$1"; shift
  local parent_id="$1"; shift

  local first=1
  printf '[' > "$out"
  while [ $# -ge 2 ]; do
    local id="$1"; local paths_csv="$2"; shift 2
    [ $first -eq 1 ] || printf ',' >> "$out"
    first=0
    # Convert csv to a space-joined paths string for the design field.
    local paths_text
    paths_text=$(printf '%s' "$paths_csv" | tr ',' ' ')
    jq -nc --arg id "$id" \
           --arg parent "$parent_id" \
           --arg design "Touches files: $paths_text" \
      '{id:$id, parent:$parent, status:"open", priority:2,
        title:"test bead", description:"", design:$design, notes:""}' \
      >> "$out"
  done
  printf ']\n' >> "$out"
}

# Build a minimal beads workspace with workflow.json + workflow-state.
mk_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '{"v":1,"mode":"full","activity":"feature","bead":null,"stage":"idle","updated":"2026-05-19T00:00:00Z"}\n' \
    > "$d/.claude/workflow-state.json"
  printf '%s' "$d"
}

# -------------------------------------------------------------------
# 1. Single ready bead → 0 candidates
# -------------------------------------------------------------------

echo "==> 1. Single ready bead → 0 candidates"
proj=$(mk_project)
ready_json="$proj/ready.json"
mk_ready_json "$ready_json" "loom-aaa" "loom-epic" \
  "loom-aaa" "skills/foo/SKILL.md"

out=$(LOOM_SEAM_SCAN_READY_JSON="$ready_json" \
      LOOM_SEAM_SCAN_PROJECT="$proj" \
      bash "$SCRIPT" "loom-aaa" 2>&1); rc=$?

if [ "$rc" -eq 0 ] && echo "$out" | grep -q "Parallelizable: none"; then
  pass "single ready bead: emits 'Parallelizable: none'"
else
  fail "single ready bead: unexpected output (rc=$rc)" "$out"
fi

# workflow-state parallel_candidates should be 0
pc=$(jq -r '.parallel_candidates // 0' "$proj/.claude/workflow-state.json")
if [ "$pc" = "0" ]; then
  pass "single ready: workflow-state parallel_candidates=0"
else
  fail "single ready: workflow-state parallel_candidates expected 0, got $pc"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 2. 3 siblings disjoint files → 2 candidates (excluding claimed)
# -------------------------------------------------------------------

echo "==> 2. 3 disjoint siblings → 2 candidates"
proj=$(mk_project)
ready_json="$proj/ready.json"
mk_ready_json "$ready_json" "loom-aaa" "loom-epic" \
  "loom-aaa" "skills/foo/SKILL.md" \
  "loom-bbb" "scripts/bar.sh" \
  "loom-ccc" "hooks/baz.sh"

out=$(LOOM_SEAM_SCAN_READY_JSON="$ready_json" \
      LOOM_SEAM_SCAN_PROJECT="$proj" \
      bash "$SCRIPT" "loom-aaa" 2>&1); rc=$?

if [ "$rc" -eq 0 ] && echo "$out" | grep -qE "Parallelizable: 2 candidates"; then
  pass "3 disjoint siblings: emits 'Parallelizable: 2 candidates'"
else
  fail "3 disjoint siblings: unexpected output (rc=$rc)" "$out"
fi

# Output should name both candidate IDs
if echo "$out" | grep -q "loom-bbb" && echo "$out" | grep -q "loom-ccc"; then
  pass "3 disjoint siblings: both candidate IDs in output"
else
  fail "3 disjoint siblings: candidate IDs missing" "$out"
fi

pc=$(jq -r '.parallel_candidates // 0' "$proj/.claude/workflow-state.json")
if [ "$pc" = "2" ]; then
  pass "3 disjoint siblings: workflow-state parallel_candidates=2"
else
  fail "3 disjoint siblings: workflow-state parallel_candidates expected 2, got $pc"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 3. 3 siblings sharing one file → 0 candidates
# -------------------------------------------------------------------

echo "==> 3. 3 siblings share a file → 0 candidates"
proj=$(mk_project)
ready_json="$proj/ready.json"
mk_ready_json "$ready_json" "loom-aaa" "loom-epic" \
  "loom-aaa" "skills/shell/SKILL.md,skills/foo/SKILL.md" \
  "loom-bbb" "skills/shell/SKILL.md,scripts/bar.sh" \
  "loom-ccc" "skills/shell/SKILL.md,hooks/baz.sh"

out=$(LOOM_SEAM_SCAN_READY_JSON="$ready_json" \
      LOOM_SEAM_SCAN_PROJECT="$proj" \
      bash "$SCRIPT" "loom-aaa" 2>&1); rc=$?

if [ "$rc" -eq 0 ] && echo "$out" | grep -q "Parallelizable: none"; then
  pass "shared-file siblings: emits 'Parallelizable: none'"
else
  fail "shared-file siblings: unexpected output (rc=$rc)" "$out"
fi

pc=$(jq -r '.parallel_candidates // 0' "$proj/.claude/workflow-state.json")
if [ "$pc" = "0" ]; then
  pass "shared-file siblings: workflow-state parallel_candidates=0"
else
  fail "shared-file siblings: parallel_candidates expected 0, got $pc"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 4. Non-sibling beads (different parent) ignored
# -------------------------------------------------------------------

echo "==> 4. Non-sibling beads ignored"
proj=$(mk_project)
ready_json="$proj/ready.json"
# Build manually: claimed under epic-X, others under epic-Y
{
  printf '['
  jq -nc '{id:"loom-aaa", parent:"epic-X", status:"open", priority:2,
           title:"a", description:"", design:"skills/foo/SKILL.md", notes:""}'
  printf ','
  jq -nc '{id:"loom-bbb", parent:"epic-Y", status:"open", priority:2,
           title:"b", description:"", design:"scripts/bar.sh", notes:""}'
  printf ','
  jq -nc '{id:"loom-ccc", parent:"epic-Y", status:"open", priority:2,
           title:"c", description:"", design:"hooks/baz.sh", notes:""}'
  printf ']\n'
} > "$ready_json"

out=$(LOOM_SEAM_SCAN_READY_JSON="$ready_json" \
      LOOM_SEAM_SCAN_PROJECT="$proj" \
      bash "$SCRIPT" "loom-aaa" 2>&1); rc=$?

if [ "$rc" -eq 0 ] && echo "$out" | grep -q "Parallelizable: none"; then
  pass "non-sibling beads: emits 'Parallelizable: none'"
else
  fail "non-sibling beads: unexpected output (rc=$rc)" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 5. Mixed: 1 disjoint sibling, 1 sharing-file sibling → 1 candidate
# -------------------------------------------------------------------

echo "==> 5. Mixed disjoint+shared → 1 candidate"
proj=$(mk_project)
ready_json="$proj/ready.json"
mk_ready_json "$ready_json" "loom-aaa" "loom-epic" \
  "loom-aaa" "skills/foo/SKILL.md" \
  "loom-bbb" "scripts/bar.sh" \
  "loom-ccc" "skills/foo/SKILL.md,hooks/baz.sh"

out=$(LOOM_SEAM_SCAN_READY_JSON="$ready_json" \
      LOOM_SEAM_SCAN_PROJECT="$proj" \
      bash "$SCRIPT" "loom-aaa" 2>&1); rc=$?

if [ "$rc" -eq 0 ] && echo "$out" | grep -qE "Parallelizable: 1 candidate"; then
  pass "mixed: emits 'Parallelizable: 1 candidate'"
else
  fail "mixed: unexpected output (rc=$rc)" "$out"
fi

if echo "$out" | grep -q "loom-bbb"; then
  pass "mixed: disjoint sibling listed"
else
  fail "mixed: disjoint sibling not listed" "$out"
fi

# loom-ccc shares with claimed, should NOT be listed
if ! echo "$out" | grep -q "loom-ccc"; then
  pass "mixed: shared-file sibling excluded"
else
  fail "mixed: shared-file sibling leaked into list" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 6. Claimed bead missing from ready-json → graceful failure (rc 0, none)
# -------------------------------------------------------------------

echo "==> 6. Claimed bead missing from ready list"
proj=$(mk_project)
ready_json="$proj/ready.json"
mk_ready_json "$ready_json" "loom-zzz" "loom-epic" \
  "loom-bbb" "scripts/bar.sh"

out=$(LOOM_SEAM_SCAN_READY_JSON="$ready_json" \
      LOOM_SEAM_SCAN_PROJECT="$proj" \
      bash "$SCRIPT" "loom-zzz" 2>&1); rc=$?

# Bead not in ready means it's already claimed (status changed) — that's
# expected and normal. Emit "Parallelizable: none" + rc=0.
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "Parallelizable: none"; then
  pass "claimed bead missing: graceful 'Parallelizable: none'"
else
  fail "claimed bead missing: rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 7. Statusline surfaces PAR:N when parallel_candidates>0
# -------------------------------------------------------------------

echo "==> 7. Statusline shows PAR:N"
proj=$(mk_project)
# Set workflow-state with parallel_candidates=3 + active bead.
cat > "$proj/.claude/workflow-state.json" <<'EOF'
{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"claim","parallel_candidates":3,"updated":"2026-05-19T00:00:00Z"}
EOF
out=$(printf '{"cwd":"%s"}' "$proj" | bash "$LOOM_ROOT/scripts/statusline.sh" 2>&1)
if echo "$out" | grep -q "PAR:3"; then
  pass "statusline: PAR:3 shown when parallel_candidates=3"
else
  fail "statusline: PAR:3 missing" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 8. Statusline omits PAR when parallel_candidates=0 or missing
# -------------------------------------------------------------------

echo "==> 8. Statusline omits PAR:0"
proj=$(mk_project)
cat > "$proj/.claude/workflow-state.json" <<'EOF'
{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"claim","parallel_candidates":0,"updated":"2026-05-19T00:00:00Z"}
EOF
out=$(printf '{"cwd":"%s"}' "$proj" | bash "$LOOM_ROOT/scripts/statusline.sh" 2>&1)
if ! echo "$out" | grep -q "PAR:"; then
  pass "statusline: PAR omitted when parallel_candidates=0"
else
  fail "statusline: PAR shown for 0" "$out"
fi

# Also: omitted entirely when field missing.
cat > "$proj/.claude/workflow-state.json" <<'EOF'
{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"claim","updated":"2026-05-19T00:00:00Z"}
EOF
out=$(printf '{"cwd":"%s"}' "$proj" | bash "$LOOM_ROOT/scripts/statusline.sh" 2>&1)
if ! echo "$out" | grep -q "PAR:"; then
  pass "statusline: PAR omitted when field missing"
else
  fail "statusline: PAR shown when field missing" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 9. workflow-state set parallel_candidates=N is persisted via CLI
# -------------------------------------------------------------------

echo "==> 9. workflow-state CLI accepts parallel_candidates"
proj=$(mk_project)
bash "$LOOM_ROOT/scripts/workflow-state" set "--start-dir=$proj" parallel_candidates=5 >/dev/null 2>&1
# read it back
pc=$(jq -r '.parallel_candidates // 0' "$proj/.claude/workflow-state.json")
if [ "$pc" = "5" ]; then
  pass "workflow-state set parallel_candidates=5 persisted"
else
  fail "workflow-state set parallel_candidates=5 NOT persisted (got '$pc')"
fi
rm -rf "$proj"

# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
