#!/usr/bin/env bash
# Fixture tests for lib/bd-canonical-export.sh.
#
# Closes loom-0ahj.1 (subsumes loom-n1sk): `bd export` is NOT byte-
# stable across repeated runs on unchanged state. The non-determinism
# is a PURE reorder of the `_type:memory` lines — Go's randomized map
# iteration emits the memory-metadata rows in a per-process-random
# order, while the issue rows themselves are already position-stable.
# On loom's bd v1.0.2 this produces spurious `.beads/issues.jsonl`
# diffs (10x order A, 30x order B observed across 40 export runs),
# which dirties the working tree and aborts merges / strands closes.
#
# The fix is a thin loom-side canonicalizer that runs `bd export` and
# emits a canonical form: it sorts ONLY the `_type:memory` lines into
# a stable order, leaving every issue row in its existing position.
# This delivers byte-stability on the CURRENT bd (v1.0.2) without
# upgrading the global binary, and backstops downstream projects on
# uncontrolled bd versions.
#
# INVARIANT under test:
#   bd export is byte-stable across repeated runs on unchanged state
#   (the diff of two consecutive canonicalized exports is empty).
#
# Run:  bash lib/tests/bd-canonical-export.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANON="$LOOM_ROOT/lib/bd-canonical-export.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ---------------------------------------------------------------------------
# A `bd` stub whose `export` emits the SAME logical state but with the two
# `_type:memory` lines in a DIFFERENT order on alternating calls. This
# deterministically simulates Go's randomized map iteration: the issue rows
# stay put, only the memory rows flip. A counter file persists across
# invocations of the stub so successive `bd export` calls differ.
#
#   $1 = path the counter file lives at (created if missing)
# Emits the stub path on stdout.
mk_flapping_bd_stub() {
  local counter="$1"
  local f
  f=$(mktemp)
  printf '0' > "$counter"
  cat > "$f" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "export" ]; then
  n=\$(cat "$counter" 2>/dev/null || echo 0)
  printf '%s' "\$(( n + 1 ))" > "$counter"
  # Two issue rows (position-stable) + two memory rows (order flips).
  echo '{"id":"x-1","title":"first issue","status":"open"}'
  echo '{"id":"x-2","title":"second issue","status":"closed"}'
  if [ "\$(( n % 2 ))" -eq 0 ]; then
    echo '{"_type":"memory","key":"bravo","value":"B"}'
    echo '{"_type":"memory","key":"alpha","value":"A"}'
  else
    echo '{"_type":"memory","key":"alpha","value":"A"}'
    echo '{"_type":"memory","key":"bravo","value":"B"}'
  fi
  exit 0
fi
exit 1
EOF
  chmod +x "$f"
  echo "$f"
}

# ---------------------------------------------------------------------------
# 1. The canonicalizer file exists and is executable.
# ---------------------------------------------------------------------------
echo "==> 1. lib/bd-canonical-export.sh exists"
if [ -f "$CANON" ]; then
  pass "lib/bd-canonical-export.sh exists"
else
  fail "lib/bd-canonical-export.sh exists" "expected at $CANON"
fi

# ---------------------------------------------------------------------------
# 2. INVARIANT: bd export is byte-stable across repeated runs on unchanged
#    state. Two consecutive canonicalized exports of the SAME (unchanged)
#    state are byte-identical, even though the raw `bd export` underneath
#    flips the memory-line order between the two calls.
# ---------------------------------------------------------------------------
echo "==> 2. INVARIANT: byte-stable across repeated runs on unchanged state"
COUNTER=$(mktemp)
STUB=$(mk_flapping_bd_stub "$COUNTER")

# Sanity: confirm the stub itself IS non-deterministic (otherwise the test
# would pass vacuously — it must actually exercise the canonicalizer).
raw1=$("$STUB" export)
raw2=$("$STUB" export)
if [ "$raw1" = "$raw2" ]; then
  fail "stub is genuinely non-deterministic (precondition)" \
       "raw exports were identical; test would be vacuous"
else
  pass "stub is genuinely non-deterministic (precondition)"
fi

# Reset the counter so the two canonical runs start from a clean phase.
printf '0' > "$COUNTER"
out1=$(BD_BIN="$STUB" bash "$CANON")
out2=$(BD_BIN="$STUB" bash "$CANON")
# Guard against a vacuous pass: empty == empty is NOT byte-stability,
# it's a missing/broken canonicalizer. Output must be non-empty.
if [ -n "$out1" ] && [ "$out1" = "$out2" ]; then
  pass "two consecutive canonical exports are byte-identical"
else
  fail "two consecutive canonical exports are byte-identical" \
       "out1=[$out1] $(diff <(printf '%s\n' "$out1") <(printf '%s\n' "$out2"))"
fi

# Run it many more times to defeat lucky alignment; ALL must match out1
# (and out1 must be non-empty — see the guard above).
stable=1
[ -n "$out1" ] || stable=0
for _ in $(seq 1 10); do
  outN=$(BD_BIN="$STUB" bash "$CANON")
  [ "$outN" = "$out1" ] || { stable=0; break; }
done
if [ "$stable" -eq 1 ]; then
  pass "canonical export is byte-stable across 12 runs"
else
  fail "canonical export is byte-stable across 12 runs" \
       "an export diverged from the first canonical form"
fi
rm -f "$COUNTER" "$STUB"

# ---------------------------------------------------------------------------
# 3. Memory lines are sorted into a stable (deterministic) order, while
#    issue rows keep their original relative position. The canonical form
#    must equal: issue rows in input order, then memory rows sorted.
# ---------------------------------------------------------------------------
echo "==> 3. memory lines sorted; issue rows keep position"
COUNTER=$(mktemp)
STUB=$(mk_flapping_bd_stub "$COUNTER")
canon=$(BD_BIN="$STUB" bash "$CANON")

expected=$(printf '%s\n' \
  '{"id":"x-1","title":"first issue","status":"open"}' \
  '{"id":"x-2","title":"second issue","status":"closed"}' \
  '{"_type":"memory","key":"alpha","value":"A"}' \
  '{"_type":"memory","key":"bravo","value":"B"}')
if [ "$canon" = "$expected" ]; then
  pass "issue rows preserved in order; memory rows sorted ascending"
else
  fail "issue rows preserved in order; memory rows sorted ascending" \
       "$(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$canon"))"
fi
rm -f "$COUNTER" "$STUB"

# ---------------------------------------------------------------------------
# 4. No memory lines at all: output is unchanged (issue rows pass through
#    verbatim, in order). The canonicalizer must be a no-op for the common
#    case of a workspace with zero `bd remember` memories.
# ---------------------------------------------------------------------------
echo "==> 4. zero memory lines: pass-through unchanged"
STUB=$(mktemp)
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "export" ]; then
  echo '{"id":"y-1","title":"a","status":"open"}'
  echo '{"id":"y-2","title":"b","status":"open"}'
  echo '{"id":"y-3","title":"c","status":"closed"}'
  exit 0
fi
exit 1
EOF
chmod +x "$STUB"
canon=$(BD_BIN="$STUB" bash "$CANON")
expected=$(printf '%s\n' \
  '{"id":"y-1","title":"a","status":"open"}' \
  '{"id":"y-2","title":"b","status":"open"}' \
  '{"id":"y-3","title":"c","status":"closed"}')
if [ "$canon" = "$expected" ]; then
  pass "zero memory lines: issue rows pass through verbatim"
else
  fail "zero memory lines: issue rows pass through verbatim" \
       "$(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$canon"))"
fi
rm -f "$STUB"

# ---------------------------------------------------------------------------
# 5. `bd export` failure propagates: the canonicalizer must exit non-zero
#    (so call sites — bd-merge-driver, post-rewrite — keep their existing
#    fail-safe semantics rather than overwriting jsonl with empty/garbage).
# ---------------------------------------------------------------------------
echo "==> 5. bd export failure propagates a non-zero exit"
STUB=$(mktemp)
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "$STUB"
if BD_BIN="$STUB" bash "$CANON" >/dev/null 2>&1; then
  fail "non-zero exit on bd export failure" "canonicalizer returned 0"
else
  pass "non-zero exit on bd export failure"
fi
rm -f "$STUB"

# ---------------------------------------------------------------------------
# 6. INVARIANT against the REAL bd, if available: two consecutive
#    canonical exports of the live (unchanged) workspace are byte-
#    identical. This is the end-to-end load-bearing assertion — it
#    exercises the actual v1.0.2 binary that exhibits the flap.
# ---------------------------------------------------------------------------
echo "==> 6. INVARIANT against real bd (end-to-end, if available)"
if command -v bd >/dev/null 2>&1; then
  e1=$(bash "$CANON" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$e1" ]; then
    echo "  SKIP: real bd export unavailable in this context (rc=$rc)"
  else
    real_stable=1
    for _ in $(seq 1 8); do
      eN=$(bash "$CANON" 2>/dev/null)
      [ "$eN" = "$e1" ] || { real_stable=0; break; }
    done
    if [ "$real_stable" -eq 1 ]; then
      pass "real bd: canonical export byte-stable across 9 runs"
    else
      fail "real bd: canonical export byte-stable across 9 runs" \
           "a live canonical export diverged from the first"
    fi
  fi
else
  echo "  SKIP: bd binary unavailable (end-to-end test)"
fi

# ---------------------------------------------------------------------------

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ]
