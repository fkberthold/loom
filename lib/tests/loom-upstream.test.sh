#!/usr/bin/env bash
# Fixture tests for lib/loom-upstream.sh.
#
# Covers loom-k2g.2: the central-cache helper consumed by the
# upstream-a-bead recipe at M2. Manages `~/.loom/upstream/<owner>/
# <repo>/` shared across loom-managed projects.
#
# Stubs `gh` via PATH-prepended fake binary (mirrors the `bd` stub
# pattern in bd-post-rewrite.test.sh). Each test isolates LOOM_HOME
# to a tmpdir so the real ~/.loom is never touched.
#
# Run:  bash lib/tests/loom-upstream.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-upstream.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a PATH-shadowing fake `gh` from a heredoc script. Returns the
# directory to prepend to PATH on stdout.
mk_gh_stub() {
  local script="$1"
  local d
  d=$(mktemp -d)
  cat > "$d/gh" <<EOF
#!/usr/bin/env bash
$script
EOF
  chmod +x "$d/gh"
  echo "$d"
}

# Make a fresh LOOM_HOME tmpdir; returns path on stdout.
mk_loom_home() {
  mktemp -d
}

# -------------------------------------------------------------------
# 1. ensure_clone: missing dir → calls `gh repo clone` and creates
#    the cache entry under $LOOM_HOME/upstream/<owner>/<repo>/.
# -------------------------------------------------------------------

echo "==> 1. ensure_clone: missing dir auto-clones"

LOOM_HOME=$(mk_loom_home)
GH_DIR=$(mk_gh_stub '
# Record invocation for assertion.
echo "$@" >> "'"$LOOM_HOME"'/gh-calls.log"
if [ "$1" = "repo" ] && [ "$2" = "clone" ]; then
  # Simulate clone by creating the directory.
  mkdir -p "$4"
  echo "stub-cloned $3 to $4"
  exit 0
fi
exit 1
')

out=$(LOOM_HOME="$LOOM_HOME" PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; ensure_clone obra superpowers" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "ensure_clone exit 0 when dir missing"
else
  fail "ensure_clone exit non-zero (rc=$rc)" "$out"
fi

if [ -d "$LOOM_HOME/upstream/obra/superpowers" ]; then
  pass "clone dir created under \$LOOM_HOME/upstream/obra/superpowers"
else
  fail "clone dir NOT created" "out: $out"
fi

if grep -q "repo clone obra/superpowers" "$LOOM_HOME/gh-calls.log" 2>/dev/null; then
  pass "gh repo clone invoked with owner/repo"
else
  fail "gh repo clone not invoked correctly" "log: $(cat "$LOOM_HOME/gh-calls.log" 2>/dev/null)"
fi

rm -rf "$LOOM_HOME" "$GH_DIR"

# -------------------------------------------------------------------
# 2. ensure_clone: dir already present → no-op, no gh call.
# -------------------------------------------------------------------

echo "==> 2. ensure_clone: present dir is no-op"

LOOM_HOME=$(mk_loom_home)
mkdir -p "$LOOM_HOME/upstream/obra/superpowers/.git"
GH_DIR=$(mk_gh_stub '
echo "$@" >> "'"$LOOM_HOME"'/gh-calls.log"
exit 0
')

out=$(LOOM_HOME="$LOOM_HOME" PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; ensure_clone obra superpowers" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then pass "no-op exit 0"; else fail "no-op exit non-zero (rc=$rc)" "$out"; fi
if [ ! -f "$LOOM_HOME/gh-calls.log" ]; then
  pass "no gh calls made for present clone"
else
  fail "gh was invoked despite present clone" "log: $(cat "$LOOM_HOME/gh-calls.log")"
fi

rm -rf "$LOOM_HOME" "$GH_DIR"

# -------------------------------------------------------------------
# 3. gh_auth_check: gh auth status non-zero → returns 1.
# -------------------------------------------------------------------

echo "==> 3. gh_auth_check: unauthenticated returns 1"

GH_DIR=$(mk_gh_stub '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "You are not logged into any GitHub hosts." >&2
  exit 1
fi
exit 0
')

out=$(PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; gh_auth_check" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "gh_auth_check returns non-zero when unauthed"
else
  fail "gh_auth_check returned 0 despite unauthed gh"
fi

if echo "$out" | grep -qi "auth"; then
  pass "gh_auth_check emits auth-related error message"
else
  fail "gh_auth_check error message missing auth context" "got: $out"
fi

rm -rf "$GH_DIR"

# -------------------------------------------------------------------
# 4. gh_auth_check: gh auth status zero → returns 0 silently.
# -------------------------------------------------------------------

echo "==> 4. gh_auth_check: authenticated returns 0"

GH_DIR=$(mk_gh_stub '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Logged in to github.com as testuser"
  exit 0
fi
exit 1
')

out=$(PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; gh_auth_check" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "gh_auth_check returns 0 when authed"
else
  fail "gh_auth_check returned non-zero despite authed gh (rc=$rc)" "$out"
fi

rm -rf "$GH_DIR"

# -------------------------------------------------------------------
# 5. canonical_owner_check: matched owner → returns 0 silently.
# -------------------------------------------------------------------

echo "==> 5. canonical_owner_check: matched owner is no-op"

GH_DIR=$(mk_gh_stub '
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  # gh repo view obra/superpowers --json owner
  echo "{\"owner\":{\"login\":\"obra\"}}"
  exit 0
fi
exit 1
')

out=$(PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; canonical_owner_check obra superpowers" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "canonical_owner_check returns 0 on match"
else
  fail "canonical_owner_check returned non-zero on match (rc=$rc)" "$out"
fi

rm -rf "$GH_DIR"

# -------------------------------------------------------------------
# 6. canonical_owner_check: mismatched owner (precedent: gastownhall
#    vs steveyegge per loom-45i) → warns to stderr and prints
#    canonical owner to stdout for caller to consume.
# -------------------------------------------------------------------

echo "==> 6. canonical_owner_check: mismatched owner warns + switches"

GH_DIR=$(mk_gh_stub '
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  echo "{\"owner\":{\"login\":\"steveyegge\"}}"
  exit 0
fi
exit 1
')

# Capture stdout + stderr separately.
tmpout=$(mktemp); tmperr=$(mktemp)
PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; canonical_owner_check gastownhall beads" >"$tmpout" 2>"$tmperr"; rc=$?
stdout_content=$(cat "$tmpout")
stderr_content=$(cat "$tmperr")
rm -f "$tmpout" "$tmperr"

if [ "$rc" -eq 0 ]; then
  pass "canonical_owner_check exits 0 even on mismatch (warning, not fatal)"
else
  fail "canonical_owner_check exit non-zero on mismatch (rc=$rc)" "stderr: $stderr_content"
fi

if echo "$stderr_content" | grep -qi "steveyegge"; then
  pass "warning names the canonical owner (steveyegge)"
else
  fail "warning missing canonical owner" "stderr: $stderr_content"
fi

if [ "$stdout_content" = "steveyegge" ]; then
  pass "stdout prints canonical owner for caller consumption"
else
  fail "stdout did not print canonical owner" "got: '$stdout_content'"
fi

rm -rf "$GH_DIR"

# -------------------------------------------------------------------
# 7. fork_or_create: user's fork already exists → no-op (no gh repo fork call).
# -------------------------------------------------------------------

echo "==> 7. fork_or_create: existing fork is no-op"

GH_DIR=$(mk_gh_stub '
LOG="$HOME/gh-calls.log"
echo "$@" >> "$LOG"
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  echo "{\"login\":\"frank\"}"
  exit 0
fi
if [ "$1" = "repo" ] && [ "$2" = "view" ] && [ "$3" = "frank/superpowers" ]; then
  # Fork exists.
  echo "{\"name\":\"superpowers\"}"
  exit 0
fi
exit 1
')

HOME_DIR=$(mktemp -d)
out=$(HOME="$HOME_DIR" PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; fork_or_create obra superpowers" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then pass "fork_or_create exit 0 when fork exists"; else fail "fork_or_create non-zero (rc=$rc)" "$out"; fi

if ! grep -q "repo fork" "$HOME_DIR/gh-calls.log" 2>/dev/null; then
  pass "no 'gh repo fork' call when fork already exists"
else
  fail "fork_or_create unnecessarily invoked gh repo fork" "log: $(cat "$HOME_DIR/gh-calls.log")"
fi

rm -rf "$GH_DIR" "$HOME_DIR"

# -------------------------------------------------------------------
# 8. fork_or_create: fork missing → invokes `gh repo fork --remote=false`.
# -------------------------------------------------------------------

echo "==> 8. fork_or_create: missing fork invokes gh repo fork"

GH_DIR=$(mk_gh_stub '
LOG="$HOME/gh-calls.log"
echo "$@" >> "$LOG"
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  echo "{\"login\":\"frank\"}"
  exit 0
fi
if [ "$1" = "repo" ] && [ "$2" = "view" ] && [ "$3" = "frank/superpowers" ]; then
  # Fork missing.
  echo "Could not resolve to a Repository" >&2
  exit 1
fi
if [ "$1" = "repo" ] && [ "$2" = "fork" ]; then
  echo "fork ok"
  exit 0
fi
exit 1
')

HOME_DIR=$(mktemp -d)
out=$(HOME="$HOME_DIR" PATH="$GH_DIR:$PATH" bash -c "source '$LIB'; fork_or_create obra superpowers" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then pass "fork_or_create exit 0 after creating fork"; else fail "fork_or_create non-zero (rc=$rc)" "$out"; fi

if grep -qE "repo fork obra/superpowers.*--remote=false|repo fork.*--remote=false.*obra/superpowers" "$HOME_DIR/gh-calls.log" 2>/dev/null; then
  pass "invoked 'gh repo fork obra/superpowers --remote=false'"
else
  fail "fork call malformed or missing" "log: $(cat "$HOME_DIR/gh-calls.log" 2>/dev/null)"
fi

rm -rf "$GH_DIR" "$HOME_DIR"

# -------------------------------------------------------------------
# 9. refuse_if_stale: uncommitted changes → returns non-zero.
# -------------------------------------------------------------------

echo "==> 9. refuse_if_stale: uncommitted changes refuses"

WORK=$(mktemp -d)
REPO="$WORK/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t)
echo seed > "$REPO/seed.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m seed)
# Introduce an uncommitted change.
echo wip > "$REPO/wip.txt"

out=$(bash -c "source '$LIB'; refuse_if_stale '$REPO'" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "refuse_if_stale returns non-zero on uncommitted changes"
else
  fail "refuse_if_stale returned 0 despite uncommitted changes"
fi

if echo "$out" | grep -qiE "uncommitted|unpushed|stale|dirty"; then
  pass "refusal message names the staleness condition"
else
  fail "refusal message lacks staleness keyword" "got: $out"
fi

rm -rf "$WORK"

# -------------------------------------------------------------------
# 10. refuse_if_stale: clean tree, no unpushed branches → returns 0.
# -------------------------------------------------------------------

echo "==> 10. refuse_if_stale: clean tree returns 0"

WORK=$(mktemp -d)
REPO="$WORK/repo"
UPSTREAM="$WORK/upstream"
mkdir -p "$REPO" "$UPSTREAM"
(cd "$UPSTREAM" && git init -q --bare -b main)
(cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t)
echo seed > "$REPO/seed.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m seed)
(cd "$REPO" && git remote add origin "$UPSTREAM" && git push -q -u origin main)

out=$(bash -c "source '$LIB'; refuse_if_stale '$REPO'" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "refuse_if_stale returns 0 on clean + pushed tree"
else
  fail "refuse_if_stale returned non-zero on clean tree (rc=$rc)" "$out"
fi

rm -rf "$WORK"

# -------------------------------------------------------------------
# 11. refuse_if_stale: clean tree but local-only branch with unpushed
#     commits → returns non-zero.
# -------------------------------------------------------------------

echo "==> 11. refuse_if_stale: unpushed branch refuses"

WORK=$(mktemp -d)
REPO="$WORK/repo"
UPSTREAM="$WORK/upstream"
mkdir -p "$REPO" "$UPSTREAM"
(cd "$UPSTREAM" && git init -q --bare -b main)
(cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t)
echo seed > "$REPO/seed.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m seed)
(cd "$REPO" && git remote add origin "$UPSTREAM" && git push -q -u origin main)
# Make a local branch with a commit not pushed anywhere.
(cd "$REPO" && git checkout -q -b feature)
echo wip > "$REPO/feature.txt"
(cd "$REPO" && git add -A && git -c core.hooksPath=/dev/null commit -q -m feat)
(cd "$REPO" && git checkout -q main)

out=$(bash -c "source '$LIB'; refuse_if_stale '$REPO'" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "refuse_if_stale refuses when feature branch has unpushed commits"
else
  fail "refuse_if_stale returned 0 despite unpushed branch commits" "$out"
fi

rm -rf "$WORK"

# -------------------------------------------------------------------
# 12. Library is shell-source-safe: sourcing alone has no side
#     effects (no functions execute, no files touched).
# -------------------------------------------------------------------

echo "==> 12. Sourcing the library is side-effect-free"

PROBE=$(mktemp -d)
out=$(cd "$PROBE" && bash -c "source '$LIB'" 2>&1); rc=$?
extras=$(ls -A "$PROBE")

if [ "$rc" -eq 0 ] && [ -z "$extras" ]; then
  pass "source-only execution is clean (no files, exit 0)"
else
  fail "sourcing the library had side effects (rc=$rc extras=$extras)" "$out"
fi

rm -rf "$PROBE"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
