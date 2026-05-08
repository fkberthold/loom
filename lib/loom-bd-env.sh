#!/usr/bin/env bash
# loom-bd-env.sh — export BEADS_DIR when guest mode demands an external bd
# workspace. Sourceable; safe to source even if bd isn't installed and even
# in non-guest projects (it's a no-op then).
#
# bd 1.0.2 (a3f834b3) honors a BEADS_DIR environment variable for workspace
# resolution — even though it's not advertised in `bd --help`, the error
# hint "check BEADS_DIR/worktree setup" reveals it, and `bd where` confirms
# it overrides the cwd-walking auto-discovery (verified empirically). This
# is Option A from loom-26w's design (no shim, no flag-rewriting wrapper).
#
# See drawer_loom_decisions_12d7f8163e8855be037a007c for the design.
#
# Resolution rules:
#
#   guest active?        bd_mode      effect
#   ─────────────        ───────      ──────
#   no                   —            no-op (caller's BEADS_DIR preserved;
#                                     bd uses cwd discovery)
#   yes                  host         no-op (host's tracker via cwd)
#   yes                  none         no-op (no bd at all)
#   yes                  personal     export BEADS_DIR=$HOME/.loom/guests/<repo-key>/.beads
#
# Public:
#   loom_bd_env_apply [start_dir]    apply the rules to current shell

# Resolve the loom lib dir relative to this file so we can source workflow-config.
__LBE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workflow-config.sh
. "$__LBE_LIB_DIR/workflow-config.sh"

loom_bd_env_apply() {
  local start="${1:-$PWD}"

  # Non-guest project: leave BEADS_DIR alone. bd will auto-discover via cwd.
  if ! workflow_config_guest_active "$start"; then
    return 0
  fi

  local bd_mode
  bd_mode=$(workflow_config_guest_get bd_mode "$start")

  case "$bd_mode" in
    personal)
      local repo_key
      repo_key=$(workflow_config_guest_get repo_key "$start")
      if [ -z "$repo_key" ]; then
        return 0
      fi
      export BEADS_DIR="$HOME/.loom/guests/$repo_key/.beads"
      ;;
    host|none|"")
      # No-op. host: cwd discovery hits the host's .beads/ naturally.
      # none: caller asked for no bd. empty: malformed config — refuse to guess.
      :
      ;;
  esac
}
