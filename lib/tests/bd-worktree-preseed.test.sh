#!/usr/bin/env bash
# Fixture tests for hooks/bd-worktree-preseed.sh.
#
# Covers loom-x4m (+ superseded sibling loom-14w):
#   Fresh git worktree has an empty bd embedded-dolt DB. Agent runs
#   `bd update --claim`, bd writes one-issue state to dolt + auto-
#   exports to .beads/issues.jsonl, overwriting the worktree's full
#   copy. On merge to main, all other issues are LOST.
#
# Fix shape (three layers):
#   1. Hook detects worktree-ness + first bd write → pre-seeds the
#      worktree's dolt from its own .beads/issues.jsonl (bd import).
#   2. Hook sets `bd config export.git-add false` in the worktree so
#      bd never auto-stages issues.jsonl during worker commits.
#   3. Hook adds .beads/issues.jsonl to <worktree>/.git/info/exclude
#      as belt-and-suspenders defense.
#
# Memoized via .beads/.loom-preseeded sentinel — fires once per
# worktree.
#
# Tests use a stub bd binary (BD_BIN env var) and a fixture git
# worktree built with `git worktree add`.
#
# Run:  bash lib/tests/bd-worktree-preseed.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-worktree-preseed.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Run the hook in a controlled env.
#   $1 = cwd
#   $2 = command string (the bd invocation we're "about to run")
#   $3 = optional BD_BIN path (default: $NULL_BD)
run_hook() {
  local cwd="$1" cmd="$2"
  local bdb="${3:-$NULL_BD}"
  local payload
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  (cd "$cwd" && BD_BIN="$bdb" bash "$HOOK" <<<"$payload" 2>&1)
}

# Stub bd that records every invocation to a log file under $1.
mk_bd_stub() {
  local logdir="$1"
  local f; f=$(mktemp)
  cat > "$f" <<EOF
#!/usr/bin/env bash
echo "BDCALL: \$*" >> "$logdir/bd-calls.log"
# Honor 'bd import' as if it really populated the dolt DB by writing
# a marker file. The sed in each test substitutes 'preseeded-flag-target'
# with the actual worktree dolt path (absolute), so this writes to the
# real worktree's .beads/embeddeddolt/ — exposing it to the hook's
# dolt-emptiness check (loom-8vc).
if [ "\$1" = "import" ]; then
  mkdir -p "preseeded-flag-target"
  echo "imported" > "preseeded-flag-target/imported.flag"
fi
# Honor 'bd config set export.git-add false' similarly.
if [ "\$1" = "config" ] && [ "\$2" = "set" ] && [ "\$3" = "export.git-add" ]; then
  echo "\$4" > "$logdir/export.git-add"
fi
exit 0
EOF
  chmod +x "$f"
  echo "$f"
}

# Build a fixture: a "main" repo with .beads/issues.jsonl populated,
# plus a git worktree of that repo.
#   echoes "main_dir worktree_dir bd_log_dir"
mk_main_plus_worktree() {
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt="$root/wt"
  local bdlog="$root/bdlog"
  mkdir -p "$main/.beads/embeddeddolt" "$bdlog"

  # Initialize main as a real git repo (we need real git-worktree).
  (cd "$main" && git init -q && git config user.email t@t && git config user.name t)
  cat > "$main/.beads/issues.jsonl" <<'JSONL'
{"id":"loom-aaa","title":"Existing issue 1"}
{"id":"loom-bbb","title":"Existing issue 2"}
{"id":"loom-ccc","title":"Existing issue 3"}
JSONL
  (cd "$main" && git add . && git commit -q -m "seed")

  # Create the worktree.
  (cd "$main" && git worktree add -q "$wt" -b test-worker 2>&1 >/dev/null)

  # Empty out the worktree's dolt (simulate the bug: worktree git-add
  # copies the dir entry but the dolt blob is local-not-checked-in).
  # In real life, embeddeddolt/ in worktree just stays empty after
  # `git worktree add` because the dolt files aren't tracked.
  rm -rf "$wt/.beads/embeddeddolt"
  mkdir -p "$wt/.beads/embeddeddolt"

  printf '%s\t%s\t%s\n' "$main" "$wt" "$bdlog"
}

NULL_BD=$(mktemp)
cat > "$NULL_BD" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$NULL_BD"

# -------------------------------------------------------------------
# 1. Non-worktree path (main repo): hook is a no-op.
# -------------------------------------------------------------------

echo "==> 1. Non-worktree (main repo): no-op"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)

BD=$(mk_bd_stub "$BDLOG")
# Tell stub where the worktree's preseed flag lives.
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

out=$(run_hook "$MAIN" "bd update loom-aaa --claim" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$BDLOG/bd-calls.log" ]; then
  pass "main repo: hook exit 0 + no bd call (no pre-seed needed)"
else
  fail "main repo: expected no bd call, got rc=$rc and bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 2. Worktree + empty dolt + first bd write: pre-seed runs.
# -------------------------------------------------------------------

echo "==> 2. Worktree + empty dolt + write command: pre-seed runs"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

out=$(run_hook "$WT" "bd update loom-aaa --claim" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && grep -q "BDCALL: import" "$BDLOG/bd-calls.log" 2>/dev/null; then
  pass "worktree + write: pre-seed ran (bd import called)"
else
  fail "worktree + write: pre-seed missing. rc=$rc. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi

# Sentinel must exist after first run.
if [ -f "$WT/.beads/.loom-preseeded" ]; then
  pass "sentinel file created after pre-seed"
else
  fail "sentinel file missing"
fi

# Re-run hook: should be no-op (sentinel present).
> "$BDLOG/bd-calls.log"
out=$(run_hook "$WT" "bd update loom-bbb --claim" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$BDLOG/bd-calls.log" ]; then
  pass "re-run with sentinel present: no-op (idempotent)"
else
  fail "re-run not idempotent. rc=$rc. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 2b. Sentinel present + dolt EMPTY (rebase wipe) → re-preseed runs.
#     loom-8vc: closes the sentinel-survives-but-dolt-doesn't gap.
# -------------------------------------------------------------------

echo "==> 2b. Sentinel present + empty dolt → re-preseed (loom-8vc)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

# Simulate post-rebase state: sentinel survived, dolt got wiped.
mkdir -p "$WT/.beads"
touch "$WT/.beads/.loom-preseeded"
rm -rf "$WT/.beads/embeddeddolt"
mkdir -p "$WT/.beads/embeddeddolt"   # empty dir, no files inside

out=$(run_hook "$WT" "bd update loom-aaa --claim" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && grep -q "BDCALL: import" "$BDLOG/bd-calls.log" 2>/dev/null; then
  pass "sentinel + empty dolt: re-preseed runs (rebase wipe recovery)"
else
  fail "re-preseed missing on dolt-empty path. rc=$rc. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# Sentinel present + dolt has files → still no-op (existing behavior).
echo "==> 2c. Sentinel present + populated dolt → no-op (existing behavior preserved)"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

# Simulate already-preseeded state: sentinel + populated dolt.
mkdir -p "$WT/.beads/embeddeddolt"
touch "$WT/.beads/.loom-preseeded"
touch "$WT/.beads/embeddeddolt/some-dolt-file"  # fake content

out=$(run_hook "$WT" "bd update loom-bbb --claim" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$BDLOG/bd-calls.log" ]; then
  pass "sentinel + populated dolt: still no-op"
else
  fail "unexpected re-preseed on populated dolt. rc=$rc. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 3. bd config export.git-add false applied during pre-seed.
# -------------------------------------------------------------------

echo "==> 3. bd config export.git-add false applied"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

out=$(run_hook "$WT" "bd update loom-aaa --claim" "$BD"); rc=$?
if [ -f "$BDLOG/export.git-add" ] && [ "$(cat $BDLOG/export.git-add)" = "false" ]; then
  pass "bd config set export.git-add false invoked"
else
  fail "export.git-add false not invoked. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 4. .git/info/exclude gets .beads/issues.jsonl entry.
# -------------------------------------------------------------------

echo "==> 4. .git/info/exclude protected"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

out=$(run_hook "$WT" "bd update loom-aaa --claim" "$BD"); rc=$?
# For a linked worktree, .git is a file pointing at the main's
# worktrees/<name>/ subdir. info/exclude lives in that subdir.
WT_GIT_DIR=$(cd "$WT" && git rev-parse --git-dir)
WT_EXCLUDE_PATH="$WT_GIT_DIR/info/exclude"
if [ -f "$WT_EXCLUDE_PATH" ] && grep -qF ".beads/issues.jsonl" "$WT_EXCLUDE_PATH"; then
  pass ".git/info/exclude has .beads/issues.jsonl"
else
  fail ".git/info/exclude missing entry. path=$WT_EXCLUDE_PATH content=$(cat $WT_EXCLUDE_PATH 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 5. Non-bd commands: hook is a no-op.
# -------------------------------------------------------------------

echo "==> 5. Non-bd commands: no-op"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

out=$(run_hook "$WT" "ls -la" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$BDLOG/bd-calls.log" ]; then
  pass "non-bd command (ls): no pre-seed triggered"
else
  fail "non-bd command triggered pre-seed. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 6. Read-only bd commands skip pre-seed (don't waste cycles).
# -------------------------------------------------------------------

echo "==> 6. Read-only bd commands skip pre-seed"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

out=$(run_hook "$WT" "bd show loom-aaa" "$BD"); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$BDLOG/bd-calls.log" ]; then
  pass "bd show (read-only): no pre-seed triggered"
else
  fail "bd show triggered pre-seed. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 7. Non-Bash tools: hook is a no-op.
# -------------------------------------------------------------------

echo "==> 7. Non-Bash tools: no-op"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

payload='{"tool_name":"Edit","tool_input":{"command":"bd update loom-aaa --claim"}}'
out=$(cd "$WT" && BD_BIN="$BD" bash "$HOOK" <<<"$payload" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$BDLOG/bd-calls.log" ]; then
  pass "non-Bash tool: no pre-seed triggered"
else
  fail "non-Bash tool triggered pre-seed. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# 8. Re-entry guard: hook's own bd import call doesn't re-fire hook.
# -------------------------------------------------------------------

echo "==> 8. Re-entry guard"

FX=$(mk_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
BDLOG=$(echo "$FX" | cut -f3)
BD=$(mk_bd_stub "$BDLOG")
sed -i "s|preseeded-flag-target|$WT/.beads/embeddeddolt|g" "$BD"

# When the hook runs `bd import` internally, that's not a recursive
# hook fire (hooks fire on the agent's Bash tool, not on subprocess
# calls from other hooks). But verify hook honors LOOM_BD_WORKTREE_PRESEED_SKIP=1
# so other code paths can disable it.
out=$(cd "$WT" && BD_BIN="$BD" LOOM_BD_WORKTREE_PRESEED_SKIP=1 bash "$HOOK" \
  <<<'{"tool_name":"Bash","tool_input":{"command":"bd update loom-aaa --claim"}}' 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$BDLOG/bd-calls.log" ]; then
  pass "LOOM_BD_WORKTREE_PRESEED_SKIP=1 disables pre-seed"
else
  fail "skip env var ignored. bd log: $(cat $BDLOG/bd-calls.log 2>/dev/null)" "$out"
fi
rm -rf "$(dirname "$MAIN")"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
