#!/usr/bin/env bash
# Fixture tests for hooks/post-rewrite.sh.
#
# Closes loom-yjo: git rebase (especially `--rebase=merges`) can land
# stale .beads/issues.jsonl in HEAD even though dolt (authoritative)
# has the correct state. The loom-4um merge driver covers `git merge`
# but not the rebase-replay path. This hook re-exports from dolt
# after any history rewrite (rebase, commit --amend) and commits the
# delta if it diverges from HEAD — so jsonl-in-HEAD always matches
# dolt.
#
# Composes orthogonally with bd-merge-driver (loom-4um) and bd-
# worktree-preseed (loom-x4m). Dolt is the source of truth across
# all three.
#
# Run:  bash lib/tests/bd-post-rewrite.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/post-rewrite.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a stub `bd` that emits a canned canonical export. Same shape
# as bd-merge-driver.test.sh's mk_bd_stub.
mk_bd_stub() {
  local canonical="$1"
  local f content
  f=$(mktemp)
  content="${f}.canonical"
  printf '%s' "$canonical" > "$content"
  cat > "$f" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "export" ]; then
  cat "$content"
  exit 0
fi
exit 1
EOF
  chmod +x "$f"
  echo "$f"
}

# Build a one-commit fixture repo with .beads/issues.jsonl seeded to
# STALE_JSONL and PATH-shadowing bd pointing at STUB_BD. Returns the
# repo path on stdout.
mk_fixture_repo() {
  local stale_jsonl="$1"
  local stub_bd="$2"
  local work fixture
  work=$(mktemp -d)
  fixture="$work/repo"
  mkdir -p "$fixture/.beads"
  printf '%s' "$stale_jsonl" > "$fixture/.beads/issues.jsonl"
  (cd "$fixture" && git init -q -b main && git config user.email t@t && git config user.name t)
  (cd "$fixture" && git add -A && git -c core.hooksPath=/dev/null commit -q -m "seed")
  # Stash stub bd path into the fixture so each test invocation can
  # PATH-shadow consistently.
  echo "$stub_bd" > "$fixture/.bd-stub-path"
  echo "$fixture"
}

# Invoke the hook from inside FIXTURE with BD_BIN pointing at the
# stub. Captures stdout+stderr and rc.
run_hook() {
  local fixture="$1"; shift
  local stub_bd
  stub_bd=$(cat "$fixture/.bd-stub-path")
  (cd "$fixture" && BD_BIN="$stub_bd" "$@" bash "$HOOK" rebase 2>&1)
}

# -------------------------------------------------------------------
# 1. Happy path: dolt diverges from jsonl → hook re-exports and
#    creates a follow-up commit. The canonical bd-export content
#    must appear in HEAD's tree.
# -------------------------------------------------------------------

echo "==> 1. Happy path: dolt differs, hook commits the re-export"

STALE='{"id":"loom-aaa","status":"in_progress"}
{"id":"loom-bbb","status":"in_progress"}
'
CANONICAL='{"id":"loom-aaa","status":"closed"}
{"id":"loom-bbb","status":"closed"}
'
STUB=$(mk_bd_stub "$CANONICAL")
REPO=$(mk_fixture_repo "$STALE" "$STUB")

orig_head=$(cd "$REPO" && git rev-parse HEAD)
out=$(run_hook "$REPO"); rc=$?

new_head=$(cd "$REPO" && git rev-parse HEAD)
# `git show` and command substitution both strip trailing newlines —
# normalize the expected value the same way before comparing.
head_content=$(cd "$REPO" && git show HEAD:.beads/issues.jsonl)
canonical_norm=$(printf '%s' "$CANONICAL")

if [ "$rc" -eq 0 ]; then
  pass "hook exits 0"
else
  fail "hook exited non-zero (rc=$rc)" "$out"
fi

if [ "$orig_head" != "$new_head" ]; then
  pass "hook created a new commit"
else
  fail "hook did not create a follow-up commit"
fi

if [ "$head_content" = "$canonical_norm" ]; then
  pass "HEAD's .beads/issues.jsonl matches canonical bd export"
else
  fail "HEAD content differs from canonical" "got: $head_content"
fi

# Commit message convention: should reference loom-yjo and "post-rewrite"
commit_msg=$(cd "$REPO" && git log -1 --format=%s)
if echo "$commit_msg" | grep -qiE "post-rewrite|loom-yjo"; then
  pass "commit message references post-rewrite / loom-yjo"
else
  fail "commit message lacks expected marker" "got: $commit_msg"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 2. No-op when jsonl already matches dolt — no spurious commit.
# -------------------------------------------------------------------

echo "==> 2. No-op when jsonl already matches dolt"

CANON='{"id":"loom-aaa","status":"closed"}
'
STUB=$(mk_bd_stub "$CANON")
REPO=$(mk_fixture_repo "$CANON" "$STUB")
orig_head=$(cd "$REPO" && git rev-parse HEAD)

out=$(run_hook "$REPO"); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)

if [ "$rc" -eq 0 ]; then
  pass "no-op exits 0"
else
  fail "no-op exited non-zero (rc=$rc)" "$out"
fi

if [ "$orig_head" = "$new_head" ]; then
  pass "no-op: HEAD unchanged"
else
  fail "no-op: hook created an unwanted commit"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 3. LOOM_BD_POST_REWRITE_SKIP=1 disables the hook entirely.
# -------------------------------------------------------------------

echo "==> 3. LOOM_BD_POST_REWRITE_SKIP=1 disables hook"

STUB=$(mk_bd_stub 'should-not-be-written')
REPO=$(mk_fixture_repo '{"id":"loom-aaa","status":"in_progress"}' "$STUB")
orig_head=$(cd "$REPO" && git rev-parse HEAD)

out=$(LOOM_BD_POST_REWRITE_SKIP=1 run_hook "$REPO"); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)
content=$(cd "$REPO" && cat .beads/issues.jsonl)

if [ "$rc" -eq 0 ]; then
  pass "SKIP=1 exits 0"
else
  fail "SKIP=1 non-zero (rc=$rc)" "$out"
fi
if [ "$orig_head" = "$new_head" ] && [ "$content" = '{"id":"loom-aaa","status":"in_progress"}' ]; then
  pass "SKIP=1: HEAD and working tree untouched"
else
  fail "SKIP=1: hook ran despite skip env"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 4. LOOM_BD_POST_REWRITE_NO_COMMIT=1: re-export the working tree
#    but do NOT create a commit. Useful for tests + manual recovery.
# -------------------------------------------------------------------

echo "==> 4. LOOM_BD_POST_REWRITE_NO_COMMIT=1: re-export only"

STALE='{"id":"loom-aaa","status":"in_progress"}
'
CANON='{"id":"loom-aaa","status":"closed"}
'
STUB=$(mk_bd_stub "$CANON")
REPO=$(mk_fixture_repo "$STALE" "$STUB")
orig_head=$(cd "$REPO" && git rev-parse HEAD)

out=$(LOOM_BD_POST_REWRITE_NO_COMMIT=1 run_hook "$REPO"); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)
wt_content=$(cd "$REPO" && cat .beads/issues.jsonl)
canon_norm=$(printf '%s' "$CANON")

if [ "$rc" -eq 0 ]; then pass "NO_COMMIT=1 exits 0"; else fail "NO_COMMIT=1 non-zero (rc=$rc)" "$out"; fi
if [ "$orig_head" = "$new_head" ]; then
  pass "NO_COMMIT=1: HEAD unchanged"
else
  fail "NO_COMMIT=1: hook still created a commit"
fi
# `cat` preserves trailing newlines, `$CANON` literal includes one;
# byte-equal comparison works without further normalization.
if [ "$wt_content" = "$canon_norm" ]; then
  pass "NO_COMMIT=1: working tree re-exported"
else
  fail "NO_COMMIT=1: working tree not updated" "got: $wt_content"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 5. .beads/ absent: no-op (don't break non-bd repos).
# -------------------------------------------------------------------

echo "==> 5. .beads/ absent: no-op"

WORK=$(mktemp -d)
REPO="$WORK/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t)
echo hello > "$REPO/x.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m "seed")
orig_head=$(cd "$REPO" && git rev-parse HEAD)

out=$(cd "$REPO" && bash "$HOOK" rebase 2>&1); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)

if [ "$rc" -eq 0 ] && [ "$orig_head" = "$new_head" ]; then
  pass "no .beads/: no-op"
else
  fail "no .beads/: hook misfired (rc=$rc head $orig_head→$new_head)" "$out"
fi

rm -rf "$WORK"

# -------------------------------------------------------------------
# 6. bd binary unavailable: no-op (don't break repos without bd).
# -------------------------------------------------------------------

echo "==> 6. bd binary unavailable: no-op"

REPO=$(mk_fixture_repo '{"id":"loom-aaa","status":"in_progress"}' "/nonexistent/bd")
orig_head=$(cd "$REPO" && git rev-parse HEAD)
orig_content=$(cat "$REPO/.beads/issues.jsonl")

out=$(cd "$REPO" && BD_BIN=/nonexistent/bd bash "$HOOK" rebase 2>&1); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)
new_content=$(cat "$REPO/.beads/issues.jsonl")

if [ "$rc" -eq 0 ] && [ "$orig_head" = "$new_head" ] && [ "$orig_content" = "$new_content" ]; then
  pass "no bd: no-op (rc=0, no commit, jsonl untouched)"
else
  fail "no bd: hook misfired (rc=$rc)" "$out"
fi

rm -rf "$(dirname "$REPO")"

# -------------------------------------------------------------------
# 7. Other staged changes present: no-op (don't entangle them).
# -------------------------------------------------------------------

echo "==> 7. Other staged changes present: no-op"

STALE='{"id":"loom-aaa","status":"in_progress"}
'
CANON='{"id":"loom-aaa","status":"closed"}
'
STUB=$(mk_bd_stub "$CANON")
REPO=$(mk_fixture_repo "$STALE" "$STUB")

# Stage an unrelated change.
echo "unrelated" > "$REPO/sibling.txt"
(cd "$REPO" && git add sibling.txt)
orig_head=$(cd "$REPO" && git rev-parse HEAD)

out=$(run_hook "$REPO"); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)

# Hook should exit 0 and NOT create a commit (which would entangle
# sibling.txt with the bd-state re-export).
if [ "$rc" -eq 0 ] && [ "$orig_head" = "$new_head" ]; then
  pass "staged-changes-present: no-op"
else
  fail "staged-changes-present: hook entangled changes (rc=$rc head $orig_head→$new_head)" "$out"
fi

# sibling.txt should still be staged (we didn't unstage it).
if (cd "$REPO" && git diff --cached --name-only | grep -q "^sibling.txt$"); then
  pass "staged-changes-present: sibling.txt still staged"
else
  fail "staged-changes-present: hook unstaged sibling.txt"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 8. Detached HEAD: no-op (can't safely commit on detached HEAD).
# -------------------------------------------------------------------

echo "==> 8. Detached HEAD: no-op"

STALE='{"id":"loom-aaa","status":"in_progress"}
'
CANON='{"id":"loom-aaa","status":"closed"}
'
STUB=$(mk_bd_stub "$CANON")
REPO=$(mk_fixture_repo "$STALE" "$STUB")
seed_sha=$(cd "$REPO" && git rev-parse HEAD)

# Detach HEAD.
(cd "$REPO" && git checkout -q --detach)

out=$(run_hook "$REPO"); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)

if [ "$rc" -eq 0 ] && [ "$seed_sha" = "$new_head" ]; then
  pass "detached HEAD: no-op (no spurious commit)"
else
  fail "detached HEAD: hook misfired (rc=$rc head $seed_sha→$new_head)" "$out"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 9. install.sh wires the hook in $GIT_COMMON_DIR/hooks/post-rewrite.
#    Mirrors the loom-kbo pre-push wiring pattern.
# -------------------------------------------------------------------

echo "==> 9. install.sh wires hooks/post-rewrite.sh"

INSTALL="$LOOM_ROOT/install.sh"

if grep -qE "hooks/post-rewrite\.sh" "$INSTALL"; then
  pass "install.sh references hooks/post-rewrite.sh"
else
  fail "install.sh missing hooks/post-rewrite.sh reference"
fi

# Should symlink into the common git dir (mirrors pre-push pattern).
if grep -qE "post-rewrite" "$INSTALL" && \
   grep -qE "GIT_COMMON_DIR" "$INSTALL"; then
  pass "install.sh wires post-rewrite via GIT_COMMON_DIR"
else
  fail "install.sh post-rewrite wiring missing GIT_COMMON_DIR usage"
fi

# Should refuse to clobber existing non-symlink (parallel to pre-push).
if awk '/post-rewrite/,/^$/' "$INSTALL" | grep -qE "non-symlink|already exists"; then
  pass "install.sh refuses to clobber existing non-symlink post-rewrite"
else
  fail "install.sh missing non-symlink-clobber guard for post-rewrite"
fi

# -------------------------------------------------------------------
# 10. Hook executable bit set.
# -------------------------------------------------------------------

echo "==> 10. Hook is executable"

if [ -x "$HOOK" ]; then
  pass "hooks/post-rewrite.sh is executable"
else
  fail "hooks/post-rewrite.sh not executable (chmod +x needed)"
fi

# -------------------------------------------------------------------
# 11. CLAUDE.md no longer advertises the manual post-rebase
#     re-export workaround as a step in Session Completion.
# -------------------------------------------------------------------

echo "==> 11. CLAUDE.md workaround line removed"

CLAUDEMD="$LOOM_ROOT/CLAUDE.md"
# The old wording was 'post-rebase issues.jsonl re-export' as a
# committed-by-hand step. After loom-yjo, that's automated by the
# hook — the CLAUDE.md prose should reflect that.
if grep -qE "post-rebase issues.jsonl re-export" "$CLAUDEMD"; then
  fail "CLAUDE.md still describes the manual post-rebase re-export workaround"
else
  pass "CLAUDE.md no longer prescribes manual post-rebase re-export"
fi

# -------------------------------------------------------------------
# 12. Bug-class: `amend` invocation behaves the same as `rebase`.
#     git invokes the hook as `post-rewrite amend` after commit
#     --amend; both code paths must converge on the same dolt-wins
#     behavior, otherwise --amend could leave jsonl out of sync.
# -------------------------------------------------------------------

echo "==> 12. amend invocation re-exports same as rebase"

STALE='{"id":"loom-aaa","status":"in_progress"}
'
CANON='{"id":"loom-aaa","status":"closed"}
'
STUB=$(mk_bd_stub "$CANON")
REPO=$(mk_fixture_repo "$STALE" "$STUB")
orig_head=$(cd "$REPO" && git rev-parse HEAD)

# Direct invocation with arg=amend instead of rebase.
out=$(cd "$REPO" && BD_BIN="$STUB" bash "$HOOK" amend 2>&1); rc=$?
new_head=$(cd "$REPO" && git rev-parse HEAD)
head_content=$(cd "$REPO" && git show HEAD:.beads/issues.jsonl)
canon_norm=$(printf '%s' "$CANON")

if [ "$rc" -eq 0 ] && [ "$orig_head" != "$new_head" ] && [ "$head_content" = "$canon_norm" ]; then
  pass "amend: re-export + commit, same as rebase"
else
  fail "amend: did not converge with rebase behavior (rc=$rc head $orig_head→$new_head)" "$out"
fi

rm -rf "$(dirname "$REPO")" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# 13. End-to-end: a real `git rebase` invokes the wired hook and
#     the hook restores dolt-canonical state. This is the strongest
#     test of the loom-yjo symptom path — exercises git's actual
#     post-rewrite event delivery, not just direct invocation.
# -------------------------------------------------------------------

echo "==> 13. End-to-end: real git rebase invokes hook"

WORK=$(mktemp -d)
REPO="$WORK/repo"
mkdir -p "$REPO/.beads"

# Stale jsonl in main: aaa=in_progress. Canonical bd export (stub)
# returns aaa=closed. After we rebase a feature commit onto main, the
# hook should fire and reconcile.
printf '%s' '{"id":"loom-aaa","status":"in_progress"}' > "$REPO/.beads/issues.jsonl"
(cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t)
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m "main: seed")

# Wire the hook into .git/hooks/post-rewrite. Use a tiny shim that
# PATH-shadows bd to the stub so the hook resolves it correctly.
STUB=$(mk_bd_stub '{"id":"loom-aaa","status":"closed"}')
HOOK_TARGET="$REPO/.git/hooks/post-rewrite"
cat > "$HOOK_TARGET" <<EOF
#!/usr/bin/env bash
exec env BD_BIN="$STUB" bash "$HOOK" "\$@"
EOF
chmod +x "$HOOK_TARGET"

# Create a feature commit (touches something unrelated so rebase
# has real work to do — empty rebases don't fire post-rewrite in
# all git versions).
(cd "$REPO" && git checkout -q -b feat)
echo "x" > "$REPO/x.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m "feat: touch x")

# Advance main by one commit so feat needs a real rebase.
(cd "$REPO" && git checkout -q main)
echo "y" > "$REPO/y.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m "main: touch y")

# Rebase feat onto main. The rebase finishing fires post-rewrite.
(cd "$REPO" && git checkout -q feat)
out=$(cd "$REPO" && git rebase main 2>&1); rebase_rc=$?

# Hook should have produced an auto-commit on feat that re-exports.
head_jsonl=$(cd "$REPO" && git show HEAD:.beads/issues.jsonl)
last_msg=$(cd "$REPO" && git log -1 --format=%s)

if [ "$rebase_rc" -eq 0 ]; then
  pass "rebase completed cleanly"
else
  fail "rebase failed (rc=$rebase_rc)" "$out"
fi

if [ "$head_jsonl" = '{"id":"loom-aaa","status":"closed"}' ]; then
  pass "post-rebase HEAD content matches canonical bd export (dolt wins)"
else
  fail "post-rebase HEAD content NOT canonical" "got: $head_jsonl"
fi

if echo "$last_msg" | grep -qiE "post-rewrite|loom-yjo"; then
  pass "post-rebase top commit is the hook's auto-commit"
else
  fail "post-rebase top commit lacks hook marker" "got: $last_msg"
fi

rm -rf "$WORK" "$STUB" "$STUB.canonical"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
