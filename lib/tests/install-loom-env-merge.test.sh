#!/usr/bin/env bash
# Fixture tests for install.sh's project-level env-block merge step
# (loom-7ro). The new step merges a canonical env block into
# `<loom_root>/.claude/settings.json` so the Claude Code harness's
# competing defaults (TaskCreate reminders, auto-memory MEMORY.md)
# stay off in loom-managed projects.
#
# Canonical env block:
#   {
#     "env": {
#       "CLAUDE_CODE_ENABLE_TASKS": "false",
#       "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
#     }
#   }
#
# Contract:
#   - Fresh project: creates .claude/settings.json with the env block.
#   - Existing settings.json missing env: adds env, preserves other
#     keys.
#   - Existing env block missing one var: inserts the missing var,
#     preserves the other.
#   - Existing env block with canonical values: idempotent no-op.
#   - Existing env block with conflicting values for loom's two keys:
#     OVERWRITES with loom canonical values (loom's opinion wins on
#     its own keys); logs the overwrite.
#   - Running install.sh twice yields identical file content.
#   - Writes .claude/settings.json.pre-loom.bak on first overwrite.
#
# Run:  bash lib/tests/install-loom-env-merge.test.sh
#
# These tests drive install.sh against a fixture LOOM_ROOT (a tmpdir
# copy of the worktree's necessary files) so the production install
# is unaffected.

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$LOOM_ROOT/install.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a fixture LOOM_ROOT that mirrors the structure install.sh
# expects (the required-files probe at install.sh:87 and the symlink
# walks). Each fixture run gets its own tmpdir copy so test runs are
# isolated from one another and from the real worktree.
mk_fixture_loom() {
  local dir="$1"
  mkdir -p "$dir"
  # Minimum files install.sh's sanity probe requires.
  mkdir -p "$dir/skills/bugfix-a-bead"
  mkdir -p "$dir/hooks" "$dir/scripts" "$dir/agents" "$dir/commands" "$dir/lib/tests"
  touch "$dir/skills/bugfix-a-bead/SKILL.md"
  touch "$dir/hooks/bd-claim-research.sh"
  # Settings snippet — minimal valid JSON so the user-global merge
  # path won't error out.
  cat >"$dir/settings.snippet.json" <<'JSON'
{
  "_comment": "fixture",
  "permissions": {"allow": []},
  "hooks": {"PreToolUse": [], "SessionStart": []},
  "statusLine": {}
}
JSON
  # install.sh + uninstall.sh
  cp "$INSTALL_SH" "$dir/install.sh"
  chmod +x "$dir/install.sh"
  # Make $dir a git repo so install.sh's worktree detection sees a
  # main checkout (not a linked worktree) and proceeds.
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name  "test"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "fixture"
}

# Run install.sh against a fixture loom root. The fixture loom root's
# own .claude/settings.json is what the new env-merge step is
# expected to touch.
#
# We point CLAUDE_HOME at a separate tmpdir so the user-global merge
# step doesn't touch the real ~/.claude/.
run_install() {
  local fixture_root="$1"
  local claude_home="$2"
  ( cd "$fixture_root" && CLAUDE_HOME="$claude_home" bash install.sh ) >"$claude_home/install.log" 2>&1
  return $?
}

# Parse a JSON value out of a settings file via python.
get_env_value() {
  local file="$1" key="$2"
  python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
except Exception as e:
    print('PARSE_ERROR:' + str(e))
    sys.exit(0)
env = d.get('env', {})
print(env.get('$key', '<MISSING>'))
"
}

get_top_key() {
  local file="$1" key="$2"
  python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
except Exception:
    print('PARSE_ERROR'); sys.exit(0)
print(d.get('$key', '<MISSING>'))
"
}

# ---------------------------------------------------------------------
# Case 1: fresh project (no .claude/settings.json)
# ---------------------------------------------------------------------
echo "==> Case 1: fresh project, no .claude/settings.json"
TMP1="$(mktemp -d)"
F1="$TMP1/loom"; CH1="$TMP1/claude_home"
mk_fixture_loom "$F1"; mkdir -p "$CH1"
run_install "$F1" "$CH1"
if [ -f "$F1/.claude/settings.json" ]; then
  pass "case 1: .claude/settings.json was created"
else
  fail "case 1: .claude/settings.json was NOT created" "$(cat "$CH1/install.log" 2>/dev/null)"
fi
v1a=$(get_env_value "$F1/.claude/settings.json" "CLAUDE_CODE_ENABLE_TASKS")
v1b=$(get_env_value "$F1/.claude/settings.json" "CLAUDE_CODE_DISABLE_AUTO_MEMORY")
if [ "$v1a" = "false" ]; then
  pass "case 1: CLAUDE_CODE_ENABLE_TASKS == false"
else
  fail "case 1: CLAUDE_CODE_ENABLE_TASKS != false (got: $v1a)"
fi
if [ "$v1b" = "1" ]; then
  pass "case 1: CLAUDE_CODE_DISABLE_AUTO_MEMORY == 1"
else
  fail "case 1: CLAUDE_CODE_DISABLE_AUTO_MEMORY != 1 (got: $v1b)"
fi

# ---------------------------------------------------------------------
# Case 2: existing settings.json, no env block — adds env, preserves
# other keys.
# ---------------------------------------------------------------------
echo "==> Case 2: existing settings.json without env block"
TMP2="$(mktemp -d)"
F2="$TMP2/loom"; CH2="$TMP2/claude_home"
mk_fixture_loom "$F2"; mkdir -p "$CH2" "$F2/.claude"
cat >"$F2/.claude/settings.json" <<'JSON'
{"someOtherKey": "preserveMe", "permissions": {"allow": ["Bash(ls:*)"]}}
JSON
run_install "$F2" "$CH2"
v2a=$(get_env_value "$F2/.claude/settings.json" "CLAUDE_CODE_ENABLE_TASKS")
v2b=$(get_env_value "$F2/.claude/settings.json" "CLAUDE_CODE_DISABLE_AUTO_MEMORY")
other=$(get_top_key "$F2/.claude/settings.json" "someOtherKey")
if [ "$v2a" = "false" ] && [ "$v2b" = "1" ]; then
  pass "case 2: env block inserted with both canonical values"
else
  fail "case 2: env block not properly inserted (TASKS=$v2a AUTO_MEMORY=$v2b)"
fi
if [ "$other" = "preserveMe" ]; then
  pass "case 2: pre-existing top-level key preserved"
else
  fail "case 2: pre-existing top-level key lost (got: $other)"
fi

# ---------------------------------------------------------------------
# Case 3: existing env block missing one var — fills in the missing
# one and preserves the present one.
# ---------------------------------------------------------------------
echo "==> Case 3: existing env block missing one of loom's vars"
TMP3="$(mktemp -d)"
F3="$TMP3/loom"; CH3="$TMP3/claude_home"
mk_fixture_loom "$F3"; mkdir -p "$CH3" "$F3/.claude"
cat >"$F3/.claude/settings.json" <<'JSON'
{"env": {"CLAUDE_CODE_ENABLE_TASKS": "false", "USER_SPECIFIC": "keepme"}}
JSON
run_install "$F3" "$CH3"
v3a=$(get_env_value "$F3/.claude/settings.json" "CLAUDE_CODE_ENABLE_TASKS")
v3b=$(get_env_value "$F3/.claude/settings.json" "CLAUDE_CODE_DISABLE_AUTO_MEMORY")
v3c=$(get_env_value "$F3/.claude/settings.json" "USER_SPECIFIC")
if [ "$v3a" = "false" ] && [ "$v3b" = "1" ] && [ "$v3c" = "keepme" ]; then
  pass "case 3: missing var added; existing canonical + user var preserved"
else
  fail "case 3: TASKS=$v3a AUTO_MEMORY=$v3b USER=$v3c (expected false/1/keepme)"
fi

# ---------------------------------------------------------------------
# Case 4: existing env block with both canonical values — idempotent.
# ---------------------------------------------------------------------
echo "==> Case 4: existing env block with canonical values is idempotent"
TMP4="$(mktemp -d)"
F4="$TMP4/loom"; CH4="$TMP4/claude_home"
mk_fixture_loom "$F4"; mkdir -p "$CH4" "$F4/.claude"
cat >"$F4/.claude/settings.json" <<'JSON'
{"env": {"CLAUDE_CODE_ENABLE_TASKS": "false", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}}
JSON
# Snapshot the canonical-shape file content. Re-run install and
# confirm both keys still match.
run_install "$F4" "$CH4"
v4a=$(get_env_value "$F4/.claude/settings.json" "CLAUDE_CODE_ENABLE_TASKS")
v4b=$(get_env_value "$F4/.claude/settings.json" "CLAUDE_CODE_DISABLE_AUTO_MEMORY")
if [ "$v4a" = "false" ] && [ "$v4b" = "1" ]; then
  pass "case 4: idempotent (both canonical values preserved)"
else
  fail "case 4: idempotent (TASKS=$v4a AUTO_MEMORY=$v4b)"
fi

# ---------------------------------------------------------------------
# Case 5: existing env block with a CONFLICTING value for loom's key
# (CLAUDE_CODE_ENABLE_TASKS=true). install.sh must OVERWRITE with the
# canonical loom value (false) AND log the overwrite.
# ---------------------------------------------------------------------
echo "==> Case 5: conflicting value for a loom key — loom overwrites"
TMP5="$(mktemp -d)"
F5="$TMP5/loom"; CH5="$TMP5/claude_home"
mk_fixture_loom "$F5"; mkdir -p "$CH5" "$F5/.claude"
cat >"$F5/.claude/settings.json" <<'JSON'
{"env": {"CLAUDE_CODE_ENABLE_TASKS": "true", "OTHER_KEY": "x"}}
JSON
run_install "$F5" "$CH5"
v5a=$(get_env_value "$F5/.claude/settings.json" "CLAUDE_CODE_ENABLE_TASKS")
v5b=$(get_env_value "$F5/.claude/settings.json" "CLAUDE_CODE_DISABLE_AUTO_MEMORY")
v5c=$(get_env_value "$F5/.claude/settings.json" "OTHER_KEY")
if [ "$v5a" = "false" ]; then
  pass "case 5: conflicting CLAUDE_CODE_ENABLE_TASKS overwritten to canonical 'false'"
else
  fail "case 5: conflict not overwritten (TASKS=$v5a)"
fi
if [ "$v5b" = "1" ]; then
  pass "case 5: CLAUDE_CODE_DISABLE_AUTO_MEMORY added to canonical '1'"
else
  fail "case 5: CLAUDE_CODE_DISABLE_AUTO_MEMORY != 1 (got $v5b)"
fi
if [ "$v5c" = "x" ]; then
  pass "case 5: non-loom env key preserved"
else
  fail "case 5: non-loom env key lost (got $v5c)"
fi
# Log line: install.sh must call out the overwrite so the user knows.
if grep -qE "overwr[oi]te|overrid|loom canonical|conflict" "$CH5/install.log"; then
  pass "case 5: log line surfaces the overwrite"
else
  fail "case 5: log line did NOT surface the overwrite" "(no overwrite line in install.log)"
fi

# ---------------------------------------------------------------------
# Case 6: running install.sh twice yields identical file content.
# ---------------------------------------------------------------------
echo "==> Case 6: install.sh is idempotent"
TMP6="$(mktemp -d)"
F6="$TMP6/loom"; CH6="$TMP6/claude_home"
mk_fixture_loom "$F6"; mkdir -p "$CH6"
run_install "$F6" "$CH6"
sha_after_first=$(sha256sum "$F6/.claude/settings.json" | awk '{print $1}')
run_install "$F6" "$CH6"
sha_after_second=$(sha256sum "$F6/.claude/settings.json" | awk '{print $1}')
if [ "$sha_after_first" = "$sha_after_second" ]; then
  pass "case 6: file content unchanged after re-run"
else
  fail "case 6: file changed on re-run (sha differs)"
fi

# ---------------------------------------------------------------------
# Case 7: install.sh writes .claude/settings.json.pre-loom.bak on
# first overwrite (when the file pre-existed). Mirrors the user-global
# backup pattern at install.sh:230.
# ---------------------------------------------------------------------
echo "==> Case 7: backup written on first overwrite"
TMP7="$(mktemp -d)"
F7="$TMP7/loom"; CH7="$TMP7/claude_home"
mk_fixture_loom "$F7"; mkdir -p "$CH7" "$F7/.claude"
cat >"$F7/.claude/settings.json" <<'JSON'
{"env": {"CLAUDE_CODE_ENABLE_TASKS": "true"}, "preExisting": true}
JSON
orig_content=$(cat "$F7/.claude/settings.json")
run_install "$F7" "$CH7"
if [ -f "$F7/.claude/settings.json.pre-loom.bak" ]; then
  pass "case 7: backup file exists"
  bak=$(cat "$F7/.claude/settings.json.pre-loom.bak")
  if [ "$bak" = "$orig_content" ]; then
    pass "case 7: backup matches original content"
  else
    fail "case 7: backup content drift"
  fi
else
  fail "case 7: .pre-loom.bak NOT written" "$(ls "$F7/.claude/" 2>/dev/null)"
fi

# ---------------------------------------------------------------------
# Case 8 (M5 integration): end-to-end against a tmpdir copy of the
# real worktree. After install, the loom repo's own .claude/
# settings.json must carry the env block with canonical values.
# ---------------------------------------------------------------------
echo "==> Case 8 (integration): install.sh against a copy of the real worktree"
TMP8="$(mktemp -d)"
F8="$TMP8/loom"
# Copy only what install.sh's sanity probe needs + the existing
# .claude/. (Full clone is overkill.)
mkdir -p "$F8"
git -C "$LOOM_ROOT" rev-parse --show-toplevel >/dev/null 2>&1 && \
  rsync -a --exclude='.git' --exclude='.claude/worktrees' \
    "$LOOM_ROOT/" "$F8/" 2>/dev/null
git -C "$F8" init -q
git -C "$F8" config user.email "t@e"; git -C "$F8" config user.name "t"
git -C "$F8" add -A 2>/dev/null
git -C "$F8" commit -q -m "snapshot" 2>/dev/null || true
CH8="$TMP8/claude_home"; mkdir -p "$CH8"
( cd "$F8" && CLAUDE_HOME="$CH8" bash install.sh ) >"$CH8/install.log" 2>&1
v8a=$(get_env_value "$F8/.claude/settings.json" "CLAUDE_CODE_ENABLE_TASKS" 2>/dev/null)
v8b=$(get_env_value "$F8/.claude/settings.json" "CLAUDE_CODE_DISABLE_AUTO_MEMORY" 2>/dev/null)
if [ "$v8a" = "false" ] && [ "$v8b" = "1" ]; then
  pass "case 8 (integration): full install against worktree-copy sets both canonical values"
else
  fail "case 8 (integration): TASKS=$v8a AUTO_MEMORY=$v8b" \
    "$(tail -30 "$CH8/install.log" 2>/dev/null)"
fi

# ---------------------------------------------------------------------
echo ""
echo "=================================================================="
echo "  install-loom-env-merge: $passed passed, $failed failed"
echo "=================================================================="
[ "$failed" -eq 0 ]
