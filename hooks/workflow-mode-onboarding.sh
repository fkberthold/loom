#!/usr/bin/env bash
# SessionStart hook: workflow-mode onboarding.
#
# When a session opens in a beads workspace:
#   1. Initialize <project>/.claude/workflow-state.json (idempotent).
#   2. If <project>/.claude/workflow.json is absent, inject an
#      additionalContext block instructing the agent to ask Frank to
#      pick a workflow mode and write the answer (ask-once-and-remember).
#
# Non-blocking; informative only. Skipped silently outside beads workspaces.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# Subagent (sidechain) sessions don't structurally use the onboarding
# preamble — the dispatch brief carries the intent. Skip silently to
# save ~21 KB of additionalContext per spawn (loom-w58 / loom-nsb).
# shellcheck source=../lib/subagent-detect.sh
. "$HOME/.claude/lib/subagent-detect.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/subagent-detect.sh" 2>/dev/null || true
if declare -F loom_is_subagent_payload >/dev/null 2>&1; then
  loom_is_subagent_payload "$INPUT" && exit 0
fi

CWD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
fi
CWD="${CWD:-$PWD}"

# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"

ROOT=$(workflow_project_root "$CWD")

# Skip outside beads workspaces.
[ -d "$ROOT/.beads" ] || exit 0

# Always initialize state (idempotent).
workflow_state_init "$CWD" >/dev/null 2>&1 || true

CFG="$ROOT/.claude/workflow.json"
[ -f "$CFG" ] && exit 0

# Inject onboarding prompt.
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "[workflow-mode-onboarding] No \`${CFG}\` found in this beads workspace. The workflow infrastructure (claim/close hooks, recipe skills, status line) supports three modes:\n  - 'full'  — all hooks fire, recipe runs, status line populated.\n  - 'light' — informational only: blocking close-capture hook passes through, recipe still runs but warns.\n  - 'off'   — workflow disabled: hooks silent, recipe refuses, status line empty.\nResolution priority: env CLAUDE_WORKFLOW_OFF=1 → off, then \`${CFG}\` \`.mode\` field, default \`full\`.\nAsk Frank which mode he wants for this project, then create \`${CFG}\` with: {\"v\":1, \"mode\":\"full|light|off\"}. Default \`full\` is appropriate for active HAW work; \`light\`/\`off\` for projects where the workflow doesn't fit. The state file at $(workflow_state_path "$CWD") has been initialized in idle state."
  }
}
EOF
