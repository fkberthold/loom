#!/usr/bin/env bash
# context-budget-sensor.sh — PreToolUse hook (Bash matcher). A proactive
# context-budget wrap-up sensor.
#
# Closes loom-z3m.9 (feature). Root cause it addresses: the agent only
# initiates wrap-up AFTER the user notices context is heavy ("we're too
# deep in context, let's wrap up"). No sensor reads usage telemetry and
# proactively nudges checkpointing at a threshold. Surfaced by
# loom-z3m.1 f5 (liza-base, 2 distinct sessions).
#
# WHAT IT DOES
#   On each PreToolUse (Bash), it reads the session's accumulated-context
#   high-water mark off the LIVE transcript and classifies it into a
#   tier (green | yellow | red) against tunable thresholds. It writes the
#   tier into workflow-state (`context_pressure`) — which statusline.sh
#   renders as CTX:Y / CTX:R — and, on a tier ESCALATION into yellow or
#   red, emits a one-shot "context is getting heavy — consider wrapping
#   up / checkpointing" nudge via additionalContext. The recipe shells
#   read context_pressure at phase boundaries.
#
# HOW IT READS TELEMETRY (loom-0ahj D7)
#   Stop/SessionEnd hooks do NOT reliably fire on sidechains for token
#   measurement, so the MEASUREMENT must ride the proven central-side
#   transcript-reader path — NOT a Stop-hook. This sensor reuses the
#   exact `.message.usage` mechanism that scripts/loom-stage-spend (the
#   closed loom-0ahj.3 reader) uses: it walks the transcript's assistant
#   records and reads the LAST one's
#       cache_read_input_tokens + cache_creation_input_tokens
#   which is the high-water mark of the session's accumulated context.
#   A PreToolUse here only TRIGGERS the threshold check; the actual
#   number comes from that proven reader path.
#
# THRESHOLDS (DESIGN, tunable)
#   yellow at  > 400000 accumulated tokens  (LOOM_CONTEXT_BUDGET_YELLOW)
#   red    at  > 700000 accumulated tokens  (LOOM_CONTEXT_BUDGET_RED)
#
# POSTURE — NUDGE, NEVER BLOCK
#   This is a loom INFO/nudge sensor. It ALWAYS exits 0. It never blocks
#   a tool call (never exit 2). The nudge surfaces as additionalContext
#   (hookSpecificOutput) — the same mechanism bd-claim-research.sh and
#   dispatch-nudge.sh use.
#
# MEMOIZATION
#   The nudge fires once per tier ESCALATION (green→yellow, yellow→red,
#   green→red), not per-tool. A re-fire at the same-or-lower tier is
#   silent (no spam). Memo is the previously-recorded context_pressure
#   in workflow-state: we only nudge when the new tier is HIGHER than
#   the last recorded one.
#
# Resolution rules:
#   - tool not Bash → still measures (cheap) but the matcher is Bash, so
#     only Bash calls reach it in practice. Non-Bash invocations from
#     the test harness behave identically.
#   - no transcript_path / unreadable transcript → fail open, silent.
#   - no assistant usage records in transcript → fail open, silent.
#
# Bypass:
#   LOOM_CONTEXT_BUDGET_SENSOR_SKIP=1
#
# Env overrides (primarily for tuning + tests):
#   LOOM_CONTEXT_BUDGET_YELLOW   yellow threshold (default 400000)
#   LOOM_CONTEXT_BUDGET_RED      red threshold    (default 700000)

set -uo pipefail

# Lib resolution: an explicitly-set LOOM_TEST_LIB_DIR wins (so a worktree's
# modified libs are what the fixture tests exercise, not main's installed
# copy — the worktree-shadow discipline). Otherwise prefer the installed
# copy, then fall back to the repo-relative copy.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

if loom_env_enabled LOOM_CONTEXT_BUDGET_SENSOR_SKIP; then
  exit 0
fi

INPUT=$(cat)

TRANSCRIPT=$(json_get '.transcript_path' 'transcript_path' "$INPUT")

# No transcript visibility → fail open, silent. We can't measure.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# --- Thresholds (tunable via env) -----------------------------------
YELLOW="${LOOM_CONTEXT_BUDGET_YELLOW:-400000}"
RED="${LOOM_CONTEXT_BUDGET_RED:-700000}"

# --- Read the accumulated-context high-water mark -------------------
# Reuse loom-stage-spend's telemetry mechanism: the LAST assistant
# record's usage block. cache_read_input_tokens is the high-water mark
# of accumulated context (it grows as the session reads more);
# cache_creation_input_tokens is the final increment. Their sum is the
# current accumulated-context size. jq required (matches the reader's
# own jq dependency); without jq we fail open silently.
command -v jq >/dev/null 2>&1 || exit 0

# USAGE_JQ mirrors scripts/loom-stage-spend: select assistant records,
# pull (.cache_read, .cache_creation) off .message.usage.
USAGE_JQ='
  select(.type == "assistant" and (.message.role // "") == "assistant")
  | .message.usage
  | select(. != null)
  | [ (.cache_read_input_tokens // 0),
      (.cache_creation_input_tokens // 0) ]
  | @tsv
'
LAST_ROW=$(jq -r "$USAGE_JQ" "$TRANSCRIPT" 2>/dev/null | tail -1)

# No assistant usage records → fail open, silent.
[ -n "$LAST_ROW" ] || exit 0

IFS=$'\t' read -r CACHE_READ CACHE_CREATION <<<"$LAST_ROW"
CACHE_READ="${CACHE_READ:-0}"
CACHE_CREATION="${CACHE_CREATION:-0}"
ACCUM=$(( CACHE_READ + CACHE_CREATION ))

# --- Classify into a tier -------------------------------------------
# Higher threshold wins. tier_rank lets us compare escalation direction.
if   [ "$ACCUM" -gt "$RED" ];    then TIER="red";    TIER_RANK=2
elif [ "$ACCUM" -gt "$YELLOW" ]; then TIER="yellow"; TIER_RANK=1
else                                  TIER="green";  TIER_RANK=0
fi

# --- Locate the workflow-state lib ----------------------------------
# Same precedence as above: explicit LOOM_TEST_LIB_DIR wins, then the
# installed copy.
WFS_LIB=""
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/workflow-state.sh" ]; then
  WFS_LIB="$LOOM_TEST_LIB_DIR/workflow-state.sh"
elif [ -f "$HOME/.claude/lib/workflow-state.sh" ]; then
  WFS_LIB="$HOME/.claude/lib/workflow-state.sh"
fi
[ -n "$WFS_LIB" ] || exit 0  # can't record/read state → fail silent

# shellcheck source=../lib/workflow-state.sh
. "$WFS_LIB"

# --- Read the prior tier for escalation-memoization -----------------
PRIOR=$(workflow_state_get context_pressure "$PWD")
case "$PRIOR" in
  red)    PRIOR_RANK=2 ;;
  yellow) PRIOR_RANK=1 ;;
  *)      PRIOR_RANK=0 ;;  # green | empty | unknown
esac

# --- Record the current tier ----------------------------------------
workflow_state_set --start-dir="$PWD" "context_pressure=$TIER"

# --- Nudge only on a tier ESCALATION into yellow/red ----------------
# green tier never nudges. A same-or-lower tier re-fire is silent.
if [ "$TIER_RANK" -le 0 ] || [ "$TIER_RANK" -le "$PRIOR_RANK" ]; then
  exit 0
fi

if [ "$TIER" = "red" ]; then
  MSG="Context budget RED (~${ACCUM} accumulated tokens, > ${RED}). Strongly consider wrapping up now: get remaining work logged as beads, capture decisions in MemPalace, run a full /wrap-up checkpoint, then start a fresh session. (This is an INFO nudge — it never blocks. Tune via LOOM_CONTEXT_BUDGET_RED.)"
else
  MSG="Context budget YELLOW (~${ACCUM} accumulated tokens, > ${YELLOW}). Context is getting heavy — consider checkpointing soon: a good spot to log open work as beads + capture decisions before it gets harder. (INFO nudge — never blocks. Tune via LOOM_CONTEXT_BUDGET_YELLOW.)"
fi

# Emit the nudge as additionalContext (jq-encoded so the message is
# always valid JSON regardless of quoting). Always exit 0.
jq -nc --arg msg "$MSG" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $msg}}'
exit 0
