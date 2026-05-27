#!/usr/bin/env bash
# Fixture tests for the discovery sub-step in commands/wrap-up.md step 1.
#
# Covers loom-6p6: mechanical discovery of merged-but-still-open beads
# BEFORE the user-enumerate prompt. Surfaced 2026-05-27 when loom-7p6.2-.6
# were merged to main 2026-05-26 but never closed.
#
# Locked contract (per loom-6p6 brief):
#   1. Generic prefix-agnostic regex (reuses bd-close-capture.sh shape).
#   2. Time window = most-recent bd close timestamp; fallback '7 days ago'.
#   3. Match BOTH "Merge <prefix>-XXX:" AND bare "<prefix>-XXX:" subjects.
#   4. Discovery snippet lives inline in commands/wrap-up.md, bounded by
#      "# DISCOVERY:START" and "# DISCOVERY:END" markers (sed-extractable).
#   5. Cross-check each ID via `bd show <id> --json`; keep only open or
#      in_progress.
#   6. Output is a sorted list of bead IDs, one per line, prefixed by
#      "Found bead(s) merged-to-main but still open:" header when non-empty.
#      Empty input → no output (silent fall-through), exit 0.
#
# Run:  bash lib/tests/wrap-up-discovery.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAP_UP_MD="$LOOM_ROOT/commands/wrap-up.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Extract the discovery snippet from commands/wrap-up.md.
# Bounded by literal "# DISCOVERY:START" and "# DISCOVERY:END" comment lines
# inside a bash fence. Emits everything BETWEEN the markers (exclusive of the
# marker lines themselves) on stdout.
extract_snippet() {
  awk '
    /# DISCOVERY:START/ { in_block = 1; next }
    /# DISCOVERY:END/   { in_block = 0; next }
    in_block            { print }
  ' "$WRAP_UP_MD"
}

# Build a fake `bd` binary that supports:
#   bd list --status=closed --json   — emit one closed bead with the closed_at
#                                      timestamp set by FAKE_BD_CLOSED_AT env
#                                      (or empty array if unset/blank).
#   bd show <id> --json              — look up `<id>` in $FAKE_BD_STATUS_FILE,
#                                      a key=value file (id=status). Emit a
#                                      one-element list with `status` set, or
#                                      exit 1 if id not present.
mk_fake_bd() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat >"$dir/bin/bd" <<'BD'
#!/usr/bin/env bash
set -u
sub="${1:-}"
case "$sub" in
  list)
    # Expect: bd list --status=closed --json
    if [ -n "${FAKE_BD_CLOSED_AT:-}" ]; then
      printf '[{"id":"fake-zzz","closed_at":"%s","status":"closed"}]\n' \
        "$FAKE_BD_CLOSED_AT"
    else
      echo "[]"
    fi
    exit 0
    ;;
  show)
    id="${2:-}"
    [ -z "$id" ] && exit 1
    sf="${FAKE_BD_STATUS_FILE:-}"
    [ -z "$sf" ] || [ ! -f "$sf" ] && exit 1
    status=$(grep -E "^${id}=" "$sf" 2>/dev/null | head -n1 | cut -d= -f2-)
    if [ -z "$status" ]; then
      echo "Error: no issue found matching \"$id\"" >&2
      exit 1
    fi
    printf '[{"id":"%s","status":"%s"}]\n' "$id" "$status"
    exit 0
    ;;
esac
exit 1
BD
  chmod +x "$dir/bin/bd"
}

# Build a fixture git repo with a tagged set of subjects on `main` (the branch
# name the discovery snippet greps against). Each arg is one commit subject.
mk_fixture_repo() {
  local dir="$1" ; shift
  mkdir -p "$dir"
  (
    cd "$dir" && \
      git init -q -b main && \
      git config user.email fixture@example.com && \
      git config user.name Fixture && \
      git commit -q --allow-empty -m "init"
    for subject in "$@"; do
      git -C "$dir" commit -q --allow-empty -m "$subject"
    done
  ) >/dev/null
}

# Run the extracted discovery snippet inside the given fixture repo with the
# given fake-bd PATH prepended. Returns combined stdout+stderr; exit code is
# captured via $?.
run_snippet() {
  local repo="$1" bdb_dir="$2"
  local snippet
  snippet=$(extract_snippet)
  if [ -z "$snippet" ]; then
    return 99   # signals "no snippet extracted" — drives the snippet-present test
  fi
  (
    cd "$repo" && \
    PATH="$bdb_dir/bin:$PATH" bash -c "$snippet" 2>&1
  )
}

# ---------------------------------------------------------------------------
# 1. Snippet is present in commands/wrap-up.md (M3 case 1)
# ---------------------------------------------------------------------------

echo "==> 1. Snippet present (marker-bounded block exists)"

if grep -qF "# DISCOVERY:START" "$WRAP_UP_MD" && grep -qF "# DISCOVERY:END" "$WRAP_UP_MD"; then
  pass "discovery markers present in commands/wrap-up.md"
else
  fail "missing # DISCOVERY:START/END markers in commands/wrap-up.md"
fi

snip=$(extract_snippet)
if [ -n "$snip" ]; then
  pass "snippet extraction yields non-empty content"
else
  fail "extract_snippet returned empty (markers missing or empty block)"
fi

# ---------------------------------------------------------------------------
# 2. Happy path — merge + bare commit, mixed open/closed (M3 case 2)
# ---------------------------------------------------------------------------

echo "==> 2. Happy path: merge-shape + bare-shape commits, mixed statuses"

T2=$(mktemp -d)
mk_fake_bd "$T2"
mk_fixture_repo "$T2/repo" \
  "Merge foo-abc: ship something" \
  "bar-xyz: ship something else"

cat >"$T2/status" <<'EOF'
foo-abc=open
bar-xyz=closed
EOF

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T2/status" \
  run_snippet "$T2/repo" "$T2"); rc=$?
if echo "$out" | grep -q "foo-abc" && ! echo "$out" | grep -q "bar-xyz"; then
  pass "happy path: foo-abc surfaced, bar-xyz (closed) filtered out"
else
  fail "happy path: expected foo-abc and NOT bar-xyz" "rc=$rc out=$out"
fi

rm -rf "$T2"

# ---------------------------------------------------------------------------
# 3. Dotted IDs (M3 case 3)
# ---------------------------------------------------------------------------

echo "==> 3. Dotted bead IDs (proj-abc.4)"

T3=$(mktemp -d)
mk_fake_bd "$T3"
mk_fixture_repo "$T3/repo" "Merge proj-abc.4: dotted sub-bead"

cat >"$T3/status" <<'EOF'
proj-abc.4=open
EOF

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T3/status" \
  run_snippet "$T3/repo" "$T3"); rc=$?
if echo "$out" | grep -q "proj-abc.4"; then
  pass "dotted ID proj-abc.4 captured"
else
  fail "dotted ID proj-abc.4 not captured" "rc=$rc out=$out"
fi

rm -rf "$T3"

# ---------------------------------------------------------------------------
# 4. No merges → silent (M3 case 4)
# ---------------------------------------------------------------------------

echo "==> 4. No matching commits → silent fall-through"

T4=$(mktemp -d)
mk_fake_bd "$T4"
mk_fixture_repo "$T4/repo" "init only"
: >"$T4/status"

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T4/status" \
  run_snippet "$T4/repo" "$T4"); rc=$?
# Empty result → no "Found bead(s)" header.
if ! echo "$out" | grep -q "Found bead"; then
  pass "no merges → no 'Found bead(s)' header, exit clean (rc=$rc)"
else
  fail "empty fixture emitted header anyway" "rc=$rc out=$out"
fi
if [ "$rc" -eq 0 ]; then
  pass "empty fixture exits 0"
else
  fail "empty fixture exited non-zero" "rc=$rc out=$out"
fi

rm -rf "$T4"

# ---------------------------------------------------------------------------
# 5. All closed → silent (M3 case 5)
# ---------------------------------------------------------------------------

echo "==> 5. All matched IDs are closed → no output"

T5=$(mktemp -d)
mk_fake_bd "$T5"
mk_fixture_repo "$T5/repo" \
  "Merge alpha-abc: shipped" \
  "Merge beta-def: shipped"

cat >"$T5/status" <<'EOF'
alpha-abc=closed
beta-def=closed
EOF

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T5/status" \
  run_snippet "$T5/repo" "$T5"); rc=$?
if ! echo "$out" | grep -q "Found bead"; then
  pass "all-closed → no header"
else
  fail "all-closed fixture emitted header anyway" "rc=$rc out=$out"
fi

rm -rf "$T5"

# ---------------------------------------------------------------------------
# 6. Non-merge subject with bare ID + bd-show-not-found rejection (M3 case 6)
# ---------------------------------------------------------------------------

echo "==> 6. Bare-ID subjects picked up; bd-show-not-found filters non-beads"

T6=$(mktemp -d)
mk_fake_bd "$T6"
mk_fixture_repo "$T6/repo" \
  "proj-abc: bd: post-rewrite re-export" \
  "Update meta-tag handling in foo"

# bd show knows about proj-abc (open). It does NOT know about meta-tag —
# the fake bd returns exit 1, simulating "no such issue".
cat >"$T6/status" <<'EOF'
proj-abc=open
EOF

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T6/status" \
  run_snippet "$T6/repo" "$T6"); rc=$?
if echo "$out" | grep -q "proj-abc"; then
  pass "bare-ID subject 'proj-abc: ...' captured"
else
  fail "bare-ID subject not captured" "rc=$rc out=$out"
fi
if ! echo "$out" | grep -q "meta-tag"; then
  pass "regex-matching non-bead 'meta-tag' rejected by bd-show cross-check"
else
  fail "non-bead 'meta-tag' leaked into output" "rc=$rc out=$out"
fi

rm -rf "$T6"

# ---------------------------------------------------------------------------
# 7. Prefix variety (M3 case 7)
# ---------------------------------------------------------------------------

echo "==> 7. Mixed-prefix bead IDs (snake_case, hyphens, dotted)"

T7=$(mktemp -d)
mk_fake_bd "$T7"
mk_fixture_repo "$T7/repo" \
  "Merge foo-abc: A" \
  "Merge bar_baz-def.2: B" \
  "liza_base-zzz: C"

cat >"$T7/status" <<'EOF'
foo-abc=open
bar_baz-def.2=in_progress
liza_base-zzz=open
EOF

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T7/status" \
  run_snippet "$T7/repo" "$T7"); rc=$?
all_three_present=1
for id in foo-abc bar_baz-def.2 liza_base-zzz; do
  if ! echo "$out" | grep -qF "$id"; then
    all_three_present=0
    fail "prefix variety: missing $id" "rc=$rc out=$out"
  fi
done
if [ "$all_three_present" -eq 1 ]; then
  pass "all three mixed-prefix IDs captured (foo-abc, bar_baz-def.2, liza_base-zzz)"
fi

rm -rf "$T7"

# ---------------------------------------------------------------------------
# 8. Order stability — output is sorted (M3 case 8)
# ---------------------------------------------------------------------------

echo "==> 8. Output order is stable (sort -u contract)"

T8=$(mktemp -d)
mk_fake_bd "$T8"
mk_fixture_repo "$T8/repo" \
  "Merge zzz-aaa: C" \
  "Merge aaa-zzz: A" \
  "Merge mmm-mmm: B"

cat >"$T8/status" <<'EOF'
zzz-aaa=open
aaa-zzz=open
mmm-mmm=open
EOF

out=$(FAKE_BD_CLOSED_AT="" FAKE_BD_STATUS_FILE="$T8/status" \
  run_snippet "$T8/repo" "$T8"); rc=$?
# Extract just bead-ID lines, in order. Only consider indented "  <id>" lines,
# not the "Found bead(s) merged-to-main..." header (which structurally matches
# the bead-ID regex).
seen=$(echo "$out" | grep -E '^  [a-z]' | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')
expected="aaa-zzz mmm-mmm zzz-aaa"
if [ "$seen" = "$expected" ]; then
  pass "output is alphabetically sorted (aaa-zzz mmm-mmm zzz-aaa)"
else
  fail "output order not stable" "expected='$expected' got='$seen' rc=$rc"
fi

rm -rf "$T8"

# ---------------------------------------------------------------------------
# 9. Integration — runs against real loom repo, real bd (M5)
# ---------------------------------------------------------------------------

echo "==> 9. Integration: snippet runs against real loom repo + real bd"

# Use the real loom repo (the worktree's toplevel) and the real bd on PATH.
out=$(cd "$LOOM_ROOT" && bash -c "$(extract_snippet)" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "integration: snippet exits 0 against real loom repo"
else
  fail "integration: snippet exited non-zero" "rc=$rc out=$out"
fi

# Anything emitted must look like a bead ID (no junk leakage).
if [ -n "$out" ]; then
  bad=$(echo "$out" \
    | grep -v '^Found bead' \
    | grep -v '^$' \
    | grep -v '^  ' \
    | head -5)
  if [ -z "$bad" ]; then
    pass "integration: output shape (header + indented IDs or empty) is well-formed"
  else
    fail "integration: unexpected line shape" "$bad"
  fi
else
  pass "integration: no output (silent fall-through is also valid)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "wrap-up-discovery: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
