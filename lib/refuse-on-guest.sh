#!/usr/bin/env bash
# refuse-on-guest.sh — shared bash helper that hooks/skills source to
# refuse an action consistently when guest mode is active.
#
# Background: guest mode (loom-4re, loom-guest skill) lets a developer
# work in a non-loom-managed repo without leaking loom-installed bd
# state, workflow.json edits, etc. into the host project. Hooks and
# skills that would otherwise write into the tree need to bail out
# cleanly when guest mode is on. This lib centralizes that check so
# every gate prints a uniform message.
#
# Design drawer: drawer_loom_decisions_12d7f8163e8855be037a007c
# (MemPalace loom/decisions wing, 2026-05-06).
#
# Sourceable library. Provides:
#   refuse_if_guest <action-name> [<override-hint>]
#     - Reads guest active state via workflow_config_guest_active
#       (sourced from lib/workflow-config.sh). The check uses $PWD as
#       the start dir, matching the calling hook/skill's cwd.
#     - If guest active: prints
#         Guest mode active — refusing <action-name>.
#         <override-hint or "Run /loom-guest off to override.">
#       to stderr, returns 1.
#     - If inactive: returns 0, no output.
#     - Missing action-name arg returns 2 (usage error).

# Resolve our directory and source workflow-config.sh exactly once.
__rog_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workflow-config.sh
. "$__rog_lib_dir/workflow-config.sh"

refuse_if_guest() {
  local action="${1:-}"
  local hint="${2:-Run /loom-guest off to override.}"

  if [ -z "$action" ]; then
    echo "refuse_if_guest: usage: refuse_if_guest <action-name> [<override-hint>]" >&2
    return 2
  fi

  if workflow_config_guest_active "$PWD"; then
    printf 'Guest mode active — refusing %s. %s\n' "$action" "$hint" >&2
    return 1
  fi

  return 0
}
