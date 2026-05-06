#!/usr/bin/env bash
# Tests for lib/info-exclude.sh — idempotent BEGIN-LOOM/END-LOOM block
# management in .git/info/exclude (per-clone, never committed).
#
# API under test:
#   info_exclude_path   [--start-dir=PATH]                   echo file path
#   info_exclude_add    [--start-dir=PATH] PAT [PAT...]      append/merge
#   info_exclude_remove [--start-dir=PATH]                   strip block
#   info_exclude_status [--start-dir=PATH]                   exit 0 if present
#
# Default start dir is $PWD when --start-dir= is omitted.
#
# Block markers:
#   # BEGIN LOOM (do not edit — managed by loom guest mode)
#   <patterns>
#   # END LOOM
#
# Run:  bash lib/tests/info-exclude.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/info-exclude.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a tmp git repo with .git/info/exclude as the default git produces.
mk_repo() {
  local d
  d=$(mktemp -d)
  (cd "$d" && git init -q)
  printf '%s' "$d"
}

# Append a snippet that mimics what git ships in .git/info/exclude when
# fresh — comments + a blank line. Some installs leave the file empty;
# both shapes should be supported.
mk_repo_with_default_exclude() {
  local d
  d=$(mk_repo)
  cat > "$d/.git/info/exclude" <<'EOF'
# git ls-files --others --exclude-from=.git/info/exclude
# Lines that start with '#' are comments.
# For a project mostly in C, the following would be a good set of
# exclude patterns (uncomment them if you want to use them):
# *.[oa]
# *~
EOF
  printf '%s' "$d"
}

mk_repo_no_exclude_file() {
  local d
  d=$(mk_repo)
  rm -f "$d/.git/info/exclude"
  printf '%s' "$d"
}

# Source the lib under test (will fail until impl exists).
. "$LIB" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# Test 1: info_exclude_path resolves to .git/info/exclude under the repo
repo=$(mk_repo_with_default_exclude)
got=$(info_exclude_path --start-dir="$repo" 2>/dev/null)
expected="$repo/.git/info/exclude"
if [ "$got" = "$expected" ]; then
  pass "info_exclude_path returns expected path"
else
  fail "info_exclude_path" "expected: $expected\ngot: $got"
fi
rm -rf "$repo"

# Test 2: status returns 1 (no block) on a fresh repo
repo=$(mk_repo_with_default_exclude)
if info_exclude_status --start-dir="$repo" 2>/dev/null; then
  fail "status=1 on fresh repo" "exit 0"
else
  pass "status=1 on fresh repo"
fi
rm -rf "$repo"

# Test 3: add appends a block with the right markers
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json .claude/settings.json 2>/dev/null
content=$(cat "$repo/.git/info/exclude")
if printf '%s' "$content" | grep -q "BEGIN LOOM" && \
   printf '%s' "$content" | grep -q "END LOOM" && \
   printf '%s' "$content" | grep -q "^.claude/workflow.json$" && \
   printf '%s' "$content" | grep -q "^.claude/settings.json$"; then
  pass "add appends block with markers + patterns"
else
  fail "add appends block" "$content"
fi
rm -rf "$repo"

# Test 4: status returns 0 after add
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json 2>/dev/null
if info_exclude_status --start-dir="$repo" 2>/dev/null; then
  pass "status=0 after add"
else
  fail "status=0 after add"
fi
rm -rf "$repo"

# Test 5: add idempotent — running twice with same patterns is a no-op
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json .claude/settings.json 2>/dev/null
sum1=$(md5sum "$repo/.git/info/exclude" | cut -d' ' -f1)
info_exclude_add --start-dir="$repo" .claude/workflow.json .claude/settings.json 2>/dev/null
sum2=$(md5sum "$repo/.git/info/exclude" | cut -d' ' -f1)
if [ "$sum1" = "$sum2" ]; then
  pass "add idempotent (same patterns)"
else
  fail "add idempotent (same patterns)" "checksum changed: $sum1 → $sum2"
fi
rm -rf "$repo"

# Test 6: add merges new patterns into existing block (idempotent for old, adds new)
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json 2>/dev/null
info_exclude_add --start-dir="$repo" .claude/workflow.json .claude/settings.json 2>/dev/null
content=$(cat "$repo/.git/info/exclude")
# Should have exactly one BEGIN LOOM, exactly one END LOOM, both patterns once
n_begin=$(printf '%s\n' "$content" | grep -c "BEGIN LOOM")
n_end=$(printf '%s\n' "$content" | grep -c "END LOOM")
n_wj=$(printf '%s\n' "$content" | grep -c "^.claude/workflow.json$")
n_st=$(printf '%s\n' "$content" | grep -c "^.claude/settings.json$")
if [ "$n_begin" = 1 ] && [ "$n_end" = 1 ] && [ "$n_wj" = 1 ] && [ "$n_st" = 1 ]; then
  pass "add merges new patterns into existing block"
else
  fail "add merges new patterns into existing block" \
    "BEGIN=$n_begin END=$n_end workflow.json=$n_wj settings.json=$n_st"
fi
rm -rf "$repo"

# Test 7: remove strips the block, leaves pre-existing content intact
repo=$(mk_repo_with_default_exclude)
pre=$(cat "$repo/.git/info/exclude")
info_exclude_add --start-dir="$repo" .claude/workflow.json 2>/dev/null
info_exclude_remove --start-dir="$repo" 2>/dev/null
post=$(cat "$repo/.git/info/exclude")
# Strip trailing newline differences for comparison
pre_norm=$(printf '%s' "$pre" | sed -e '$a\')
post_norm=$(printf '%s' "$post" | sed -e '$a\')
if [ "$pre_norm" = "$post_norm" ]; then
  pass "remove restores original file content"
else
  fail "remove restores original file content" \
    "pre:\n$pre\npost:\n$post"
fi
rm -rf "$repo"

# Test 8: remove idempotent on never-added repo
repo=$(mk_repo_with_default_exclude)
pre=$(cat "$repo/.git/info/exclude")
info_exclude_remove --start-dir="$repo" 2>/dev/null
post=$(cat "$repo/.git/info/exclude")
if [ "$pre" = "$post" ]; then
  pass "remove idempotent (never added)"
else
  fail "remove idempotent (never added)"
fi
rm -rf "$repo"

# Test 9: remove idempotent (run twice)
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json 2>/dev/null
info_exclude_remove --start-dir="$repo" 2>/dev/null
mid=$(cat "$repo/.git/info/exclude")
info_exclude_remove --start-dir="$repo" 2>/dev/null
post=$(cat "$repo/.git/info/exclude")
if [ "$mid" = "$post" ]; then
  pass "remove idempotent (after one remove)"
else
  fail "remove idempotent (after one remove)"
fi
rm -rf "$repo"

# Test 10: status=1 after remove
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json 2>/dev/null
info_exclude_remove --start-dir="$repo" 2>/dev/null
if info_exclude_status --start-dir="$repo" 2>/dev/null; then
  fail "status=1 after remove" "exit 0 (still present)"
else
  pass "status=1 after remove"
fi
rm -rf "$repo"

# Test 11: works when .git/info/exclude is missing (creates parent if needed)
repo=$(mk_repo_no_exclude_file)
info_exclude_add --start-dir="$repo" .claude/workflow.json 2>/dev/null
if [ -f "$repo/.git/info/exclude" ] && \
   grep -q "BEGIN LOOM" "$repo/.git/info/exclude" && \
   grep -q "^.claude/workflow.json$" "$repo/.git/info/exclude"; then
  pass "add works when exclude file initially missing"
else
  fail "add works when exclude file initially missing"
fi
rm -rf "$repo"

# Test 12: refuses to operate outside a git repo
nonrepo=$(mktemp -d)
if info_exclude_add --start-dir="$nonrepo" .claude/workflow.json 2>/dev/null; then
  fail "refuses non-git dir" "exit 0 outside a repo"
else
  pass "refuses non-git dir"
fi
rm -rf "$nonrepo"

# Test 13: respects start_dir defaulting (cd into repo, omit arg)
repo=$(mk_repo_with_default_exclude)
(cd "$repo" && info_exclude_add .claude/workflow.json 2>/dev/null)
if grep -q "BEGIN LOOM" "$repo/.git/info/exclude"; then
  pass "no-arg form: uses cwd as start_dir"
else
  fail "no-arg form: uses cwd as start_dir"
fi
rm -rf "$repo"

# Test 14: each pattern listed on its own line, with no leading space
repo=$(mk_repo_with_default_exclude)
info_exclude_add --start-dir="$repo" .claude/workflow.json .claude/rules/ 2>/dev/null
content=$(cat "$repo/.git/info/exclude")
if printf '%s\n' "$content" | grep -qx ".claude/workflow.json" && \
   printf '%s\n' "$content" | grep -qx ".claude/rules/"; then
  pass "patterns appear on own lines, no leading space"
else
  fail "patterns appear on own lines" "$content"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
