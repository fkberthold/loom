#!/usr/bin/env bash
# Tests for lib/auto-exclude.sh — auto-hide loom's own artifacts from the
# git of a repo loom does NOT manage, via the per-clone .git/info/exclude
# (never committed). The "auto" counterpart to explicit guest mode
# (loom-e5ys). ADD-ONLY by design — it never removes a block, so it can
# never clobber the # BEGIN LOOM block that guest mode or
# bd-worktree-preseed (.beads/issues.jsonl) may have written.
#
# API under test:
#   loom_auto_exclude_sync [--start-dir=PATH]
#
# Contract (loom-e5ys, ADD-only after the clobber-risk refinement):
#   - workflow.json ABSENT (not loom-managed) -> add artifact block.
#   - workflow.json PRESENT (managed or guest) -> NO-OP (never remove).
#
# Artifact set (loom-created ONLY; deliberately excludes .beads/ — the
# team's shared bd tracker — and .claude/settings.json — the team's
# shared Claude Code config):
#   .claude/workflow.json .claude/workflow-state.json
#   .claude/settings.local.json /issues.jsonl
#
# Run:  bash lib/tests/auto-exclude.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/auto-exclude.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# A tmp git repo with a .beads/ dir (a beads workspace — the scope loom
# actually litters). Fresh git ships a comment-only .git/info/exclude.
mk_beads_repo() {
  local d
  d=$(mktemp -d)
  (cd "$d" && git init -q)
  mkdir -p "$d/.beads"
  printf '%s' "$d"
}

# Source the lib under test (will fail until impl exists).
. "$LIB" 2>/dev/null || true

EXCL=".git/info/exclude"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# Test 1: UNMANAGED repo (no workflow.json) -> a well-formed block (BEGIN +
# END markers) holding exactly the 4 artifacts.
repo=$(mk_beads_repo)
loom_auto_exclude_sync --start-dir="$repo" 2>/dev/null
content=$(cat "$repo/$EXCL" 2>/dev/null || true)
# Count non-comment, non-blank lines inside the BEGIN LOOM..END LOOM block.
block_lines=$(printf '%s\n' "$content" | awk '
  /^# BEGIN LOOM/           { in_b = 1; next }
  in_b && /^# END LOOM/     { in_b = 0; next }
  in_b && NF                { n++ }
  END                       { print n + 0 }')
if printf '%s' "$content" | grep -q "^# BEGIN LOOM" && \
   printf '%s' "$content" | grep -q "^# END LOOM" && \
   printf '%s' "$content" | grep -qx ".claude/workflow.json" && \
   printf '%s' "$content" | grep -qx ".claude/workflow-state.json" && \
   printf '%s' "$content" | grep -qx ".claude/settings.local.json" && \
   printf '%s' "$content" | grep -qx "/issues.jsonl" && \
   [ "$block_lines" = "4" ]; then
  pass "unmanaged repo: well-formed block with exactly the 4 artifacts"
else
  fail "unmanaged repo: artifact block (block_lines=$block_lines)" "$content"
fi
rm -rf "$repo"

# Test 2: .beads/ is NEVER in the excluded set (team's shared tracker).
repo=$(mk_beads_repo)
loom_auto_exclude_sync --start-dir="$repo" 2>/dev/null
content=$(cat "$repo/$EXCL" 2>/dev/null || true)
if printf '%s' "$content" | grep -qE "(^|/)\.beads(/|$)"; then
  fail "unmanaged repo: .beads/ leaked into exclude" "$content"
else
  pass "unmanaged repo: .beads/ NOT excluded"
fi
rm -rf "$repo"

# Test 3: MANAGED repo (workflow.json present, non-guest) -> no-op.
repo=$(mk_beads_repo)
mkdir -p "$repo/.claude"
printf '{"v":1,"mode":"full"}\n' > "$repo/.claude/workflow.json"
loom_auto_exclude_sync --start-dir="$repo" 2>/dev/null
content=$(cat "$repo/$EXCL" 2>/dev/null || true)
if printf '%s' "$content" | grep -q "BEGIN LOOM"; then
  fail "managed repo: should be a no-op but a block was added" "$content"
else
  pass "managed repo (workflow.json present): no-op, no block added"
fi
rm -rf "$repo"

# Test 4: GUEST repo — a pre-existing # BEGIN LOOM block is left UNCHANGED
# (never removed/clobbered). Simulates loom-guest having added its block.
repo=$(mk_beads_repo)
mkdir -p "$repo/.claude"
printf '{"v":1,"mode":"full","guest":{"active":true,"bd_mode":"host","repo_key":"x-000"}}\n' \
  > "$repo/.claude/workflow.json"
cat > "$repo/$EXCL" <<'EOF'
# BEGIN LOOM (managed by loom guest mode — do not edit)
.claude/workflow.json
.claude/settings.json
# END LOOM
EOF
before=$(cat "$repo/$EXCL")
loom_auto_exclude_sync --start-dir="$repo" 2>/dev/null
after=$(cat "$repo/$EXCL")
if [ "$before" = "$after" ]; then
  pass "guest repo: pre-existing block left unchanged (no clobber)"
else
  fail "guest repo: block was modified/clobbered" "before:\n$before\nafter:\n$after"
fi
rm -rf "$repo"

# Test 5: idempotent — running twice yields the same file.
repo=$(mk_beads_repo)
loom_auto_exclude_sync --start-dir="$repo" 2>/dev/null
once=$(cat "$repo/$EXCL")
loom_auto_exclude_sync --start-dir="$repo" 2>/dev/null
twice=$(cat "$repo/$EXCL")
if [ "$once" = "$twice" ]; then
  pass "idempotent: second sync is a no-op"
else
  fail "idempotent" "once:\n$once\ntwice:\n$twice"
fi
rm -rf "$repo"

# Test 6: not a git repo -> no-op, no crash, no file created.
dir=$(mktemp -d)
if loom_auto_exclude_sync --start-dir="$dir" 2>/dev/null; rc=$?; [ "$rc" -eq 0 ] && [ ! -e "$dir/$EXCL" ]; then
  pass "non-git dir: no-op, exit 0, no exclude file created"
else
  fail "non-git dir: expected clean no-op (rc=$rc)"
fi
rm -rf "$dir"

# ---------------------------------------------------------------------------
echo
echo "auto-exclude: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
