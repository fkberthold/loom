#!/usr/bin/env bash
# workflow-mode.sh — resolve workflow mode (full/light/off) for the current project.
#
# Three modes:
#   full   — everything: hooks fire, recipe runs, status line populated.
#   light  — informational only: blocking hooks pass through, recipe still
#            available but warns when invoked.
#   off    — workflow disabled: hooks silent, recipe refuses, status line empty.
#
# Resolution priority:
#   1. CLAUDE_WORKFLOW_OFF=1 env var → "off" (hard escape hatch)
#   2. <project>/.claude/workflow.json `.mode` field
#   3. Default → "full"
#
# Sourceable library. Provides:
#   workflow_project_root [start_dir]   echoes detected project root
#   workflow_resolve_mode [start_dir]   echoes "full" | "light" | "off"
#   workflow_mode_is_full [start_dir]   exit 0 iff resolved mode is "full"
#   workflow_mode_is_off  [start_dir]   exit 0 iff resolved mode is "off"

# Walk up from start_dir until .beads/ is found. Fallback: git toplevel.
# Final fallback: start_dir itself.
workflow_project_root() {
  local start="${1:-$PWD}"
  local d="$start"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/.beads" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d=$(dirname "$d")
  done
  if d=$(cd "$start" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null); then
    printf '%s\n' "$d"
    return 0
  fi
  printf '%s\n' "$start"
}

workflow_resolve_mode() {
  if [ "${CLAUDE_WORKFLOW_OFF:-0}" = "1" ]; then
    printf 'off\n'
    return 0
  fi

  local root
  root=$(workflow_project_root "${1:-$PWD}")
  local cfg="$root/.claude/workflow.json"
  if [ -f "$cfg" ]; then
    local mode=""
    if command -v jq >/dev/null 2>&1; then
      mode=$(jq -r '.mode // ""' "$cfg" 2>/dev/null || true)
    else
      mode=$(grep -oE '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" 2>/dev/null \
        | sed -E 's/.*"([^"]+)"$/\1/' | head -1)
    fi
    case "$mode" in
      full|light|off)
        printf '%s\n' "$mode"
        return 0
        ;;
    esac
  fi

  printf 'full\n'
}

workflow_mode_is_full() {
  [ "$(workflow_resolve_mode "${1:-$PWD}")" = "full" ]
}

workflow_mode_is_off() {
  [ "$(workflow_resolve_mode "${1:-$PWD}")" = "off" ]
}
