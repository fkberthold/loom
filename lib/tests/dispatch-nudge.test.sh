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
#   - the target file_path is a NUDGE-ELIGIBLE file: a SOURCE file
#     (hooks/*.sh, scripts/*, lib/*.sh) OR a TEST file (lib/tests/
#     *.test.sh, *_test.*) — central editing a test inline is the
#     same anti-pattern. EXCLUDES *.md, docs/, config.
# The nudge names /dispatch-middle as the default (the cheap command).
# When dispatch=worker but central edits a nudge-eligible file, it emits
# a softer one-line mismatch reminder. Otherwise silent. Always exit 0.
# Memoized once-per-bead via a sentinel keyed on the in_progress id.
#
# Run:  bash lib/tests/dispatch-nudge.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/dispatch-nudge.sh"
WS="$LOOM_ROOT/scripts/workflow-state"
HELPERS="$LOOM_ROOT/lib/loom-hook-helpers.sh"

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
#   $3 = OPTIONAL space-separated bead ids listed AHEAD of $1 in the
#        fake `bd list --status=in_progress` output. Lets a test make
#        `bd list | head -1` name a DIFFERENT bead than the one
#        workflow-state records (the loom-p5ee D3 case).
#   $4 = OPTIONAL workflow-state `bead` value. Defaults to $1. The
#        literal token NONE writes JSON null (field unset), forcing the
#        hook onto its bd-list regex fallback.
# echoes the project dir
mk_project() {
  local ip_bead="$1" dispatch="$2" ahead="${3:-}" wfs_bead="${4:-}"
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads" "$d/bin"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  if [ -z "$wfs_bead" ]; then
    wfs_bead="${ip_bead:-loom-xxx}"
  fi
  if [ "$wfs_bead" = "NONE" ]; then
    printf '{"v":1,"mode":"full","activity":"feature","bead":null,"stage":"tdd-red","updated":"2026-06-06T00:00:00Z"}\n' \
      > "$d/.claude/workflow-state.json"
  else
    printf '{"v":1,"mode":"full","activity":"feature","bead":"%s","stage":"tdd-red","updated":"2026-06-06T00:00:00Z"}\n' \
      "$wfs_bead" > "$d/.claude/workflow-state.json"
  fi
  if [ -n "$dispatch" ]; then
    bash "$WS" set "--start-dir=$d" "dispatch=$dispatch" >/dev/null 2>&1
  fi

  # Fake bd: emit one issue line per in_progress bead ($3 ahead of $1).
  cat > "$d/bin/bd" <<EOF
#!/usr/bin/env bash
if printf '%s ' "\$@" | grep -q 'list' && printf '%s ' "\$@" | grep -q 'in_progress'; then
  for b in ${ahead}; do
    echo "\$b  [in_progress]  some other title"
  done
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

# Write a project constitution pinning language.runtime.
#   $1 = project dir   $2 = runtime value
add_constitution() {
  local d="$1" rt="$2"
  mkdir -p "$d/.claude"
  cat > "$d/.claude/project-constitution.md" <<EOF
---
package_manager: none

language:
  runtime: ${rt}
  version: ""

canonical_commands:
  test: "fixture-test"
---

# fixture constitution
EOF
}

# Write a constitution whose front-matter is NOT parseable YAML.
add_broken_constitution() {
  local d="$1"
  mkdir -p "$d/.claude"
  cat > "$d/.claude/project-constitution.md" <<'EOF'
---
language:
  runtime: "unterminated
 	: [ }
---

# broken fixture constitution
EOF
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
echo "==> 1. unset + in_progress + source → nudge naming /dispatch-middle"
proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?
c=$(ctx "$out")
if [ "$rc" -eq 0 ] && echo "$c" | grep -q "/dispatch-middle"; then
  pass "nudge emitted on hooks/foo.sh naming /dispatch-middle, exit 0"
else
  fail "expected nudge naming /dispatch-middle + exit 0. rc=$rc" "$out"
fi
rm -rf "$proj"
# scripts/* and lib/*.sh also count as source (fresh project — the
# nudge is memoized once-per-bead, so reuse would be silent).
proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" Write "scripts/bar"); c=$(ctx "$out")
echo "$c" | grep -q "/dispatch-middle" && pass "scripts/* counts as source" \
  || fail "scripts/* not nudged" "$out"
rm -rf "$proj"

proj=$(mk_project "loom-h5s" "")
out=$(run_hook "$proj" MultiEdit "lib/baz.sh"); c=$(ctx "$out")
echo "$c" | grep -q "/dispatch-middle" && pass "lib/*.sh counts as source" \
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
# 4. docs / md / config target → silent (NOT nudge-eligible).
#    NOTE: test files are NO LONGER silent — they nudge (see case 9).
# -------------------------------------------------------------------
echo "==> 4. docs/md/config targets → silent"
proj=$(mk_project "loom-h5s" "")
for tgt in "docs/reference/x.md" "README.md" "settings.snippet.json"; do
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
# 9. test-file edit + in_progress + dispatch-unset → nudge naming
#    /dispatch-middle (central editing a test inline is the issue-#2
#    anti-pattern). Covers lib/tests/*.test.sh and *_test.* shapes.
# -------------------------------------------------------------------
echo "==> 9. test-file edit + unset → nudge naming /dispatch-middle"
for tgt in "lib/tests/foo.test.sh" "scripts/foo_test.sh" "pkg/bar_test.go" "x/foo.test.js"; do
  proj=$(mk_project "loom-h5s" "")
  out=$(run_hook "$proj" Edit "$tgt"); rc=$?
  c=$(ctx "$out")
  if [ "$rc" -eq 0 ] && echo "$c" | grep -q "/dispatch-middle"; then
    pass "test file $tgt nudges naming /dispatch-middle"
  else
    fail "expected nudge naming /dispatch-middle on $tgt. rc=$rc" "$out"
  fi
  rm -rf "$proj"
done

# ===================================================================
# loom-p5ee — three defects in hooks/dispatch-nudge.sh.
#
# INVARIANT: for a project whose sources are *.py and whose tests are
# test_*.py, the eligibility predicate returns TRUE for both a source
# path and a test path; a bead id containing `_` round-trips unchanged
# through the id parse; and with N>1 in_progress beads the memoization
# sentinel keys on the bead recorded in workflow-state, not on
# `bd list --status=in_progress | head -1`.
# ===================================================================

# -------------------------------------------------------------------
# 10. D1 — the shared source/test classifier in lib/.
#     Extracted so the sibling main-checkout-edit-guard hook (loom-vr6k)
#     consumes the same predicate. Unit-level contract.
# -------------------------------------------------------------------
echo "==> 10. shared classifier: loom_path_class / loom_is_source_or_test"
# shellcheck source=../loom-hook-helpers.sh
. "$HELPERS"

if ! declare -F loom_is_source_or_test >/dev/null 2>&1; then
  fail "lib/loom-hook-helpers.sh does not define loom_is_source_or_test"
fi
if ! declare -F loom_path_class >/dev/null 2>&1; then
  fail "lib/loom-hook-helpers.sh does not define loom_path_class"
fi

cls() { loom_path_class "$1" "${2:-$PWD}" 2>/dev/null; }

# 10a. No constitution → WIDENED built-in list covering py/sh/go/js/ts/rb/rs.
nocon=$(mktemp -d)
for p in \
  "palace/episodic_store.py:source" \
  "hooks/foo.sh:source" \
  "scripts/bar:source" \
  "pkg/thing.go:source" \
  "src/app.ts:source" \
  "src/app.js:source" \
  "lib/thing.rb:source" \
  "src/main.rs:source" \
  "tests/palace/test_episodic_store.py:test" \
  "palace/test_episodic_store.py:test" \
  "pkg/thing_test.go:test" \
  "src/app.test.js:test" \
  "spec/thing_spec.rb:test" \
  "README.md:other" \
  "docs/reference/x.md:other" \
  "settings.snippet.json:other" \
; do
  path="${p%:*}"; want="${p##*:}"
  got=$(cls "$path" "$nocon")
  if [ "$got" = "$want" ]; then
    pass "no-constitution: $path → $want"
  else
    fail "no-constitution: $path → got '$got', want '$want'"
  fi
done
rm -rf "$nocon"

# 10b. Constitution with language.runtime: python → *.py source,
#      test_*.py test. This is the exact liza_base shape the hook went
#      100% dark on.
if command -v yq >/dev/null 2>&1; then
  pycon=$(mktemp -d); add_constitution "$pycon" "python"
  for p in \
    "palace/episodic_store.py:source" \
    "tests/palace/test_episodic_store.py:test" \
    "palace/test_episodic_store.py:test" \
    "palace/episodic_store_test.py:test" \
    "scripts/test:source" \
    "README.md:other" \
  ; do
    path="${p%:*}"; want="${p##*:}"
    got=$(cls "$path" "$pycon")
    if [ "$got" = "$want" ]; then
      pass "python-constitution: $path → $want"
    else
      fail "python-constitution: $path → got '$got', want '$want'"
    fi
  done
  # The runtime is actually CONSULTED: a Go file is not a python source.
  got=$(cls "pkg/thing.go" "$pycon")
  [ "$got" = "other" ] && pass "python-constitution: pkg/thing.go → other (runtime consulted)" \
    || fail "python-constitution: pkg/thing.go → got '$got', want 'other'"
  rm -rf "$pycon"
else
  echo "  (skip: yq unavailable — constitution-driven cases)"
fi

# 10c. Constitution present but UNPARSEABLE → widened fallback still
#      classifies (must NOT go dark).
brokencon=$(mktemp -d); add_broken_constitution "$brokencon"
got=$(cls "palace/episodic_store.py" "$brokencon")
[ "$got" = "source" ] && pass "broken-constitution: *.py still source (fallback)" \
  || fail "broken-constitution: palace/episodic_store.py → got '$got', want 'source'"
got=$(cls "tests/palace/test_episodic_store.py" "$brokencon")
[ "$got" = "test" ] && pass "broken-constitution: test_*.py still test (fallback)" \
  || fail "broken-constitution: tests/.../test_*.py → got '$got', want 'test'"
rm -rf "$brokencon"

# 10d. yq MISSING from PATH → widened fallback still classifies. This is
#      a REAL code path, not an error path: bd memory
#      `yq-required-for-constitution-enforce` records constitution-enforce
#      silently failing open for weeks on a yq-less host. Falling back
#      must still nudge.
yqlesscon=$(mktemp -d); add_constitution "$yqlesscon" "python"
got=$(LOOM_YQ_BIN="__loom_absent_yq__" cls "palace/episodic_store.py" "$yqlesscon")
[ "$got" = "source" ] && pass "yq-missing: *.py still source (fallback)" \
  || fail "yq-missing: palace/episodic_store.py → got '$got', want 'source'"
got=$(LOOM_YQ_BIN="__loom_absent_yq__" cls "tests/palace/test_episodic_store.py" "$yqlesscon")
[ "$got" = "test" ] && pass "yq-missing: test_*.py still test (fallback)" \
  || fail "yq-missing: tests/.../test_*.py → got '$got', want 'test'"
# The widened fallback is genuinely wider than the python set.
got=$(LOOM_YQ_BIN="__loom_absent_yq__" cls "pkg/thing.go" "$yqlesscon")
[ "$got" = "source" ] && pass "yq-missing: pkg/thing.go → source (widened list)" \
  || fail "yq-missing: pkg/thing.go → got '$got', want 'source'"
rm -rf "$yqlesscon"

# 10e. loom_is_source_or_test is the boolean face of the same predicate.
boolcon=$(mktemp -d)
loom_is_source_or_test "palace/episodic_store.py" "$boolcon" \
  && pass "loom_is_source_or_test: source path true" \
  || fail "loom_is_source_or_test: source path returned false"
loom_is_source_or_test "tests/palace/test_episodic_store.py" "$boolcon" \
  && pass "loom_is_source_or_test: test path true" \
  || fail "loom_is_source_or_test: test path returned false"
if loom_is_source_or_test "README.md" "$boolcon"; then
  fail "loom_is_source_or_test: README.md returned true"
else
  pass "loom_is_source_or_test: README.md false"
fi
rm -rf "$boolcon"

# -------------------------------------------------------------------
# 11. D1 end-to-end — a Python-shaped project nudges on BOTH a source
#     and a test edit (previously 100% dark).
# -------------------------------------------------------------------
echo "==> 11. python project: source + test edits both nudge"
for tgt in "palace/episodic_store.py" "tests/palace/test_episodic_store.py"; do
  proj=$(mk_project "loom-h5s" "")
  add_constitution "$proj" "python"
  out=$(run_hook "$proj" Edit "$tgt"); rc=$?
  c=$(ctx "$out")
  if [ "$rc" -eq 0 ] && echo "$c" | grep -q "/dispatch-middle"; then
    pass "python project nudges on $tgt"
  else
    fail "expected nudge on $tgt. rc=$rc" "$out"
  fi
  rm -rf "$proj"
done
# Same two paths with NO constitution at all → widened fallback nudges.
for tgt in "palace/episodic_store.py" "tests/palace/test_episodic_store.py"; do
  proj=$(mk_project "loom-h5s" "")
  out=$(run_hook "$proj" Edit "$tgt")
  c=$(ctx "$out")
  echo "$c" | grep -q "/dispatch-middle" \
    && pass "no-constitution project nudges on $tgt" \
    || fail "expected nudge on $tgt (no constitution)" "$out"
  rm -rf "$proj"
done

# -------------------------------------------------------------------
# 12. D2 — bead ids containing `_` round-trip through the id parse.
#     `liza_base-6r49` must NOT be truncated to `base-6r49`.
#     workflow-state's bead is unset (NONE) so the bd-list regex path
#     is the one under test.
# -------------------------------------------------------------------
echo "==> 12. snake_case bead prefix survives the id parse"
for bead in "liza_base-6r49" "loom-ig3p.1" "loom-h5s"; do
  proj=$(mk_project "$bead" "" "" NONE)
  out=$(run_hook "$proj" Edit "hooks/foo.sh"); rc=$?
  c=$(ctx "$out")
  if [ "$rc" -eq 0 ] && echo "$c" | grep -qF "/dispatch-middle $bead"; then
    pass "id parse round-trips $bead"
  else
    fail "expected '/dispatch-middle $bead' in nudge. rc=$rc" "$out"
  fi
  # The sentinel is keyed on the FULL id, not a truncation.
  if [ -e "$proj/.claude/.loom-dispatch-nudged-$bead" ]; then
    pass "sentinel keyed on full id $bead"
  else
    fail "sentinel .loom-dispatch-nudged-$bead missing" "$(ls -a "$proj/.claude")"
  fi
  rm -rf "$proj"
done

# -------------------------------------------------------------------
# 13. D3 — memoization keys on the workflow-state bead, not on
#     `bd list --status=in_progress | head -1`.
# -------------------------------------------------------------------
echo "==> 13. memoization keys on the workflow-state bead"
proj=$(mk_project "loom-h5s" "" "loom-aaa loom-bbb")
out=$(run_hook "$proj" Edit "hooks/foo.sh")
c=$(ctx "$out")
if echo "$c" | grep -qF "/dispatch-middle loom-h5s"; then
  pass "nudge names the workflow-state bead (loom-h5s), not bd-list head"
else
  fail "expected nudge to name loom-h5s" "$out"
fi
if [ -e "$proj/.claude/.loom-dispatch-nudged-loom-h5s" ]; then
  pass "sentinel keyed on workflow-state bead"
else
  fail "sentinel .loom-dispatch-nudged-loom-h5s missing" "$(ls -a "$proj/.claude")"
fi
if [ -e "$proj/.claude/.loom-dispatch-nudged-loom-aaa" ]; then
  fail "sentinel wrongly keyed on bd-list head loom-aaa"
else
  pass "no sentinel for the bd-list head bead"
fi
# One nudge must NOT permanently suppress every other concurrent bead.
bash "$WS" set "--start-dir=$proj" "bead=loom-ccc" >/dev/null 2>&1
out2=$(run_hook "$proj" Edit "hooks/foo.sh")
c2=$(ctx "$out2")
if echo "$c2" | grep -qF "/dispatch-middle loom-ccc"; then
  pass "a second concurrent bead still nudges (not suppressed)"
else
  fail "second bead loom-ccc was suppressed by the first bead's sentinel" "$out2"
fi
rm -rf "$proj"

# -------------------------------------------------------------------
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
