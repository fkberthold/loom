#!/usr/bin/env bash
# info-exclude.sh — manage a BEGIN LOOM / END LOOM block in
# <repo>/.git/info/exclude (per-clone, never committed). Used by guest
# mode to hide loom artifacts (.claude/workflow.json, etc.) from the
# host repo's git without modifying the committed .gitignore.
#
# Sourceable library. API:
#   info_exclude_path   [--start-dir=PATH]                  # echo file path
#   info_exclude_status [--start-dir=PATH]                  # exit 0 if present
#   info_exclude_add    [--start-dir=PATH] PATTERN [PATTERN...]
#   info_exclude_remove [--start-dir=PATH]
#
# Default start dir is $PWD when --start-dir= is omitted. All commands
# require start dir to be inside a git working tree.
#
# Block format:
#   # BEGIN LOOM (managed by loom guest mode — do not edit)
#   <pattern>
#   <pattern>
#   # END LOOM
#
# add() merges new patterns into an existing block (deduped, preserving
# insertion order). remove() strips the block exactly, leaving any
# pre-existing content untouched. Both are idempotent.

# Resolve the repo's exclude file path. Echoes the path; returns 1 if
# start dir isn't inside a git working tree.
__ie_resolve_path() {
  local start="$1"
  local toplevel
  toplevel=$(cd "$start" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1
  printf '%s/.git/info/exclude\n' "$toplevel"
}

info_exclude_path() {
  local start="$PWD"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --start-dir=*) start="${arg#--start-dir=}" ;;
    esac
  done
  __ie_resolve_path "$start"
}

info_exclude_status() {
  local path
  path=$(info_exclude_path "$@") || return 1
  [ -f "$path" ] || return 1
  grep -q '^# BEGIN LOOM' "$path"
}

info_exclude_add() {
  local start="$PWD"
  local patterns=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --start-dir=*) start="${arg#--start-dir=}" ;;
      *) patterns+=("$arg") ;;
    esac
  done

  if [ ${#patterns[@]} -eq 0 ]; then
    echo "info_exclude_add: at least one pattern required" >&2
    return 2
  fi

  local path
  path=$(__ie_resolve_path "$start") || return 1
  mkdir -p "$(dirname "$path")"
  [ -f "$path" ] || touch "$path"

  # Capture existing block patterns (if any), preserving order.
  local existing
  existing=$(awk '
    /^# BEGIN LOOM/             { in_block = 1; next }
    in_block && /^# END LOOM/   { in_block = 0; next }
    in_block                    { print }
  ' "$path")

  # Read file content WITHOUT the block, stripped of trailing whitespace
  # so we can re-append the block with a deterministic boundary.
  local pre
  pre=$(awk '
    /^# BEGIN LOOM/             { in_block = 1; next }
    in_block && /^# END LOOM/   { in_block = 0; next }
    !in_block                   { print }
  ' "$path")
  # $(...) already strips trailing newlines; that is what we want.

  # Merge existing + new, dedup (preserve first-occurrence order).
  local pat all=""
  if [ -n "$existing" ]; then
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      all="${all}${pat}"$'\n'
    done <<<"$existing"
  fi
  for pat in "${patterns[@]}"; do
    if ! printf '%s' "$all" | grep -qxF "$pat"; then
      all="${all}${pat}"$'\n'
    fi
  done

  # Rewrite file: pre-block content (with single trailing newline if
  # non-empty) + block.
  local tmp
  tmp=$(mktemp)
  if [ -n "$pre" ]; then
    printf '%s\n' "$pre" >> "$tmp"
  fi
  printf '# BEGIN LOOM (managed by loom guest mode — do not edit)\n' >> "$tmp"
  printf '%s' "$all" >> "$tmp"
  printf '# END LOOM\n' >> "$tmp"

  mv "$tmp" "$path"
}

info_exclude_remove() {
  local start="$PWD"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --start-dir=*) start="${arg#--start-dir=}" ;;
    esac
  done

  local path
  path=$(__ie_resolve_path "$start") || return 1
  [ -f "$path" ] || return 0

  local tmp
  tmp=$(mktemp)
  awk '
    /^# BEGIN LOOM/             { in_block = 1; next }
    in_block && /^# END LOOM/   { in_block = 0; next }
    !in_block                   { print }
  ' "$path" > "$tmp"

  mv "$tmp" "$path"
}
