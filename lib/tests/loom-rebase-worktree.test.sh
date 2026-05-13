#!/usr/bin/env bash
# Fixture tests for scripts/loom-rebase-worktree.
#
# Closes loom-azt (split from loom-35b symptom 2): wraps `git rebase`
# in a worktree so untracked WIP files survive the rebase.
#
# Failure mode the wrapper mitigates:
#   Agent crashes mid-flight in a worktree leaving untracked WIP on
#   disk. Resume agent runs `git stash + rebase + pop`, which wipes
#   untracked files. The wrapper snapshots untracked files, runs the
#   rebase, then restores them — conflicts (WIP collides with
#   incoming) saved as `<path>.wip` for manual resolution.
#
# Run:  bash lib/tests/loom-rebase-worktree.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$LOOM_ROOT/scripts/loom-rebase-worktree"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a fixture: a "main" repo, a feature-branch worktree behind
# current main by 1 commit.
#   echoes "main_dir worktree_dir"
mk_main_plus_behind_worktree() {
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt="$root/wt"
  mkdir -p "$main"

  (cd "$main" && git init -q && git config user.email t@t && git config user.name t)
  echo "seed line" > "$main/seed.txt"
  (cd "$main" && git add seed.txt && git commit -q -m "seed")

  # Create the feature branch + worktree from current HEAD.
  (cd "$main" && git worktree add -q "$wt" -b feature 2>&1 >/dev/null)

  # Move main forward by 1 commit (this is what the worktree needs to rebase onto).
  echo "main moved forward" > "$main/incoming.txt"
  (cd "$main" && git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null || true)
  # Detect the default branch (master vs main) and stay on it.
  DEFAULT_BR=$(cd "$main" && git symbolic-ref --short HEAD)
  (cd "$main" && git add incoming.txt && git commit -q -m "main forward")

  printf '%s\t%s\t%s\n' "$main" "$wt" "$DEFAULT_BR"
}

# -------------------------------------------------------------------
# 1. Untracked WIP preserved through rebase.
# -------------------------------------------------------------------

echo "==> 1. Untracked WIP preserved through rebase"

FX=$(mk_main_plus_behind_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
DEFAULT_BR=$(echo "$FX" | cut -f3)

# Drop untracked WIP into the worktree.
echo "WIP work in progress" > "$WT/wip-notes.md"
mkdir -p "$WT/src"
echo "def foo(): pass" > "$WT/src/feature.py"

out=$(cd "$WT" && "$WRAPPER" "$DEFAULT_BR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
   && [ -f "$WT/wip-notes.md" ] \
   && [ -f "$WT/src/feature.py" ] \
   && grep -q "WIP work in progress" "$WT/wip-notes.md" \
   && grep -q "def foo(): pass" "$WT/src/feature.py"; then
  pass "untracked WIP files restored post-rebase (top-level + nested)"
else
  fail "WIP not preserved. rc=$rc. wt contents: $(ls $WT)" "$out"
fi

# Verify the rebase actually picked up main's new commit.
if [ -f "$WT/incoming.txt" ]; then
  pass "rebase picked up main's incoming commit"
else
  fail "incoming.txt missing — rebase didn't actually run"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 2. No untracked files → wrapper passthrough.
# -------------------------------------------------------------------

echo "==> 2. No untracked WIP → wrapper passthrough"

FX=$(mk_main_plus_behind_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
DEFAULT_BR=$(echo "$FX" | cut -f3)

out=$(cd "$WT" && "$WRAPPER" "$DEFAULT_BR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WT/incoming.txt" ]; then
  pass "no WIP: rebase succeeded, wrapper exit 0"
else
  fail "no-WIP path broken. rc=$rc" "$out"
fi

# Wrapper output should mention "no untracked WIP" or similar.
if echo "$out" | grep -qi "no untracked"; then
  pass "no-WIP path emits informational message"
else
  fail "no-WIP path message missing" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 3. WIP collides with incoming file → saved as .wip.
# -------------------------------------------------------------------

echo "==> 3. WIP collision saved as .wip"

FX=$(mk_main_plus_behind_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
DEFAULT_BR=$(echo "$FX" | cut -f3)

# WIP file has the same name as the incoming file from main.
echo "MY WIP VERSION" > "$WT/incoming.txt"

out=$(cd "$WT" && "$WRAPPER" "$DEFAULT_BR" 2>&1); rc=$?
# Incoming version wins; WIP saved as .wip.
if [ -f "$WT/incoming.txt" ] && grep -q "main moved forward" "$WT/incoming.txt" \
   && [ -f "$WT/incoming.txt.wip" ] && grep -q "MY WIP VERSION" "$WT/incoming.txt.wip"; then
  pass "collision: incoming wins, WIP saved as .wip"
else
  fail "collision handling broken. incoming.txt=$(cat $WT/incoming.txt 2>/dev/null) wip=$(cat $WT/incoming.txt.wip 2>/dev/null)" "$out"
fi

# Wrapper should mention the conflict.
if echo "$out" | grep -qiE "conflict|wip"; then
  pass "collision message emitted"
else
  fail "no collision message" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 4. Skips .beads/embeddeddolt/ (handled by bd-worktree-preseed hook).
# -------------------------------------------------------------------

echo "==> 4. Skips .beads/embeddeddolt/ (8vc territory)"

FX=$(mk_main_plus_behind_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
DEFAULT_BR=$(echo "$FX" | cut -f3)

mkdir -p "$WT/.beads/embeddeddolt"
echo "fake dolt data" > "$WT/.beads/embeddeddolt/somefile"

# Also some real WIP elsewhere.
echo "real wip" > "$WT/work.md"

out=$(cd "$WT" && "$WRAPPER" "$DEFAULT_BR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WT/work.md" ]; then
  pass "rebase succeeded with real WIP preserved"
else
  fail "rebase failed. rc=$rc" "$out"
fi

# Wrapper output should NOT mention the dolt path as a preserved file
# (it should be excluded from the snapshot).
if echo "$out" | grep -qE 'embeddeddolt'; then
  fail ".beads/embeddeddolt/ leaked into snapshot output" "$out"
else
  pass ".beads/embeddeddolt/ excluded from WIP snapshot"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 5. Refuses outside a worktree (vanilla main repo) → exit 0 with msg.
# -------------------------------------------------------------------

echo "==> 5. Refuses outside a linked worktree"

FX=$(mk_main_plus_behind_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
DEFAULT_BR=$(echo "$FX" | cut -f3)

# Run wrapper from MAIN — not a linked worktree.
out=$(cd "$MAIN" && "$WRAPPER" "$DEFAULT_BR" 2>&1); rc=$?
# Wrapper should refuse with a clear message + non-zero rc.
if [ "$rc" -ne 0 ] && echo "$out" | grep -qiE "worktree|main"; then
  pass "main repo: wrapper refuses with rc != 0 + helpful message"
else
  fail "main repo: expected refusal, got rc=$rc" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
