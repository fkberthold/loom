#!/usr/bin/env bash
# Fixture tests for install.sh's invocability assertion (loom-7f3).
#
# Failure mode this guards against (loom-k2g.7):
#   A primitive (skill / command / agent / hook) can be SHIPPED in the
#   repo — committed, merged, present on disk — yet never become
#   INVOCABLE because no `~/.claude/...` symlink points at it. This is
#   exactly what happened to upstream-a-bead: the skill shipped, but no
#   `~/.claude/skills/upstream-a-bead` symlink existed until install.sh
#   was re-run. "Shipped but not invocable" is a real, silent gap —
#   nothing in the suite caught it, because the file existed and the
#   tests only checked the file.
#
# Fix shape (loom-7f3):
#   install.sh grows a `--check-invocable` mode: a post-install
#   verification pass (NO mutation) that asserts every
#   skills/*/SKILL.md, commands/*.md, agents/*.md, and hooks/*.sh has a
#   corresponding LIVE symlink under $CLAUDE_HOME resolving back to the
#   repo file. On any missing/broken link it names the un-invocable
#   primitive and exits NON-ZERO; with all links present it exits 0.
#   The normal install path and the dry-run `--check` path are
#   unchanged.
#
# RED contract:
#   Given a shipped skill with no ~/.claude symlink
#   When  install.sh --check-invocable runs
#   Then  it exits non-zero naming the un-invocable primitive;
#         with all symlinks present it exits 0.
#
# Run:  bash lib/tests/install-invocability.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$LOOM_ROOT/install.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Build a fixture LOOM_ROOT mirroring the structure install.sh expects
# (the required-files probe at install.sh:87 + the symlink walks). Each
# fixture run gets its own tmpdir so runs are isolated from the real
# worktree. We ship TWO skills, a command, an agent, and the hooks the
# probe requires — enough surface that dropping one link is detectable.
mk_fixture_loom() {
  local dir="$1"
  mkdir -p "$dir/skills/bugfix-a-bead" "$dir/skills/upstream-a-bead"
  mkdir -p "$dir/hooks" "$dir/scripts" "$dir/agents" "$dir/commands" "$dir/lib/tests"
  echo "# bugfix" > "$dir/skills/bugfix-a-bead/SKILL.md"
  echo "# upstream" > "$dir/skills/upstream-a-bead/SKILL.md"
  echo "# agent" > "$dir/agents/sample-agent.md"
  echo "# command" > "$dir/commands/sample-command.md"
  echo "stub" > "$dir/hooks/bd-claim-research.sh"
  cat >"$dir/settings.snippet.json" <<'JSON'
{
  "_comment": "fixture",
  "permissions": {"allow": []},
  "hooks": {"PreToolUse": [], "SessionStart": []},
  "statusLine": {}
}
JSON
  cp "$INSTALL_SH" "$dir/install.sh"
  chmod +x "$dir/install.sh"
  # Make $dir a git repo so install.sh's worktree detection sees a main
  # checkout (not a linked worktree) and proceeds.
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name  "test"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "fixture"
}

# Run a full (non-dry) install against a fixture loom root, pointing
# CLAUDE_HOME at a temp dir so the real ~/.claude/ is untouched.
run_install() {
  local fixture_root="$1" claude_home="$2"
  ( cd "$fixture_root" && CLAUDE_HOME="$claude_home" bash install.sh ) \
    >"$claude_home/install.log" 2>&1
  return $?
}

# Run install.sh --check-invocable against a fixture; echoes combined
# output, leaves rc in $? for the caller.
run_check_invocable() {
  local fixture_root="$1" claude_home="$2"
  ( cd "$fixture_root" && CLAUDE_HOME="$claude_home" bash install.sh --check-invocable ) 2>&1
}

# -------------------------------------------------------------------
# 1. All symlinks present → --check-invocable exits 0.
# -------------------------------------------------------------------

echo "==> 1. All primitives symlinked: --check-invocable exits 0"

FX=$(mktemp -d)
HOME_DIR=$(mktemp -d)
mk_fixture_loom "$FX"
run_install "$FX" "$HOME_DIR"

out=$(run_check_invocable "$FX" "$HOME_DIR"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "all-symlinked: --check-invocable exits 0"
else
  fail "all-symlinked: expected exit 0, got rc=$rc" "$out"
fi

rm -rf "$FX" "$HOME_DIR"

# -------------------------------------------------------------------
# 2. A shipped skill with NO ~/.claude symlink → non-zero + named.
# -------------------------------------------------------------------

echo "==> 2. Shipped skill, missing symlink: non-zero + names primitive"

FX=$(mktemp -d)
HOME_DIR=$(mktemp -d)
mk_fixture_loom "$FX"
run_install "$FX" "$HOME_DIR"

# Simulate the loom-k2g.7 gap: the skill is shipped (present in the
# repo) but its invocability symlink is absent under ~/.claude.
rm -f "$HOME_DIR/skills/upstream-a-bead/SKILL.md"

out=$(run_check_invocable "$FX" "$HOME_DIR"); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "missing-skill-symlink: --check-invocable exits non-zero (rc=$rc)"
else
  fail "missing-skill-symlink: expected non-zero, got rc=0" "$out"
fi

if echo "$out" | grep -q "upstream-a-bead"; then
  pass "missing-skill-symlink: names the un-invocable primitive (upstream-a-bead)"
else
  fail "missing-skill-symlink: output does not name upstream-a-bead" "$out"
fi

rm -rf "$FX" "$HOME_DIR"

# -------------------------------------------------------------------
# 3. A BROKEN (dangling) symlink also fails the check + names it.
# -------------------------------------------------------------------

echo "==> 3. Broken/dangling symlink: non-zero + names primitive"

FX=$(mktemp -d)
HOME_DIR=$(mktemp -d)
mk_fixture_loom "$FX"
run_install "$FX" "$HOME_DIR"

# Make the link dangle: point it at a now-nonexistent target.
rm -f "$HOME_DIR/skills/upstream-a-bead/SKILL.md"
ln -s "$FX/skills/upstream-a-bead/GONE.md" "$HOME_DIR/skills/upstream-a-bead/SKILL.md"

out=$(run_check_invocable "$FX" "$HOME_DIR"); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "broken-symlink: --check-invocable exits non-zero (rc=$rc)"
else
  fail "broken-symlink: expected non-zero, got rc=0" "$out"
fi

if echo "$out" | grep -q "upstream-a-bead"; then
  pass "broken-symlink: names the un-invocable primitive"
else
  fail "broken-symlink: output does not name upstream-a-bead" "$out"
fi

rm -rf "$FX" "$HOME_DIR"

# -------------------------------------------------------------------
# 4. A missing COMMAND symlink is also caught + named.
# -------------------------------------------------------------------

echo "==> 4. Missing command symlink: non-zero + names command"

FX=$(mktemp -d)
HOME_DIR=$(mktemp -d)
mk_fixture_loom "$FX"
run_install "$FX" "$HOME_DIR"

rm -f "$HOME_DIR/commands/sample-command.md"

out=$(run_check_invocable "$FX" "$HOME_DIR"); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "missing-command-symlink: --check-invocable exits non-zero (rc=$rc)"
else
  fail "missing-command-symlink: expected non-zero, got rc=0" "$out"
fi

if echo "$out" | grep -q "sample-command"; then
  pass "missing-command-symlink: names the un-invocable command"
else
  fail "missing-command-symlink: output does not name sample-command" "$out"
fi

rm -rf "$FX" "$HOME_DIR"

# -------------------------------------------------------------------
# 5. --check-invocable does NOT mutate ~/.claude (verification-only).
#    Re-running install --check-invocable on an all-good fixture must
#    not create/remove symlinks.
# -------------------------------------------------------------------

echo "==> 5. --check-invocable is non-mutating"

FX=$(mktemp -d)
HOME_DIR=$(mktemp -d)
mk_fixture_loom "$FX"
run_install "$FX" "$HOME_DIR"

before=$(find "$HOME_DIR" -type l 2>/dev/null | sort)
run_check_invocable "$FX" "$HOME_DIR" >/dev/null 2>&1
after=$(find "$HOME_DIR" -type l 2>/dev/null | sort)

if [ "$before" = "$after" ]; then
  pass "non-mutating: symlink set unchanged after --check-invocable"
else
  fail "non-mutating: symlink set changed" "$(diff <(echo "$before") <(echo "$after"))"
fi

rm -rf "$FX" "$HOME_DIR"

# -------------------------------------------------------------------
# 6. The dry-run --check mode is UNCHANGED (still a dry-run preview,
#    not invocability verification). Guards against regressing
#    install-refuse-from-worktree.test.sh's reliance on --check.
# -------------------------------------------------------------------

echo "==> 6. --check (dry-run) still previews install without mutating"

FX=$(mktemp -d)
HOME_DIR=$(mktemp -d)
mk_fixture_loom "$FX"

out=$( cd "$FX" && CLAUDE_HOME="$HOME_DIR" bash install.sh --check 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "--check (dry-run): exits 0 on a fresh fixture"
else
  fail "--check (dry-run): expected exit 0, got rc=$rc" "$out"
fi

# Dry-run must not have created symlinks.
baked=$(find "$HOME_DIR" -type l 2>/dev/null | wc -l | tr -d ' ')
if [ "$baked" = "0" ]; then
  pass "--check (dry-run): created no symlinks"
else
  fail "--check (dry-run): created $baked symlinks (should be 0)"
fi

rm -rf "$FX" "$HOME_DIR"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
