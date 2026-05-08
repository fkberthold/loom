#!/usr/bin/env bash
# Tests for lib/loom-bd-env.sh — BEADS_DIR resolution for guest mode.
#
# Resolution rules (Option A: bd respects BEADS_DIR env var):
#   - Non-guest:                       BEADS_DIR is NOT exported (cwd discovery wins)
#   - Guest + bd_mode=host:            BEADS_DIR is NOT exported (host's tracker via cwd)
#   - Guest + bd_mode=personal:        BEADS_DIR=$HOME/.loom/guests/<repo-key>/.beads
#   - Guest + bd_mode=none:            BEADS_DIR is NOT exported (no bd at all)
#
# Also covers `loom-guest on --personal-bd` running `bd init` against the
# external workspace so that `BEADS_DIR` resolution actually has a populated
# db waiting for it.
#
# Run:  bash lib/tests/bd-resolve.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-bd-env.sh"
GUEST_SCRIPT="$LOOM_ROOT/scripts/loom-guest"

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

# Source the lib in a subshell rooted at $1 (cwd) and echo BEADS_DIR (or
# empty). Pre-existing BEADS_DIR is cleared before sourcing.
resolve_in() {
  local cwd="$1"
  (
    cd "$cwd"
    unset BEADS_DIR
    # shellcheck source=/dev/null
    . "$LIB"
    loom_bd_env_apply
    printf '%s' "${BEADS_DIR:-}"
  )
}

# ---------------------------------------------------------------------------
# Tests for loom-bd-env.sh
# ---------------------------------------------------------------------------

# Test 1: lib file exists and is sourceable
if [ -f "$LIB" ]; then
  pass "lib/loom-bd-env.sh exists"
else
  fail "lib/loom-bd-env.sh exists" "expected at $LIB"
fi

# Test 2: non-guest mode → BEADS_DIR not set (empty)
repo=$(mk_repo_with_host_bd)
got=$(resolve_in "$repo")
if [ -z "$got" ]; then
  pass "non-guest: BEADS_DIR not exported"
else
  fail "non-guest: BEADS_DIR not exported" "got: $got"
fi
rm -rf "$repo"

# Test 3: guest + bd_mode=host → BEADS_DIR not set (cwd discovery wins)
repo=$(mk_repo_with_host_bd)
(cd "$repo" && "$GUEST_SCRIPT" on >/dev/null 2>&1) || true
got=$(resolve_in "$repo")
if [ -z "$got" ]; then
  pass "guest + host bd_mode: BEADS_DIR not exported"
else
  fail "guest + host bd_mode: BEADS_DIR not exported" "got: $got"
fi
rm -rf "$repo"

# Test 4: guest + bd_mode=personal → BEADS_DIR points at external workspace
repo=$(mk_repo)
HOME_BACKUP="$HOME"
export HOME="$(mktemp -d)"
(cd "$repo" && "$GUEST_SCRIPT" on --personal-bd >/dev/null 2>&1) || true
repo_key=$(jq -r '.guest.repo_key' "$repo/.claude/workflow.json" 2>/dev/null)
expected="$HOME/.loom/guests/$repo_key/.beads"
got=$(resolve_in "$repo")
if [ "$got" = "$expected" ]; then
  pass "guest + personal bd_mode: BEADS_DIR=$expected"
else
  fail "guest + personal bd_mode: BEADS_DIR" "got=$got expected=$expected"
fi
rm -rf "$HOME"
export HOME="$HOME_BACKUP"
rm -rf "$repo"

# Test 5: guest + bd_mode=none → BEADS_DIR not set
repo=$(mk_repo)
(cd "$repo" && "$GUEST_SCRIPT" on --no-bd >/dev/null 2>&1) || true
got=$(resolve_in "$repo")
if [ -z "$got" ]; then
  pass "guest + no-bd mode: BEADS_DIR not exported"
else
  fail "guest + no-bd mode: BEADS_DIR not exported" "got: $got"
fi
rm -rf "$repo"

# Test 6: loom-guest on --personal-bd actually initializes a bd workspace
# (so that bd commands resolved via BEADS_DIR will find a populated db).
# We assert the externally-initialized .beads/ contains an embeddeddolt
# directory — bd init's hallmark output.
repo=$(mk_repo)
HOME_BACKUP="$HOME"
export HOME="$(mktemp -d)"
out=$(cd "$repo" && "$GUEST_SCRIPT" on --personal-bd 2>&1)
repo_key=$(jq -r '.guest.repo_key' "$repo/.claude/workflow.json" 2>/dev/null)
ext="$HOME/.loom/guests/$repo_key/.beads"
if [ -d "$ext/embeddeddolt" ]; then
  pass "on --personal-bd: bd init populates external workspace"
else
  fail "on --personal-bd: bd init populates external workspace" \
       "ext=$ext contents=$(ls -la "$ext" 2>&1) out=$out"
fi
rm -rf "$HOME"
export HOME="$HOME_BACKUP"
rm -rf "$repo"

# Test 7: end-to-end — after `on --personal-bd`, sourcing the env lib and
# running `bd where` reports the external workspace, NOT the cwd's host
# tracker (if any). This is the load-bearing assertion of the whole bead.
if command -v bd >/dev/null 2>&1; then
  repo=$(mk_repo_with_host_bd)
  HOME_BACKUP="$HOME"
  export HOME="$(mktemp -d)"
  (cd "$repo" && "$GUEST_SCRIPT" on --personal-bd >/dev/null 2>&1) || true
  repo_key=$(jq -r '.guest.repo_key' "$repo/.claude/workflow.json" 2>/dev/null)
  expected="$HOME/.loom/guests/$repo_key/.beads"
  out=$(
    cd "$repo"
    unset BEADS_DIR
    # shellcheck source=/dev/null
    . "$LIB"
    loom_bd_env_apply
    bd where 2>&1
  )
  # bd where echoes the workspace dir on the first line.
  first=$(printf '%s\n' "$out" | head -n1)
  if [ "$first" = "$expected" ]; then
    pass "end-to-end: bd where → external workspace under BEADS_DIR"
  else
    fail "end-to-end: bd where → external workspace under BEADS_DIR" \
         "first=$first expected=$expected full=$out"
  fi
  rm -rf "$HOME"
  export HOME="$HOME_BACKUP"
  rm -rf "$repo"
else
  echo "  SKIP: bd binary unavailable (end-to-end test)"
fi

# Test 8: `loom_bd_env_apply` does not clobber an externally-set BEADS_DIR
# when in non-guest mode. Caller's BEADS_DIR wins.
repo=$(mk_repo_with_host_bd)
got=$(
  cd "$repo"
  export BEADS_DIR=/tmp/explicit-from-caller
  # shellcheck source=/dev/null
  . "$LIB"
  loom_bd_env_apply
  printf '%s' "${BEADS_DIR:-}"
)
if [ "$got" = "/tmp/explicit-from-caller" ]; then
  pass "non-guest: caller's BEADS_DIR is preserved"
else
  fail "non-guest: caller's BEADS_DIR is preserved" "got=$got"
fi
rm -rf "$repo"

# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
