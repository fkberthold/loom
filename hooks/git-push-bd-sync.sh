#!/usr/bin/env bash
# PreToolUse hook for `git push`.
#
# Reminds the agent to commit beads state before pushing so git remote
# and Dolt remote stay aligned. The beads pre-push git hook (installed
# via `bd hooks install`) does the real enforcement on the git side.
#
# Mode-aware (per workflow-infra v1.5):
#   full   → warn (existing behavior).
#   light  → warn (informational only).
#   off    → silent.
#
# Non-blocking (exit 0) — advisory.

set -euo pipefail

INPUT=$(cat)

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
CMD=$(json_get '.tool_input.command' 'command' "$INPUT")

[ "$TOOL" = "Bash" ] || exit 0

# Match `git push` (with or without args). Ignore `git push --dry-run`.
echo "$CMD" | grep -qE '(^|[;&|]|\n)[[:space:]]*git[[:space:]]+push([[:space:]]|$)' || exit 0
echo "$CMD" | grep -qE '\-\-dry-run' && exit 0

# Silence false-positive when the same Bash chain commits BEFORE pushing —
# the chain itself handles staging, so the .beads/ dirty-at-fire-time check
# would warn unnecessarily. Detect: `git commit` appears earlier in the
# command than `git push` (separated by `&&` or `;`). See loom-0r6.
if echo "$CMD" | grep -qE '(^|[;&|])[[:space:]]*git[[:space:]]+commit\b.*(&&|;)[[:space:]]*.*git[[:space:]]+push\b'; then
  exit 0
fi

# Determine the directory `git push` will actually run in. If the command
# chains `cd <dir>` (with `&&` or `;`) before `git push`, that <dir> is the
# real push target — not $PWD. Otherwise default to $PWD.
TARGET_DIR="$PWD"
if echo "$CMD" | grep -qE '(^|[;&|]|\n)[[:space:]]*cd[[:space:]]+[^[:space:];&|]+[[:space:]]*(&&|;)[[:space:]]*git[[:space:]]+push'; then
  CD_DIR=$(echo "$CMD" \
    | grep -oE '(^|[;&|]|\n)[[:space:]]*cd[[:space:]]+[^[:space:];&|]+' \
    | tail -1 \
    | sed -E 's/^.*cd[[:space:]]+//')
  case "$CD_DIR" in
    /*) TARGET_DIR="$CD_DIR" ;;
    *)  TARGET_DIR="$PWD/$CD_DIR" ;;
  esac
fi

# Only when the push target is inside a beads workspace.
[ -d "$TARGET_DIR/.beads" ] || exit 0

# Mode check: silent in off (resolved against the push target's project).
# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"
MODE=$(workflow_resolve_mode "$TARGET_DIR")
[ "$MODE" = "off" ] && exit 0

# Check whether the push target's .beads/ has uncommitted modifications.
if (cd "$TARGET_DIR" && git status --porcelain .beads/ 2>/dev/null | grep -q '.'); then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[git-push-bd-sync hook] About to push, but .beads/ has uncommitted modifications. If beads state changed this session (claims, closes, deps), commit them BEFORE pushing so git remote and Dolt remote stay aligned. Run: git add .beads/issues.jsonl .beads/interactions.jsonl && git commit -m '...' && bd dolt push"
  }
}
EOF
fi

exit 0
