#!/usr/bin/env bash
# loom-hook-helpers.sh — shared boilerplate for loom's PreToolUse/
# SessionStart hooks. Sourceable; defines functions only (no top-level
# side effects), so it is safe to source from any hook.
#
# Harvested by loom-0ahj.2 (design-doc 14f08e6d D2 + exploration F6) as a
# behavior-preserving DRY refactor of three idioms that were copy-pasted
# across ~13 hooks:
#
#   1. json_get        — the jq -> grep-oP/sed JSON field-parse ladder.
#   2. json_get_py     — the jq -> python3 field-parse ladder (used where
#                        the hook needs python's JSON escape-decoding).
#   3. loom_env_enabled — the literal-"1" env-var bypass gate.
#
# A fourth idiom (mode_dispatch, full/light/off) lives in
# lib/workflow-state.sh because it composes with workflow_resolve_mode
# already there.
#
# ---------------------------------------------------------------------------
# json_get <jq_path> <flat_fallback_field> [input]
#
# Extract a string field from a hook's JSON payload, echoing it (no
# trailing newline beyond the one echo adds). Reproduces the historical
# inline ladder byte-for-byte:
#
#   if command -v jq >/dev/null 2>&1; then
#     V=$(echo "$INPUT" | jq -r '<jq_path> // ""')
#   else
#     V=$(echo "$INPUT" | grep -oP '"<field>"\s*:\s*"[^"]*"' | head -1 \
#           | sed -E 's/.*"([^"]*)"/\1/')
#   fi
#
# Args:
#   jq_path             jq path expression, e.g. '.tool_name' or
#                       '.tool_input.command'. `// ""` is appended here.
#   flat_fallback_field bare JSON key name used by the no-jq grep
#                       fallback, e.g. 'tool_name' or 'command'. The
#                       fallback is a FLAT first-match scan (matching the
#                       pre-refactor behavior — it does not descend into
#                       tool_input structurally; it grabs the first
#                       "<field>":"..." anywhere in the payload).
#   input               optional; the JSON payload. If omitted, read stdin.
json_get() {
  local jq_path="$1"
  local field="$2"
  local input
  if [ "$#" -ge 3 ]; then
    input="$3"
  else
    input=$(cat)
  fi

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "${jq_path} // \"\""
  else
    printf '%s' "$input" \
      | grep -oP "\"${field}\"\\s*:\\s*\"[^\"]*\"" \
      | head -1 \
      | sed -E 's/.*"([^"]*)"/\1/'
  fi
}

# ---------------------------------------------------------------------------
# json_get_py <jq_path> <python_expr> [input]
#
# Like json_get, but the no-jq fallback routes through python3 (which
# JSON-decodes escape sequences). Reproduces the historical ladder:
#
#   if command -v jq >/dev/null 2>&1; then
#     V=$(echo "$INPUT" | jq -r '<jq_path> // ""')
#   else
#     V=$(printf '%s' "$INPUT" | python3 -c \
#           'import json,sys; d=json.load(sys.stdin); print(<python_expr>)')
#   fi
#
# Args:
#   jq_path      jq path expression (e.g. '.tool_name'). `// ""` appended.
#   python_expr  python expression evaluated with `d` bound to the parsed
#                payload, e.g. 'd.get("tool_name","")' or
#                'd.get("tool_input",{}).get("command","")'.
#   input        optional; JSON payload. If omitted, read stdin.
json_get_py() {
  local jq_path="$1"
  local py_expr="$2"
  local input
  if [ "$#" -ge 3 ]; then
    input="$3"
  else
    input=$(cat)
  fi

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "${jq_path} // \"\""
  else
    printf '%s' "$input" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(${py_expr})"
  fi
}

# ---------------------------------------------------------------------------
# loom_env_enabled <VAR>
#
# True (return 0) iff the named environment variable equals the literal
# string "1". Everything else — "0", "yes", "true", "10", empty, unset —
# returns 1. This is the loom-b1l literal-"1" bypass convention shared by
# every `LOOM_*_SKIP` / `BD_*` env gate.
#
# Usage (replaces `if [ "${LOOM_FOO_SKIP:-0}" = "1" ]; then`):
#   if loom_env_enabled LOOM_FOO_SKIP; then exit 0; fi
loom_env_enabled() {
  local name="$1"
  [ "${!name:-}" = "1" ]
}
