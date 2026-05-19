#!/usr/bin/env bash
# Fixture tests for hooks/bd-preflight-docs-strict.sh.
#
# Hook contract pinned here:
#   - PreToolUse Bash matcher; only fires on `bd close` or `bd preflight`.
#   - Skips fast when: not a docs-bearing project (no mkdocs.yml),
#     mkdocs not installed, no docs-relevant diff vs main, env-bypass
#     set, or workflow mode is off.
#   - Otherwise runs `mkdocs build --strict`. On pass: exit 0 silent.
#     On fail in full mode: exit 2 with first WARNING/ERROR line +
#     remediation. In light mode: exit 0 with WARN-prefix stderr.
#
# Test injection points (mirrors bd-close-capture.sh pattern):
#   LOOM_BD_PRECLOSE_STRICT_SKIP=1
#     User-facing bypass for emergencies.
#   LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1
#     Test-only: force the file-relevance gate to pass without needing
#     real git history (the relevance check is unit-tested separately
#     in the "diff-empty" case).
#   MKDOCS_BIN=<path>
#     Override the mkdocs binary path (used to simulate "not installed"
#     and to point at a no-op mkdocs in fixtures that don't need a real
#     strict build).
#
# Run:  bash lib/tests/bd-preflight-docs-strict.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-preflight-docs-strict.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook in a controlled env. Returns combined stdout+stderr;
# exit code captured separately via $?.
run_hook() {
  local proj="$1" cmd="$2"
  local payload
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  (cd "$proj" && bash "$HOOK" <<<"$payload" 2>&1)
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Project with mkdocs.yml + workflow.json mode=full + clean docs/.
mk_clean_docs_project() {
  local dir="$1" mode="${2:-full}"
  mkdir -p "$dir/.claude" "$dir/docs"
  echo "{\"v\":1,\"mode\":\"$mode\"}" > "$dir/.claude/workflow.json"
  cat > "$dir/mkdocs.yml" <<'YML'
site_name: fixture
docs_dir: docs
nav:
  - Home: index.md
YML
  cat > "$dir/docs/index.md" <<'MD'
# Home

Welcome.
MD
}

# Project with mkdocs.yml + broken link → mkdocs --strict will fail.
mk_broken_docs_project() {
  local dir="$1" mode="${2:-full}"
  mk_clean_docs_project "$dir" "$mode"
  cat >> "$dir/docs/index.md" <<'MD'

See [the missing page](nope.md).
MD
}

# Project without mkdocs.yml at all.
mk_non_docs_project() {
  local dir="$1" mode="${2:-full}"
  mkdir -p "$dir/.claude"
  echo "{\"v\":1,\"mode\":\"$mode\"}" > "$dir/.claude/workflow.json"
}

# A no-op mkdocs binary that always succeeds. Used when the hook should
# proceed past the install-check but we don't want to pay the real build
# cost in tests of branching logic.
mk_noop_mkdocs() {
  local path="$1"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$path"
}

# A failing mkdocs binary — stand-in for "strict found a broken link".
mk_failing_mkdocs() {
  local path="$1"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
echo "INFO    -  Building documentation..."
echo "WARNING -  Doc file 'index.md' contains a link 'nope.md', but the target is not found among documentation files."
echo "Aborted with 1 warnings in strict mode!"
exit 1
SH
  chmod +x "$path"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "==> 1. Non-Bash tool → exit 0"
proj="$TMP/p1"; mk_clean_docs_project "$proj"
payload='{"tool_name":"Edit","tool_input":{"file_path":"x"}}'
out=$( (cd "$proj" && bash "$HOOK" <<<"$payload" 2>&1) ); rc=$?
[ "$rc" -eq 0 ] && pass "non-Bash tool ignored" || fail "non-Bash should be no-op (exit=$rc)" "$out"

echo "==> 2. Bash but not bd close|preflight → exit 0"
proj="$TMP/p2"; mk_clean_docs_project "$proj"
out=$(run_hook "$proj" "ls -la"); rc=$?
[ "$rc" -eq 0 ] && pass "irrelevant bash ignored" || fail "irrelevant bash should be no-op (exit=$rc)" "$out"

echo "==> 3. LOOM_BD_PRECLOSE_STRICT_SKIP=1 → exit 0 even with broken docs"
proj="$TMP/p3"; mk_broken_docs_project "$proj"
out=$(LOOM_BD_PRECLOSE_STRICT_SKIP=1 LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd close loom-cya"); rc=$?
[ "$rc" -eq 0 ] && pass "user bypass honored" || fail "bypass should exit 0 (exit=$rc)" "$out"

echo "==> 4. No mkdocs.yml → exit 0 (not a docs project)"
proj="$TMP/p4"; mk_non_docs_project "$proj"
out=$(LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 run_hook "$proj" "bd close loom-cya"); rc=$?
[ "$rc" -eq 0 ] && pass "non-docs project skipped" || fail "no mkdocs.yml should exit 0 (exit=$rc)" "$out"

echo "==> 5. mkdocs not installed → exit 0 (graceful skip)"
proj="$TMP/p5"; mk_clean_docs_project "$proj"
out=$(MKDOCS_BIN="/nonexistent/mkdocs" LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd close loom-cya"); rc=$?
[ "$rc" -eq 0 ] && pass "mkdocs-absent skipped" || fail "missing mkdocs should exit 0 (exit=$rc)" "$out"

echo "==> 6. workflow mode=off → exit 0 silent"
proj="$TMP/p6"; mk_broken_docs_project "$proj" "off"
out=$(LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 run_hook "$proj" "bd close loom-cya"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "mode=off silent skip" \
  || fail "mode=off should be silent (exit=$rc out='$out')"

echo "==> 7. No docs-relevant diff → exit 0 without invoking mkdocs"
# Force-relevant defaults to OFF here; with no git history at all the
# hook's diff check should produce empty → skip.
proj="$TMP/p7"; mk_broken_docs_project "$proj"
out=$(run_hook "$proj" "bd close loom-cya"); rc=$?
[ "$rc" -eq 0 ] && pass "no-relevant-diff skipped" || fail "no-relevant-diff should exit 0 (exit=$rc)" "$out"

echo "==> 8. Relevant diff + mkdocs --strict passes → exit 0"
proj="$TMP/p8"; mk_clean_docs_project "$proj"
mk_noop_mkdocs "$TMP/mkdocs-ok"
out=$(MKDOCS_BIN="$TMP/mkdocs-ok" LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd close loom-cya"); rc=$?
[ "$rc" -eq 0 ] && pass "passing strict build allows close" \
  || fail "passing build should exit 0 (exit=$rc)" "$out"

echo "==> 9. Relevant diff + mkdocs --strict fails + mode=full → exit 2 with remediation"
proj="$TMP/p9"; mk_broken_docs_project "$proj" "full"
mk_failing_mkdocs "$TMP/mkdocs-fail"
out=$(MKDOCS_BIN="$TMP/mkdocs-fail" LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd close loom-cya"); rc=$?
if [ "$rc" -eq 2 ]; then
  echo "$out" | grep -q "WARNING" \
    && echo "$out" | grep -q "LOOM_BD_PRECLOSE_STRICT_SKIP" \
    && pass "full mode blocks with WARNING line + bypass hint" \
    || fail "exit 2 but missing expected stderr content" "$out"
else
  fail "full mode should block (exit=$rc)" "$out"
fi

echo "==> 10. Relevant diff + failing strict + mode=light → exit 0 with WARN prefix"
proj="$TMP/p10"; mk_broken_docs_project "$proj" "light"
out=$(MKDOCS_BIN="$TMP/mkdocs-fail" LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd close loom-cya"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "WARN"; then
  pass "light mode warns without blocking"
else
  fail "light mode should warn (exit=$rc)" "$out"
fi

echo "==> 11. Matches 'bd preflight' as well as 'bd close'"
proj="$TMP/p11"; mk_broken_docs_project "$proj" "full"
out=$(MKDOCS_BIN="$TMP/mkdocs-fail" LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd preflight --check"); rc=$?
[ "$rc" -eq 2 ] && pass "bd preflight gated too" \
  || fail "bd preflight should be gated (exit=$rc)" "$out"

echo "==> 12. Does NOT match 'bd closeable' or similar prefix collisions"
proj="$TMP/p12"; mk_broken_docs_project "$proj" "full"
out=$(MKDOCS_BIN="$TMP/mkdocs-fail" LOOM_BD_PRECLOSE_STRICT_FORCE_RELEVANT=1 \
  run_hook "$proj" "bd closeable-thing"); rc=$?
[ "$rc" -eq 0 ] && pass "no false match on 'bd closeable-thing'" \
  || fail "false-positive on lookalike (exit=$rc)" "$out"

echo ""
echo "Results: $passed passed, $failed failed"

[ "$failed" -eq 0 ]
