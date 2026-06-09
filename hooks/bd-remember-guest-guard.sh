#!/usr/bin/env bash
# PreToolUse hook: refuse `bd remember` when running in loom-guest mode
# against the host project's bd. Without this guard, `bd remember` (which
# writes to the host's .beads/issues.jsonl) would silently leak guest-side
# notes into the host's tracker — exactly the contamination loom-guest
# exists to prevent.
#
# Design: drawer_loom_decisions_12d7f8163e8855be037a007c (loom-n7x case A
# only — the host-bd case; personal/none modes are out of scope).
#
# Behavior matrix:
#
#   guest active | bd_mode    | command           | result
#   no           | n/a        | n/a               | passthrough (exit 0)
#   yes          | host       | bd remember ...   | block (exit 2) + hint
#   yes          | host       | not bd remember   | passthrough
#   yes          | personal   | bd remember ...   | passthrough (own bd ok)
#   yes          | none       | bd remember ...   | passthrough (bd will err)
#
# False-positive avoidance: word-boundary regex `\bbd[[:space:]]+remember\b`,
# so `gbd remember`, `bd remember-not-this`, etc. pass through. We prefer
# false-allow over false-deny — the cost of a missed block is one stray bd
# memory; the cost of a wrongful block is user friction.
#
# settings.json snippet (per-user; do NOT commit):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             { "type": "command",
#               "command": "bash ~/.claude/hooks/bd-remember-guest-guard.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# Block strategy: exit 2 with a stderr message. Claude Code surfaces stderr
# and aborts the tool call.

set -uo pipefail

INPUT=$(cat)

# --- Tool dispatch ---------------------------------------------------------

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
TOOL=$(json_get_py '.tool_name' 'd.get("tool_name","")' "$INPUT")
CMD=$(json_get_py '.tool_input.command' 'd.get("tool_input",{}).get("command","")' "$INPUT")

[ "$TOOL" = "Bash" ] || exit 0

# Word-boundary match: `bd` and `remember` as separate, full tokens.
# Rejects `gbd remember`, `bd remember-not-this`, `bd-remember-foo`, etc.
echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])bd[[:space:]]+remember([^[:alnum:]_-]|$)' || exit 0

# --- Guest mode + bd_mode resolution --------------------------------------

# shellcheck source=../lib/workflow-config.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/workflow-config.sh"

workflow_config_guest_active "$PWD" || exit 0

BD_MODE=$(workflow_config_guest_get bd_mode "$PWD")

# Only block case A: host bd. personal/none are passthrough by design.
[ "$BD_MODE" = "host" ] || exit 0

# --- Block ----------------------------------------------------------------

cat >&2 <<'EOF'
[bd-remember-guest-guard hook] Guest mode + host bd. Refusing `bd remember`
(would commit to host's issues.jsonl). Use a MemPalace drawer instead:

  mempalace_add_drawer wing=<project> room=notes ...

Bypass (rarely correct — implies you actually do want this in the host's bd):
  /loom-guest off
EOF
exit 2
