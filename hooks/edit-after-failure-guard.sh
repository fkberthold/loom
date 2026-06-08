#!/usr/bin/env bash
# PreToolUse hook for Edit / Write / MultiEdit. Catches the recurring
# TDD-discipline-slip where a test or build command JUST failed and
# the agent's next move is to Edit the source file (writing the fix
# before the failing test is captured / written / understood).
#
# Closes loom-z3m.6 (variable-middle TDD slippage, surfaced 2026-05-12
# liza f3: "Ok, your discipline is slipping. First you need to write
# a test that will fail until you get this right. _then_ do the fix.").
#
# Detection: scan the transcript tail (last N tool-uses) for a Bash
# tool call whose output contained test-failure markers. If a failure
# was observed AND no test file has been touched since (Edit/Write/
# MultiEdit on a path matching test-file heuristics), refuse the next
# source-file Edit/Write/MultiEdit with a TDD reminder.
#
# Resolution rules:
#   - tool not in {Edit, Write, MultiEdit} → exit 0
#   - no transcript_path → exit 0 (fail open; can't tell)
#   - no recent failure marker in transcript tail → exit 0
#   - failure marker exists but a test file was edited after it → exit 0
#   - target IS itself a test file → exit 0 (writing/fixing the test)
#   - otherwise → exit 2 with TDD reminder
#
# Bypass:
#   LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1
#     For deliberate non-TDD edits (e.g. doc fix triggered by a flaky
#     test failure that's unrelated to the edit).

set -uo pipefail

if [ "${LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
  PATH_RAW=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
else
  TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
  PATH_RAW=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
  TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
fi

# Only guard Edit-class tools.
case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

# Empty file_path → let the underlying tool reject.
[ -n "$PATH_RAW" ] || exit 0

# No transcript visibility → fail open. We can't tell whether a
# failure preceded this edit.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Heuristic: is this path itself a test file? If yes, the agent is
# writing/fixing a test — the desired TDD next move. Allow.
#
# Match common test-file conventions:
#   - bash:   *.test.sh, *_test.sh, tests/, test_*.sh
#   - python: test_*.py, *_test.py, tests/, conftest.py
#   - go:     *_test.go
#   - js/ts:  *.test.{js,ts,jsx,tsx}, *.spec.{js,ts,jsx,tsx}, __tests__/
is_test_path() {
  local p="$1"
  case "$p" in
    */tests/*|*/test/*|*/__tests__/*) return 0 ;;
    *.test.sh|*_test.sh|*.test.bash) return 0 ;;
    *test_*.py|*_test.py|*/conftest.py) return 0 ;;
    *_test.go) return 0 ;;
    *.test.js|*.test.ts|*.test.jsx|*.test.tsx) return 0 ;;
    *.spec.js|*.spec.ts|*.spec.jsx|*.spec.tsx) return 0 ;;
  esac
  case "$(basename "$p")" in
    test_*.py|test_*.sh) return 0 ;;
  esac
  return 1
}

if is_test_path "$PATH_RAW"; then
  exit 0
fi

# Marker-file bypass (loom-n1q): a per-project escape hatch that any
# agent can create with one Bash call (touch .claude/no-edit-after-
# failure-guard). The env-var bypass above requires export BEFORE
# `claude` forks — useless to in-session agents. The marker file is
# reachable at runtime.
#
# Walk up from the target file's directory (preferred — most precise
# for cross-project edits) looking for .claude/no-edit-after-failure-
# guard. If not found there, walk up from PWD as a fallback.
walk_up_for_marker() {
  local d="$1"
  d=$(cd "$d" 2>/dev/null && pwd) || return 1
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -f "$d/.claude/no-edit-after-failure-guard" ]; then
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}

target_dir=$(dirname "$PATH_RAW")
[ -d "$target_dir" ] || target_dir="$PWD"
if walk_up_for_marker "$target_dir" || walk_up_for_marker "$PWD"; then
  exit 0
fi

# Scan the transcript tail. Use python for robust JSON parsing of
# JSONL transcripts. We look at the last ~N records for:
#   1. A Bash tool result containing failure markers
#   2. Whether ANY Edit/Write/MultiEdit since that failure was a test file
#
# If (1) is true AND (2) is false → refuse.
#
# We only care about Bash tool results — test/build runners are
# invoked via Bash. Edit/Write tool results don't carry failure
# semantics relevant here. tool_result blocks pair with their
# preceding tool_use via tool_use_id, so the python below builds an
# id→name map and ignores tool_results whose issuing tool was not
# Bash (loom-7j5 fix #1). Doc / drawer / source text returned by
# Read / mempalace_* / bd / etc. with "fail" prose no longer trips.
#
# Failure markers (after loom-7j5 fix #2 tightening): start-of-line
# anchors and known framing patterns (pytest, go test, panic, npm),
# plus existing assertion / Error / Traceback matchers. The lax
# \bFAIL(?:ED|URE)?\b substring match was dropped — prose containing
# "Failure" / "failed" no longer counts as a marker.
#
# loom-9ng: the count-based matchers require a NON-ZERO leading
# digit ([1-9]\d* rather than \d+). A green run's "N passed, 0
# failed" / "Tests: 15 passed, 0 failed" summary no longer trips the
# guard; only a non-zero failure count counts as a marker.

RESULT=$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null
import json, re, sys

path = sys.argv[1]
TAIL = 80   # last N transcript entries to consider

FAIL_RE = re.compile(
    r"("
    r"^FAIL\s"
    r"|^FAIL:\s"
    r"|\bFAILED\s+\S+(?:::|/)"
    r"|^--- FAIL:"
    r"|\b[1-9]\d*\s+(?:tests?\s+)?failed\b"
    r"|\bassertion\s+(?:failed|error)\b"
    r"|^Error:\s"
    r"|\bTraceback \(most recent call last\)"
    r"|^panic:\s"
    r"|\bTests?:.*\b[1-9]\d*\s+(?:tests?\s+)?failed\b"
    r"|\bexit code:\s*[1-9]"
    r")",
    re.IGNORECASE | re.MULTILINE,
)

# loom-7j5 fix #3: hook self-reference whitelist. The hook's own
# BLOCKED stderr contains failure-marker substrings. When the prior
# BLOCKED message lands in the transcript tail it would otherwise
# become a fresh failure marker for the next Edit/Write attempt
# (recursive self-trigger). Skip any tool_result text containing
# this sentinel before scanning for markers.
SELF_REF = "edit-after-failure-guard"

# loom-n1q: git-merge CONFLICT whitelist. A `git merge` with
# conflicts produces output containing CONFLICT (content): /
# Automatic merge failed; fix conflicts and then commit the result.
# The Bash tool then appends Exit code: 1, which trips FAIL_RE
# (\bexit code:\s*[1-9]). But the user's REQUIRED next action is
# precisely to Edit the conflict files — exactly what the guard
# would refuse. Treat conflict-resolution Bash results as a clean
# Bash result (clearing any prior latch).
MERGE_CONFLICT_MARKERS = (
    "CONFLICT (content):",
    "Automatic merge failed; fix conflicts",
)

try:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
except OSError:
    sys.exit(0)

# Keep only the tail.
lines = lines[-TAIL:]

# Walk forward. Track:
#   - failure_idx: index of the LAST Bash tool_result that matched
#                  FAIL_RE. loom-n1q "last-Bash-only" semantics —
#                  this is overwritten by every later Bash result.
#                  A subsequent clean Bash result (no FAIL_RE match,
#                  no CONFLICT whitelist hit) clears the latch back
#                  to -1. Self-ref tool_results are skipped entirely
#                  (don't clear, don't latch).
#   - test_edit_after_failure: True iff any Edit/Write/MultiEdit on
#                              a test path occurred AFTER failure_idx.
#                              Resets to False whenever failure_idx
#                              is updated (latched OR cleared).
#   - tool_use_by_id: tool_use_id → issuing tool name map
#                     (loom-7j5 fix #1).
failure_idx = -1
test_edit_after_failure = False
tool_use_by_id = {}

TEST_PATH_RE = re.compile(
    r"(/tests?/|/__tests__/"
    r"|\.test\.(?:sh|bash|py|js|ts|jsx|tsx)$"
    r"|_test\.(?:sh|bash|py|go)$"
    r"|^test_.*\.(?:sh|py)$"
    r"|/conftest\.py$"
    r"|\.spec\.(?:js|ts|jsx|tsx)$"
    r")"
)

def is_test_path(p: str) -> bool:
    if not p:
        return False
    return bool(TEST_PATH_RE.search(p)) or "/tests/" in p or "/test/" in p

for i, raw in enumerate(lines):
    raw = raw.strip()
    if not raw:
        continue
    try:
        rec = json.loads(raw)
    except Exception:
        continue

    # Anthropic transcript shape: content is a list of blocks. tool_use
    # blocks (assistant role) and tool_result blocks (user role) share
    # the list. The id→name map is built from tool_use blocks; each
    # tool_result block looks up its issuing tool via tool_use_id.
    role = rec.get("role") or rec.get("type") or ""
    msg = rec.get("message") or rec
    content = msg.get("content") if isinstance(msg, dict) else None

    blocks = content if isinstance(content, list) else []
    for blk in blocks:
        if not isinstance(blk, dict):
            continue
        btype = blk.get("type", "")
        if btype == "tool_use":
            tu_id = blk.get("id", "")
            tu_name = blk.get("name", "")
            if tu_id:
                tool_use_by_id[tu_id] = tu_name
            if tu_name in ("Edit", "Write", "MultiEdit"):
                inp = blk.get("input", {}) or {}
                fp = inp.get("file_path", "") if isinstance(inp, dict) else ""
                if failure_idx >= 0 and is_test_path(fp):
                    test_edit_after_failure = True
        elif btype == "tool_result":
            # loom-7j5 fix #1: only Bash-originated tool_results count
            # as failure markers. tool_result blocks pair with their
            # preceding tool_use via tool_use_id; look up the issuing
            # tool's name. An orphaned tool_use_id (preceding tool_use
            # outside the tail window) resolves to "" — fail-safe (no
            # false block).
            tu_id = blk.get("tool_use_id", "")
            if tool_use_by_id.get(tu_id, "") != "Bash":
                continue

            inner = blk.get("content", "")
            if isinstance(inner, list):
                texts = []
                for sub in inner:
                    if isinstance(sub, dict):
                        texts.append(sub.get("text", "") or "")
                    elif isinstance(sub, str):
                        texts.append(sub)
                text = "\n".join(texts)
            elif isinstance(inner, str):
                text = inner
            else:
                text = ""

            # loom-7j5 fix #3: skip texts that reference the hook
            # itself (recursive self-trigger sub-bug). Don't latch
            # AND don't clear — leave the previous Bash decision
            # intact.
            if SELF_REF in text:
                continue

            # loom-n1q whitelist: git-merge CONFLICT output looks
            # like a failure but is actually the conflict-resolution
            # opportunity. Treat as clean Bash — clear any latch.
            if text and any(m in text for m in MERGE_CONFLICT_MARKERS):
                failure_idx = -1
                test_edit_after_failure = False
                continue

            # loom-n1q "last-Bash-only" TTL: every Bash tool_result
            # decides its own latch state. A clean result clears the
            # prior failure; a fresh failure re-latches.
            if text and FAIL_RE.search(text):
                failure_idx = i
                test_edit_after_failure = False
            else:
                failure_idx = -1
                test_edit_after_failure = False

# Emit result on stdout: "BLOCK" if failure observed and no test edit
# since; "ALLOW" otherwise.
if failure_idx >= 0 and not test_edit_after_failure:
    print("BLOCK")
else:
    print("ALLOW")
PY
)

[ -n "$RESULT" ] || RESULT="ALLOW"

if [ "$RESULT" != "BLOCK" ]; then
  exit 0
fi

cat >&2 <<EOF
[edit-after-failure-guard] BLOCKED: $TOOL refused.

  file_path = $PATH_RAW

A test or build failure was observed in recent Bash output, and
no test file has been edited since. The next Edit/Write to a
non-test file would be a TDD discipline slip — fixing the source
before pinning the failure with a RED test.

To proceed, do ONE of:

  1. Write/edit the failing test first (RED), then re-attempt the
     source edit. The test edit clears this guard.
  2. If the failure is unrelated to this edit (e.g. flaky test,
     unrelated lint warning surfaced incidentally), set
     LOOM_EDIT_AFTER_FAILURE_GUARD_SKIP=1 in the env and retry.
  3. If you've already considered the test and consciously chose
     not to add one (trivial typo fix, doc edit), use the bypass
     env var above.

Reference: superpowers:test-driven-development. The bead-lifecycle-
shell's mid-recipe branchpoint (post-loom-z3m.6) mandates routing
through TDD when a NEW failure mode surfaces during the variable
middle.
EOF
exit 2
