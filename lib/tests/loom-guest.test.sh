#!/usr/bin/env bash
# Tests for scripts/loom-guest — the /loom-guest slash command's
# underlying script. Owns the activation flow:
#   - git-repo guard
#   - repo_key derivation: <basename>-<sha8(toplevel-path)>
#   - host-bd detection
#   - workflow.json marker write (delegates to workflow-config lib)
#   - info/exclude entries (delegates to info-exclude lib)
#   - off: remove both atomically
#   - status: report what's suppressed
#
# Run:  bash lib/tests/loom-guest.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-guest"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a tmp dir set up as a git repo with .claude/ and the workflow.json.
mk_repo() {
  local d
  d=$(mktemp -d)
  (cd "$d" && git init -q)
  mkdir -p "$d/.claude"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '%s' "$d"
}

mk_repo_with_host_bd() {
  local d
  d=$(mk_repo)
  mkdir -p "$d/.beads"
  printf '%s' "$d"
}

run_in() {
  local repo="$1"
  shift
  (cd "$repo" && "$SCRIPT" "$@")
}

# ---------------------------------------------------------------------------

# Test 1: status reports inactive on fresh project
repo=$(mk_repo)
out=$(run_in "$repo" status 2>&1)
if echo "$out" | grep -qi "INACTIVE"; then
  pass "status: inactive on fresh project"
else
  fail "status: inactive on fresh project" "$out"
fi
rm -rf "$repo"

# Test 2: on (no flags, host has bd) → bd_mode=host
repo=$(mk_repo_with_host_bd)
out=$(run_in "$repo" on 2>&1)
if echo "$out" | grep -q "bd_mode=host" && \
   grep -q '"active": true' "$repo/.claude/workflow.json"; then
  pass "on (host bd present): bd_mode=host, marker written"
else
  fail "on (host bd present)" "$out"
fi
rm -rf "$repo"

# Test 3: on without bd flag fails when no host bd
repo=$(mk_repo)
out=$(run_in "$repo" on 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi "no host"; then
  pass "on without flag refuses when no host bd"
else
  fail "on without flag refuses when no host bd" "rc=$rc out=$out"
fi
rm -rf "$repo"

# Test 4: on --personal-bd writes personal mode, creates external dir
repo=$(mk_repo)
HOME_BACKUP="$HOME"
export HOME="$(mktemp -d)"
out=$(run_in "$repo" on --personal-bd 2>&1)
bd_mode=$(jq -r '.guest.bd_mode' "$repo/.claude/workflow.json" 2>/dev/null)
repo_key=$(jq -r '.guest.repo_key' "$repo/.claude/workflow.json" 2>/dev/null)
ext_dir="$HOME/.loom/guests/$repo_key/.beads"
if [ "$bd_mode" = "personal" ] && [ -d "$ext_dir" ]; then
  pass "on --personal-bd: bd_mode=personal, external dir created"
else
  fail "on --personal-bd" "bd_mode=$bd_mode ext_dir=$ext_dir out=$out"
fi
rm -rf "$HOME"
export HOME="$HOME_BACKUP"
rm -rf "$repo"

# Test 5: on --no-bd writes none mode
repo=$(mk_repo)
out=$(run_in "$repo" on --no-bd 2>&1)
bd_mode=$(jq -r '.guest.bd_mode' "$repo/.claude/workflow.json" 2>/dev/null)
if [ "$bd_mode" = "none" ]; then
  pass "on --no-bd: bd_mode=none"
else
  fail "on --no-bd" "bd_mode=$bd_mode out=$out"
fi
rm -rf "$repo"

# Test 6: on populates info/exclude block with default patterns
repo=$(mk_repo_with_host_bd)
run_in "$repo" on >/dev/null 2>&1
exclude_file="$repo/.git/info/exclude"
if grep -q "BEGIN LOOM" "$exclude_file" && \
   grep -qx ".claude/workflow.json" "$exclude_file" && \
   grep -qx ".claude/settings.json" "$exclude_file"; then
  pass "on: info/exclude block has default patterns"
else
  fail "on: info/exclude block" "$(cat "$exclude_file")"
fi
rm -rf "$repo"

# Test 7: status reports active state with bd_mode
repo=$(mk_repo_with_host_bd)
run_in "$repo" on >/dev/null 2>&1
out=$(run_in "$repo" status 2>&1)
if echo "$out" | grep -qi "ACTIVE" && \
   echo "$out" | grep -q "bd_mode: host" && \
   echo "$out" | grep -q "repo_key:"; then
  pass "status: reports active + bd_mode + repo_key"
else
  fail "status: reports active" "$out"
fi
rm -rf "$repo"

# Test 8: off clears both marker and info/exclude
repo=$(mk_repo_with_host_bd)
run_in "$repo" on >/dev/null 2>&1
run_in "$repo" off >/dev/null 2>&1
marker_present=$(jq -r '.guest // empty' "$repo/.claude/workflow.json" 2>/dev/null)
if grep -q "BEGIN LOOM" "$repo/.git/info/exclude" 2>/dev/null; then
  exclude_block_present=1
else
  exclude_block_present=0
fi
if [ -z "$marker_present" ] && [ "$exclude_block_present" = "0" ]; then
  pass "off: clears marker and info/exclude"
else
  fail "off" "marker='$marker_present' exclude_block=$exclude_block_present"
fi
rm -rf "$repo"

# Test 9: status reports inactive after off
repo=$(mk_repo_with_host_bd)
run_in "$repo" on >/dev/null 2>&1
run_in "$repo" off >/dev/null 2>&1
out=$(run_in "$repo" status 2>&1)
if echo "$out" | grep -qi "INACTIVE"; then
  pass "status: inactive after off"
else
  fail "status: inactive after off" "$out"
fi
rm -rf "$repo"

# Test 10: repo_key format <basename>-<sha8>
repo=$(mk_repo_with_host_bd)
run_in "$repo" on >/dev/null 2>&1
repo_key=$(jq -r '.guest.repo_key' "$repo/.claude/workflow.json")
basename=$(basename "$repo")
expected_sha=$(printf '%s' "$repo" | sha1sum | cut -c1-8)
expected="$basename-$expected_sha"
if [ "$repo_key" = "$expected" ]; then
  pass "repo_key format: <basename>-<sha8>"
else
  fail "repo_key format" "got: $repo_key expected: $expected"
fi
rm -rf "$repo"

# Test 11: refuses outside a git repo
nonrepo=$(mktemp -d)
mkdir -p "$nonrepo/.claude"
printf '{"v": 1}\n' > "$nonrepo/.claude/workflow.json"
out=$(run_in "$nonrepo" on 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "refuses outside a git repo"
else
  fail "refuses outside a git repo" "rc=$rc out=$out"
fi
rm -rf "$nonrepo"

# Test 12: idempotent — `on` then `on` produces same state
repo=$(mk_repo_with_host_bd)
run_in "$repo" on >/dev/null 2>&1
sum1=$(md5sum "$repo/.claude/workflow.json" | cut -d' ' -f1)
sum1e=$(md5sum "$repo/.git/info/exclude" | cut -d' ' -f1)
run_in "$repo" on >/dev/null 2>&1
sum2=$(md5sum "$repo/.claude/workflow.json" | cut -d' ' -f1)
sum2e=$(md5sum "$repo/.git/info/exclude" | cut -d' ' -f1)
if [ "$sum1" = "$sum2" ] && [ "$sum1e" = "$sum2e" ]; then
  pass "on idempotent (run twice)"
else
  fail "on idempotent" "marker $sum1→$sum2 exclude $sum1e→$sum2e"
fi
rm -rf "$repo"

# Test 13: idempotent — `off` then `off` is a no-op
repo=$(mk_repo_with_host_bd)
run_in "$repo" off >/dev/null 2>&1
sum1=$(md5sum "$repo/.claude/workflow.json" | cut -d' ' -f1)
run_in "$repo" off >/dev/null 2>&1
sum2=$(md5sum "$repo/.claude/workflow.json" | cut -d' ' -f1)
if [ "$sum1" = "$sum2" ]; then
  pass "off idempotent (never on)"
else
  fail "off idempotent (never on)" "$sum1 → $sum2"
fi
rm -rf "$repo"

# Test 14: --help shows usage
out=$($SCRIPT --help 2>&1)
if echo "$out" | grep -qi "usage" && echo "$out" | grep -q "personal-bd"; then
  pass "--help shows usage"
else
  fail "--help shows usage" "$out"
fi

# Test 15: unknown subcommand fails
if $SCRIPT bogus 2>/dev/null; then
  fail "unknown subcommand fails"
else
  pass "unknown subcommand fails"
fi

# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
