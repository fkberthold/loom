#!/usr/bin/env bash
# Fixture tests for hooks/pre-push-mkdocs-strict.sh.
#
# Hook contract pinned here (loom-kbo):
#   - Pre-push git hook. Reads pre-push stdin lines of the form
#     `<local_ref> <local_sha> <remote_ref> <remote_sha>`.
#   - For each push range, compute the changed file list via
#     `git diff --name-only $remote_sha..$local_sha`. When remote_sha
#     is all-zeros (new branch on remote), fall back to diff against
#     `main`.
#   - If any changed path matches ^(docs/|mkdocs\.yml$|skills/), run
#     `mkdocs build --strict` from the repo root.
#   - On success: silent exit 0.
#   - On strict failure: emit a WARN block on stderr and STILL exit 0.
#     This hook is WARN-only, never BLOCK. It is the third line of a
#     three-layer defence (preflight @ bd close → pre-push @ git push
#     → CI on origin), and we keep it permissive so the dispatcher
#     workflow is never wedged by a transient docs error.
#   - LOOM_PRE_PUSH_MKDOCS_SKIP=1 short-circuits silently.
#   - MKDOCS_BIN=<path> overrides the mkdocs binary (test seam).
#
# Run:  bash lib/tests/pre-push-mkdocs-strict.test.sh
# (RED-confirmed 0/9 before implementing hooks/pre-push-mkdocs-strict.sh
#  per superpowers:test-driven-development; tests pin the hook contract.)

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/pre-push-mkdocs-strict.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

ZERO_SHA="0000000000000000000000000000000000000000"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Build a real, isolated git repo with:
#   - main branch
#   - a feature branch ahead of main by N commits
#
# Args:
#   $1  repo dir to create
#   $2  comma-separated list of files changed on the feature branch
#       e.g. "docs/foo.md,README.md"
mk_repo() {
  local dir="$1" files="$2"
  mkdir -p "$dir"
  (
    cd "$dir"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name  "test"
    # Seed main with a baseline so diff has something to compute against.
    mkdir -p docs
    echo "site_name: fixture" > mkdocs.yml
    echo "# Home" > docs/index.md
    echo "baseline" > README.md
    git add -A
    git commit -q -m "baseline on main"
    # Branch off and modify the requested files.
    git checkout -q -b feature
    local IFS=,
    for f in $files; do
      mkdir -p "$(dirname "$f")"
      echo "change-on-feature" >> "$f"
    done
    git add -A
    git commit -q -m "feature changes"
  )
}

# A no-op mkdocs that always succeeds.
mk_noop_mkdocs() {
  local path="$1"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$path"
}

# A failing mkdocs — stand-in for "strict found a broken link".
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

# A mkdocs that records each invocation to a log file
# (used to assert non-invocation).
mk_tracer_mkdocs() {
  local path="$1" log_path="$2"
  cat > "$path" <<SH
#!/usr/bin/env bash
echo "called: \$*" >> "$log_path"
exit 0
SH
  chmod +x "$path"
}

# Build the stdin payload that git pipes into pre-push:
#   <local_ref> <local_sha> <remote_ref> <remote_sha>
mk_stdin() {
  local local_ref="$1" local_sha="$2" remote_ref="$3" remote_sha="$4"
  printf '%s %s %s %s\n' "$local_ref" "$local_sha" "$remote_ref" "$remote_sha"
}

run_hook() {
  local repo="$1" stdin="$2"; shift 2
  (cd "$repo" && env "$@" bash "$HOOK" <<<"$stdin" 2>&1)
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "==> 1. Docs file in push range + mkdocs strict succeeds → silent exit 0"
repo="$TMP/r1"; mk_repo "$repo" "docs/index.md"
mk_noop_mkdocs "$TMP/mkdocs-ok"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-ok"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "passing strict + docs change → silent exit 0"
else
  fail "should be silent exit 0 (rc=$rc out='$out')"
fi

echo "==> 2. Docs file in push range + mkdocs strict fails → exit 0 with WARN on stderr"
repo="$TMP/r2"; mk_repo "$repo" "docs/index.md"
mk_failing_mkdocs "$TMP/mkdocs-fail"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-fail"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "WARN" && echo "$out" | grep -qi "mkdocs"; then
  pass "failing strict + docs change → exit 0 with WARN block"
else
  fail "should warn-but-not-block (rc=$rc)" "$out"
fi

echo "==> 3. Non-docs file only in push range → mkdocs not invoked, silent exit 0"
repo="$TMP/r3"; mk_repo "$repo" "README.md"
mk_tracer_mkdocs "$TMP/mkdocs-trace" "$TMP/r3-invocations"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-trace"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -f "$TMP/r3-invocations" ]; then
  pass "non-docs-only push → mkdocs not invoked, silent exit 0"
else
  fail "non-docs push should skip mkdocs (rc=$rc out='$out' invoked=$([ -f "$TMP/r3-invocations" ] && echo yes || echo no))"
fi

echo "==> 4. LOOM_PRE_PUSH_MKDOCS_SKIP=1 → silent exit 0 even with docs changes + failing mkdocs"
repo="$TMP/r4"; mk_repo "$repo" "docs/index.md"
mk_failing_mkdocs "$TMP/mkdocs-fail4"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-fail4" LOOM_PRE_PUSH_MKDOCS_SKIP=1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "env bypass honored even with broken docs"
else
  fail "bypass should silence everything (rc=$rc out='$out')"
fi

echo "==> 5. skills/ change triggers mkdocs"
repo="$TMP/r5"; mk_repo "$repo" "skills/foo/SKILL.md"
mk_tracer_mkdocs "$TMP/mkdocs-trace5" "$TMP/r5-invocations"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-trace5"); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/r5-invocations" ]; then
  pass "skills/ change triggers mkdocs"
else
  fail "skills/ should trigger mkdocs (rc=$rc out='$out' invoked=$([ -f "$TMP/r5-invocations" ] && echo yes || echo no))"
fi

echo "==> 6. New-branch push (remote_sha=000…) falls back to diff vs main"
# Push line where the remote has never seen this branch — remote_sha is
# all-zeros. The hook must fall back to `git diff --name-only main..local_sha`.
repo="$TMP/r6"; mk_repo "$repo" "docs/index.md"
mk_tracer_mkdocs "$TMP/mkdocs-trace6" "$TMP/r6-invocations"
feature_sha=$(git -C "$repo" rev-parse feature)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$ZERO_SHA")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-trace6"); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/r6-invocations" ]; then
  pass "all-zeros remote_sha → diff vs main → mkdocs invoked"
else
  fail "new-branch path didn't trigger (rc=$rc out='$out')"
fi

echo "==> 7. mkdocs.yml change triggers mkdocs"
repo="$TMP/r7"; mk_repo "$repo" "mkdocs.yml"
mk_tracer_mkdocs "$TMP/mkdocs-trace7" "$TMP/r7-invocations"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-trace7"); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/r7-invocations" ]; then
  pass "mkdocs.yml change triggers mkdocs"
else
  fail "mkdocs.yml should trigger mkdocs (rc=$rc out='$out')"
fi

echo "==> 8. mkdocs not installed → silent exit 0 (graceful skip)"
repo="$TMP/r8"; mk_repo "$repo" "docs/index.md"
feature_sha=$(git -C "$repo" rev-parse feature)
main_sha=$(git -C "$repo" rev-parse main)
stdin=$(mk_stdin "refs/heads/feature" "$feature_sha" "refs/heads/feature" "$main_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="/nonexistent/mkdocs"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "missing mkdocs binary → graceful silent skip"
else
  fail "missing mkdocs should be silent skip (rc=$rc out='$out')"
fi

echo "==> 9. Delete-branch push (local_sha=000…) → silent skip, no mkdocs invocation"
repo="$TMP/r9"; mk_repo "$repo" "docs/index.md"
mk_tracer_mkdocs "$TMP/mkdocs-trace9" "$TMP/r9-invocations"
feature_sha=$(git -C "$repo" rev-parse feature)
stdin=$(mk_stdin "(delete)" "$ZERO_SHA" "refs/heads/feature" "$feature_sha")
out=$(run_hook "$repo" "$stdin" MKDOCS_BIN="$TMP/mkdocs-trace9"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -f "$TMP/r9-invocations" ]; then
  pass "branch-delete push → silent skip"
else
  fail "branch-delete should skip (rc=$rc out='$out')"
fi

echo ""
echo "Results: $passed passed, $failed failed"

[ "$failed" -eq 0 ]
