#!/usr/bin/env bash
# workflow-state.sh — read/write the per-project workflow state file at
# <project>/.claude/workflow-state.json.
#
# Schema (v1):
#   {
#     "v": 1,
#     "mode":     "full" | "light" | "off",
#     "activity": "bug" | "feature" | "refactor" | "research" |
#                 "cleanup" | "docs" | "task" | "epic" | "idle",
#     "bead":     "<id>" | null,
#     "stage":    "idle" | "claim" | "research" | "tdd-red" |
#                 "tdd-green" | "verify" | "review" | "commit" |
#                 "wrap-up" | "close",
#     "parallel_candidates": <int>,   # seam-scan result (loom-z3m.5)
#     "dispatch":   "worker" | "inline:<reason>" | null,  # loom-0zr
#     "dispatched": <int>,   # session tally of dispatch=worker sets
#     "inline":     <int>,   # session tally of dispatch=inline:... sets
#     "stage_spend": "<tally>" | null,  # loom-0ahj.3 per-stage net token
#                                       # spend, e.g. "test-author:30705,
#                                       # implementer:81810,verify:18300"
#     "context_pressure": "green" | "yellow" | "red" | null,
#                                       # loom-z3m.9 — accumulated-context
#                                       # budget tier read off the live
#                                       # transcript usage high-water mark
#                                       # by hooks/context-budget-sensor.sh
#     "orphan_pressure": <int>,         # loom-z3m.7 — count of orphan
#                                       # agent worktrees (dead-pid lock) +
#                                       # leftover background procs, written
#                                       # by hooks/worktree-bg-inventory.sh;
#                                       # rendered by statusline.sh as
#                                       # WT:N/BG:M
#     "updated":  "ISO-8601 UTC"
#   }
#
# This file is per-session ephemera; gitignore it in your project.
#
# Sourceable library. Provides:
#   workflow_state_path [start_dir]                 echoes JSON file path
#   workflow_state_init [start_dir]                 writes idle state if absent
#   workflow_state_get  <field> [start_dir]         echoes one field's value
#   workflow_state_set  [--start-dir=...] k=v ...   atomically merges fields

# Source the mode resolver (project root + initial mode).
__WFS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workflow-mode.sh
. "$__WFS_LIB_DIR/workflow-mode.sh"

workflow_state_path() {
  local root
  root=$(workflow_project_root "${1:-$PWD}")
  printf '%s/.claude/workflow-state.json\n' "$root"
}

# Initialize an idle state file if it doesn't exist. Idempotent.
workflow_state_init() {
  local start="${1:-$PWD}"
  local path
  path=$(workflow_state_path "$start")
  local dir
  dir=$(dirname "$path")

  [ -f "$path" ] && return 0

  mkdir -p "$dir"
  local mode now
  mode=$(workflow_resolve_mode "$start")
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  printf '{"v":1,"mode":"%s","activity":"idle","bead":null,"stage":"idle","updated":"%s"}\n' \
    "$mode" "$now" > "$path.tmp.$$"
  mv "$path.tmp.$$" "$path"
}

# Read one field. Echoes empty string if missing or file absent.
workflow_state_get() {
  local field="$1"
  local start="${2:-$PWD}"
  local path
  path=$(workflow_state_path "$start")

  [ -f "$path" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // "" | tostring' "$path" 2>/dev/null \
      | sed 's/^null$//'
  else
    grep -oE "\"$field\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|null|[0-9]+)" "$path" 2>/dev/null \
      | head -1 \
      | sed -E "s/.*:[[:space:]]*\"?([^\"]*)\"?$/\1/" \
      | sed 's/^null$//'
  fi
}

# Atomic merge-update. Args: optional --start-dir=PATH, then key=value pairs.
# Always refreshes the 'updated' timestamp. Unknown keys are ignored.
# Special: bead= (empty) or bead=null sets bead to JSON null.
workflow_state_set() {
  local start_dir=""
  local pairs=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --start-dir=*) start_dir="${arg#--start-dir=}" ;;
      *) pairs+=("$arg") ;;
    esac
  done
  start_dir="${start_dir:-$PWD}"

  workflow_state_init "$start_dir"

  local path
  path=$(workflow_state_path "$start_dir")
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Always refresh state.mode from live resolution unless caller overrides.
  local override_mode=""
  local kv0
  for kv0 in "${pairs[@]}"; do
    if [ "${kv0%%=*}" = "mode" ]; then
      override_mode="1"
      break
    fi
  done
  if [ -z "$override_mode" ]; then
    local resolved_mode
    resolved_mode=$(workflow_resolve_mode "$start_dir")
    pairs+=("mode=$resolved_mode")
  fi

  if command -v jq >/dev/null 2>&1; then
    local jq_filter='.updated = $now'
    local -a jq_args=(--arg now "$now")
    local kv k v
    for kv in "${pairs[@]}"; do
      k="${kv%%=*}"
      v="${kv#*=}"
      case "$k" in
        v|mode|activity|stage)
          jq_filter="$jq_filter | .$k = \$$k"
          jq_args+=(--arg "$k" "$v")
          ;;
        bead)
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            jq_filter="$jq_filter | .bead = null"
          else
            jq_filter="$jq_filter | .bead = \$bead"
            jq_args+=(--arg bead "$v")
          fi
          ;;
        parallel_candidates)
          # Integer-typed field (loom-z3m.5). Default to 0 when not
          # a valid non-negative integer.
          if [[ "$v" =~ ^[0-9]+$ ]]; then
            jq_filter="$jq_filter | .parallel_candidates = (\$parallel_candidates | tonumber)"
            jq_args+=(--arg parallel_candidates "$v")
          else
            jq_filter="$jq_filter | .parallel_candidates = 0"
          fi
          ;;
        dispatch)
          # Per-bead dispatch field (loom-0zr). Latest-write-wins
          # string: `worker` or `inline:<reason>`. Empty/null clears
          # it. As a side effect, increments a session-scoped drift
          # counter: `dispatch=worker` bumps `dispatched`,
          # `dispatch=inline:...` bumps `inline`. The counters are
          # running tallies (not overwritten), so the central session
          # can read off how often it diverged from the dispatch
          # default.
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            jq_filter="$jq_filter | .dispatch = null"
          else
            jq_filter="$jq_filter | .dispatch = \$dispatch"
            jq_args+=(--arg dispatch "$v")
            case "$v" in
              worker)
                jq_filter="$jq_filter | .dispatched = ((.dispatched // 0) + 1)"
                ;;
              inline:*)
                jq_filter="$jq_filter | .inline = ((.inline // 0) + 1)"
                ;;
            esac
          fi
          ;;
        stage_spend)
          # Per-stage net token spend tally (loom-0ahj.3). Latest-write-wins
          # free-form string, e.g. "test-author:30705,implementer:81810".
          # Empty/null clears it. No counter side-effect (unlike dispatch).
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            jq_filter="$jq_filter | .stage_spend = null"
          else
            jq_filter="$jq_filter | .stage_spend = \$stage_spend"
            jq_args+=(--arg stage_spend "$v")
          fi
          ;;
        context_pressure)
          # Accumulated-context budget tier (loom-z3m.9). Latest-write-wins
          # string: green | yellow | red. Empty/null clears it. No counter
          # side-effect (like stage_spend). Written by
          # hooks/context-budget-sensor.sh off the live transcript usage
          # high-water mark; rendered by statusline.sh as CTX:Y / CTX:R.
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            jq_filter="$jq_filter | .context_pressure = null"
          else
            jq_filter="$jq_filter | .context_pressure = \$context_pressure"
            jq_args+=(--arg context_pressure "$v")
          fi
          ;;
        orphan_pressure)
          # Orphan-worktree + bg-proc count (loom-z3m.7). Integer-typed,
          # like parallel_candidates. Default to 0 when not a valid
          # non-negative integer. Written by
          # hooks/worktree-bg-inventory.sh; rendered by statusline.sh as
          # WT:N/BG:M.
          if [[ "$v" =~ ^[0-9]+$ ]]; then
            jq_filter="$jq_filter | .orphan_pressure = (\$orphan_pressure | tonumber)"
            jq_args+=(--arg orphan_pressure "$v")
          else
            jq_filter="$jq_filter | .orphan_pressure = 0"
          fi
          ;;
        *) ;;
      esac
    done
    jq "${jq_args[@]}" "$jq_filter" "$path" > "$path.tmp.$$" \
      && mv "$path.tmp.$$" "$path"
  else
    # No jq fallback: read current values, apply overrides, rewrite.
    local cur_v cur_mode cur_activity cur_bead cur_stage cur_pc
    local cur_dispatch cur_dispatched cur_inline
    cur_v=$(workflow_state_get v "$start_dir")
    cur_mode=$(workflow_state_get mode "$start_dir")
    cur_activity=$(workflow_state_get activity "$start_dir")
    cur_bead=$(workflow_state_get bead "$start_dir")
    cur_stage=$(workflow_state_get stage "$start_dir")
    cur_pc=$(workflow_state_get parallel_candidates "$start_dir")
    cur_dispatch=$(workflow_state_get dispatch "$start_dir")
    cur_dispatched=$(workflow_state_get dispatched "$start_dir")
    cur_inline=$(workflow_state_get inline "$start_dir")
    local cur_stage_spend
    cur_stage_spend=$(workflow_state_get stage_spend "$start_dir")
    local cur_context_pressure
    cur_context_pressure=$(workflow_state_get context_pressure "$start_dir")
    local cur_orphan_pressure
    cur_orphan_pressure=$(workflow_state_get orphan_pressure "$start_dir")
    [ -z "$cur_v" ] && cur_v=1
    [ -z "$cur_mode" ] && cur_mode=full
    [ -z "$cur_activity" ] && cur_activity=idle
    [ -z "$cur_stage" ] && cur_stage=idle
    [ -z "$cur_pc" ] && cur_pc=0
    [ -z "$cur_dispatched" ] && cur_dispatched=0
    [ -z "$cur_inline" ] && cur_inline=0
    [ -z "$cur_orphan_pressure" ] && cur_orphan_pressure=0

    local kv k v
    for kv in "${pairs[@]}"; do
      k="${kv%%=*}"
      v="${kv#*=}"
      case "$k" in
        v) cur_v="$v" ;;
        mode) cur_mode="$v" ;;
        activity) cur_activity="$v" ;;
        bead) cur_bead="$v" ;;
        stage) cur_stage="$v" ;;
        parallel_candidates)
          if [[ "$v" =~ ^[0-9]+$ ]]; then
            cur_pc="$v"
          else
            cur_pc=0
          fi
          ;;
        dispatch)
          # See jq branch above (loom-0zr). Latest-write-wins string;
          # increments the matching session counter as a side effect.
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            cur_dispatch=""
          else
            cur_dispatch="$v"
            case "$v" in
              worker)     cur_dispatched=$((cur_dispatched + 1)) ;;
              inline:*)   cur_inline=$((cur_inline + 1)) ;;
            esac
          fi
          ;;
        stage_spend)
          # See jq branch above (loom-0ahj.3). Latest-write-wins string,
          # no counter side-effect. Empty/null clears it.
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            cur_stage_spend=""
          else
            cur_stage_spend="$v"
          fi
          ;;
        context_pressure)
          # See jq branch above (loom-z3m.9). green | yellow | red.
          # Empty/null clears it.
          if [ -z "$v" ] || [ "$v" = "null" ]; then
            cur_context_pressure=""
          else
            cur_context_pressure="$v"
          fi
          ;;
        orphan_pressure)
          # See jq branch above (loom-z3m.7). Integer count; default 0
          # when not a valid non-negative integer.
          if [[ "$v" =~ ^[0-9]+$ ]]; then
            cur_orphan_pressure="$v"
          else
            cur_orphan_pressure=0
          fi
          ;;
      esac
    done

    local bead_json
    if [ -z "$cur_bead" ] || [ "$cur_bead" = "null" ]; then
      bead_json=null
    else
      bead_json="\"$cur_bead\""
    fi

    local dispatch_json
    if [ -z "$cur_dispatch" ] || [ "$cur_dispatch" = "null" ]; then
      dispatch_json=null
    else
      dispatch_json="\"$cur_dispatch\""
    fi

    local stage_spend_json
    if [ -z "$cur_stage_spend" ] || [ "$cur_stage_spend" = "null" ]; then
      stage_spend_json=null
    else
      stage_spend_json="\"$cur_stage_spend\""
    fi

    local context_pressure_json
    if [ -z "$cur_context_pressure" ] || [ "$cur_context_pressure" = "null" ]; then
      context_pressure_json=null
    else
      context_pressure_json="\"$cur_context_pressure\""
    fi

    printf '{"v":%s,"mode":"%s","activity":"%s","bead":%s,"stage":"%s","parallel_candidates":%s,"dispatch":%s,"dispatched":%s,"inline":%s,"stage_spend":%s,"context_pressure":%s,"orphan_pressure":%s,"updated":"%s"}\n' \
      "$cur_v" "$cur_mode" "$cur_activity" "$bead_json" "$cur_stage" "$cur_pc" \
      "$dispatch_json" "$cur_dispatched" "$cur_inline" "$stage_spend_json" "$context_pressure_json" "$cur_orphan_pressure" "$now" \
      > "$path.tmp.$$"
    mv "$path.tmp.$$" "$path"
  fi
}

# mode_dispatch <mode> <full_cmd> <light_cmd> <off_cmd>  (loom-0ahj.2)
#
# Run exactly one of three commands selected by workflow mode, returning
# that command's exit code. This collapses the full/light/off branching
# that PreToolUse hooks repeated inline after resolving the mode via
# workflow_resolve_mode. An UNKNOWN mode is treated as `full` — matching
# workflow_resolve_mode's own default, so a malformed/absent state file
# still falls through to the strict path rather than silently disabling
# the hook.
#
# Each *_cmd arg is a command string evaluated with `eval` (so callers can
# pass `'exit 0'`, `'do_block_path'`, a function name + args, etc.). Pass
# an empty string (or `:`) for a mode that should be a no-op.
#
# Usage:
#   . "$HOME/.claude/lib/workflow-state.sh"
#   MODE=$(workflow_resolve_mode "$PWD")
#   mode_dispatch "$MODE" 'run_strict' 'run_warn' 'exit 0'
mode_dispatch() {
  local mode="$1"
  local full_cmd="${2:-}"
  local light_cmd="${3:-}"
  local off_cmd="${4:-}"

  case "$mode" in
    light) eval "$light_cmd" ;;
    off)   eval "$off_cmd" ;;
    *)     eval "$full_cmd" ;;  # full + any unknown mode -> strict default
  esac
}
