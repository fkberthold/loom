#!/usr/bin/env bash
# Fixture tests for commands/loom-upstream-gc.md.
#
# The slash command itself is markdown — Claude executes the
# embedded bash snippets at /loom-upstream-gc invocation time.
# These tests exercise the EXACT bash logic from the command body,
# stubbing `bd` + `git` via PATH-prepended fake binaries and
# isolating LOOM_HOME to a tmpdir so the real ~/.loom is never
# touched.
#
# Covers loom-k2g.4. Cases per the dispatcher brief:
#   1. refusal on uncommitted-changes
#   2. refusal on open watch-bead reference
#   3. clean prune once both gates pass (no prompt, loom-42cw)
#   4. empty upstream dir no-op
#
# Run:  bash lib/tests/loom-upstream-gc.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

mk_loom_home() { mktemp -d; }

# Stub `bd` via PATH-prepended fake. WATCH_JSON is the canned
# `bd list --label=upstream:watch --status=open --json` output.
mk_bd_stub() {
  local watch_json="$1"
  local d
  d=$(mktemp -d)
  cat > "$d/bd" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list" ]; then
  cat <<'JSON'
$watch_json
JSON
  exit 0
fi
exit 0
EOF
  chmod +x "$d/bd"
  echo "$d"
}

# Run the per-clone gating logic.
# The function consolidates the bash body from commands/loom-upstream-gc.md
# (Step 1 + Step 2 + Step 3 + Step 4) into a single executable so
# tests don't need to re-parse the markdown. Updates here MUST mirror
# any change to the command body's bash blocks.
#
# It takes no user-answer parameter: under loom-42cw the per-clone
# prompt was removed, so the two gates are the whole decision and there
# is no third input to vary.
run_gc() {
  local loom_home="$1"
  local bd_dir="$2"
  PATH="$bd_dir:$PATH" LOOM_HOME="$loom_home" bash <<'SCRIPT'
set -uo pipefail
LOOM_HOME=${LOOM_HOME:-$HOME/.loom}
UPSTREAM_ROOT="$LOOM_HOME/upstream"

if [ ! -d "$UPSTREAM_ROOT" ]; then
  echo "No upstream cache at $UPSTREAM_ROOT — nothing to prune."
  exit 0
fi

mapfile -t CLONES < <(find "$UPSTREAM_ROOT" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)

if [ "${#CLONES[@]}" -eq 0 ]; then
  echo "Upstream cache at $UPSTREAM_ROOT contains no clones — nothing to prune."
  exit 0
fi

echo "Found ${#CLONES[@]} clone(s) under $UPSTREAM_ROOT:"
for clone in "${CLONES[@]}"; do
  echo "  - ${clone#$UPSTREAM_ROOT/}"
done

WATCH_REFS=$(bd list --label=upstream:watch --status=open --json 2>/dev/null \
  | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
seen = set()
for issue in data if isinstance(data, list) else []:
    desc = (issue.get("description") or "") + " " + (issue.get("title") or "")
    for m in re.finditer(r"github\.com[/:]([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+?)(?:\.git)?(?:/(?:pull|issues|tree|commit)/|[\s)]|$)", desc):
        seen.add(f"{m.group(1)}/{m.group(2)}")
for slug in sorted(seen):
    print(slug)
' 2>/dev/null)

pruned_count=0
refused_count=0

for clone in "${CLONES[@]}"; do
  rel="${clone#$UPSTREAM_ROOT/}"
  echo "----"
  echo "Clone: $rel"
  echo "  Path: $clone"

  if [ ! -d "$clone/.git" ] && ! git -C "$clone" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  REFUSE: $clone is not a git repository — skipping."
    refused_count=$((refused_count + 1))
    continue
  fi
  porcelain=$(git -C "$clone" status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    echo "  REFUSE: clone has uncommitted changes:"
    echo "$porcelain" | sed 's/^/    /'
    refused_count=$((refused_count + 1))
    continue
  fi
  if printf '%s\n' "$WATCH_REFS" | grep -Fxq "$rel"; then
    echo "  REFUSE: an open upstream:watch bead references $rel."
    refused_count=$((refused_count + 1))
    continue
  fi

  echo "  Both safety gates passed."
  rm -rf "$clone"
  echo "  PRUNED: $clone"
  pruned_count=$((pruned_count + 1))
  owner_dir="$(dirname "$clone")"
  if [ -d "$owner_dir" ] && [ -z "$(ls -A "$owner_dir")" ]; then
    rmdir "$owner_dir"
    echo "  Removed empty owner dir: $owner_dir"
  fi
done

echo "----"
echo "Summary: $pruned_count clone(s) pruned, $refused_count refused."
SCRIPT
}

# Init a git repo at $1 with one commit. Optional extra wip file
# leaves the tree dirty.
mk_clone_repo() {
  local path="$1"
  local dirty="${2:-clean}"
  mkdir -p "$path"
  (cd "$path" && git init -q -b main && git config user.email t@t && git config user.name t)
  echo seed > "$path/seed.txt"
  (cd "$path" && git add -A && git -c core.hooksPath=/dev/null commit -q -m seed)
  if [ "$dirty" = "dirty" ]; then
    echo wip > "$path/wip.txt"
  fi
}

# -------------------------------------------------------------------
# 1. Empty upstream cache: no clones → no-op + exit 0.
# -------------------------------------------------------------------

echo "==> 1. Empty upstream dir is a no-op"

LOOM_HOME=$(mk_loom_home)
mkdir -p "$LOOM_HOME/upstream"
BD_DIR=$(mk_bd_stub '[]')

out=$(run_gc "$LOOM_HOME" "$BD_DIR" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "exit 0 on empty upstream cache"
else
  fail "non-zero exit on empty cache (rc=$rc)" "$out"
fi

if echo "$out" | grep -qi "no clones"; then
  pass "reports empty cache to user"
else
  fail "missing empty-cache message" "$out"
fi

rm -rf "$LOOM_HOME" "$BD_DIR"

# -------------------------------------------------------------------
# 1b. Truly-absent upstream dir: exits with friendly message.
# -------------------------------------------------------------------

echo "==> 1b. Absent upstream dir is a no-op"

LOOM_HOME=$(mk_loom_home)
# Don't create $LOOM_HOME/upstream at all.
BD_DIR=$(mk_bd_stub '[]')

out=$(run_gc "$LOOM_HOME" "$BD_DIR" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "exit 0 when upstream dir absent"
else
  fail "non-zero exit when upstream dir absent (rc=$rc)" "$out"
fi

if echo "$out" | grep -qi "nothing to prune"; then
  pass "reports absent-cache to user"
else
  fail "missing absent-cache message" "$out"
fi

rm -rf "$LOOM_HOME" "$BD_DIR"

# -------------------------------------------------------------------
# 2. Refusal on uncommitted changes.
# -------------------------------------------------------------------

echo "==> 2. Refuses prune when clone has uncommitted changes"

LOOM_HOME=$(mk_loom_home)
mk_clone_repo "$LOOM_HOME/upstream/obra/superpowers" dirty
BD_DIR=$(mk_bd_stub '[]')

out=$(run_gc "$LOOM_HOME" "$BD_DIR" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "exit 0 even when refusing (refusal is not fatal)"
else
  fail "non-zero exit on refusal (rc=$rc)" "$out"
fi

if echo "$out" | grep -qi "REFUSE.*uncommitted"; then
  pass "refusal message names uncommitted-changes condition"
else
  fail "refusal message missing uncommitted-changes context" "$out"
fi

if [ -d "$LOOM_HOME/upstream/obra/superpowers" ]; then
  pass "dirty clone NOT removed (gate 1 short-circuits)"
else
  fail "dirty clone was removed — refusal failed to short-circuit"
fi

if echo "$out" | grep -q "Summary: 0 clone(s) pruned, 1 refused"; then
  pass "summary tallies refusal correctly"
else
  fail "summary missing or wrong" "$out"
fi

rm -rf "$LOOM_HOME" "$BD_DIR"

# -------------------------------------------------------------------
# 3. Refusal on open watch-bead reference.
# -------------------------------------------------------------------

echo "==> 3. Refuses prune when open watch-bead references the clone"

LOOM_HOME=$(mk_loom_home)
mk_clone_repo "$LOOM_HOME/upstream/obra/superpowers" clean

# Canned bd watch-bead listing — description contains a PR URL that
# matches obra/superpowers.
WATCH_JSON='[{"id":"foo-001","title":"watch upstream obra/superpowers#42","description":"PR URL: https://github.com/obra/superpowers/pull/42"}]'
BD_DIR=$(mk_bd_stub "$WATCH_JSON")

out=$(run_gc "$LOOM_HOME" "$BD_DIR" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "exit 0 on watch-bead refusal"
else
  fail "non-zero exit (rc=$rc)" "$out"
fi

if echo "$out" | grep -qi "REFUSE.*upstream:watch.*obra/superpowers"; then
  pass "refusal names the offending watch-bead reference"
else
  fail "refusal message missing watch-bead context" "$out"
fi

if [ -d "$LOOM_HOME/upstream/obra/superpowers" ]; then
  pass "watch-referenced clone NOT removed (gate 2 short-circuits)"
else
  fail "watch-referenced clone was removed — refusal failed"
fi

rm -rf "$LOOM_HOME" "$BD_DIR"

# -------------------------------------------------------------------
# 4. Clean prune once both gates pass.
# -------------------------------------------------------------------

echo "==> 4. Clean tree + no watch-ref → prunes"

LOOM_HOME=$(mk_loom_home)
mk_clone_repo "$LOOM_HOME/upstream/obra/superpowers" clean
BD_DIR=$(mk_bd_stub '[]')

# Sanity precondition.
[ -d "$LOOM_HOME/upstream/obra/superpowers/.git" ] || { echo "  SETUP FAIL"; exit 1; }

out=$(run_gc "$LOOM_HOME" "$BD_DIR" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "exit 0 on successful prune"
else
  fail "non-zero exit on successful prune (rc=$rc)" "$out"
fi

if [ ! -d "$LOOM_HOME/upstream/obra/superpowers" ]; then
  pass "clone removed once both gates pass"
else
  fail "clone NOT removed despite both gates passing"
fi

if [ ! -d "$LOOM_HOME/upstream/obra" ]; then
  pass "empty owner dir cleaned up"
else
  fail "empty owner dir left behind"
fi

if echo "$out" | grep -q "Summary: 1 clone(s) pruned, 0 refused"; then
  pass "summary tallies prune correctly"
else
  fail "summary missing prune count" "$out"
fi

rm -rf "$LOOM_HOME" "$BD_DIR"

# -------------------------------------------------------------------
# 4b. The per-clone prompt is gone from the command body (loom-42cw).
#
# This replaces the old "user decline keeps the clone" case, which
# pinned a behavior D8 retired: the two gates already establish that
# the clone is clean and unreferenced, so the prompt asked for assent
# to a decision it had finished making, once per clone.
#
# It is a grep-contract check over the markdown rather than a run of
# run_gc, because run_gc is a COPY of the command's bash. A copy can
# agree with itself while the command body drifts, which is exactly
# how this file passed 23/23 against a body that no longer matched.
# -------------------------------------------------------------------

echo "==> 4b. Command body carries no per-clone prompt"

CMD_FILE="$LOOM_ROOT/commands/loom-upstream-gc.md"

if [ -f "$CMD_FILE" ]; then
  pass "commands/loom-upstream-gc.md exists"

  # This was the only AskUserQuestion call in the repo. Keep it gone.
  if grep -q 'AskUserQuestion' "$CMD_FILE"; then
    fail "no AskUserQuestion in the command body" \
      "(the per-clone assent prompt was removed under loom-42cw)"
  else
    pass "no AskUserQuestion in the command body"
  fi

  # No prompt shape survives either.
  if grep -qiE 'prompt for assent|\(y/N\)|user assent|on user decline' "$CMD_FILE"; then
    fail "no per-clone assent prompt survives" \
      "(found prompt-shaped text in the command body)"
  else
    pass "no per-clone assent prompt survives"
  fi

  # The contract section says the gates carry the decision.
  if grep -qiE 'gates are the whole decision|gates carry the whole decision' "$CMD_FILE"; then
    pass "contract states the gates are the whole decision"
  else
    fail "contract does not state the gates are the whole decision"
  fi

  # The command reports what it pruned (D9: act, then say what you did).
  if grep -qiE 'report what went|reports what it removed|name the clones' "$CMD_FILE"; then
    pass "command reports what it pruned"
  else
    fail "command does not say it reports the pruned clones"
  fi
else
  fail "commands/loom-upstream-gc.md exists" "(file missing: $CMD_FILE)"
fi

# -------------------------------------------------------------------
# 5. Multi-clone: one prunable, one watch-blocked, one dirty.
# -------------------------------------------------------------------

echo "==> 5. Multi-clone: mixed gates produce mixed outcomes"

LOOM_HOME=$(mk_loom_home)
mk_clone_repo "$LOOM_HOME/upstream/obra/superpowers" clean   # will prune
mk_clone_repo "$LOOM_HOME/upstream/gastownhall/beads" clean  # blocked by watch
mk_clone_repo "$LOOM_HOME/upstream/mempalace/mempalace" dirty # blocked by dirty

WATCH_JSON='[{"id":"foo-001","title":"watch upstream gastownhall/beads#7","description":"https://github.com/gastownhall/beads/pull/7"}]'
BD_DIR=$(mk_bd_stub "$WATCH_JSON")

out=$(run_gc "$LOOM_HOME" "$BD_DIR" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then pass "multi-clone run exits 0"; else fail "multi-clone rc=$rc" "$out"; fi

if [ ! -d "$LOOM_HOME/upstream/obra/superpowers" ]; then
  pass "obra/superpowers (clean + unreferenced) pruned"
else
  fail "obra/superpowers should have been pruned"
fi

if [ -d "$LOOM_HOME/upstream/gastownhall/beads" ]; then
  pass "gastownhall/beads (watch-blocked) preserved"
else
  fail "gastownhall/beads should have been preserved"
fi

if [ -d "$LOOM_HOME/upstream/mempalace/mempalace" ]; then
  pass "mempalace/mempalace (dirty) preserved"
else
  fail "mempalace/mempalace should have been preserved"
fi

if echo "$out" | grep -q "Summary: 1 clone(s) pruned, 2 refused"; then
  pass "multi-clone summary tallies correctly (1/2/0)"
else
  fail "multi-clone summary wrong" "$out"
fi

rm -rf "$LOOM_HOME" "$BD_DIR"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
