#!/usr/bin/env bash
# Fixture tests for scripts/loom-fanout-detect (loom-asr, T3 of loom-yb5).
#
# The fan-out detector proposes parallel worker WAVES at bead selection:
# given the ready queue, it groups beads that are safe to dispatch in
# parallel — NO dependency edge between them AND NO overlapping `Files:`
# path declared in their descriptions. A bead with no `Files:` line is
# "unknown, not safe to auto-parallelize" and is EXCLUDED from any
# proposed wave (conservative-by-default).
#
# This mirrors scripts/loom-mine-history + scripts/loom-audit-resolve:
# the deterministic resolution logic lives in a fixture-testable bash
# script so the session-startup / working-a-bead router PROSE can call
# it and read back the proposed group, rather than re-deriving the
# dep-graph + Files-overlap arithmetic in prose.
#
# Test strategy (mirrors loom-mine-history-cmd.test.sh + the
# check-upstream-prs gh-stub pattern):
#   - A PATH-prepended `bd` STUB, steered by side-channel files so each
#     case prepares its own fixture (ready list + per-bead show JSON)
#     without rewriting the stub body. The detector calls real `bd`
#     subcommands (`bd ready --json`, `bd show <id> --json`); the stub
#     answers from fixture files keyed by subcommand.
#
# Detector contract (the surface this test pins):
#   scripts/loom-fanout-detect
#     - reads `bd ready --json` for the candidate set
#     - reads `bd show <id> --json` per candidate for dep edges
#       (.dependencies[].id) + the `Files:` line in .description
#     - groups beads with NO dep edge between them AND NO overlapping
#       Files path; beads with no Files: line are EXCLUDED
#     - stdout: one proposed wave per line, space-separated bead IDs,
#       IDs sorted; only waves of size >=2 are emitted (a lone bead is
#       not a "parallel" proposal)
#     - exit 0 always (a detector, not a gate); empty stdout = no wave
#
# Run:  bash lib/tests/loom-fanout-detect.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$LOOM_ROOT/scripts/loom-fanout-detect"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- bd stub ---------------------------------------------------------
#
# PATH-prepended `bd` stub. Driven by a fixture directory whose path is
# passed via BD_FIXTURE_DIR:
#   $BD_FIXTURE_DIR/ready.json        -> answer for `bd ready --json`
#   $BD_FIXTURE_DIR/show-<id>.json    -> answer for `bd show <id> --json`
# Any other subcommand exits 1 (the detector must not depend on it).
mk_bd_stub() {
  local d
  d=$(mktemp -d)
  cat > "$d/bd" <<'EOF'
#!/usr/bin/env bash
sub="${1:-}"
case "$sub" in
  ready)
    cat "${BD_FIXTURE_DIR}/ready.json"
    ;;
  show)
    id="${2:-}"
    f="${BD_FIXTURE_DIR}/show-${id}.json"
    if [ -f "$f" ]; then cat "$f"; else echo "[]"; fi
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$d/bd"
  echo "$d"
}

# Build a fixture dir. Writes ready.json listing the given bead IDs, and
# one show-<id>.json per bead. Per-bead config passed as repeated triples
# on stdin: "<id>|<deps csv>|<files csv>" — deps are dependency IDs
# (any type), files are the Files: paths (empty string = no Files: line).
mk_fixture() {
  local fdir
  fdir=$(mktemp -d)
  local ids=()
  local line id rest deps files
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line%%|*}"; rest="${line#*|}"
    deps="${rest%%|*}"; files="${rest#*|}"
    ids+=("$id")
    # Build dependencies[] array from csv.
    local depjson="" first=1 d
    if [ -n "$deps" ]; then
      local oldifs="$IFS"; IFS=,
      for d in $deps; do
        [ "$first" = 1 ] || depjson="$depjson,"
        depjson="$depjson{\"id\":\"$d\",\"dependency_type\":\"blocks\"}"
        first=0
      done
      IFS="$oldifs"
    fi
    # Build the description, with a Files: line only when files non-empty.
    local descr="Goal: do thing $id."
    if [ -n "$files" ]; then
      descr="$descr\nFiles: $files\nSteps: 1. do it."
    else
      descr="$descr\nSteps: 1. do it."
    fi
    cat > "$fdir/show-$id.json" <<JSON
[{"id":"$id","description":"$descr","dependencies":[$depjson]}]
JSON
  done

  # ready.json: array of the bead IDs.
  local rjson="[" first=1 i
  for i in "${ids[@]}"; do
    [ "$first" = 1 ] || rjson="$rjson,"
    rjson="$rjson{\"id\":\"$i\"}"
    first=0
  done
  rjson="$rjson]"
  printf '%s\n' "$rjson" > "$fdir/ready.json"
  echo "$fdir"
}

run_detect() {
  local stub="$1" fdir="$2"
  PATH="$stub:$PATH" BD_FIXTURE_DIR="$fdir" bash "$BIN" 2>&1
}

STUB=$(mk_bd_stub)

# =====================================================================
# 0. Detector exists + is an executable bash script.
# =====================================================================
echo "==> 0. detector shape"
if [ -x "$BIN" ]; then pass "scripts/loom-fanout-detect exists + executable"; else fail "detector missing/not executable"; fi
if head -1 "$BIN" 2>/dev/null | grep -q '^#!.*bash'; then pass "detector is bash-shebanged"; else fail "detector not bash-shebanged"; fi

# =====================================================================
# (a) 3 independent beads (no deps, disjoint Files:) → all proposed.
# =====================================================================
echo "==> (a) 3 independent beads → all proposed as one wave"
FDIR=$(mk_fixture <<'F'
loom-aaa||scripts/loom-fanout-detect, lib/tests/loom-fanout-detect.test.sh
loom-bbb||hooks/dispatch-nudge.sh, lib/tests/dispatch-nudge.test.sh
loom-ccc||scripts/workflow-state, scripts/statusline.sh
F
)
out=$(run_detect "$STUB" "$FDIR")
# Expect a single wave line containing all three IDs (sorted).
if printf '%s\n' "$out" | grep -qE '(^| )loom-aaa( |$)' \
   && printf '%s\n' "$out" | grep -qE '(^| )loom-bbb( |$)' \
   && printf '%s\n' "$out" | grep -qE '(^| )loom-ccc( |$)'; then
  pass "all 3 disjoint independent beads proposed"
else
  fail "3 independent beads not all proposed" "out=$out"
fi
# And they should be ONE wave (one line), since pairwise-compatible.
nlines=$(printf '%s\n' "$out" | grep -c 'loom-')
if [ "$nlines" -eq 1 ]; then pass "proposed as a single wave (one line)"; else fail "expected 1 wave line, got $nlines" "out=$out"; fi
rm -rf "$FDIR"

# =====================================================================
# (b) 2 beads sharing a Files: path → NOT grouped (bn7.2/bn7.3 case).
# =====================================================================
echo "==> (b) shared Files: path → NOT grouped"
FDIR=$(mk_fixture <<'F'
loom-bn72||lib/loom-mine-history.sh, scripts/a.sh
loom-bn73||lib/loom-mine-history.sh, scripts/b.sh
F
)
out=$(run_detect "$STUB" "$FDIR")
# No wave of size >=2 → the two file-colliding beads are never on the
# same line. Empty stdout is acceptable (no wave proposed).
if printf '%s\n' "$out" | grep -qE 'loom-bn72.*loom-bn73|loom-bn73.*loom-bn72'; then
  fail "file-colliding beads were grouped (must not be)" "out=$out"
else
  pass "shared lib/loom-mine-history.sh → bn72 + bn73 NOT grouped"
fi
rm -rf "$FDIR"

# =====================================================================
# (c) a bead with no Files: line → EXCLUDED (conservative).
# =====================================================================
echo "==> (c) bead with no Files: line → excluded"
FDIR=$(mk_fixture <<'F'
loom-have||scripts/x.sh, lib/tests/x.test.sh
loom-also||scripts/y.sh, lib/tests/y.test.sh
loom-none||
F
)
out=$(run_detect "$STUB" "$FDIR")
if printf '%s\n' "$out" | grep -qE '(^| )loom-none( |$)'; then
  fail "bead with no Files: was included (must be excluded)" "out=$out"
else
  pass "loom-none (no Files:) excluded from proposed wave"
fi
# The two that DO declare disjoint Files: should still be proposed.
if printf '%s\n' "$out" | grep -qE 'loom-have' && printf '%s\n' "$out" | grep -qE 'loom-also'; then
  pass "the two Files:-declaring disjoint beads still proposed"
else
  fail "Files:-declaring beads not proposed alongside excluded one" "out=$out"
fi
rm -rf "$FDIR"

# =====================================================================
# (d) a dep edge between two → not grouped.
# =====================================================================
echo "==> (d) dependency edge between two → not grouped"
# loom-dep1 depends on loom-dep2 (edge present). Files disjoint, so the
# ONLY reason to not group is the dep edge.
FDIR=$(mk_fixture <<'F'
loom-dep1|loom-dep2|scripts/p.sh, lib/tests/p.test.sh
loom-dep2||scripts/q.sh, lib/tests/q.test.sh
F
)
out=$(run_detect "$STUB" "$FDIR")
if printf '%s\n' "$out" | grep -qE 'loom-dep1.*loom-dep2|loom-dep2.*loom-dep1'; then
  fail "dep-edged beads were grouped (must not be)" "out=$out"
else
  pass "dep edge dep1->dep2 → NOT grouped"
fi
rm -rf "$FDIR"

# =====================================================================
# (e) exit code is 0 (detector, not a gate), even with no wave.
# =====================================================================
echo "==> (e) exit 0 always"
FDIR=$(mk_fixture <<'F'
loom-solo||scripts/only.sh
F
)
PATH="$STUB:$PATH" BD_FIXTURE_DIR="$FDIR" bash "$BIN" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then pass "exit 0 with a single ready bead (no wave)"; else fail "expected exit 0, got $rc"; fi
# A single ready bead is not a "wave" — nothing of size >=2.
out=$(run_detect "$STUB" "$FDIR")
nlines=$(printf '%s\n' "$out" | grep -c 'loom-' || true)
if [ "$nlines" -eq 0 ]; then pass "single ready bead → no wave proposed"; else fail "single bead wrongly proposed as wave" "out=$out"; fi
rm -rf "$FDIR"

rm -rf "$STUB"

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
