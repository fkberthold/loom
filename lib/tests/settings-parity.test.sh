#!/usr/bin/env bash
# Fixture tests + live gate for install.sh's settings-registration
# parity check (loom-kwkc).
#
# Failure mode this guards against:
#   A hook can be SHIPPED (file in hooks/), SYMLINKED (~/.claude/hooks/
#   link live — `install.sh --check-invocable` green), and REGISTERED IN
#   THE SNIPPET (settings.snippet.json names it under an event) and STILL
#   never run — because `~/.claude/settings.json`, the file the harness
#   actually reads, has no such registration. `settings.json` is
#   deliberately NOT checked in (it is user-machine-specific and holds
#   config outside loom's scope), so the repo cannot own it; nothing in
#   the suite compared the two halves.
#
#   Live instance at the time this gate was written:
#   `hooks/loom-drift-nudge.sh` shipped 2026-07-17 (loom-ig3p.3), is
#   registered at settings.snippet.json as a SessionStart hook, and was
#   ABSENT from the live settings.json — loom's own downstream
#   convention-drift detector had never fired, in any project, including
#   loom itself. Every future hook loom ships inherits this
#   silent-dark failure mode.
#
# Fix shape:
#   install.sh grows a `--check-registration` mode: a NO-MUTATION pass
#   that reads settings.snippet.json DYNAMICALLY (so hooks added later
#   are covered without editing this test or install.sh), reads the live
#   ~/.claude/settings.json, and reports every (event, command) pair
#   present in the snippet but missing from live. Exits non-zero on
#   drift. The normal install path additionally REPORTS the same drift
#   before merging; it never gains a new auto-write of settings.json
#   (loom does not own that file).
#
# RED contract:
#   INVARIANT: a hook registered in settings.snippet.json but absent
#   from the live ~/.claude/settings.json fails `script/test`, naming
#   the missing hook and its event. The check reads the snippet
#   DYNAMICALLY, so hooks added later are covered without editing the
#   test.
#
# Env-var overrides (used by the fixtures below):
#   LOOM_SETTINGS_PARITY_SNIPPET  -- snippet path (default: repo snippet)
#   LOOM_SETTINGS_PARITY_LIVE     -- live settings path
#                                    (default: $CLAUDE_HOME/settings.json)
#   LOOM_SETTINGS_PARITY_SKIP_LIVE=1 -- skip ONLY the live-machine gate
#                                    (the fixtures still run)
#
# Missing-vs-unreadable policy (asserted below):
#   * live settings file ABSENT  -> SKIP, exit 0. loom is simply not
#     installed on this machine (fresh clone / CI / container); there is
#     no live registration surface to be out of parity WITH, so the
#     invariant is vacuous. Failing here would be a false red that
#     trains people to ignore the gate.
#   * live settings file PRESENT but unparseable -> FAIL, exit non-zero.
#     A corrupt settings.json means EVERY registration is dark, which is
#     strictly worse than the drift this gate hunts. It is a real defect
#     and must not be swallowed.
#
# Run:  bash lib/tests/settings-parity.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$LOOM_ROOT/install.sh"
SNIPPET="$LOOM_ROOT/settings.snippet.json"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not available (needed to build fixtures + parse JSON)"
  exit 0
fi

# ----------------------------------------------------------------------
# Helper: run install.sh --check-registration against explicit paths.
# Sets globals OUT (combined stdout+stderr) and RC (exit code).
#
# Deliberately NOT called via command substitution — a subshell would
# discard RC and every exit-code assertion below would silently read the
# initial 0 (a false-green trap this harness hit once already).
# ----------------------------------------------------------------------
RC=0
OUT=""
run_check() {
  local snippet="$1" live="$2"
  OUT=$(LOOM_SETTINGS_PARITY_SNIPPET="$snippet" \
        LOOM_SETTINGS_PARITY_LIVE="$live" \
        bash "$INSTALL_SH" --check-registration 2>&1)
  RC=$?
}

# write_settings <path> <json>
write_settings() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" >"$1"; }

FIXTURE_SNIPPET_JSON='{
  "_comment": "fixture",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-alpha.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-beta.sh"},
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-gamma.sh"}
        ]
      }
    ]
  }
}'

FULL_LIVE_JSON='{
  "model": "opusplan",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-alpha.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-beta.sh"},
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-gamma.sh"}
        ]
      }
    ]
  }
}'

# Same as FULL_LIVE_JSON but zz-fixture-gamma.sh is not registered.
PARTIAL_LIVE_JSON='{
  "model": "opusplan",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-alpha.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/zz-fixture-beta.sh"}
        ]
      }
    ]
  }
}'

# ----------------------------------------------------------------------
# 1. install.sh exposes a --check-registration mode
# ----------------------------------------------------------------------
echo "==> install.sh --check-registration mode exists"
fix=$(mktemp -d)
write_settings "$fix/snippet.json" "$FIXTURE_SNIPPET_JSON"
write_settings "$fix/settings.json" "$FULL_LIVE_JSON"
run_check "$fix/snippet.json" "$fix/settings.json"
if [ "$RC" = "0" ]; then
  pass "full parity -> exit 0"
else
  fail "full parity -> exit 0" "(rc=$RC out=$OUT)"
fi
if echo "$OUT" | grep -qi "unknown\|usage\|no such"; then
  fail "--check-registration is a recognized mode" "(got: $OUT)"
else
  pass "--check-registration is a recognized mode"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 2. Snippet hook missing from live -> non-zero, NAMES hook + event
# ----------------------------------------------------------------------
echo "==> Missing registration -> non-zero naming hook + event"
fix=$(mktemp -d)
write_settings "$fix/snippet.json" "$FIXTURE_SNIPPET_JSON"
write_settings "$fix/settings.json" "$PARTIAL_LIVE_JSON"
run_check "$fix/snippet.json" "$fix/settings.json"
if [ "$RC" != "0" ]; then
  pass "missing registration -> non-zero exit"
else
  fail "missing registration -> non-zero exit" "(rc=$RC out=$OUT)"
fi
if echo "$OUT" | grep -q "zz-fixture-gamma.sh"; then
  pass "output names the missing hook"
else
  fail "output names the missing hook" "(got: $OUT)"
fi
if echo "$OUT" | grep -q "SessionStart"; then
  pass "output names the event"
else
  fail "output names the event" "(got: $OUT)"
fi
# Registered siblings must NOT be reported as missing.
if echo "$OUT" | grep -q "zz-fixture-beta.sh"; then
  fail "registered sibling not reported" "(got: $OUT)"
else
  pass "registered sibling not reported"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 3. DYNAMIC snippet read — a brand-new hook name is covered with no
#    edit to install.sh or this test
# ----------------------------------------------------------------------
echo "==> Snippet is read dynamically (new hook covered automatically)"
fix=$(mktemp -d)
python3 - "$fix/snippet.json" <<'PY'
import json, sys
snip = {
    "hooks": {
        "SessionStart": [
            {"hooks": [
                {"type": "command",
                 "command": "bash $HOME/.claude/hooks/zz-never-hardcoded-anywhere.sh"}
            ]}
        ]
    }
}
with open(sys.argv[1], "w") as f:
    json.dump(snip, f, indent=2)
PY
write_settings "$fix/settings.json" '{"hooks": {"SessionStart": [{"hooks": []}]}}'
run_check "$fix/snippet.json" "$fix/settings.json"
if [ "$RC" != "0" ] && echo "$OUT" | grep -q "zz-never-hardcoded-anywhere.sh"; then
  pass "brand-new snippet hook detected without editing the checker"
else
  fail "brand-new snippet hook detected without editing the checker" "(rc=$RC out=$OUT)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 4. Events present in snippet but wholly absent from live
# ----------------------------------------------------------------------
echo "==> Whole event absent from live -> reported"
fix=$(mktemp -d)
write_settings "$fix/snippet.json" "$FIXTURE_SNIPPET_JSON"
write_settings "$fix/settings.json" '{"model": "opusplan", "hooks": {}}'
run_check "$fix/snippet.json" "$fix/settings.json"
if [ "$RC" != "0" ]; then
  pass "empty live hooks block -> non-zero"
else
  fail "empty live hooks block -> non-zero" "(rc=$RC out=$OUT)"
fi
for h in zz-fixture-alpha.sh zz-fixture-beta.sh zz-fixture-gamma.sh; do
  if echo "$OUT" | grep -q "$h"; then
    pass "reports $h"
  else
    fail "reports $h" "(got: $OUT)"
  fi
done
rm -rf "$fix"

# ----------------------------------------------------------------------
# 5. Missing live settings file -> SKIP (exit 0), loudly
# ----------------------------------------------------------------------
echo "==> Absent live settings.json -> SKIP, exit 0"
fix=$(mktemp -d)
write_settings "$fix/snippet.json" "$FIXTURE_SNIPPET_JSON"
run_check "$fix/snippet.json" "$fix/does-not-exist/settings.json"
if [ "$RC" = "0" ]; then
  pass "absent live settings -> exit 0"
else
  fail "absent live settings -> exit 0" "(rc=$RC out=$OUT)"
fi
if echo "$OUT" | grep -qi "skip"; then
  pass "absent live settings -> says SKIP"
else
  fail "absent live settings -> says SKIP" "(got: $OUT)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 6. Unparseable live settings file -> FAIL (exit non-zero)
# ----------------------------------------------------------------------
echo "==> Malformed live settings.json -> non-zero"
fix=$(mktemp -d)
write_settings "$fix/snippet.json" "$FIXTURE_SNIPPET_JSON"
write_settings "$fix/settings.json" '{this is not json'
run_check "$fix/snippet.json" "$fix/settings.json"
if [ "$RC" != "0" ]; then
  pass "malformed live settings -> non-zero"
else
  fail "malformed live settings -> non-zero" "(rc=$RC out=$OUT)"
fi
if echo "$OUT" | grep -qi "parse\|json\|malformed\|invalid"; then
  pass "malformed live settings -> diagnostic names the parse problem"
else
  fail "malformed live settings -> diagnostic names the parse problem" "(got: $OUT)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 7. NO MUTATION — the live settings file is byte-identical afterwards
# ----------------------------------------------------------------------
echo "==> --check-registration never writes the live settings file"
fix=$(mktemp -d)
write_settings "$fix/snippet.json" "$FIXTURE_SNIPPET_JSON"
write_settings "$fix/settings.json" "$PARTIAL_LIVE_JSON"
before=$(md5sum <"$fix/settings.json")
run_check "$fix/snippet.json" "$fix/settings.json"
after=$(md5sum <"$fix/settings.json")
if [ "$before" = "$after" ]; then
  pass "live settings unchanged by the check"
else
  fail "live settings unchanged by the check"
fi
if [ -e "$fix/settings.json.pre-loom.bak" ]; then
  fail "check does not create a backup (no mutation path taken)"
else
  pass "check does not create a backup (no mutation path taken)"
fi
rm -rf "$fix"

# ----------------------------------------------------------------------
# 8. Repo snippet itself is well-formed and non-empty (guards the input)
# ----------------------------------------------------------------------
echo "==> Repo settings.snippet.json is parseable and registers hooks"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("hooks") else 1)' "$SNIPPET" 2>/dev/null; then
  pass "settings.snippet.json parses and has a hooks block"
else
  fail "settings.snippet.json parses and has a hooks block"
fi

# ----------------------------------------------------------------------
# 9. THE LIVE GATE — every snippet-registered hook must be registered in
#    the real ~/.claude/settings.json on THIS machine.
#
#    This is the gate the bead exists for. It reads the repo snippet and
#    the real live settings; any snippet hook the harness would never
#    run is a defect. Set LOOM_SETTINGS_PARITY_SKIP_LIVE=1 to run only
#    the fixtures (e.g. when deliberately auditing the fixtures alone).
# ----------------------------------------------------------------------
echo "==> LIVE GATE: snippet hooks are registered in \$HOME/.claude/settings.json"
if [ "${LOOM_SETTINGS_PARITY_SKIP_LIVE:-0}" = "1" ]; then
  echo "  SKIP: LOOM_SETTINGS_PARITY_SKIP_LIVE=1"
else
  live="${CLAUDE_HOME:-$HOME/.claude}/settings.json"
  run_check "$SNIPPET" "$live"
  if [ "$RC" = "0" ]; then
    pass "all snippet-registered hooks present in live settings.json"
  else
    fail "all snippet-registered hooks present in live settings.json" "$OUT"
  fi
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
