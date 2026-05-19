#!/usr/bin/env bash
# loom install.sh — symlink loom's files into ~/.claude/ and merge
# settings.snippet.json into ~/.claude/settings.json.
#
# Idempotent: re-running is safe. Existing files at the install paths
# are backed up (suffixed .pre-loom.bak) only on FIRST install; on
# subsequent runs the symlinks are reset but backups aren't re-created.
#
# Usage:
#   ./install.sh           # install (default)
#   ./install.sh --check   # report what WOULD be done; no changes
#
# Run from the loom repo root.

set -euo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DRY_RUN=0

if [ "${1:-}" = "--check" ]; then
  DRY_RUN=1
fi

log() { echo "[loom-install] $*"; }
do_or_print() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  WOULD: $*"
  else
    eval "$*"
  fi
}

# Sanity check: are we in the loom repo?
for required in skills/bugfix-a-bead/SKILL.md hooks/bd-claim-research.sh settings.snippet.json; do
  if [ ! -f "$LOOM_ROOT/$required" ]; then
    echo "[loom-install] ERROR: not in loom repo root (missing $required)" >&2
    exit 1
  fi
done

log "loom root:    $LOOM_ROOT"
log "install into: $CLAUDE_HOME"
[ "$DRY_RUN" = "1" ] && log "(dry-run mode — no changes)"
echo ""

# Ensure target directories exist.
for d in skills agents commands hooks lib lib/tests scripts; do
  if [ ! -d "$CLAUDE_HOME/$d" ]; then
    do_or_print "mkdir -p '$CLAUDE_HOME/$d'"
  fi
done

# install_link <relpath-in-loom> <relpath-in-claude-home>
# - if target exists and is NOT a symlink: back up to .pre-loom.bak (once)
# - if target is a symlink already: replace it
# - then symlink target → loom source
install_link() {
  local src_rel="$1"
  local dst_rel="$2"
  local src="$LOOM_ROOT/$src_rel"
  local dst="$CLAUDE_HOME/$dst_rel"

  if [ ! -e "$src" ]; then
    log "SKIP (source missing): $src_rel"
    return 0
  fi

  # Ensure parent dir exists (per-skill subdirs aren't pre-created above).
  local dst_parent
  dst_parent="$(dirname "$dst")"
  if [ ! -d "$dst_parent" ]; then
    do_or_print "mkdir -p '$dst_parent'"
  fi

  if [ -L "$dst" ]; then
    # Already a symlink. Reset it.
    do_or_print "rm '$dst'"
  elif [ -e "$dst" ]; then
    # Real file — back up if no backup exists yet.
    if [ ! -e "$dst.pre-loom.bak" ]; then
      do_or_print "mv '$dst' '$dst.pre-loom.bak'"
      log "  backed up existing $dst_rel → ${dst_rel}.pre-loom.bak"
    else
      do_or_print "rm '$dst'"
    fi
  fi

  do_or_print "ln -s '$src' '$dst'"
  log "  linked $dst_rel → loom/$src_rel"
}

# Prune dangling loom-owned symlinks (orphans from renamed/deleted
# loom files). Walks ~/.claude/{skills,agents,commands,hooks,lib,scripts}/
# symlinks; removes those whose target points into $LOOM_ROOT/ but
# the source file no longer exists. Preserves .pre-loom.bak files
# (regular files; the -type l filter excludes them).
log "Pruning dangling loom-owned symlinks..."
for dir in skills agents commands hooks lib scripts; do
  [ -d "$CLAUDE_HOME/$dir" ] || continue
  find "$CLAUDE_HOME/$dir" -maxdepth 3 -type l 2>/dev/null | while read -r link; do
    target=$(readlink "$link")
    case "$target" in
      "$LOOM_ROOT"/*)
        if [ ! -e "$target" ]; then
          do_or_print "rm '$link'"
          log "  pruned dangling: $link"
        fi
        ;;
    esac
  done
done

log "Linking skills..."
for f in "$LOOM_ROOT"/skills/*/SKILL.md; do
  rel="${f#$LOOM_ROOT/}"
  install_link "$rel" "$rel"
done

log "Linking agents..."
for f in "$LOOM_ROOT"/agents/*.md; do
  name=$(basename "$f")
  install_link "agents/$name" "agents/$name"
done

log "Linking commands..."
for f in "$LOOM_ROOT"/commands/*.md; do
  name=$(basename "$f")
  install_link "commands/$name" "commands/$name"
done

log "Linking hooks..."
for f in "$LOOM_ROOT"/hooks/*.sh; do
  name=$(basename "$f")
  install_link "hooks/$name" "hooks/$name"
done

log "Linking lib..."
for f in "$LOOM_ROOT"/lib/*.sh; do
  name=$(basename "$f")
  install_link "lib/$name" "lib/$name"
done

log "Linking lib/tests..."
if [ -d "$LOOM_ROOT/lib/tests" ]; then
  for f in "$LOOM_ROOT"/lib/tests/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    install_link "lib/tests/$name" "lib/tests/$name"
  done
fi

log "Linking scripts..."
for f in "$LOOM_ROOT"/scripts/*; do
  name=$(basename "$f")
  install_link "scripts/$name" "scripts/$name"
done

# Make sure scripts + hooks are executable.
if [ "$DRY_RUN" = "0" ]; then
  chmod +x "$LOOM_ROOT"/hooks/*.sh "$LOOM_ROOT"/scripts/* "$LOOM_ROOT"/install.sh "$LOOM_ROOT"/uninstall.sh 2>/dev/null || true
fi

# Merge settings.snippet.json into ~/.claude/settings.json.
log ""
log "Settings.json merge:"
SETTINGS="$CLAUDE_HOME/settings.json"
SNIPPET="$LOOM_ROOT/settings.snippet.json"

if [ ! -f "$SETTINGS" ]; then
  log "  $SETTINGS does not exist — creating from snippet."
  do_or_print "cp '$SNIPPET' '$SETTINGS'"
else
  if [ "$DRY_RUN" = "1" ]; then
    log "  WOULD: merge $SNIPPET into $SETTINGS (additive; preserves existing keys)"
  else
    # Back up existing settings once.
    if [ ! -e "$SETTINGS.pre-loom.bak" ]; then
      cp "$SETTINGS" "$SETTINGS.pre-loom.bak"
      log "  backed up existing settings.json → settings.json.pre-loom.bak"
    fi

    # Merge using python (jq could also do this; python is more universally available).
    python3 - <<EOF
import json, sys
with open("$SETTINGS") as f:
    cur = json.load(f)
with open("$SNIPPET") as f:
    snip = json.load(f)
snip.pop("_comment", None)

# Deep-merge permissions.allow (union of lists).
if "permissions" in snip:
    cur.setdefault("permissions", {})
    cur_allow = set(cur["permissions"].get("allow", []))
    snip_allow = set(snip["permissions"].get("allow", []))
    cur["permissions"]["allow"] = sorted(cur_allow | snip_allow)

# Replace hooks.PreToolUse[matcher=Bash] and hooks.SessionStart with snippet versions
# (loom owns these specific stanzas).
if "hooks" in snip:
    cur.setdefault("hooks", {})
    cur["hooks"]["PreToolUse"] = snip["hooks"]["PreToolUse"]
    cur["hooks"]["SessionStart"] = snip["hooks"]["SessionStart"]

# Replace statusLine with snippet version (loom owns it).
if "statusLine" in snip:
    cur["statusLine"] = snip["statusLine"]

with open("$SETTINGS", "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")
EOF
    log "  merged settings.snippet.json into settings.json"
  fi
fi

# Wire the bd-merge-driver in loom's own .git/config (loom-4um).
# Merge drivers are stored in git config (not in the tree), so the
# repo's .gitattributes references `merge=bd-export` but nothing
# resolves that name until `git config merge.bd-export.driver` is
# set. Set it here so loom's own .beads/issues.jsonl is protected
# against the silent-auto-merge regression class.
#
# Downstream projects that adopt loom set the same `git config`
# entry in their own .git/config — that wiring is handled by
# /audit-project, not by this install.sh (loom's install only
# touches ~/.claude/ and the loom repo itself).
log ""
log "Wiring bd-merge-driver in loom's .git/config..."
if [ "$DRY_RUN" = "1" ]; then
  log "  WOULD: git -C '$LOOM_ROOT' config merge.bd-export.name 'bd-export merge driver (loom-4um)'"
  log "  WOULD: git -C '$LOOM_ROOT' config merge.bd-export.driver 'scripts/bd-merge-driver.sh %O %A %B %P'"
else
  git -C "$LOOM_ROOT" config merge.bd-export.name 'bd-export merge driver (loom-4um)' || true
  git -C "$LOOM_ROOT" config merge.bd-export.driver 'scripts/bd-merge-driver.sh %O %A %B %P' || true
  log "  set merge.bd-export.driver → scripts/bd-merge-driver.sh"
fi

log ""
log "Install complete."
log ""
log "Next steps:"
log "  1. Verify with: /hooks (in Claude Code) — should list 5 PreToolUse Bash hooks + 1 SessionStart hook"
log "  2. Confirm status line in Claude Code TUI shows 'WORKFLOW: ...'"
log "  3. For per-project setup, run /audit-project from inside a beads workspace"
