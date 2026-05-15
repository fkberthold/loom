#!/usr/bin/env bash
# find-hook-dups.sh — detect duplicate Claude Code hook command
# registrations across a project's settings, the user's settings,
# and the enabled plugins' manifests.
#
# Surfaced by loom-nsb research (2026-05-09): a duplicate `bd prime`
# SessionStart in liza_base fired the command twice per session,
# billing wasted tokens. Shipping detection here (loom-ann) so future
# projects don't accumulate the same drift.
#
# Usage: find-hook-dups.sh <project_root>
#
# Stdout (one line per duplicate, exit always 0):
#   WARN <event> "<command>": registered in both <project_settings_path> AND <plugin_manifest_path>
#   INFO <event> "<command>": registered in both <user_settings_path> AND <plugin_manifest_path>
#
# WARN = project-level dup (fixable by editing project settings).
# INFO = user-level dup (machine-specific; advisory only).
#
# Env-var overrides (for tests; defaults are the real CC paths):
#   LOOM_FIND_HOOK_DUPS_USER_SETTINGS  — path to user settings.json
#   LOOM_FIND_HOOK_DUPS_PLUGIN_BASE    — plugin cache directory

set -uo pipefail

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  echo "usage: find-hook-dups.sh <project_root>" >&2
  exit 2
fi

USER_SETTINGS="${LOOM_FIND_HOOK_DUPS_USER_SETTINGS:-$HOME/.claude/settings.json}"
PLUGIN_BASE="${LOOM_FIND_HOOK_DUPS_PLUGIN_BASE:-$HOME/.claude/plugins/cache}"
PROJECT_SETTINGS="$PROJECT_ROOT/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  # No jq → cannot parse; silently exit 0 (informational check).
  exit 0
fi

# Extract (event TAB matcher TAB command) triples from a settings-shaped
# JSON file. Returns empty on missing/malformed file.
extract_triples() {
  local file="$1"
  [ -f "$file" ] || return 0
  jq -r '
    (.hooks // {}) | to_entries[]
    | .key as $event
    | (.value // []) | .[]?
    | (.matcher // "") as $matcher
    | (.hooks // []) | .[]?
    | select(.type == "command")
    | [$event, $matcher, .command] | join("")
  ' "$file" 2>/dev/null || true
}

# Collect all plugin manifest triples into a temp file with manifest path
# appended as a 4th tab-separated field.
PLUGIN_TUPLES=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$PLUGIN_TUPLES"' EXIT

if [ -d "$PLUGIN_BASE" ]; then
  # Enumerate both layouts:
  #   <base>/<marketplace>/<plugin>/<version>/plugin.json            (flat)
  #   <base>/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json (nested)
  while IFS= read -r -d '' manifest; do
    extract_triples "$manifest" | while IFS=$'\x1f' read -r event matcher command; do
      [ -z "$event" ] && continue
      printf "%s\x1f%s\x1f%s\x1f%s\n" "$event" "$matcher" "$command" "$manifest" >>"$PLUGIN_TUPLES"
    done
  done < <(find "$PLUGIN_BASE" \
    \( -path "*/plugin.json" -o -path "*/.claude-plugin/plugin.json" \) \
    -type f -print0 2>/dev/null)
fi

# Compare a settings file's tuples against the plugin tuples; emit
# one prefixed line per match.
emit_dups() {
  local prefix="$1" settings_file="$2"
  [ -f "$settings_file" ] || return 0
  extract_triples "$settings_file" | while IFS=$'\x1f' read -r event matcher command; do
    [ -z "$event" ] && continue
    [ -z "$command" ] && continue
    while IFS=$'\x1f' read -r p_event p_matcher p_command p_manifest; do
      if [ "$event" = "$p_event" ] && \
         [ "$matcher" = "$p_matcher" ] && \
         [ "$command" = "$p_command" ]; then
        printf '%s %s "%s": registered in both %s AND %s\n' \
          "$prefix" "$event" "$command" "$settings_file" "$p_manifest"
      fi
    done <"$PLUGIN_TUPLES"
  done
}

emit_dups "WARN" "$PROJECT_SETTINGS"
emit_dups "INFO" "$USER_SETTINGS"

exit 0
