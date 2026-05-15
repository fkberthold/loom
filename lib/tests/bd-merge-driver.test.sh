#!/usr/bin/env bash
# Fixture tests for scripts/bd-merge-driver.sh.
#
# Closes loom-4um: git's line-based auto-merge of .beads/issues.jsonl
# can silently revert bead state when a feature branch based on stale
# main is merged into post-newer-work main. The `--ours` conflict
# resolution only fires on ACTUAL conflicts; auto-merges look
# successful but reconcile lines across semantic boundaries.
#
# Fix shape (tier c — structural):
#   1. scripts/bd-merge-driver.sh — custom merge driver. Git invokes
#      it as `merge-driver %O %A %B %P`. The driver runs `bd export`
#      in the toplevel and writes the result to %A (the merge
#      result). This regenerates from bd's authoritative dolt store,
#      ignoring whatever git's line-merge produced.
#   2. .gitattributes — `.beads/issues.jsonl merge=bd-export` wires
#      the driver to the file.
#   3. install.sh — sets `merge.bd-export.driver` in this repo's
#      .git/config (per-repo, since merge drivers are git-config-
#      based, not committable).
#
# Tests verify the driver script itself behaves correctly under
# direct invocation (the same way git would invoke it). Wiring
# tests (gitattributes presence, install.sh `git config` write)
# are simpler and covered by inline assertions.
#
# Run:  bash lib/tests/bd-merge-driver.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIVER="$LOOM_ROOT/scripts/bd-merge-driver.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Make a stub `bd` that writes a canned canonical export when asked.
# The stub is the entire substitute for the bd binary during these
# tests (we set BD_BIN to point at it). The canonical text is
# stored in a sibling file and `cat`-ed by the stub — that avoids
# the heredoc-vs-JSON-double-quote escaping hazard.
#   $1 = canonical content the stub should emit on `bd export`
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

# -------------------------------------------------------------------
# 1. Driver overwrites %A with bd export output.
# -------------------------------------------------------------------

echo "==> 1. Driver overwrites %A with bd export output"

WORK=$(mktemp -d)
ANCESTOR="$WORK/ancestor.jsonl"
CURRENT="$WORK/current.jsonl"
OTHER="$WORK/other.jsonl"

# Simulate the scenario: a line-based auto-merge has produced a
# semantically-wrong %A. The driver must replace it with bd export.
cat > "$ANCESTOR" <<'JSONL'
{"id":"loom-aaa","status":"open"}
{"id":"loom-bbb","status":"open"}
JSONL
# %A starts out as the (semantically-broken) result of line-merge.
cat > "$CURRENT" <<'JSONL'
{"id":"loom-aaa","status":"open"}
{"id":"loom-bbb","status":"open"}
JSONL
cat > "$OTHER" <<'JSONL'
{"id":"loom-aaa","status":"closed"}
{"id":"loom-bbb","status":"open"}
JSONL

CANONICAL='{"id":"loom-aaa","status":"closed"}
{"id":"loom-bbb","status":"closed"}
'
BD=$(mk_bd_stub "$CANONICAL")

# Driver is invoked with: %O %A %B %P
out=$(BD_BIN="$BD" bash "$DRIVER" "$ANCESTOR" "$CURRENT" "$OTHER" ".beads/issues.jsonl" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "driver exits 0 on success"
else
  fail "driver did not exit 0 (rc=$rc)" "$out"
fi

if diff <(printf '%s' "$CANONICAL") "$CURRENT" >/dev/null 2>&1; then
  pass "%A overwritten with bd export output"
else
  fail "%A content does not match canonical export. Got:" "$(cat "$CURRENT")"
fi

rm -rf "$WORK" "$BD"

# -------------------------------------------------------------------
# 2. Driver fails (non-zero) when bd export fails.
# -------------------------------------------------------------------

echo "==> 2. Driver propagates bd export failure"

WORK=$(mktemp -d)
CURRENT="$WORK/current.jsonl"
echo "stale" > "$CURRENT"

# Stub that always fails.
BD=$(mktemp)
cat > "$BD" <<'EOF'
#!/usr/bin/env bash
echo "simulated bd export failure" >&2
exit 7
EOF
chmod +x "$BD"

out=$(BD_BIN="$BD" bash "$DRIVER" "/dev/null" "$CURRENT" "/dev/null" ".beads/issues.jsonl" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "driver exits non-zero when bd export fails"
else
  fail "driver swallowed bd export failure (rc=$rc)" "$out"
fi

# When the export fails, %A must NOT be silently overwritten with
# empty/garbage content. Either left alone or marked as a conflict.
if [ -s "$CURRENT" ]; then
  pass "%A not silently emptied on failure"
else
  fail "%A emptied on failure — this would silently lose state"
fi

rm -rf "$WORK" "$BD"

# -------------------------------------------------------------------
# 3. Driver verifies output is well-formed JSONL (one JSON object per
#    line). A malformed export should fail loudly.
# -------------------------------------------------------------------

echo "==> 3. Driver rejects malformed JSONL from bd export"

WORK=$(mktemp -d)
CURRENT="$WORK/current.jsonl"
echo "stale" > "$CURRENT"

# Stub emits broken output.
BD=$(mk_bd_stub "this is not json
neither is this
")

out=$(BD_BIN="$BD" bash "$DRIVER" "/dev/null" "$CURRENT" "/dev/null" ".beads/issues.jsonl" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "driver exits non-zero on malformed JSONL"
else
  fail "driver accepted malformed JSONL (rc=$rc)" "$out"
fi

rm -rf "$WORK" "$BD"

# -------------------------------------------------------------------
# 4. .gitattributes wiring exists and references the driver name.
# -------------------------------------------------------------------

echo "==> 4. .gitattributes references merge=bd-export"

GA="$LOOM_ROOT/.gitattributes"
if [ -f "$GA" ] && grep -qE '^\.beads/issues\.jsonl[[:space:]]+merge=bd-export' "$GA"; then
  pass ".gitattributes has '.beads/issues.jsonl merge=bd-export'"
else
  fail ".gitattributes missing the merge=bd-export entry" "$(cat "$GA" 2>/dev/null)"
fi

# -------------------------------------------------------------------
# 5. install.sh configures merge.bd-export.driver via git config.
# -------------------------------------------------------------------

echo "==> 5. install.sh wires merge.bd-export.driver"

INSTALL="$LOOM_ROOT/install.sh"
if grep -qE "merge\.bd-export\.driver" "$INSTALL"; then
  pass "install.sh references merge.bd-export.driver"
else
  fail "install.sh missing merge.bd-export.driver wiring"
fi

# Also verify install.sh references the driver script path.
if grep -qE "bd-merge-driver\.sh" "$INSTALL"; then
  pass "install.sh references scripts/bd-merge-driver.sh"
else
  fail "install.sh missing scripts/bd-merge-driver.sh reference"
fi

# -------------------------------------------------------------------
# 6. End-to-end: simulate the regression scenario with a real git
#    merge using the driver configured locally in a fixture repo.
# -------------------------------------------------------------------

echo "==> 6. End-to-end: real git merge invokes the driver"

WORK=$(mktemp -d)
FIXTURE="$WORK/repo"
mkdir -p "$FIXTURE"
(cd "$FIXTURE" && git init -q && git config user.email t@t && git config user.name t)

# Seed canonical bd state.
mkdir -p "$FIXTURE/.beads"
cat > "$FIXTURE/.beads/issues.jsonl" <<'JSONL'
{"id":"loom-aaa","status":"open"}
{"id":"loom-bbb","status":"open"}
JSONL

# Wire the merge driver. We give the stub `bd` a fixed canonical
# output via a wrapper script that lives next to the driver.
STUB_BD=$(mk_bd_stub '{"id":"loom-aaa","status":"closed"}
{"id":"loom-bbb","status":"closed"}
')

# Set BD_BIN so the driver finds our stub.
# Configure the driver via `git config` in the fixture repo.
(cd "$FIXTURE" && git config merge.bd-export.driver "BD_BIN=$STUB_BD bash $DRIVER %O %A %B %P")
(cd "$FIXTURE" && git config merge.bd-export.name "bd-export merge driver (fixture)")

# Wire .gitattributes inside the fixture.
echo '.beads/issues.jsonl merge=bd-export' > "$FIXTURE/.gitattributes"

(cd "$FIXTURE" && git add -A && git commit -q -m "seed")

# Diverge: branch A advances .beads/issues.jsonl one way; branch B
# advances it another way. Both look like line-additions that
# auto-merge cleanly but lose semantic state.
(cd "$FIXTURE" && git checkout -q -b branch-a)
cat > "$FIXTURE/.beads/issues.jsonl" <<'JSONL'
{"id":"loom-aaa","status":"open"}
{"id":"loom-bbb","status":"in_progress"}
JSONL
(cd "$FIXTURE" && git add -A && git commit -q -m "branch-a: bbb in progress")

(cd "$FIXTURE" && git checkout -q -)
(cd "$FIXTURE" && git checkout -q -b branch-b)
cat > "$FIXTURE/.beads/issues.jsonl" <<'JSONL'
{"id":"loom-aaa","status":"closed"}
{"id":"loom-bbb","status":"open"}
JSONL
(cd "$FIXTURE" && git add -A && git commit -q -m "branch-b: aaa closed")

# Merge branch-a into branch-b. Without the driver, git's auto-merge
# would silently reconcile the lines wrong. With the driver, bd export
# (our stub) replaces the result.
(cd "$FIXTURE" && git merge -q branch-a 2>&1 >/dev/null) || true

# Check result.
if grep -qE '"loom-aaa".*"closed"' "$FIXTURE/.beads/issues.jsonl" && \
   grep -qE '"loom-bbb".*"closed"' "$FIXTURE/.beads/issues.jsonl"; then
  pass "real git merge: driver fired, result matches canonical bd export"
else
  fail "real git merge: result does not match canonical export" "$(cat "$FIXTURE/.beads/issues.jsonl")"
fi

rm -rf "$WORK" "$STUB_BD"

# -------------------------------------------------------------------
# 7. Bug-class coverage: bd binary missing → driver fails loud.
#    The original bug class is "silent reconciliation"; if bd is
#    unavailable, the driver MUST fail rather than silently fall
#    back to whatever line-merge produced.
# -------------------------------------------------------------------

echo "==> 7. Missing bd binary: driver fails loud (no silent fallback)"

WORK=$(mktemp -d)
CURRENT="$WORK/current.jsonl"
echo "stale-state" > "$CURRENT"
ORIG_CONTENT=$(cat "$CURRENT")

out=$(BD_BIN="/nonexistent/path/bd" bash "$DRIVER" "/dev/null" "$CURRENT" "/dev/null" ".beads/issues.jsonl" 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "missing bd binary: driver exits non-zero"
else
  fail "missing bd binary: driver silently succeeded (rc=$rc)" "$out"
fi

NEW_CONTENT=$(cat "$CURRENT")
if [ "$ORIG_CONTENT" = "$NEW_CONTENT" ]; then
  pass "missing bd binary: %A preserved (no silent overwrite)"
else
  fail "%A was modified despite bd failure. Original: '$ORIG_CONTENT' Now: '$NEW_CONTENT'"
fi

rm -rf "$WORK"

# -------------------------------------------------------------------
# 8. Bug-class coverage: argc < 4 (driver invoked without %P, etc.)
#    Driver MUST reject malformed git-merge-driver invocations rather
#    than process partial state.
# -------------------------------------------------------------------

echo "==> 8. Malformed invocation (argc < 4): driver rejects"

out=$(BD_BIN="/dev/null" bash "$DRIVER" "only-one-arg" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "argc < 4: driver exits non-zero"
else
  fail "argc < 4: driver accepted partial args (rc=$rc)" "$out"
fi

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
