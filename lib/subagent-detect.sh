#!/usr/bin/env bash
# lib/subagent-detect.sh — detect subagent context from a hook stdin
# JSON payload. Shared by loom-owned SessionStart hooks so all of them
# can short-circuit silently when invoked under a subagent (sidechain)
# session.
#
# Why: Claude Code's SessionStart hook output is injected as an
# additionalContext prefix that re-bills every turn until /clear. For
# subagents (Task-tool spawns, application-helper agents like liza_base's
# voice translator, parallel workers) the brief carries the intent —
# loom's onboarding preamble is structurally unusable. Skipping
# emission saves ~21 KB per spawn (top-leverage finding from loom-nsb;
# drawer_loom_decisions_3eec30046461f0766ac92eec).
#
# Detection signals (any one triggers a match):
#   0. $LOOM_SUBAGENT_LEAN == "1"  — env-var force-override (loom-b1l);
#                                    short-circuits all payload inspection.
#                                    For app code wrapping subprocess
#                                    Claude Code invocations that want
#                                    deterministic slim emission.
#   1. .isSidechain == true        — Claude Code transcript marker
#   2. .parentUuid is a non-null   — Claude Code transcript marker
#      string
#   3. .source matches subagent    — defensive; future-proof for
#      (case-insensitive)            possible CC schema additions
#
# Usage:
#   . "$(dirname "$0")/../lib/subagent-detect.sh"   # or via $HOME path
#   INPUT=$(cat 2>/dev/null || true)
#   loom_is_subagent_payload "$INPUT" && exit 0
#
# Returns 0 (match — caller should skip) when any subagent marker is
# present in the payload OR when LOOM_SUBAGENT_LEAN=1. Returns 1
# (no match — caller continues) for normal orchestrator payloads,
# empty input, or malformed JSON.

loom_is_subagent_payload() {
  # Env-var override (loom-b1l): app code can wrap subprocess Claude
  # Code with `LOOM_SUBAGENT_LEAN=1` to force slim emission regardless
  # of payload contents. Only the literal "1" triggers — conservative
  # match avoids surprise from `=yes` / `=true` / non-empty-truthy.
  if [ "${LOOM_SUBAGENT_LEAN:-}" = "1" ]; then
    return 0
  fi

  local payload="${1:-}"
  [ -n "$payload" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$payload" <<'PY' >/dev/null 2>&1
import json, sys
raw = sys.argv[1]
try:
    d = json.loads(raw)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)
# Signal 1: isSidechain boolean.
if d.get("isSidechain") is True:
    sys.exit(0)
# Signal 2: parentUuid non-null/non-empty string.
p = d.get("parentUuid")
if isinstance(p, str) and p:
    sys.exit(0)
# Signal 3: source matches subagent (defensive).
s = d.get("source")
if isinstance(s, str) and "subagent" in s.lower():
    sys.exit(0)
sys.exit(1)
PY
}
