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

# Scan the transcript tail. Use python for robust JSON parsing of
# JSONL transcripts. We look at the last ~N records for:
#   1. A Bash tool result containing failure markers
#   2. Whether ANY Edit/Write/MultiEdit since that failure was a test file
#
# If (1) is true AND (2) is false → refuse.
#
# Failure markers (case-insensitive substrings on result/output):
#   - "FAIL " / "FAILED" / "FAILURE"
#   - "Error:" / "error:"
#   - "assertion" + ("failed"|"error")
#   - "Tests:" line with " failed"
#   - "Traceback (most recent call last)"
#   - "panic:" (Go)
#   - explicit non-zero exit indication: "exit code: <nonzero>"
#
# We only care about Bash tool results — test/build runners are
# invoked via Bash. Edit/Write tool results don't carry failure
# semantics relevant here.

RESULT=$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null
import json, re, sys

path = sys.argv[1]
TAIL = 80   # last N transcript entries to consider

FAIL_RE = re.compile(
    r"("
    r"\bFAIL(?:ED|URE)?\b"
    r"|^FAIL\s"
    r"|\bassertion\s+(?:failed|error)\b"
    r"|^Error:\s"
    r"|\bTraceback \(most recent call last\)"
    r"|^panic:\s"
    r"|\bTests?:.*\bfailed\b"
    r"|\bexit code:\s*[1-9]"
    r")",
    re.IGNORECASE | re.MULTILINE,
)

try:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
except OSError:
    sys.exit(0)

# Keep only the tail.
lines = lines[-TAIL:]

# Walk forward. Track (a) most-recent-failure index, (b) any test-file
# edit AFTER (a).
failure_idx = -1
test_edit_after_failure = False

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

    # Tool-result records (user role w/ tool_result content) — scan
    # bash outputs for failure markers.
    role = rec.get("role") or rec.get("type") or ""
    msg = rec.get("message") or rec
    content = msg.get("content") if isinstance(msg, dict) else None

    # Anthropic transcript shape: content is a list of blocks.
    blocks = content if isinstance(content, list) else []
    for blk in blocks:
        if not isinstance(blk, dict):
            continue
        btype = blk.get("type", "")
        if btype == "tool_result":
            # tool_result content can be string or list-of-text-blocks
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
            # Heuristic: only treat as failure marker if substantial output.
            # Reduce false positives on incidental "error:" mentions.
            if text and FAIL_RE.search(text):
                # Distinguish bash-class results from other tools by
                # looking at the preceding tool_use's name (if known).
                # Conservative: any tool_result with failure markers
                # counts. Tool-name disambiguation is best-effort below.
                failure_idx = i
                # Reset the test-edit tracker — the failure is fresh.
                test_edit_after_failure = False
        elif btype == "tool_use":
            name = blk.get("name", "")
            if name in ("Edit", "Write", "MultiEdit"):
                inp = blk.get("input", {}) or {}
                fp = inp.get("file_path", "") if isinstance(inp, dict) else ""
                if failure_idx >= 0 and is_test_path(fp):
                    test_edit_after_failure = True

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
