#!/usr/bin/env bash
# Fixture tests for hooks/git-push-bd-sync.sh.
#
# Covers the loom-u9v false-positive: when cwd has dirty .beads/ but the
# `git push` command is for a different repo (`cd /other && git push`),
# the hook must stay silent.
#
# Run:  bash lib/tests/git-push-bd-sync.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/git-push-bd-sync.sh"

passed=0
failed=0

run_hook() {
  local dir="$1" input="$2"
  (cd "$dir" && echo "$input" | bash "$HOOK" 2>&1)
}

assert_warns() {
  local name="$1" output="$2"
  if echo "$output" | grep -q 'git-push-bd-sync hook'; then
    echo "  PASS: $name"
    passed=$((passed + 1))
  else
    echo "  FAIL: $name (expected warning, got:)"
    echo "$output" | sed 's/^/    /'
    failed=$((failed + 1))
  fi
}

assert_silent() {
  local name="$1" output="$2"
  if echo "$output" | grep -q 'git-push-bd-sync hook'; then
    echo "  FAIL: $name (expected silent, got:)"
    echo "$output" | sed 's/^/    /'
    failed=$((failed + 1))
  else
    echo "  PASS: $name"
    passed=$((passed + 1))
  fi
}

mk_dirty_beads_repo() {
  local dir
  dir=$(mktemp -d)
  (cd "$dir" \
    && git init -q \
    && git config user.email t@e.x \
    && git config user.name t \
    && mkdir .beads \
    && printf '{"id":"a"}\n' > .beads/issues.jsonl \
    && git add . \
    && git commit -qm init) >/dev/null
  printf '{"id":"b"}\n' > "$dir/.beads/issues.jsonl"
  echo "$dir"
}

mk_clean_repo() {
  local dir
  dir=$(mktemp -d)
  (cd "$dir" \
    && git init -q \
    && git config user.email t@e.x \
    && git config user.name t \
    && touch README \
    && git add . \
    && git commit -qm init) >/dev/null
  echo "$dir"
}

mk_no_beads_repo() {
  mk_clean_repo
}

DIRTY=$(mk_dirty_beads_repo)
CLEAN=$(mk_dirty_beads_repo)  # second dirty repo
NOBEADS=$(mk_no_beads_repo)

# 1. Same-cwd push from a dirty-beads repo → WARN (regression)
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git push"}}')
assert_warns "same-cwd push warns when .beads/ is dirty" "$out"

# 2. `cd /clean && git push` from dirty cwd → SILENT (the loom-u9v bug)
out=$(run_hook "$DIRTY" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $NOBEADS && git push\"}}")
assert_silent "cd-elsewhere-then-push is silent when target has no .beads/" "$out"

# 3. `cd /clean-with-no-beads ; git push` from dirty cwd → SILENT
out=$(run_hook "$DIRTY" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $NOBEADS ; git push\"}}")
assert_silent "cd-elsewhere-with-semicolon is silent" "$out"

# 4. `cd /dirty-target && git push` from clean cwd → WARN about target
out=$(run_hook "$NOBEADS" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $DIRTY && git push\"}}")
assert_warns "cd-to-dirty-target then push warns about target" "$out"

# 5. cwd has no .beads/, plain `git push` → SILENT (control)
out=$(run_hook "$NOBEADS" '{"tool_name":"Bash","tool_input":{"command":"git push"}}')
assert_silent "no-.beads/ cwd is silent" "$out"

# 6. --dry-run is always silent
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git push --dry-run"}}')
assert_silent "--dry-run is silent" "$out"

# 7. Non-Bash tool calls are ignored
out=$(run_hook "$DIRTY" '{"tool_name":"Edit","tool_input":{"command":"git push"}}')
assert_silent "non-Bash tools are ignored" "$out"

# Bug-class: chain shapes that resolve effective cwd correctly.

# 8. Multiple chained `cd`s — last cd before push wins
out=$(run_hook "$DIRTY" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $DIRTY && cd $NOBEADS && git push\"}}")
assert_silent "chained cd's pick last (push target = no-beads)" "$out"

# 9. Relative cd path resolved against cwd
SUBDIR="$NOBEADS/sub"
mkdir -p "$SUBDIR"
out=$(run_hook "$NOBEADS" '{"tool_name":"Bash","tool_input":{"command":"cd ./sub && git push"}}')
assert_silent "relative cd ./sub resolves against cwd" "$out"

# 10. Force-push variants stay covered (no --dry-run)
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')
assert_warns "force-push warns when dirty" "$out"

# 11. Push with refspec
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')
assert_warns "push with refspec warns when dirty" "$out"

# Bug-class (loom-0r6): same Bash chain commits BEFORE pushing — the chain
# itself stages-and-commits .beads/, so the dirty-at-fire-time check would
# warn unnecessarily.

# 12. Chained: add + commit + push (dirty at fire-time) → SILENT
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git add .beads/issues.jsonl && git commit -m \"x\" && git push"}}')
assert_silent "chained commit-then-push is silent (simple)" "$out"

# 13. Chained: add + commit + bd dolt push + git push (multi-step) → SILENT
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git add .beads/issues.jsonl && git commit -m \"x\" && git pull --rebase=merges && bd dolt push && git push"}}')
assert_silent "chained commit-then-multi-step-then-push is silent" "$out"

# 14. Chained with semicolon separators → SILENT
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git add .beads/ ; git commit -m \"x\" ; git push"}}')
assert_silent "chained commit-then-push with semicolons is silent" "$out"

# 15. Push BEFORE commit in the chain (commit doesn't precede push) → WARN
out=$(run_hook "$DIRTY" '{"tool_name":"Bash","tool_input":{"command":"git push && git commit -m \"x\""}}')
assert_warns "push-then-commit (commit AFTER push) still warns" "$out"

# 16. Cleanup
rm -rf "$DIRTY" "$CLEAN" "$NOBEADS"

echo "---"
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
