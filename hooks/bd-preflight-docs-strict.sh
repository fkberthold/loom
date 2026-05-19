#!/usr/bin/env bash
# PreToolUse Bash hook for `bd close` and `bd preflight`.
#
# Closes loom-cya. Catches the recurring "broken-markdown-link-in-
# docs/-caught-only-by-mkdocs-strict-in-CI" bug class (loom-59w,
# loom-tx7 — 3 instances in 4 days) at bead-close time instead of
# waiting for CI to find it on origin.
#
# Composes with sibling loom-kbo (pre-push hook): preflight catches
# at close, pre-push catches at push, CI catches on origin —
# defense-in-depth.
#
# Behavior:
#   1. Fires only on Bash tool calls whose command starts with
#      `bd close` or `bd preflight` (word-boundary matched, no
#      lookalike-prefix false positives).
#   2. Skips fast when:
#      - LOOM_BD_PRECLOSE_STRICT_SKIP=1 (user bypass for emergencies)
#      - cwd has no mkdocs.yml (not a docs-bearing project)
#      - workflow mode is "off"
#      - mkdocs binary not found (graceful skip)
#      - branch diff vs main touches no docs-relevant paths
#        (docs/, mkdocs.yml, requirements.txt, skills/, commands/,
#        agents/, hooks/)
#   3. Otherwise runs `mkdocs build --strict` against the current
#      tree.
#   4. On pass: exit 0 silent.
#   5. On fail:
#      - full mode → exit 2 with first WARNING/ERROR line +
#        remediation hint (Claude Code surfaces stderr and blocks
#        the tool call).
#      - light mode → exit 0 with WARN-prefix stderr (informational
#        only, does not block).
#
# Test injection points (mirrors bd-close-capture.sh convention):
#   LOOM_BD_PRECLOSE_STRICT_SKIP=1
#     User-facing emergency bypass.
#   LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1
#     Test-only: skip the git-diff relevance check (assume relevant).
#   MKDOCS_BIN=<path>
#     Override the mkdocs binary path (defaults to `mkdocs` on PATH).

set -uo pipefail

if [ "${LOOM_BD_PRECLOSE_STRICT_SKIP:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
  TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))')
  CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))')
fi

[ "$TOOL" = "Bash" ] || exit 0

# Match `bd close` or `bd preflight` with word-boundary discipline so
# `bd closeable-thing` doesn't trigger. Same regex shape as
# bd-close-capture.sh, extended to cover `bd preflight`.
echo "$CMD" | grep -qE '(^|[;&|]|^&&|\n)[[:space:]]*bd[[:space:]]+(close|preflight)([[:space:]]|$)' || exit 0

# Not a docs-bearing project → skip silently.
[ -f "mkdocs.yml" ] || exit 0

# --- Mode resolution -------------------------------------------------------

# shellcheck source=../lib/workflow-state.sh
. "$HOME/.claude/lib/workflow-state.sh"
MODE=$(workflow_resolve_mode "$PWD")

# mode=off short-circuits.
if [ "$MODE" = "off" ]; then
  exit 0
fi

# --- mkdocs binary resolution ---------------------------------------------

MKDOCS="${MKDOCS_BIN:-mkdocs}"
if [ "$MKDOCS" = "mkdocs" ]; then
  command -v mkdocs >/dev/null 2>&1 || exit 0
else
  [ -x "$MKDOCS" ] || exit 0
fi

# --- File-relevance gate --------------------------------------------------

if [ "${LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT:-0}" != "1" ]; then
  # No git or no main → cannot determine relevance; skip silently.
  command -v git >/dev/null 2>&1 || exit 0
  git rev-parse --git-dir >/dev/null 2>&1 || exit 0
  git rev-parse --verify main >/dev/null 2>&1 || exit 0

  diff_paths=$(git diff --name-only main...HEAD 2>/dev/null) || exit 0
  echo "$diff_paths" | grep -qE '^(docs/|mkdocs\.yml$|requirements\.txt$|skills/|commands/|agents/|hooks/)' || exit 0
fi

# --- Run mkdocs --strict --------------------------------------------------

build_output=$("$MKDOCS" build --strict 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
  exit 0
fi

# Extract the first WARNING/ERROR line for a compact message.
first_problem=$(echo "$build_output" | grep -E 'WARNING|ERROR|Aborted' | head -1)

if [ "$MODE" = "light" ]; then
  {
    echo "WARN: mkdocs --strict failed (workflow mode=light, not blocking):"
    [ -n "$first_problem" ] && echo "  $first_problem"
    echo "  Bypass: set LOOM_BD_PRECLOSE_STRICT_SKIP=1 to suppress entirely."
  } >&2
  exit 0
fi

# full mode → block.
{
  echo "✗ mkdocs --strict failed — refusing bd close/preflight (workflow mode=full)"
  [ -n "$first_problem" ] && echo "  $first_problem"
  echo ""
  echo "  Fix the broken link / nav warning, or bypass with:"
  echo "    LOOM_BD_PRECLOSE_STRICT_SKIP=1 bd close <id>"
  echo ""
  echo "  Full mkdocs output:"
  echo "$build_output" | sed 's/^/    /'
} >&2
exit 2
