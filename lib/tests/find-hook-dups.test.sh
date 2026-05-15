#!/usr/bin/env bash
# Fixture tests for scripts/find-hook-dups.sh.
#
# Closes loom-ann: detect duplicate Claude Code hook commands registered
# both in a project's `.claude/settings.json` and in an enabled plugin's
# `plugin.json`. The duplicate fires the same command twice per event,
# billing wasted tokens (observed in liza_base 2026-05-09 via loom-nsb).
#
# The script scans BOTH:
#   - <project_root>/.claude/settings.json (WARN-class — project-level dup)
#   - ~/.claude/settings.json              (INFO-class — user-level dup)
# against the hook blocks of every plugin manifest under
# ~/.claude/plugins/cache/*/*/*/plugin.json (flat) or
# ~/.claude/plugins/cache/*/*/*/.claude-plugin/plugin.json (nested).
#
# Env-var overrides for testing:
#   LOOM_FIND_HOOK_DUPS_USER_SETTINGS  -- fake user settings path
#   LOOM_FIND_HOOK_DUPS_PLUGIN_BASE    -- fake plugin cache base
#
# Exit code is always 0 (informational). Stdout: one line per duplicate.
# Line prefix: "WARN " (project dup) or "INFO " (user dup).
#
# Run:  bash lib/tests/find-hook-dups.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/find-hook-dups.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Skip the whole suite if jq isn't available — the script needs it
# to parse settings.json + plugin.json hook blocks.
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# ----------------------------------------------------------------------
# Fixture builder
# ----------------------------------------------------------------------
make_fixture() {
  # Layout under tmpdir:
  #   $fix/proj/                          <- project root
  #     .claude/settings.json             <- project-level hooks (may be absent)
  #   $fix/user-settings.json             <- fake ~/.claude/settings.json
  #   $fix/plugin-cache/<mp>/<plug>/<ver>/<plugin.json | .claude-plugin/plugin.json>
  local fix
  fix=$(mktemp -d)
  mkdir -p "$fix/proj/.claude" "$fix/plugin-cache"
  echo "$fix"
}

# Settings/manifest JSON helpers
# write_hooks_file <path> <event> <matcher> <command>  (creates a one-hook file)
write_hooks_file() {
  local file="$1" event="$2" matcher="$3" command="$4"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
{
  "hooks": {
    "$event": [
      {
        "matcher": "$matcher",
        "hooks": [
          {"type": "command", "command": "$command"}
        ]
      }
    ]
  }
}
EOF
}

write_empty_hooks_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo '{"hooks": {}}' >"$file"
}

write_plugin_manifest() {
  # write_plugin_manifest <plugin-base> <marketplace> <plugin> <version> <event> <matcher> <command> <layout=nested|flat>
  local base="$1" mp="$2" plug="$3" ver="$4" event="$5" matcher="$6" command="$7" layout="${8:-nested}"
  local manifest
  if [ "$layout" = "nested" ]; then
    manifest="$base/$mp/$plug/$ver/.claude-plugin/plugin.json"
  else
    manifest="$base/$mp/$plug/$ver/plugin.json"
  fi
  write_hooks_file "$manifest" "$event" "$matcher" "$command"
}

run_script() {
  # run_script <project_root> <user_settings> <plugin_base>
  local proj="$1" user="$2" plugbase="$3"
  LOOM_FIND_HOOK_DUPS_USER_SETTINGS="$user" \
  LOOM_FIND_HOOK_DUPS_PLUGIN_BASE="$plugbase" \
  bash "$SCRIPT" "$proj" 2>/dev/null
}

# ----------------------------------------------------------------------
# 1. Script existence + executable
# ----------------------------------------------------------------------
echo "==> Script exists and is executable"
if [ -f "$SCRIPT" ]; then
  pass "find-hook-dups.sh present"
else
  fail "find-hook-dups.sh present" "(missing: $SCRIPT)"
fi
if [ -x "$SCRIPT" ]; then
  pass "find-hook-dups.sh executable"
else
  fail "find-hook-dups.sh executable"
fi

# ----------------------------------------------------------------------
# 2. Clean fixture (no settings, no plugins) → empty output
# ----------------------------------------------------------------------
echo "==> Clean fixture produces no output"
fix=$(make_fixture)
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if [ -z "$out" ]; then
  pass "empty fixture → no output"
else
  fail "empty fixture → no output" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 3. Empty hooks blocks → no output
# ----------------------------------------------------------------------
echo "==> Empty hooks blocks → no output"
fix=$(make_fixture)
write_empty_hooks_file "$fix/proj/.claude/settings.json"
write_empty_hooks_file "$fix/user-settings.json"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if [ -z "$out" ]; then
  pass "empty hooks → no output"
else
  fail "empty hooks → no output" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 4. Project hook with no matching plugin → no output
# ----------------------------------------------------------------------
echo "==> Project hook, no plugin match → no output"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "SessionStart" "" "bd prime"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if [ -z "$out" ]; then
  pass "lone project hook → no output"
else
  fail "lone project hook → no output" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 5. Project + plugin match (nested layout) → WARN line
# ----------------------------------------------------------------------
echo "==> Project dup vs nested-layout plugin → WARN line"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "SessionStart" "" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "SessionStart" "" "bd prime" "nested"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if echo "$out" | grep -q "^WARN .*SessionStart.*bd prime"; then
  pass "project dup → WARN line"
else
  fail "project dup → WARN line" "(got: $out)"
fi
# Should NOT have INFO line — there's no user-level settings
if echo "$out" | grep -q "^INFO "; then
  fail "project dup → no spurious INFO" "(got: $out)"
else
  pass "project dup → no spurious INFO"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 6. Project + plugin match (flat layout) → WARN line
# ----------------------------------------------------------------------
echo "==> Project dup vs flat-layout plugin → WARN line"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "SessionStart" "" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "mempalace-mp" "mempalace" "3.3.0" "SessionStart" "" "bd prime" "flat"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if echo "$out" | grep -q "^WARN .*SessionStart.*bd prime"; then
  pass "project dup vs flat layout → WARN line"
else
  fail "project dup vs flat layout → WARN line" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 7. User-level dup → INFO line (not WARN)
# ----------------------------------------------------------------------
echo "==> User-level dup vs plugin → INFO line"
fix=$(make_fixture)
write_hooks_file "$fix/user-settings.json" "SessionStart" "" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "SessionStart" "" "bd prime" "nested"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if echo "$out" | grep -q "^INFO .*SessionStart.*bd prime"; then
  pass "user dup → INFO line"
else
  fail "user dup → INFO line" "(got: $out)"
fi
if echo "$out" | grep -q "^WARN "; then
  fail "user dup → no spurious WARN" "(got: $out)"
else
  pass "user dup → no spurious WARN"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 8. Matchers differ → not a dup
# ----------------------------------------------------------------------
echo "==> Different matchers → no dup"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "PreToolUse" "Bash" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "PreToolUse" "Edit" "bd prime" "nested"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if [ -z "$out" ]; then
  pass "different matchers → no dup"
else
  fail "different matchers → no dup" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 9. Commands differ → not a dup
# ----------------------------------------------------------------------
echo "==> Different commands → no dup"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "SessionStart" "" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "mempalace-mp" "mempalace" "3.3.0" "SessionStart" "" "mempalace status" "nested"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if [ -z "$out" ]; then
  pass "different commands → no dup"
else
  fail "different commands → no dup" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 10. Both project + user dup → one WARN AND one INFO
# ----------------------------------------------------------------------
echo "==> Project + user both dup → WARN + INFO"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "SessionStart" "" "bd prime"
write_hooks_file "$fix/user-settings.json" "SessionStart" "" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "SessionStart" "" "bd prime" "nested"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
warn_count=$(echo "$out" | grep -c "^WARN " || true)
info_count=$(echo "$out" | grep -c "^INFO " || true)
if [ "$warn_count" = "1" ] && [ "$info_count" = "1" ]; then
  pass "both dup → 1 WARN + 1 INFO"
else
  fail "both dup → 1 WARN + 1 INFO" "(WARN=$warn_count INFO=$info_count out=$out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 11. Manifest paths surface in output (for actionability)
# ----------------------------------------------------------------------
echo "==> Output names BOTH registration sites"
fix=$(make_fixture)
write_hooks_file "$fix/proj/.claude/settings.json" "SessionStart" "" "bd prime"
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "SessionStart" "" "bd prime" "nested"
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" || true)
if echo "$out" | grep -q "settings.json" && echo "$out" | grep -q "plugin.json"; then
  pass "output names both settings.json AND plugin.json paths"
else
  fail "output names both registration sites" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 12. Missing project settings.json → no crash, no output
# ----------------------------------------------------------------------
echo "==> Missing project settings.json → silent"
fix=$(make_fixture)
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "SessionStart" "" "bd prime" "nested"
# No project settings at all
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" 2>&1 || true)
if [ -z "$out" ]; then
  pass "missing settings.json → silent"
else
  fail "missing settings.json → silent" "(got: $out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 13. Malformed JSON in settings → no crash
# ----------------------------------------------------------------------
echo "==> Malformed JSON → no crash"
fix=$(make_fixture)
mkdir -p "$fix/proj/.claude"
echo "{this is not json" >"$fix/proj/.claude/settings.json"
write_plugin_manifest "$fix/plugin-cache" "beads-mp" "beads" "0.49.3" "SessionStart" "" "bd prime" "nested"
rc=0
out=$(run_script "$fix/proj" "$fix/user-settings.json" "$fix/plugin-cache" 2>/dev/null) || rc=$?
if [ "$rc" = "0" ]; then
  pass "malformed JSON → exit 0 (no crash)"
else
  fail "malformed JSON → exit 0 (no crash)" "(rc=$rc out=$out)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
