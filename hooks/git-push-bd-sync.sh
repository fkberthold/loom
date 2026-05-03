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

if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
  TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
  CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
fi

[ "$TOOL" = "Bash" ] || exit 0

# Match `git push` (with or without args). Ignore `git push --dry-run`.
echo "$CMD" | grep -qE '(^|[;&|]|\n)[[:space:]]*git[[:space:]]+push([[:space:]]|$)' || exit 0
echo "$CMD" | grep -qE '\-\-dry-run' && exit 0

# Only inside a beads workspace.
[ -d ".beads" ] || exit 0

# Mode check: silent in off.
# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"
MODE=$(workflow_resolve_mode "$PWD")
[ "$MODE" = "off" ] && exit 0

# Check whether .beads/ has uncommitted modifications.
if git status --porcelain .beads/ 2>/dev/null | grep -q '.'; then
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
