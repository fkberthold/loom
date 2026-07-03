#!/usr/bin/env bash
# auto-exclude.sh — automatically hide loom's OWN artifacts from the git of
# a repo loom does NOT manage, so they never surface in a teammate's
# `git status`. The "auto" counterpart to explicit guest mode
# (scripts/loom-guest): guest mode's 2026-05-06 design deliberately
# declined auto-detect; this supplies it for the narrow artifact-hiding
# case (loom-e5ys, grounded_in the guest-mode drawer).
#
# Mechanism: reuse lib/info-exclude.sh's # BEGIN LOOM / # END LOOM block in
# <repo>/.git/info/exclude — per-clone, NEVER committed. Frank's pick over a
# committed .gitignore, which would itself be a diff the team must accept.
#
# Sourceable library. API:
#   loom_auto_exclude_sync [--start-dir=PATH]
#
# ADD-ONLY, keyed on <repo>/.claude/workflow.json:
#   - ABSENT  (not loom-managed)   -> info_exclude_add(<artifact set>)
#   - PRESENT (managed OR guest)   -> NO-OP
#
# Why ADD-only (no self-heal remove): bd-worktree-preseed.sh and loom-guest
# both write a # BEGIN LOOM block that info_exclude_remove matches on a loose
# prefix, so a blanket remove would clobber the preseed .beads/issues.jsonl
# exclusion and re-open the loom-x4m data-loss bug. "Present -> no-op" also
# covers guest mode (loom-guest owns its own block) with no special case, and
# a shared repo typically wants loom artifacts hidden even after a mode is
# picked. Un-hiding for a repo becoming genuinely loom-owned is the explicit
# /audit-project adoption path's job, not an every-session blanket remove.
#
# The artifact set is loom-created files ONLY. It deliberately EXCLUDES
# .beads/ (may be the team's shared bd tracker) and .claude/settings.json
# (may be the team's shared Claude Code config). .claude/settings.local.json
# is per-machine by Claude Code convention, so hiding it is always safe.

__AE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=info-exclude.sh
. "$__AE_LIB_DIR/info-exclude.sh"
# shellcheck source=workflow-config.sh
. "$__AE_LIB_DIR/workflow-config.sh"

# The loom-created artifact set auto-hidden in unmanaged repos.
__AE_ARTIFACTS=(
  .claude/workflow.json
  .claude/workflow-state.json
  .claude/settings.local.json
  /issues.jsonl
)

# Sync .git/info/exclude for the repo containing --start-dir (default $PWD).
# Add loom's artifact block when the repo is NOT loom-managed; no-op when it
# is (or when it isn't a git working tree). Always exits 0 — never fatal to a
# caller (e.g. a SessionStart hook).
loom_auto_exclude_sync() {
  local start="$PWD"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --start-dir=*) start="${arg#--start-dir=}" ;;
    esac
  done

  # Must be inside a git working tree; degrade to a clean no-op otherwise.
  info_exclude_path --start-dir="$start" >/dev/null 2>&1 || return 0

  # Loom-managed (workflow.json present) OR guest mode active -> leave the
  # repo's exclude untouched. Guest mode's block is owned by loom-guest;
  # a genuinely loom-owned repo commits its own artifacts.
  local cfg
  cfg=$(workflow_config_path "$start" 2>/dev/null || true)
  [ -n "$cfg" ] && [ -f "$cfg" ] && return 0

  # Not loom-managed -> hide loom's own artifacts (additive + idempotent).
  info_exclude_add --start-dir="$start" "${__AE_ARTIFACTS[@]}"
}
