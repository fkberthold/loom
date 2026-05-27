#!/usr/bin/env bash
# Fixture tests for scripts/loom-doctor (loom-cuk M5).
#
# Companion to install.sh's refuse-from-worktree guard (loom-cuk M4):
#   M4 prevents NEW dangling symlinks; M5 surfaces ones that
#   pre-existed the guard (or slipped through via the bypass env var).
#
# The doctor scans loom-owned subdirs under $CLAUDE_HOME for symlinks
# whose target path contains 'loom' AND no longer resolves. Loom-
# ownership heuristic deliberately conservative — non-loom symlinks
# from other tools aren't false-flagged.
#
# Run:  bash lib/tests/loom-doctor.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="$LOOM_ROOT/scripts/loom-doctor"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a fake ~/.claude/ with the loom-owned subdir structure.
#   echoes "claude_home_dir loom_src_dir"
mk_fake_home() {
  local root; root=$(mktemp -d)
  local home="$root/dot-claude"
  local src="$root/loom-src"
  mkdir -p "$home"/{skills,agents,commands,hooks,lib,scripts,lib/tests}
  mkdir -p "$src"/{skills,agents,commands,hooks,lib,scripts,lib/tests}
  printf '%s\t%s\n' "$home" "$src"
}

# -------------------------------------------------------------------
# 1. Clean home: doctor reports OK, exit 0.
# -------------------------------------------------------------------

echo "==> 1. Clean ~/.claude/: doctor exits 0"

FX=$(mk_fake_home)
HOME_DIR=$(echo "$FX" | cut -f1)
SRC=$(echo "$FX" | cut -f2)

# Wire a valid symlink so the doctor has something to walk past.
echo "x" > "$SRC/hooks/foo.sh"
ln -s "$SRC/hooks/foo.sh" "$HOME_DIR/hooks/foo.sh"

out=$("$DOCTOR" --claude-home "$HOME_DIR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qE "OK.*no dangling"; then
  pass "clean home: exit 0 + OK message"
else
  fail "clean home: rc=$rc, out=$out"
fi

rm -rf "$(dirname "$HOME_DIR")"

# -------------------------------------------------------------------
# 2. Seed a dangling loom symlink → doctor reports it, exit 1.
# -------------------------------------------------------------------

echo "==> 2. Dangling loom symlink: doctor reports + exit 1"

FX=$(mk_fake_home)
HOME_DIR=$(echo "$FX" | cut -f1)
SRC=$(echo "$FX" | cut -f2)

# Create a source file, link it, then delete the source so the
# symlink dangles.
echo "x" > "$SRC/hooks/foo.sh"
ln -s "$SRC/hooks/foo.sh" "$HOME_DIR/hooks/foo.sh"
rm "$SRC/hooks/foo.sh"

# The target path contains 'loom' in $SRC name (mk_fake_home uses
# 'loom-src'), so the loom-ownership heuristic matches.
out=$("$DOCTOR" --claude-home "$HOME_DIR" 2>&1); rc=$?
if [ "$rc" -eq 1 ]; then
  pass "dangling: exit 1"
else
  fail "dangling: expected exit 1, got $rc" "$out"
fi
if echo "$out" | grep -qE "FOUND 1 dangling"; then
  pass "dangling: count line printed"
else
  fail "dangling: count line missing" "$out"
fi
if echo "$out" | grep -q "$HOME_DIR/hooks/foo.sh"; then
  pass "dangling: link path reported"
else
  fail "dangling: link path missing" "$out"
fi

rm -rf "$(dirname "$HOME_DIR")"

# -------------------------------------------------------------------
# 3. Multiple subdirs with dangling symlinks: doctor reports count.
# -------------------------------------------------------------------

echo "==> 3. Multiple subdirs: doctor counts across all"

FX=$(mk_fake_home)
HOME_DIR=$(echo "$FX" | cut -f1)
SRC=$(echo "$FX" | cut -f2)

# Reproduce the loom-yjo failure scale: dangling symlinks across
# hooks/, agents/, commands/, lib/, scripts/, skills/. Smaller
# number for test speed but same shape.
mkdir -p "$SRC/skills/my-skill"
for sub_file in "hooks/h.sh" "agents/a.md" "commands/c.md" \
                "lib/l.sh" "scripts/s" "skills/my-skill/SKILL.md"; do
  parent="$HOME_DIR/$(dirname "$sub_file")"
  mkdir -p "$parent"
  echo "x" > "$SRC/$sub_file"
  ln -s "$SRC/$sub_file" "$HOME_DIR/$sub_file"
  rm "$SRC/$sub_file"
done

out=$("$DOCTOR" --claude-home "$HOME_DIR" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qE "FOUND 6 dangling"; then
  pass "6 dangling symlinks across subdirs: counted correctly"
else
  fail "expected FOUND 6, got rc=$rc" "$out"
fi

rm -rf "$(dirname "$HOME_DIR")"

# -------------------------------------------------------------------
# 4. Non-loom dangling symlinks ignored (no false flag).
# -------------------------------------------------------------------

echo "==> 4. Non-loom dangling symlink: ignored"

FX=$(mk_fake_home)
HOME_DIR=$(echo "$FX" | cut -f1)
SRC=$(echo "$FX" | cut -f2)

# Create a dangling symlink whose target has no 'loom' substring.
nonloom_src=$(mktemp -d)
mv "$nonloom_src" "${nonloom_src}-other-tool"
nonloom_src="${nonloom_src}-other-tool"
echo "x" > "$nonloom_src/external.sh"
ln -s "$nonloom_src/external.sh" "$HOME_DIR/hooks/external.sh"
rm "$nonloom_src/external.sh"
rmdir "$nonloom_src"

out=$("$DOCTOR" --claude-home "$HOME_DIR" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "non-loom dangling symlink: not flagged (exit 0)"
else
  fail "non-loom dangling: false-flagged (rc=$rc)" "$out"
fi

rm -rf "$(dirname "$HOME_DIR")"

# -------------------------------------------------------------------
# 5. --json output: machine-readable format.
# -------------------------------------------------------------------

echo "==> 5. --json output format"

FX=$(mk_fake_home)
HOME_DIR=$(echo "$FX" | cut -f1)
SRC=$(echo "$FX" | cut -f2)

echo "x" > "$SRC/hooks/foo.sh"
ln -s "$SRC/hooks/foo.sh" "$HOME_DIR/hooks/foo.sh"
rm "$SRC/hooks/foo.sh"

out=$("$DOCTOR" --claude-home "$HOME_DIR" --json 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["dangling_count"]==1; assert "foo.sh" in d["dangling"][0]["link"]; print("ok")' 2>&1 | grep -q "ok"; then
  pass "--json: valid JSON, count=1, link path present"
else
  fail "--json: invalid output" "$out"
fi

rm -rf "$(dirname "$HOME_DIR")"

# -------------------------------------------------------------------
# 6. End-to-end regression smoke: worktree install → cleanup → doctor
#    flags the orphaned symlinks (the loom-cuk reproduction case).
# -------------------------------------------------------------------

echo "==> 6. End-to-end: worktree install → cleanup → doctor flags"

# Build a fake "main loom" repo with install.sh + the sanity-check
# files, plus a worktree of it. Run install.sh from the worktree
# with LOOM_INSTALL_FROM_WORKTREE=1 (simulating the pre-guard
# behavior or a user who deliberately bypassed) into a fake
# CLAUDE_HOME. Delete the worktree. Run the doctor against the
# fake CLAUDE_HOME and confirm the dangling links are reported.

root=$(mktemp -d)
main="$root/loom"   # 'loom' in path so loom-ownership heuristic matches
wt="$root/loom-wt"  # ditto
mkdir -p "$main"

(cd "$main" && git init -q && git config user.email t@t && git config user.name t)

# Copy the real install.sh + minimal sanity-check files.
cp "$LOOM_ROOT/install.sh" "$main/install.sh"
chmod +x "$main/install.sh"
mkdir -p "$main/skills/bugfix-a-bead" "$main/hooks"
echo "stub" > "$main/skills/bugfix-a-bead/SKILL.md"
echo "stub" > "$main/hooks/bd-claim-research.sh"
echo '{}' > "$main/settings.snippet.json"
(cd "$main" && git add . && git commit -q -m seed)

(cd "$main" && git worktree add -q "$wt" -b smoke 2>&1 >/dev/null)

TMPHOME=$(mktemp -d)

# Install from the worktree, bypassing the guard, into TMPHOME.
# Use the worktree's install.sh (which is the same file).
(cd "$wt" && CLAUDE_HOME="$TMPHOME" LOOM_INSTALL_FROM_WORKTREE=1 \
   bash "$wt/install.sh" 2>&1 >/dev/null) || true

# Confirm the install baked the worktree path into hooks/<name>.sh.
wt_baked=$(find "$TMPHOME" -type l -lname "$wt*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$wt_baked" -gt 0 ]; then
  pass "smoke: $wt_baked symlinks baked with worktree path (reproduction confirmed)"
else
  fail "smoke: no worktree-baked symlinks — install.sh may not have run"
fi

# Now delete the worktree. (Use `git worktree remove --force` to
# delete cleanly, then rm -rf the directory just in case.)
(cd "$main" && git worktree remove --force "$wt" 2>&1 >/dev/null) || true
rm -rf "$wt"

# Run the doctor.
out=$("$DOCTOR" --claude-home "$TMPHOME" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qE "FOUND [1-9]"; then
  pass "smoke: doctor flags worktree-orphaned symlinks (rc=1, FOUND >0)"
else
  fail "smoke: doctor did not flag orphaned symlinks. rc=$rc" "$out"
fi

rm -rf "$root" "$TMPHOME"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
