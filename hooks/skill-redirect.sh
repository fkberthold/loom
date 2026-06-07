#!/usr/bin/env bash
# PreToolUse hook for Skill. In a beads-tracked project, redirects a
# spontaneous superpowers:brainstorming Skill invocation to
# beadpowers:brainstorming (so the design lands as beads).
#
# Closes loom-i8t. The two skills carry WORD-FOR-WORD identical
# descriptions, so on auto-trigger the model has no distinguishing
# signal and defaults to superpowers; loom wants beadpowers. We do
# NOT control the plugin descriptions (plugin-owned, overwritten on
# upgrade), so a loom-owned PreToolUse hook is the robust fix. Bites
# every beads project, not just one.
#
# Confirmed PreToolUse payload shape for a Skill call:
#   {"tool_name":"Skill","tool_input":{"skill":"<name>","args":"<args>"}}
# The skill name lives in tool_input.skill.
#
# Resolution rules:
#   - tool not Skill → exit 0
#   - no .beads/ dir in the project (walk up from cwd) → exit 0
#   - tool_input.skill not a mapped key → exit 0
#   - mapped key → exit 2 with a stderr naming the replacement
#
# WHY BLOCK (exit 2), NOT a non-blocking nudge: a non-blocking nudge
# would let superpowers:brainstorming load and the wrong brainstorm
# starts — only exit 2 prevents the load so the model re-picks. This
# is a legitimate block case (differs from the loom-yb5 dispatch-nudge
# by design); the env bypass keeps it escapable and recovery is
# trivial (re-invoke the right skill).
#
# Bypass:
#   LOOM_SKILL_REDIRECT_SKIP=1   (literal "1" only, per loom-b1l)

set -uo pipefail

if [ "${LOOM_SKILL_REDIRECT_SKIP:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
  SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""')
else
  TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
  SKILL=$(echo "$INPUT" | grep -oP '"skill"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
fi

# Only act on Skill calls.
[ "$TOOL" = "Skill" ] || exit 0

# Empty skill name → nothing to redirect.
[ -n "$SKILL" ] || exit 0

# --- Redirect table (config-as-code) --------------------------------
# Currently ONE entry. To add more, add a `key) echo <value> ;;`
# case below. An unmapped skill returns empty → no redirect.
redirect_for() {
  case "$1" in
    superpowers:brainstorming) echo "beadpowers:brainstorming" ;;
    *) echo "" ;;
  esac
}

TARGET=$(redirect_for "$SKILL")
[ -n "$TARGET" ] || exit 0  # unmapped skill → passthrough

# --- Beads-project gate ---------------------------------------------
# Only redirect inside a beads-tracked project. Walk up from cwd
# looking for a .beads/ directory (mirrors the marker-walk in
# edit-after-failure-guard.sh).
walk_up_for_beads() {
  local d="$1"
  d=$(cd "$d" 2>/dev/null && pwd) || return 1
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/.beads" ]; then
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}

walk_up_for_beads "$PWD" || exit 0  # not a beads project → passthrough

# --- Redirect (block) -----------------------------------------------
cat >&2 <<EOF
skill-redirect: beads-tracked project — use \`$TARGET\` (design lands as beads), not $SKILL.
EOF
exit 2
