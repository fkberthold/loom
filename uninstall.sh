#!/usr/bin/env bash
# loom uninstall.sh — remove loom's symlinks from ~/.claude/, restore
# any .pre-loom.bak backups, and revert settings.json (best-effort).
#
# Usage:
#   ./uninstall.sh           # uninstall
#   ./uninstall.sh --check   # report what WOULD be done

set -euo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DRY_RUN=0

if [ "${1:-}" = "--check" ]; then
  DRY_RUN=1
fi

log() { echo "[loom-uninstall] $*"; }
do_or_print() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  WOULD: $*"
  else
    eval "$*"
  fi
}

# uninstall_link <relpath-in-claude-home>
uninstall_link() {
  local rel="$1"
  local dst="$CLAUDE_HOME/$rel"

  if [ -L "$dst" ]; then
    # Confirm it points into loom before removing.
    target=$(readlink "$dst")
    case "$target" in
      "$LOOM_ROOT"/*)
        do_or_print "rm '$dst'"
        log "  removed symlink $rel"
        ;;
      *)
        log "  SKIP $rel (symlink not pointing into loom: $target)"
        ;;
    esac
  fi

  # Restore backup if one exists.
  if [ -e "$dst.pre-loom.bak" ]; then
    do_or_print "mv '$dst.pre-loom.bak' '$dst'"
    log "  restored $rel from .pre-loom.bak"
  fi
}

log "loom root:      $LOOM_ROOT"
log "uninstall from: $CLAUDE_HOME"
[ "$DRY_RUN" = "1" ] && log "(dry-run mode — no changes)"
echo ""

log "Removing skill links..."
uninstall_link skills/bugfix-a-bead/SKILL.md
uninstall_link skills/bead-lifecycle-shell/SKILL.md
uninstall_link skills/session-startup/SKILL.md
# v1 working-a-bead skill (renamed to bugfix-a-bead 2026-05-03 by loom-lzi); remove any stale link
uninstall_link skills/working-a-bead/SKILL.md

log "Removing agent links..."
for f in "$LOOM_ROOT"/agents/*.md; do
  uninstall_link "agents/$(basename "$f")"
done

log "Removing command links..."
for f in "$LOOM_ROOT"/commands/*.md; do
  uninstall_link "commands/$(basename "$f")"
done

log "Removing hook links..."
for f in "$LOOM_ROOT"/hooks/*.sh; do
  uninstall_link "hooks/$(basename "$f")"
done

log "Removing lib links..."
for f in "$LOOM_ROOT"/lib/*.sh; do
  uninstall_link "lib/$(basename "$f")"
done
if [ -d "$LOOM_ROOT/lib/tests" ]; then
  for f in "$LOOM_ROOT"/lib/tests/*; do
    [ -e "$f" ] || continue
    uninstall_link "lib/tests/$(basename "$f")"
  done
fi

log "Removing script links..."
for f in "$LOOM_ROOT"/scripts/*; do
  uninstall_link "scripts/$(basename "$f")"
done

# Settings: restore from backup if it exists.
SETTINGS="$CLAUDE_HOME/settings.json"
if [ -e "$SETTINGS.pre-loom.bak" ]; then
  log ""
  log "Restoring settings.json from .pre-loom.bak..."
  do_or_print "mv '$SETTINGS.pre-loom.bak' '$SETTINGS'"
else
  log ""
  log "No settings.json.pre-loom.bak found — leaving settings.json as-is."
  log "If you want to remove loom's stanzas manually, edit ~/.claude/settings.json"
  log "and remove: hooks.PreToolUse[matcher=Bash] entries pointing at \$HOME/.claude/hooks/{bd-*,git-push-bd-sync,workflow-mode-onboarding}.sh,"
  log "hooks.SessionStart entry, statusLine, and the Bash(bd:*) + mcp__mempalace__* permissions."
fi

log ""
log "Uninstall complete."
