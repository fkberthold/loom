#!/usr/bin/env bash
# Fixture tests for hooks/dispatch-nudge.sh.
#
# Closes loom-h5s (T2 of epic loom-yb5): a NON-BLOCKING PreToolUse
# hook on Edit/Write/MultiEdit that nudges the central session toward
# worker-dispatch as the default for a RED→GREEN bead, once per
# claimed bead.
#
# The hook fires (emits additionalContext, always exit 0) ONLY when:
#   - tool is Edit / Write / MultiEdit
#   - a bead is in_progress (bd list --status=in_progress non-empty)
#   - workflow-state get dispatch is EMPTY
#   - the target file_path is a SOURCE file (hooks/*.sh, scripts/*,
#     lib/*.sh) but NOT lib/tests/*, NOT *.md, NOT docs/, NOT config.
# When dispatch=worker but central edits a source file, it emits a
# softer one-line mismatch reminder. Otherwise silent. Always exit 0.
# Memoized once-per-bead via a sentinel keyed on the in_progress id.
#
# Run:  bash lib/tests/dispatch-nudge.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/dispatch-nudge.sh"
WS="$LOOM_ROOT/scripts/workflow-state"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# The hook resolves the state lib via $HOME/.claude/lib/ first, then
# LOOM_TEST_LIB_DIR — point the latter at the repo copy.
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# Build a project fixture with a fake `bd` on PATH whose
# `list --status=in_progress` output is controlled per-test.
#   $1 = in_progress bead id (empty string => no in_progress beads)
#   $2 = dispatch value to seed into workflow-state ("" => unset)
# echoes the project dir
mk_project() {
  local ip_bead="$1" dispatch="$2"
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads" "$d/bin"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '{"v":1,"mode":"full","activity":"feature","bead":"%s","stage":"tdd-red","updated":"2026-06-06T00:00:00Z"}\n' \
    "${ip_bead:-loom-xxx}" > "$d/.claude/workflow-state.json"
  if [ -n "$dispatch" ]; then
    bash "$WS" set "--start-dir=$d" "dispatch=$dispatch" >/dev/null 2>&1
  fi

  # Fake bd: emit one issue line for in_progress when ip_bead set.
  cat > "$d/bin/bd" <<EOF
#!/usr/bin/env bash
if printf '%s ' "\$@" | grep -q 'list' && printf '%s ' "\$@" | grep -q 'in_progress'; then
  if [ -n "${ip_bead}" ]; then
    echo "${ip_bead}  [in_progress]  some title here"
  fi
  exit 0
fi
exit 0
EOF
  chmod +x "$d/bin/bd"
  printf '%s' "$d"
}

# Run the hook in a project with PATH-stubbed bd.
#   $1 = project dir   $2 = tool   $3 = file_path  (rest: env assignments)
run_hook() {
  local proj="$1" tool="$2" path="$3"; shift 3
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"file_path": sys.argv[2]}}))
' "$tool" "$path")
  (cd "$proj" && PATH="$proj/bin:$PATH" env "$@" bash "$HOOK" <<<"$payload" 2>&1)
}

# Extract the additionalContext string (empty if no JSON emitted).
ctx() { echo "$1" | jq -r 'try .hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# -------------------------------------------------------------------
# 1. dispatch unset + in_progress bead + SOURCE file → nudge.
# -------------------------------------------------------------------
echo "==> 1. unset + in_progress + source → nudge"
proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && echo "$c" | grep -qi "dispatch a worker"; then
  pass "nudge emitted on hooks/foo.sh, exit 0"
else
  fail "expected nudge + exit 0. rc=$rc" "$out"
fi
rm -rf "$proj"
# scripts/* and lib/*.sh also count as source (fresh project — the
# nudge is memoized once-per-bead, so reuse would be silent).
proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" Write "scripts/bar"); c=$(ctx "$out")
echo "$c" | grep -qi "dispatch a worker" && pass "scripts/* counts as source" \
  || fail "scripts/* not nudged" "$out"
rm -rf "$proj"

proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" MultiEdit "lib/baz.sh"); c=$(ctx "$out")
echo "$c" | grep -qi "dispatch a worker" && pass "lib/*.sh counts as source" \
  || fail "lib/*.sh not nudged" "$out"
rm -rf "$proj"

# -------------------------------------------------------------------
# 2. dispatch=worker + source file → softer mismatch reminder.
# -------------------------------------------------------------------
echo "==> 2. dispatch=worker + source → mismatch reminder"
proj=$(mk_project "loom-h5s" "worker")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && [ -n "$c" ] && ! echo "$c" | grep -qi "Default for a RED"; then
  pass "softer mismatch reminder (not the full nudge), exit 0"
else
  fail "expected softer mismatch reminder. rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 3. dispatch=inline:<reason> → silent.
# -------------------------------------------------------------------
echo "==> 3. dispatch=inline:reason → silent"
proj=$(mk_project "loom-h5s" "inline:trivial one-liner")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && [ -z "$c" ]; then
  pass "inline opt-out: silent, exit 0"
else
  fail "expected silent. rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 4. docs / test / md target → silent (even when nudge-eligible).
# -------------------------------------------------------------------
echo "==> 4. non-source targets → silent"
proj=$(mk_project "loom-h5s" "")
for tgt in "lib/tests/foo.test.sh" "docs/reference/x.md" "README.md" "settings.snippet.json"; do
  out=$(run_hook "$proj" Edit "$tgt"); rc=$?
  c=$(ctx "$out")
  if [ "$rc" -eq 0 ] && [ -z "$c" ]; then
    pass "silent on $tgt"
  else
    fail "expected silent on $tgt. rc=$rc" "$out"
  fi
done
rm -rf "$proj"

# -------------------------------------------------------------------
# 5. no in_progress bead → silent.
# -------------------------------------------------------------------
echo "==> 5. no in_progress bead → silent"
proj=$(mk_project "" "")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && [ -z "$c" ]; then
  pass "no in_progress: silent, exit 0"
else
  fail "expected silent. rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 6. once-per-bead memoization.
# -------------------------------------------------------------------
echo "==> 6. once-per-bead memoization"
proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); c1=$(ctx "$out")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?; c2=$(ctx "$out")
if [ -n "$c1" ] && [ "$rc" -eq 0 ] && [ -z "$c2" ]; then
  pass "first edit nudges, second edit silent (memoized)"
else
  fail "memoization failed: c1='$c1' c2='$c2' rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
# 7. non-Edit tool → silent.
# -------------------------------------------------------------------
echo "==> 7. non-Edit tool → silent"
proj=$(mk_project "loom-h5s" "")
for tool in Read Bash Glob Grep; do
  out=$(run_hook "$proj" "$tool" "hooks/foo.sh"); rc=$?
  c=$(ctx "$out")
  [ "$rc" -eq 0 ] && [ -z "$c" ] && pass "$tool silent" \
    || fail "$tool not silent. rc=$rc" "$out"
done
rm -rf "$proj"

# -------------------------------------------------------------------
# 8. LOOM_DISPATCH_NUDGE_SKIP=1 bypass.
# -------------------------------------------------------------------
echo "==> 8. LOOM_DISPATCH_NUDGE_SKIP=1 bypass"
proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" Edit "hooks/foo.sh" LOOM_DISPATCH_NUDGE_SKIP=1); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && [ -z "$c" ]; then
  pass "SKIP=1 bypass: silent, exit 0"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
