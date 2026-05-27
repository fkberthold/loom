#!/usr/bin/env bash
# workflow-config.sh — read/write the per-project workflow CONFIG file at
# <project>/.claude/workflow.json. Distinct from workflow-state.json (which
# is per-session ephemera). The config file holds:
#
#   - .mode    "full" | "light" | "off" (read by workflow_resolve_mode)
#   - .guest   { active: bool, bd_mode: "host"|"personal"|"none",
#                repo_key: "<basename>-<sha8>" }
#   - .deploy  string — shell command surfaced by /wrap-up section 6 as a
#              hint after the bead is closed. Optional. Empty / null /
#              absent → /wrap-up skips the section silently. Surface-only;
#              /wrap-up does NOT auto-run the command (loom-0k0).
#
# Sourceable library. Provides:
#   workflow_config_path [start_dir]
#   workflow_config_guest_active [start_dir]              exit 0 iff active
#   workflow_config_guest_get <field> [start_dir]         echo guest.<field>
#   workflow_config_guest_on <bd_mode> <repo_key> [start_dir]
#   workflow_config_guest_off [start_dir]
#   workflow_resolve_deploy [start_dir]                   echo .deploy or ""
#
# bd_mode must be one of: host, personal, none.

# Ensure project root resolution helper is available.
__WFC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workflow-mode.sh
. "$__WFC_LIB_DIR/workflow-mode.sh"

workflow_config_path() {
  local root
  root=$(workflow_project_root "${1:-$PWD}")
  printf '%s/.claude/workflow.json\n' "$root"
}

# Exit 0 if guest mode is active, non-zero otherwise.
workflow_config_guest_active() {
  local path
  path=$(workflow_config_path "${1:-$PWD}")
  [ -f "$path" ] || return 1

  local v=""
  if command -v jq >/dev/null 2>&1; then
    v=$(jq -r '.guest.active // false' "$path" 2>/dev/null || true)
  else
    # Naive fallback: look for "active": true within a "guest" block.
    v=$(awk '
      /"guest"[[:space:]]*:/ { in_g = 1 }
      in_g && /"active"[[:space:]]*:[[:space:]]*true/ { print "true"; exit }
      in_g && /}/ { in_g = 0 }
    ' "$path")
  fi
  [ "$v" = "true" ]
}

# Echo .guest.<field>; empty if missing or guest block absent.
# Field is one of: active, bd_mode, repo_key.
workflow_config_guest_get() {
  local field="$1"
  local path
  path=$(workflow_config_path "${2:-$PWD}")
  [ -f "$path" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.guest[$f] // "" | tostring' "$path" 2>/dev/null \
      | sed 's/^null$//'
  else
    # Naive fallback: scan the guest block.
    awk -v f="$field" '
      /"guest"[[:space:]]*:/ { in_g = 1 }
      in_g && $0 ~ "\"" f "\"[[:space:]]*:" {
        # Extract the value after the colon.
        sub(/^[^:]*:[[:space:]]*/, "")
        sub(/[,}[:space:]]*$/, "")
        gsub(/^"|"$/, "")
        print
        exit
      }
      in_g && /}/ { in_g = 0 }
    ' "$path"
  fi
}

# Validate bd_mode arg.
__wfc_validate_bd_mode() {
  case "$1" in
    host|personal|none) return 0 ;;
    *) return 1 ;;
  esac
}

# Activate guest mode. Writes guest.{active=true, bd_mode, repo_key}.
# Idempotent: rewriting the same values is a no-op.
workflow_config_guest_on() {
  local bd_mode="${1:-}"
  local repo_key="${2:-}"
  local start="${3:-$PWD}"

  if [ -z "$bd_mode" ] || [ -z "$repo_key" ]; then
    echo "workflow_config_guest_on: usage: bd_mode repo_key [start_dir]" >&2
    return 2
  fi
  if ! __wfc_validate_bd_mode "$bd_mode"; then
    echo "workflow_config_guest_on: invalid bd_mode '$bd_mode' (expected host|personal|none)" >&2
    return 2
  fi

  local path
  path=$(workflow_config_path "$start")
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"

  if [ ! -f "$path" ]; then
    printf '{"v": 1, "mode": "full"}\n' > "$path"
  fi

  if command -v jq >/dev/null 2>&1; then
    jq --arg bd "$bd_mode" --arg rk "$repo_key" \
      '.guest = {active: true, bd_mode: $bd, repo_key: $rk}' \
      "$path" > "$path.tmp.$$" && mv "$path.tmp.$$" "$path"
  else
    # Without jq, hand-merge: read mode, write a fresh object.
    local mode
    mode=$(workflow_resolve_mode "$start")
    printf '{"v": 1, "mode": "%s", "guest": {"active": true, "bd_mode": "%s", "repo_key": "%s"}}\n' \
      "$mode" "$bd_mode" "$repo_key" > "$path.tmp.$$"
    mv "$path.tmp.$$" "$path"
  fi
}

# Deactivate guest mode. Removes the guest block entirely (rather than
# setting active=false), so the on-disk config returns to its pre-guest
# shape. Other fields preserved. Idempotent.
workflow_config_guest_off() {
  local start="${1:-$PWD}"
  local path
  path=$(workflow_config_path "$start")
  [ -f "$path" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    jq 'del(.guest)' "$path" > "$path.tmp.$$" && mv "$path.tmp.$$" "$path"
  else
    # Without jq: read mode, rewrite without guest block.
    local mode
    mode=$(workflow_resolve_mode "$start")
    printf '{"v": 1, "mode": "%s"}\n' "$mode" > "$path.tmp.$$"
    mv "$path.tmp.$$" "$path"
  fi
}

# Resolve .deploy — the project's wrap-up deploy-hint command (loom-0k0).
# Echo the string verbatim; empty when absent, null, empty-string, malformed,
# or workflow.json missing. Always exit 0 — /wrap-up must not crash on bad
# config; an empty string just means "skip section 6 silently."
workflow_resolve_deploy() {
  local start="${1:-$PWD}"
  local path
  path=$(workflow_config_path "$start")
  [ -f "$path" ] || return 0
  local val=""
  if command -v jq >/dev/null 2>&1; then
    val=$(jq -r '.deploy // ""' "$path" 2>/dev/null || true)
  else
    # No-jq fallback: extract the .deploy string with grep/sed. Supports
    # plain quoted-string values; nested objects / arrays unsupported (the
    # whole schema is flat in practice).
    val=$(grep -oE '"deploy"[[:space:]]*:[[:space:]]*"[^"]*"' "$path" 2>/dev/null \
      | sed -E 's/^"deploy"[[:space:]]*:[[:space:]]*"(.*)"$/\1/' | head -1)
  fi
  # jq returns the literal string "null" for a JSON null when -r is used
  # only if the filter explicitly evaluates to null — `.deploy // ""`
  # already collapses null → "", so this guard is belt-and-suspenders.
  [ "$val" = "null" ] && val=""
  printf '%s' "$val"
}
