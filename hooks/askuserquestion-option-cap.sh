#!/usr/bin/env bash
# PreToolUse hook for AskUserQuestion. Refuses a call that carries three
# or more authored options in one question.
#
# Closes loom-42cw.9 — the GATE half of D7, from the decision-routing
# design cycle (drawer_loom_decisions_97b8a01aa8d18d7a32e86c2d).
#
# D3 caps an ask at two authored options, on the grounds that an
# alternative earns its place only if you can describe someone who would
# actually take it. A third option is not a style problem. It is a
# diagnosis, and it means one of two things: the problem needs more
# research, or there is more than one problem. So the refusal names both
# branches rather than reporting a count, because the count alone does
# not tell the caller which repair to make.
#
# WHY BLOCK (exit 2), NOT a nudge: gate-don't-advise (loom-wj26.1) draws
# the line at "is a human supposed to weigh in?". Nobody is supposed to
# weigh in on whether three exceeds two, so the check just needs to be
# true. The judgment half of the same decision (D1, D2, D4, D5, D6) ships
# as prose convention instead, in templates/rules/loom-conventions.md.
#
# PreToolUse payload shape for an AskUserQuestion call:
#   {"tool_name":"AskUserQuestion",
#    "tool_input":{"questions":[
#      {"question":"...","header":"...","multiSelect":false,
#       "options":[{"label":"...","description":"..."}, ...]}]}}
#
# AUTHORED options are the ones in that array, which is what the caller
# wrote. The free-form escape hatch the harness adds for the user is not
# counted, since it never appears in tool_input and nobody authored it.
#
# THE CAP IS PER QUESTION, not per call. D3 rests on choice-set evidence,
# and a choice set is one question's option list. A call asking two
# questions of two options each is two decisions of two, so it passes.
# The hook counts the largest option list in the call and compares that.
#
# Resolution rules:
#   - bypass env set to the literal "1" → exit 0
#   - empty stdin → exit 0
#   - tool not AskUserQuestion → exit 0
#   - payload the counter cannot read → exit 0 (fail open)
#   - largest authored option list <= 2 → exit 0
#   - largest authored option list >= 3 → exit 2, naming the diagnosis
#
# Fail-open is deliberate on every path where the hook cannot prove a
# violation. A gate that blocks on a payload it does not understand
# stops work it was never meant to judge.
#
# Bypass:
#   LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP=1   (literal "1" only, per loom-b1l)
#
# Test-only binary overrides, both scoped to the counter below and
# neither one a global switch (json_get resolves jq on its own):
#   LOOM_JQ_BIN   the jq binary the counter looks for   (default jq)
#   LOOM_PY_BIN   the python3 binary it falls back to   (default python3)

set -uo pipefail

# Lib ladder (loom-8ztk): LOOM_TEST_LIB_DIR > installed copy > repo-
# relative fallback (readlink -f so it resolves through an installed
# .git/hooks symlink, loom-fxad). TESTLIB must win, or a worktree's tests
# silently load MAIN's lib/ — ~/.claude/lib/* are symlinks into the main
# checkout, the bash flavor of the loom-rsk Python-import shadow.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

if loom_env_enabled LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP; then
  exit 0
fi

CAP=2

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")

# Only act on AskUserQuestion calls. A malformed payload lands here too,
# with an empty TOOL, and takes the same exit.
[ "$TOOL" = "AskUserQuestion" ] || exit 0

# --- Counter ----------------------------------------------------------
# The shared json_get helpers read string scalars, and this hook needs an
# array length, so the jq -> python3 ladder is repeated locally rather
# than bent into json_get.
#
# max_authored_options <payload> — echo the largest options-array length
# across the call's questions. Returns 1 and echoes nothing when the
# payload cannot be counted, which the caller reads as fail-open.
max_authored_options() {
  local input="$1" n=""
  local jq_bin="${LOOM_JQ_BIN:-jq}"
  local py_bin="${LOOM_PY_BIN:-python3}"

  if command -v "$jq_bin" >/dev/null 2>&1; then
    n=$(printf '%s' "$input" \
      | "$jq_bin" -r '[ .tool_input.questions[]? | ((.options? // []) | length) ] | max // 0' \
        2>/dev/null)
  elif command -v "$py_bin" >/dev/null 2>&1; then
    n=$(printf '%s' "$input" | "$py_bin" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)
ti = d.get("tool_input")
qs = ti.get("questions") if isinstance(ti, dict) else None
if not isinstance(qs, list):
    qs = []
counts = [len(q["options"]) for q in qs
          if isinstance(q, dict) and isinstance(q.get("options"), list)]
print(max(counts) if counts else 0)
' 2>/dev/null)
  fi

  # Anything that is not a bare non-negative integer means the counter
  # did not run or the payload did not parse.
  case "$n" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s' "$n"
}

COUNT=$(max_authored_options "$INPUT") || exit 0

[ "$COUNT" -gt "$CAP" ] || exit 0

# --- Refuse -----------------------------------------------------------
cat >&2 <<EOF
askuserquestion-option-cap: this call carries $COUNT authored options in a
single question. The cap is $CAP.

A third option is a diagnosis, not a style problem. It means one of two
things.

  1. The problem needs more research. Dispatch a researcher. Ask again
     with what comes back.
  2. There is more than one problem. Split it. Ask one question at a
     time.

Cut the set to $CAP options. Then call again.

Rule: D3 and D7, drawer_loom_decisions_97b8a01aa8d18d7a32e86c2d.
Bypass: LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP=1, set before launching claude.
EOF
exit 2
