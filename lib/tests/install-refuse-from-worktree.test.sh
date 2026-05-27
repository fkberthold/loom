#!/usr/bin/env bash
# Fixture tests for install.sh's refuse-from-worktree guard (loom-cuk).
#
# Failure mode the guard mitigates:
#   install.sh:17 resolves LOOM_ROOT via BASH_SOURCE. When invoked from
#   a linked worktree path (e.g. .claude/worktrees/agent-<id>/install.sh),
#   every `ln -s "$LOOM_ROOT/..."` bakes the worktree path as the symlink
#   target. After the worktree is cleaned up post-merge, all 95-ish
#   ~/.claude/{hooks,agents,commands,lib,scripts}/ symlinks dangle at
#   once. Observed 2026-05-26 (95 dangling) after the loom-yjo worktree
#   was deleted.
#
# Fix shape (loom-cuk M4):
#   install.sh detects whether $LOOM_ROOT lives in the main worktree
#   (TOPLEVEL == dirname(git-common-dir)) vs a linked worktree. Refuses
#   from a linked worktree with a clear error pointing the user at the
#   main checkout. Bypass via LOOM_INSTALL_FROM_WORKTREE=1 for the rare
#   case where intentional install-from-worktree is wanted.
#
# Companion: scripts/loom-doctor (M5) reports already-dangling
# ~/.claude/ symlinks. Tested in lib/tests/loom-doctor.test.sh.
#
# Run:  bash lib/tests/install-refuse-from-worktree.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$LOOM_ROOT/install.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a fixture: a "main" repo with loom's install.sh + the files it
# sanity-checks (the require list at install.sh:35), plus a linked
# worktree of that repo.
#   echoes "main_dir worktree_dir"
mk_fake_loom_main_plus_worktree() {
  local root; root=$(mktemp -d)
  local main="$root/main"
  local wt="$root/wt"
  mkdir -p "$main"

  (cd "$main" && git init -q && git config user.email t@t && git config user.name t)

  # Copy install.sh from the real loom into the fake repo so each
  # fixture exercises the version under test.
  cp "$INSTALL" "$main/install.sh"
  chmod +x "$main/install.sh"

  # Stub the sanity-check files the loom install.sh requires (line 35).
  mkdir -p "$main/skills/bugfix-a-bead" "$main/hooks"
  echo "stub" > "$main/skills/bugfix-a-bead/SKILL.md"
  echo "stub" > "$main/hooks/bd-claim-research.sh"
  echo '{}' > "$main/settings.snippet.json"

  (cd "$main" && git add . && git commit -q -m "seed" 2>/dev/null)

  # Create a linked worktree.
  (cd "$main" && git worktree add -q "$wt" -b test-worker 2>&1 >/dev/null)

  printf '%s\t%s\n' "$main" "$wt"
}

# -------------------------------------------------------------------
# 1. RED: invocation from a linked worktree → refuse with non-zero exit
# -------------------------------------------------------------------

echo "==> 1. Refuse when invoked from a linked worktree"

FX=$(mk_fake_loom_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
TMPHOME=$(mktemp -d)

out=$(cd "$WT" && CLAUDE_HOME="$TMPHOME" bash "$WT/install.sh" --check 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "install.sh from worktree exits non-zero (got rc=$rc)"
else
  fail "install.sh from worktree exited 0 — should refuse" "$out"
fi

if echo "$out" | grep -qE "worktree|main checkout|main working tree"; then
  pass "error message mentions worktree / main checkout"
else
  fail "error message lacks worktree/main-checkout guidance" "$out"
fi

# No symlinks should have been baked into TMPHOME (--check is dry-run,
# so this is a belt-and-suspenders check; the prod path is non-dry).
baked=$(find "$TMPHOME" -type l 2>/dev/null | wc -l | tr -d ' ')
if [ "$baked" = "0" ]; then
  pass "no symlinks created when refusing (--check is dry-run, but verify path-of-no-mutation)"
else
  fail "expected 0 symlinks in TMPHOME, found $baked"
fi

rm -rf "$(dirname "$MAIN")" "$TMPHOME"

# -------------------------------------------------------------------
# 2. From the main checkout: install.sh runs normally.
# -------------------------------------------------------------------

echo "==> 2. Main checkout: install.sh proceeds (no refuse)"

FX=$(mk_fake_loom_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
TMPHOME=$(mktemp -d)

# Use --check so we don't actually link anything but do execute the
# guard path. A zero exit + presence of "loom root:" log line proves
# the guard let it through.
out=$(cd "$MAIN" && CLAUDE_HOME="$TMPHOME" bash "$MAIN/install.sh" --check 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "install.sh from main checkout: exit 0"
else
  fail "install.sh from main checkout: unexpected non-zero rc=$rc" "$out"
fi

if echo "$out" | grep -qE "^\[loom-install\] loom root:"; then
  pass "main checkout: install.sh log line printed (proceeded past guard)"
else
  fail "main checkout: no loom-install log — guard wrongly refused?" "$out"
fi

rm -rf "$(dirname "$MAIN")" "$TMPHOME"

# -------------------------------------------------------------------
# 3. LOOM_INSTALL_FROM_WORKTREE=1 bypasses the refusal.
# -------------------------------------------------------------------

echo "==> 3. LOOM_INSTALL_FROM_WORKTREE=1 bypass works"

FX=$(mk_fake_loom_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
TMPHOME=$(mktemp -d)

out=$(cd "$WT" && CLAUDE_HOME="$TMPHOME" LOOM_INSTALL_FROM_WORKTREE=1 \
  bash "$WT/install.sh" --check 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "bypass env var: install.sh from worktree exits 0"
else
  fail "bypass env var did not bypass refusal (rc=$rc)" "$out"
fi

rm -rf "$(dirname "$MAIN")" "$TMPHOME"

# -------------------------------------------------------------------
# 4. Refusal error names the main checkout path the user should cd to.
# -------------------------------------------------------------------

echo "==> 4. Refusal error points at main checkout path"

FX=$(mk_fake_loom_main_plus_worktree)
MAIN=$(echo "$FX" | cut -f1)
WT=$(echo "$FX" | cut -f2)
TMPHOME=$(mktemp -d)

out=$(cd "$WT" && CLAUDE_HOME="$TMPHOME" bash "$WT/install.sh" --check 2>&1); rc=$?
# realpath the main, since the install.sh may resolve symlinks.
MAIN_REAL=$(realpath "$MAIN")
if echo "$out" | grep -qF "$MAIN_REAL"; then
  pass "refusal message names main checkout path"
else
  fail "refusal message does not include main path ($MAIN_REAL)" "$out"
fi

rm -rf "$(dirname "$MAIN")" "$TMPHOME"

# -------------------------------------------------------------------
# 5. Non-git path: refuse-from-worktree guard is a no-op (no git
#    context to evaluate). install.sh's downstream `set -e` plus the
#    .git/hooks/ wiring steps would still fail on a non-git path —
#    that's pre-existing behavior unrelated to loom-cuk. This test
#    asserts only that the guard itself doesn't emit a worktree
#    refusal in the non-git case, by checking the error (if any)
#    contains no "worktree" / "main checkout" wording.
# -------------------------------------------------------------------

echo "==> 5. Non-git directory: guard does not refuse (no false worktree error)"

root=$(mktemp -d)
mkdir -p "$root/skills/bugfix-a-bead" "$root/hooks"
echo "stub" > "$root/skills/bugfix-a-bead/SKILL.md"
echo "stub" > "$root/hooks/bd-claim-research.sh"
echo '{}' > "$root/settings.snippet.json"
cp "$INSTALL" "$root/install.sh"
chmod +x "$root/install.sh"
TMPHOME=$(mktemp -d)

out=$(cd "$root" && CLAUDE_HOME="$TMPHOME" bash "$root/install.sh" --check 2>&1); rc=$?
# Don't assert rc=0 (downstream .git/hooks wiring legitimately fails
# outside a git context — pre-existing, out of scope). Assert only
# that no worktree-refusal-style error leaked through.
if echo "$out" | grep -qE "install.sh must be run from the main loom checkout"; then
  fail "non-git dir: guard emitted false-positive worktree refusal" "$out"
else
  pass "non-git dir: no false worktree-refusal error"
fi

rm -rf "$root" "$TMPHOME"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
